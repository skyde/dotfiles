#!/bin/bash
# Simple dotfiles installer
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
Usage: ./init.sh [apply options]

Install and apply the dotfiles for this platform.

Common options:
  -n, --no, --no-act, --simulate  Preview stow changes and skip installers
  --delete                        Remove stowed links and skip installers
  -h, --help                      Show this help message

Set AUTO_INSTALL=1 to answer yes to installer prompts.
Set AUTO_INSTALL=0 to answer no to installer prompts.
EOF
}

for arg in "$@"; do
  case "$arg" in
  --help | -h)
    usage
    exit 0
    ;;
  esac
done

# Function to get user confirmation with auto-install support
get_user_confirmation() {
  local prompt="$1"
  local response

  if [ "${AUTO_INSTALL:-}" = "1" ]; then
    response="y"
  elif [ "${AUTO_INSTALL:-}" = "0" ]; then
    response="n"
  else
    read -r -p "$prompt" response
  fi

  echo "$response"
}

echo "Installing dotfiles..."

# Change to script directory to ensure relative paths work
cd "$SCRIPT_DIR"

# Detect apply-only modes so dry-run/delete operations do not continue into
# package installs or platform setup.
APPLY_ONLY=false
for arg in "$@"; do
  case "$arg" in
  --no-act | --no | --simulate | -n | --delete)
    APPLY_ONLY=true
    ;;
  esac
done

# Manually use apply.sh with --adopt to handle conflicts if required
# Pass through all command line arguments to apply.sh
./apply.sh "$@"

if $APPLY_ONLY; then
  echo "Skipping installer steps for apply-only mode."
  exit 0
fi

# Install packages
if [ -f "packages.txt" ]; then
  # Build package list with platform-specific names
  packages=()
  while IFS= read -r pkg; do
    case "$pkg" in
      '' | \#*) continue ;;
    esac
    if [[ "$(uname)" == "Linux" ]]; then
      case "$pkg" in
        fd) pkg="fd-find" ;;
        delta) pkg="git-delta" ;;
        tree-sitter-cli)
          echo "Skipping distro tree-sitter-cli package on Linux; install-tree-sitter-cli.sh installs the version required by nvim-treesitter."
          continue
          ;;
        neovim)
          echo "Skipping distro neovim package on Linux; install-nvim.sh installs a LazyVim-compatible release build."
          continue
          ;;
      esac
    elif [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* || "$(uname -s)" == CYGWIN* ]]; then
      case "$pkg" in
        tmux)
          echo "Skipping native Windows tmux package; the dotfiles tmux wrapper uses WSL tmux when available."
          continue
          ;;
      esac
    fi
    packages+=("$pkg")
  done <packages.txt
  package_list="${packages[*]}"

  install_apps=$(get_user_confirmation "Install packages ($package_list)? (y/N): ")
  if [[ "$install_apps" =~ ^[Yy] ]]; then
    echo "Installing packages..."
    case "$(uname)" in
    Darwin)
      command -v brew >/dev/null && brew install "${packages[@]}" || echo "Homebrew not found. Install it first: https://brew.sh"
      ;;
    Linux)
      command -v apt >/dev/null && sudo apt update && sudo apt install -y "${packages[@]}"
      ;;
    MINGW* | MSYS* | CYGWIN*)
      if command -v winget >/dev/null; then
        for pkg in "${packages[@]}"; do winget install "$pkg" --silent --accept-source-agreements --accept-package-agreements; done
      elif command -v choco >/dev/null; then
        choco install "${packages[@]}" -y
      else
        echo "Neither winget nor chocolatey found. Please install packages manually: $package_list"
      fi
      ;;
    esac
  fi
fi

if [ -f "install-tmux-plugins.sh" ]; then
  install_tmux_plugins=$(get_user_confirmation "Install tmux plugin manager (TPM) and plugins? (y/N): ")
  if [[ "$install_tmux_plugins" =~ ^[Yy] ]]; then
    echo "Setting up tmux plugin manager (TPM) and plugins..."
    ./install-tmux-plugins.sh
  else
    echo "Skipping tmux plugin manager setup"
  fi
fi

vscode_state_db() {
  case "$(uname -s)" in
    Darwin)
      printf '%s\n' "$HOME/Library/Application Support/Code/User/globalStorage/state.vscdb"
      ;;
    *)
      printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/globalStorage/state.vscdb"
      ;;
  esac
}

enable_vscode_required_extensions() {
  local extensions_file="${1:-vscode_extensions.txt}"
  local state_db
  state_db="$(vscode_state_db)"

  [[ -f "$extensions_file" && -f "$state_db" ]] || return 0

  if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "Note: sqlite3 not found; manually re-enable any disabled required VS Code extensions."
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Note: python3 not found; cannot inspect VS Code disabled-extension state."
    return 0
  fi

  local disabled_json
  disabled_json="$(sqlite3 "$state_db" "SELECT value FROM ItemTable WHERE key = 'extensionsIdentifiers/disabled';" 2>/dev/null || true)"
  [[ -n "$disabled_json" ]] || return 0

  local new_disabled
  new_disabled="$(
    DISABLED_JSON="$disabled_json" python3 - "$extensions_file" <<'PY'
import json
import os
import sys

extensions_file = sys.argv[1]
required = set()
with open(extensions_file, encoding="utf-8") as handle:
    for line in handle:
        line = line.strip()
        if line and not line.startswith("#"):
            required.add(line.lower())

try:
    disabled = json.loads(os.environ.get("DISABLED_JSON", "[]"))
except json.JSONDecodeError:
    sys.exit(2)

remaining = [
    item for item in disabled
    if str(item.get("id", "")).lower() not in required
]

if len(remaining) != len(disabled):
    print(json.dumps(remaining, separators=(",", ":")))
PY
  )"

  if [[ -n "$new_disabled" ]]; then
    local escaped_json="${new_disabled//\'/\'\'}"
    sqlite3 "$state_db" "UPDATE ItemTable SET value = '$escaped_json' WHERE key = 'extensionsIdentifiers/disabled';"
    echo "Re-enabled persisted VS Code extension(s) from $extensions_file"
  fi
}

disable_vscode_conflicting_extensions() {
  local extensions_file="${1:-vscode_conflicting_extensions.txt}"
  local state_db
  state_db="$(vscode_state_db)"

  [[ -f "$extensions_file" && -f "$state_db" ]] || return 0

  if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "Note: sqlite3 not found; manually disable conflicting VS Code extensions."
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "Note: python3 not found; cannot inspect VS Code disabled-extension state."
    return 0
  fi

  local disabled_json
  disabled_json="$(sqlite3 "$state_db" "SELECT value FROM ItemTable WHERE key = 'extensionsIdentifiers/disabled';" 2>/dev/null || true)"
  local has_disabled_row=1
  if [[ -z "$disabled_json" ]]; then
    disabled_json="[]"
    has_disabled_row=0
  fi

  local new_disabled
  new_disabled="$(
    DISABLED_JSON="$disabled_json" python3 - "$extensions_file" <<'PY'
import json
import os
import sys

extensions_file = sys.argv[1]
conflicts = []
with open(extensions_file, encoding="utf-8") as handle:
    for line in handle:
        line = line.strip()
        if line and not line.startswith("#"):
            conflicts.append(line)

try:
    disabled = json.loads(os.environ.get("DISABLED_JSON", "[]"))
except json.JSONDecodeError:
    sys.exit(2)

known_uuids = {
    "asvetliakov.vscode-neovim": "caf8995c-5426-4bf7-9d01-f7968ebd49bb",
    "jasew.vscode-helix-emulation": "bbfec3b6-db49-48ca-ac93-b3141e35a9eb",
}
seen = {str(item.get("id", "")).lower() for item in disabled}
changed = False
for ext in conflicts:
    key = ext.lower()
    if key in seen:
        continue
    item = {"id": ext}
    if key in known_uuids:
        item["uuid"] = known_uuids[key]
    disabled.append(item)
    seen.add(key)
    changed = True

if changed:
    print(json.dumps(disabled, separators=(",", ":")))
PY
  )"

  if [[ -n "$new_disabled" ]]; then
    local escaped_json="${new_disabled//\'/\'\'}"
    if [[ "$has_disabled_row" -eq 1 ]]; then
      sqlite3 "$state_db" "UPDATE ItemTable SET value = '$escaped_json' WHERE key = 'extensionsIdentifiers/disabled';"
    else
      sqlite3 "$state_db" "INSERT INTO ItemTable(key, value) VALUES('extensionsIdentifiers/disabled', '$escaped_json');"
    fi
    echo "Disabled conflicting VS Code extension(s) from $extensions_file"
  fi
}

# Install VS Code extensions
if command -v code >/dev/null 2>&1; then
  if [ -f "vscode_extensions.txt" ]; then
    install_extensions=$(get_user_confirmation "Install VS Code extensions? (y/N): ")
    if [[ "$install_extensions" =~ ^[Yy] ]]; then
      echo "Installing VS Code extensions..."
      enable_vscode_required_extensions vscode_extensions.txt
      while read -r ext; do
        if [ -n "$ext" ] && [[ ! "$ext" =~ ^[[:space:]]*# ]]; then
          echo "  Installing: $ext"
          code --install-extension "$ext" --force
        fi
      done <vscode_extensions.txt
      enable_vscode_required_extensions vscode_extensions.txt
      disable_vscode_conflicting_extensions vscode_conflicting_extensions.txt
      echo "✅ VS Code extensions installed"
    else
      echo "Skipping VS Code extensions"
    fi
  fi
else
  echo "VS Code not found, skipping extensions"
fi

# Optional: Install tree-sitter CLI for current LazyVim/nvim-treesitter releases.
if [ -f "install-tree-sitter-cli.sh" ] && [[ "$(uname)" == "Linux" ]]; then
  install_tree_sitter=$(get_user_confirmation "Install tree-sitter CLI to ~/.local/bin? (y/N): ")
  if [[ "$install_tree_sitter" =~ ^[Yy] ]]; then
    echo "Running tree-sitter CLI installation script..."
    ./install-tree-sitter-cli.sh
  else
    echo "Skipping tree-sitter CLI installation"
  fi
fi

# Optional: Install Neovim AppImage (Linux only)
if [ -f "install-nvim.sh" ] && [[ "$(uname)" == "Linux" ]]; then
  install_nvim=$(get_user_confirmation "Install latest Neovim to ~/.local/bin? (y/N): ")
  if [[ "$install_nvim" =~ ^[Yy] ]]; then
    echo "Running Neovim installation script..."
    ./install-nvim.sh
  else
    echo "Skipping Neovim installation"
  fi
fi

# Optional: Install Yazi with enhanced features (GitHub binary for Linux)
if [ -f "install-yazi.sh" ]; then
  install_yazi=$(get_user_confirmation "Install Yazi (may prompt again for install method)? (y/N): ")
  if [[ "$install_yazi" =~ ^[Yy] ]]; then
    echo "Running Yazi installation script..."
    ./install-yazi.sh
  else
    echo "Skipping enhanced Yazi installation"
  fi
fi

# Optional: Install Zoekt (Go-based code search)
if [ -f "install-zoekt.sh" ]; then
  install_zoekt=$(get_user_confirmation "Install Zoekt (may prompt again for install method)? (y/N): ")
  if [[ "$install_zoekt" =~ ^[Yy] ]]; then
    echo "Running Zoekt installation script..."
    ./install-zoekt.sh
  else
    echo "Skipping Zoekt installation"
  fi
fi

# Optional: Install zsh-fast-syntax-highlighting (manual install/clone)
if [ -f "install-fast-syntax-highlighting.sh" ]; then
  install_fsh=$(get_user_confirmation "Install zsh-fast-syntax-highlighting? (y/N): ")
  if [[ "$install_fsh" =~ ^[Yy] ]]; then
    echo "Running zsh-fast-syntax-highlighting installation script..."
    ./install-fast-syntax-highlighting.sh
  else
    echo "Skipping zsh-fast-syntax-highlighting installation"
  fi
fi

# Run platform-specific initialization
platform_init=$(get_user_confirmation "Run platform-specific setup? (y/N): ")
if [[ "$platform_init" =~ ^[Yy] ]]; then
  echo "Running platform-specific initialization..."
  case "$(uname)" in
  Darwin)
    if [ -f "init-macos.sh" ]; then
      echo "Running macOS-specific setup..."
      ./init-macos.sh
    else
      echo "init-macos.sh not found, skipping macOS setup"
    fi
    ;;
  Linux)
    if [ -f "init-linux.sh" ]; then
      echo "Running Linux-specific setup..."
      ./init-linux.sh
    else
      echo "init-linux.sh not found, skipping Linux setup"
    fi
    ;;
  MINGW* | MSYS* | CYGWIN*)
    if [ -f "init-windows.ps1" ]; then
      echo "Running Windows-specific setup..."
      powershell.exe -ExecutionPolicy Bypass -File "./init-windows.ps1"
    else
      echo "init-windows.ps1 not found, skipping Windows setup"
    fi
    ;;
  esac
else
  echo "Skipping platform-specific setup"
fi

if command -v bat >/dev/null 2>&1; then
  echo "Building bat cache for custom theme..."
  bat cache --build
else
  echo "bat not found, skipping bat cache build"
fi

# Run local dotfiles initialization if it exists
LOCAL_INIT_SCRIPT="$HOME/dotfiles-local/init.sh"
if [ -f "$LOCAL_INIT_SCRIPT" ]; then
  run_local=$(get_user_confirmation "Run local dotfiles initialization? (y/N): ")
  if [[ "$run_local" =~ ^[Yy] ]]; then
    echo "Running local initialization script..."
    "$LOCAL_INIT_SCRIPT"
  fi
fi
echo "Init complete!"
