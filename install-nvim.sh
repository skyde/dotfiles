#!/usr/bin/env bash
set -euo pipefail

# Install the latest Neovim release on Linux by downloading the official
# tarball from GitHub. Supports sudo/system installs and user-local
# installs when sudo is unavailable. Prompts before making changes unless
# AUTO_INSTALL=1.

HAVE() {
  command -v "$1" >/dev/null 2>&1
}

SUDO_CMD=""
if [ "$(id -u)" -ne 0 ] && HAVE sudo; then
  SUDO_CMD="sudo"
fi

OS_NAME="$(uname -s)"
if [ "$OS_NAME" != "Linux" ]; then
  echo "error: this installer currently supports Linux only (detected $OS_NAME)" >&2
  exit 1
fi

_truthy() {
  case "${1:-}" in
    1 | true | TRUE | True | yes | YES | Yes | on | ON | On) return 0 ;;
    *) return 1 ;;
  esac
}

is_tty() {
  [ -t 0 ] && [ -t 1 ]
}

ask() {
  local prompt="$1"
  if ! is_tty; then
    echo "[skip] $prompt (non-interactive; default = no)"
    return 1
  fi
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" =~ ^([yY]|[yY][eE][sS])$ ]]
}

confirm_nvim_install() {
  local msg="$1"
  if _truthy "${AUTO_INSTALL:-}"; then
    echo "[auto] $msg (AUTO_INSTALL=1)"
    return 0
  fi
  ask "$msg"
}

ensure_pkg_cmd() {
  local pkg="$1"
  local check_cmd="${2:-}"
  if [ -n "$check_cmd" ] && HAVE "$check_cmd"; then
    return 0
  fi
  if [ -n "$pkg" ] && dpkg -s "$pkg" >/dev/null 2>&1; then
    return 0
  fi
  if _truthy "${AUTO_INSTALL:-}"; then
    if [ -z "$SUDO_CMD" ] && [ "$(id -u)" -ne 0 ]; then
      echo "error: need $pkg but cannot escalate privileges" >&2
      return 1
    fi
    echo "[auto] Installing dependency $pkg"
    $SUDO_CMD apt-get update -y
    $SUDO_CMD apt-get install -y "$pkg"
    return 0
  fi
  if ask "Install dependency $pkg?"; then
    if [ -z "$SUDO_CMD" ] && [ "$(id -u)" -ne 0 ]; then
      echo "error: need $pkg but cannot escalate privileges" >&2
      return 1
    fi
    $SUDO_CMD apt-get update -y
    $SUDO_CMD apt-get install -y "$pkg"
  else
    echo "[skip] $pkg not installed"
    return 1
  fi
}

for dep in curl tar gzip; do
  if ! HAVE "$dep"; then
    ensure_pkg_cmd "$dep" "$dep" || exit 1
  fi
done

arch_suffix=""
case "$(uname -m)" in
  x86_64 | amd64)
    arch_suffix="linux64"
    ;;
  aarch64 | arm64)
    arch_suffix="linux-arm64"
    ;;
  *)
    echo "error: unsupported architecture $(uname -m)" >&2
    exit 1
    ;;
esac

latest_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/neovim/neovim/releases/latest || true)"
if [ -z "$latest_url" ]; then
  echo "error: unable to determine latest Neovim release" >&2
  exit 1
fi
latest_tag="${latest_url##*/}"
if [ -z "$latest_tag" ] || [ "$latest_tag" = "latest" ]; then
  echo "error: unexpected tag from $latest_url" >&2
  exit 1
fi

archive_name="nvim-${arch_suffix}.tar.gz"
download_url="https://github.com/neovim/neovim/releases/download/${latest_tag}/${archive_name}"

install_dir_default="${NVIM_INSTALL_DIR:-/opt/nvim}"
bin_dir_default="${NVIM_BIN_DIR:-/usr/local/bin}"
use_sudo="$SUDO_CMD"

if [ "$(id -u)" -ne 0 ] && [ -z "$use_sudo" ]; then
  install_dir_default="${NVIM_INSTALL_DIR:-$HOME/.local/nvim}"
  bin_dir_default="${NVIM_BIN_DIR:-$HOME/.local/bin}"
  echo "[info] sudo not available; using user-local install path at $install_dir_default"
fi

install_dir="$install_dir_default"
bin_dir="$bin_dir_default"

if ! confirm_nvim_install "Install Neovim ${latest_tag} to ${install_dir}?"; then
  echo "[skip] Installation aborted"
  exit 0
fi

archive_tmp=""
tmp_dir="$(mktemp -d)"
cleanup() {
  if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
    rm -rf "$tmp_dir"
  fi
}
trap cleanup EXIT

archive_tmp="$tmp_dir/${archive_name}"

printf 'Downloading %s...\n' "$download_url"
if ! curl -fL "$download_url" -o "$archive_tmp"; then
  echo "error: failed to download Neovim archive" >&2
  exit 1
fi

printf 'Extracting archive...\n'
if ! tar -C "$tmp_dir" -xzf "$archive_tmp"; then
  echo "error: failed to extract $archive_name" >&2
  exit 1
fi

extracted_dir="$tmp_dir/nvim-${arch_suffix}"
if [ ! -d "$extracted_dir" ]; then
  echo "error: extracted directory $extracted_dir not found" >&2
  exit 1
fi

if [ -n "$use_sudo" ]; then
  $use_sudo rm -rf "$install_dir"
  $use_sudo mkdir -p "$install_dir"
  $use_sudo cp -a "$extracted_dir/." "$install_dir/"
  $use_sudo mkdir -p "$bin_dir"
  $use_sudo ln -sfn "$install_dir/bin/nvim" "$bin_dir/nvim"
else
  rm -rf "$install_dir"
  mkdir -p "$install_dir"
  cp -a "$extracted_dir/." "$install_dir/"
  mkdir -p "$bin_dir"
  ln -sfn "$install_dir/bin/nvim" "$bin_dir/nvim"
fi

printf '\nNeovim %s installed to %s\n' "$latest_tag" "$install_dir"
printf 'Symlinked nvim to %s\n' "$bin_dir/nvim"

if ! command -v nvim >/dev/null 2>&1; then
  echo "[note] nvim is not currently on PATH. Ensure $bin_dir is added to your PATH." >&2
fi

printf '\nDone.\n'
