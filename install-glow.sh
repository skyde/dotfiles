#!/usr/bin/env bash
set -euo pipefail

# Install glow (terminal markdown viewer) from Charm
# Uses Homebrew on macOS, GitHub releases on Linux

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

# Fallback prompt helpers if not sourced
_truthy() {
  case "${1:-}" in
    1 | true | TRUE | True | yes | YES | Yes | on | ON | On) return 0 ;;
    *) return 1 ;;
  esac
}

is_tty() { [ -t 0 ] && [ -t 1 ]; }

ask() {
  local prompt="$1"
  if ! is_tty; then
    echo "[skip] $prompt (non-interactive; default = no)"
    return 1
  fi
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" =~ ^([yY]|[yY][eE][sS])$ ]]
}

confirm_glow_install() {
  local method_msg="$1"
  if _truthy "${AUTO_INSTALL:-}"; then
    echo "[auto] Install glow via $method_msg (AUTO_INSTALL=1)"
    return 0
  fi
  ask "Install glow now via $method_msg?"
}

install_from_github() {
  # Install prebuilt glow binaries from GitHub releases
  local repo="charmbracelet/glow"
  local os_arch=""
  local uname_s="$(uname -s)"
  local uname_m="$(uname -m)"

  case "$uname_s" in
    Linux)
      case "$uname_m" in
        x86_64) os_arch="Linux_x86_64" ;;
        aarch64 | arm64) os_arch="Linux_arm64" ;;
        armv7l) os_arch="Linux_armv7" ;;
        *)
          echo "Unsupported Linux arch: $uname_m" >&2
          return 1
          ;;
      esac
      ;;
    Darwin)
      case "$uname_m" in
        x86_64) os_arch="Darwin_x86_64" ;;
        arm64) os_arch="Darwin_arm64" ;;
        *)
          echo "Unsupported macOS arch: $uname_m" >&2
          return 1
          ;;
      esac
      ;;
    *)
      echo "Unsupported OS: $uname_s" >&2
      return 1
      ;;
  esac

  local tag="${GLOW_VERSION:-}"
  if [ -z "$tag" ]; then
    # Fetch latest tag via GitHub API
    tag="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name"\s*:\s*"\([^"]\+\)".*/\1/p' | head -n1)"
  fi
  if [ -z "$tag" ] || [ "$tag" = "null" ]; then
    echo "Failed to determine latest glow release tag" >&2
    return 1
  fi

  # Remove 'v' prefix if present for archive naming
  local version="${tag#v}"

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  trap 'if [ -n "${tmp_dir:-}" ]; then rm -rf "${tmp_dir}"; fi' EXIT

  # Glow release archive naming: glow_VERSION_OS_ARCH.tar.gz
  local archive_url="https://github.com/${repo}/releases/download/${tag}/glow_${version}_${os_arch}.tar.gz"
  local archive="$tmp_dir/glow.tar.gz"

  echo "Downloading glow ${tag} for ${os_arch}..."
  if ! curl -fSL "$archive_url" -o "$archive"; then
    echo "Failed to download glow from $archive_url" >&2
    return 1
  fi

  # Extract
  mkdir -p "$tmp_dir/extract"
  tar -xzf "$archive" -C "$tmp_dir/extract"

  # Find glow binary
  local glow_bin
  glow_bin="$(find "$tmp_dir/extract" -type f -name glow -perm -u+x | head -n1 || true)"
  if [ -z "$glow_bin" ]; then
    # Try without execute permission check (some archives don't preserve perms)
    glow_bin="$(find "$tmp_dir/extract" -type f -name glow | head -n1 || true)"
  fi
  if [ -z "$glow_bin" ]; then
    echo "glow binary not found in archive" >&2
    return 1
  fi

  # Install to appropriate location
  local install_prefix="/usr/local"
  if [ "$OS" = "Darwin" ] && [ -w "/opt/homebrew/bin" ]; then
    install_prefix="/opt/homebrew"
  fi

  $SUDO_CMD install -m 0755 "$glow_bin" "${install_prefix}/bin/glow"

  if ! command -v glow >/dev/null 2>&1; then
    echo "Installed glow to ${install_prefix}/bin/glow"
    echo "You may need to add ${install_prefix}/bin to your PATH"
  else
    echo "glow installed successfully: $(glow --version 2>/dev/null || echo 'version unknown')"
  fi
}

echo "Glow installation script starting..."

case "$OS" in
  Linux)
    if HAVE glow; then
      echo "[info] glow is already installed: $(glow --version 2>/dev/null || echo '')"
      exit 0
    fi

    # Try apt first (available on Debian testing and newer)
    if HAVE apt-get; then
      # Check if glow is available in apt repos
      if apt-cache show glow >/dev/null 2>&1; then
        if confirm_glow_install "apt"; then
          $SUDO_CMD apt-get update -y
          $SUDO_CMD apt-get install -y glow
          if HAVE glow; then
            echo "glow installed successfully via apt"
            exit 0
          fi
        fi
      fi
    fi

    # Fallback to GitHub releases for Linux
    if ! HAVE glow; then
      if confirm_glow_install "GitHub prebuilt binary"; then
        install_from_github || echo "[warn] GitHub install failed; glow not installed" >&2
      else
        echo "[skip] glow install (user declined)"
      fi
    fi
    ;;
  Darwin)
    if HAVE glow; then
      echo "[info] glow is already installed: $(glow --version 2>/dev/null || echo '')"
      exit 0
    fi

    # On macOS, prefer Homebrew
    if HAVE brew; then
      if confirm_glow_install "Homebrew"; then
        brew install glow || echo "[warn] Homebrew install failed" >&2
      else
        echo "[skip] glow install (user declined)"
      fi
    else
      # Fallback to GitHub releases
      if confirm_glow_install "GitHub prebuilt binary (macOS)"; then
        install_from_github || echo "[warn] GitHub install failed; glow not installed" >&2
      else
        echo "[skip] glow install (user declined)"
      fi
    fi
    ;;
  *)
    echo "[info] Unsupported OS for automatic glow install: $OS"
    echo "[info] Please install glow manually from: https://github.com/charmbracelet/glow"
    ;;
esac

echo "Glow installation complete."
