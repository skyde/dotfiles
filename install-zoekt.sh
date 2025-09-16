#!/usr/bin/env bash
set -euo pipefail

# Install Zoekt command-line tools if they are missing.

HAVE() { command -v "$1" >/dev/null 2>&1; }

SUDO_CMD=""
if [ "$(id -u)" -ne 0 ] && HAVE sudo; then
  SUDO_CMD="sudo"
fi

OS="$(uname -s)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try to source shared helpers if available
if [ -f "$SCRIPT_DIR/lib/run_ensure.sh" ]; then
  # shellcheck disable=SC1090
  . "$SCRIPT_DIR/lib/run_ensure.sh"
fi

if ! declare -F _truthy >/dev/null 2>&1; then
  _truthy() {
    case "${1:-}" in
      1 | true | TRUE | True | yes | YES | Yes | on | ON | On) return 0 ;;
      *) return 1 ;;
    esac
  }
fi

if ! declare -F is_tty >/dev/null 2>&1; then
  is_tty() { [ -t 0 ] && [ -t 1 ]; }
fi

if ! declare -F ask >/dev/null 2>&1; then
  ask() {
    local prompt="$1"
    if _truthy "${AUTO_INSTALL:-}"; then
      echo "[auto] $prompt (AUTO_INSTALL=1)"
      return 0
    fi
    if ! is_tty; then
      echo "[skip] $prompt (non-interactive; default = no)"
      return 1
    fi
    read -r -p "$prompt [y/N] " reply
    [[ "$reply" =~ ^([yY]|[yY][eE][sS])$ ]]
  }
fi

confirm_zoekt_install() {
  local method_msg="$1"
  if _truthy "${AUTO_INSTALL:-}"; then
    echo "[auto] Install Zoekt via $method_msg (AUTO_INSTALL=1)"
    return 0
  fi
  ask "Install Zoekt now via $method_msg?"
}

# Fallback ensure for Debian-based systems when ensure_apt is unavailable
ensure_pkg_cmd() {
  local pkg="$1"
  shift || true
  local check_cmd="${1:-}"
  if [ -n "$check_cmd" ] && HAVE "$check_cmd"; then
    return 0
  fi
  if [ -n "$pkg" ] && dpkg -s "$pkg" >/dev/null 2>&1; then
    return 0
  fi
  if _truthy "${AUTO_INSTALL:-}"; then
    echo "[auto] Install dependency $pkg (AUTO_INSTALL=1)"
    $SUDO_CMD apt-get update -y
    $SUDO_CMD apt-get install -y "$pkg"
    return 0
  fi
  if ask "Install dependency $pkg?"; then
    $SUDO_CMD apt-get update -y
    $SUDO_CMD apt-get install -y "$pkg"
  else
    echo "[skip] $pkg not installed"
  fi
}

ensure_go_linux() {
  if HAVE go; then
    return 0
  fi
  if declare -F ensure_apt >/dev/null 2>&1; then
    if ! ensure_apt golang-go; then
      echo "[warn] Failed to install golang-go via ensure_apt" >&2
    fi
  else
    ensure_pkg_cmd golang-go go
  fi
}

ensure_go_macos() {
  if HAVE go; then
    return 0
  fi
  if HAVE brew; then
    if declare -F ensure_brew >/dev/null 2>&1; then
      ensure_brew go
    else
      if _truthy "${AUTO_INSTALL:-}"; then
        echo "[auto] Install Go via Homebrew (AUTO_INSTALL=1)"
        brew install go || brew upgrade go || true
      elif ask "Install Go via Homebrew?"; then
        brew install go || brew upgrade go || true
      else
        echo "[skip] Go install via Homebrew declined"
      fi
    fi
  fi
}

install_via_go() {
  if ! HAVE go; then
    echo "[warn] Go toolchain not found; cannot install Zoekt." >&2
    return 1
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'if [ -n "${tmp_dir:-}" ]; then rm -rf "${tmp_dir}"; fi' EXIT

  local build_bin="$tmp_dir/bin"
  mkdir -p "$build_bin"

  echo "[info] Building Zoekt binaries via 'go install github.com/google/zoekt/cmd/...@latest'"
  if ! GOBIN="$build_bin" GO111MODULE=on go install github.com/google/zoekt/cmd/...@latest; then
    echo "[warn] go install failed; Zoekt was not installed" >&2
    return 1
  fi

  local install_prefix="/usr/local"
  if [ "$OS" = "Darwin" ] && [ -d "/opt/homebrew/bin" ]; then
    install_prefix="/opt/homebrew"
  fi
  local install_bin="${install_prefix}/bin"

  $SUDO_CMD install -d -m 0755 "$install_bin"

  local copied=0
  local bin_path
  for bin_path in "$build_bin"/*; do
    if [ -f "$bin_path" ]; then
      $SUDO_CMD install -m 0755 "$bin_path" "$install_bin/$(basename "$bin_path")"
      copied=1
    fi
  done

  if [ "$copied" -eq 0 ]; then
    echo "[warn] No Zoekt binaries were produced" >&2
    return 1
  fi

  if ! HAVE zoekt; then
    echo "[warn] Zoekt binary not found on PATH after installation. Ensure ${install_bin} is on your PATH." >&2
  fi
}

echo "Zoekt installation script starting..."

if HAVE zoekt; then
  echo "[info] Zoekt is already installed"
else
  case "$OS" in
    Linux)
      if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
      fi
      if ! HAVE go; then
        if [[ "${ID:-}" == "debian" || "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" == *"debian"* || "${ID_LIKE:-}" == *"ubuntu"* ]]; then
          ensure_go_linux || true
        fi
      fi
      if HAVE go; then
        if confirm_zoekt_install "Go toolchain (build from source)"; then
          install_via_go || echo "[warn] Automatic Zoekt install failed" >&2
        else
          echo "[skip] Zoekt install (user declined)"
        fi
      else
        echo "[warn] Go is required to install Zoekt. Please install Go manually and re-run this script." >&2
      fi
      ;;
    Darwin)
      if ! HAVE go; then
        ensure_go_macos || true
      fi
      if HAVE go; then
        if confirm_zoekt_install "Go toolchain (build from source)"; then
          install_via_go || echo "[warn] Automatic Zoekt install failed" >&2
        else
          echo "[skip] Zoekt install (user declined)"
        fi
      else
        echo "[warn] Go is required to install Zoekt. Please install Go (e.g., via Homebrew or https://go.dev/dl/) and re-run this script." >&2
      fi
      ;;
    *)
      echo "[info] Unsupported OS for automatic Zoekt install: $OS"
      echo "[info] Please install Zoekt manually: https://github.com/google/zoekt"
      ;;
  esac
fi

echo "Zoekt installation script complete."
