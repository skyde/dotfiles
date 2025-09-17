#!/usr/bin/env bash
set -euo pipefail

# Install Zoekt command-line tools if they are missing.

REQUIRED_GO_VERSION="1.23.4"

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

normalize_version_triplet() {
  local version="${1#go}"
  if [[ "$version" == devel* ]]; then
    echo "999 0 0"
    return 0
  fi
  local major minor patch
  IFS='.' read -r major minor patch <<<"$version"
  major="${major//[^0-9]/}"
  minor="${minor//[^0-9]/}"
  patch="${patch//[^0-9]/}"
  [ -n "$major" ] || major=0
  [ -n "$minor" ] || minor=0
  [ -n "$patch" ] || patch=0
  echo "$major $minor $patch"
}

version_ge() {
  local left right
  left=( $(normalize_version_triplet "$1") )
  right=( $(normalize_version_triplet "$2") )
  if [ "${#left[@]}" -ne 3 ] || [ "${#right[@]}" -ne 3 ]; then
    return 1
  fi
  for idx in 0 1 2; do
    if [ "${left[$idx]}" -gt "${right[$idx]}" ]; then
      return 0
    fi
    if [ "${left[$idx]}" -lt "${right[$idx]}" ]; then
      return 1
    fi
  done
  return 0
}

current_go_version() {
  if ! HAVE go; then
    return 1
  fi
  local version
  version="$(go env GOVERSION 2>/dev/null || true)"
  if [ -z "$version" ]; then
    version="$(go version 2>/dev/null | awk '{print $3}')"
  fi
  if [ -n "$version" ]; then
    echo "$version"
    return 0
  fi
  return 1
}

go_version_at_least() {
  local required="$1"
  local current
  current="$(current_go_version 2>/dev/null || true)"
  if [ -z "$current" ]; then
    return 1
  fi
  version_ge "$current" "$required"
}

install_go_tarball_linux() {
  local version="$1"
  local arch
  case "$(uname -m)" in
    x86_64 | amd64)
      arch="amd64"
      ;;
    aarch64 | arm64)
      arch="arm64"
      ;;
    *)
      echo "[warn] Unsupported architecture $(uname -m) for automatic Go install" >&2
      return 1
      ;;
  esac

  local filename="go${version}.linux-${arch}.tar.gz"
  local url="https://go.dev/dl/${filename}"
  local tmp_dir="$(mktemp -d)"
  local archive_path="${tmp_dir}/${filename}"
  local use_curl=0
  local use_wget=0

  if HAVE curl; then
    use_curl=1
  elif HAVE wget; then
    use_wget=1
  else
    if declare -F ensure_apt >/dev/null 2>&1; then
      ensure_apt curl || ensure_apt wget || true
    elif HAVE apt-get; then
      ensure_pkg_cmd curl curl || ensure_pkg_cmd wget wget || true
    fi
    if HAVE curl; then
      use_curl=1
    elif HAVE wget; then
      use_wget=1
    fi
  fi

  if [ "$use_curl" -eq 0 ] && [ "$use_wget" -eq 0 ]; then
    echo "[warn] Neither curl nor wget is available to download Go" >&2
    rm -rf "$tmp_dir"
    return 1
  fi

  echo "[info] Downloading Go ${version} from ${url}"
  if [ "$use_curl" -eq 1 ]; then
    if ! curl -fsSL "$url" -o "$archive_path"; then
      echo "[warn] Failed to download Go toolchain from ${url}" >&2
      rm -rf "$tmp_dir"
      return 1
    fi
  else
    if ! wget -qO "$archive_path" "$url"; then
      echo "[warn] Failed to download Go toolchain from ${url}" >&2
      rm -rf "$tmp_dir"
      return 1
    fi
  fi

  echo "[info] Installing Go ${version} to /usr/local/go"
  if ! $SUDO_CMD rm -rf /usr/local/go; then
    echo "[warn] Failed to remove existing /usr/local/go" >&2
    rm -rf "$tmp_dir"
    return 1
  fi
  if ! $SUDO_CMD tar -C /usr/local -xzf "$archive_path"; then
    echo "[warn] Failed to extract Go toolchain" >&2
    rm -rf "$tmp_dir"
    return 1
  fi
  if ! $SUDO_CMD install -d -m 0755 /usr/local/bin; then
    echo "[warn] Failed to ensure /usr/local/bin exists" >&2
    rm -rf "$tmp_dir"
    return 1
  fi

  local bin_file
  for bin_file in /usr/local/go/bin/*; do
    if [ -f "$bin_file" ]; then
      if ! $SUDO_CMD ln -sf "$bin_file" "/usr/local/bin/$(basename "$bin_file")"; then
        echo "[warn] Failed to link $(basename "$bin_file") into /usr/local/bin" >&2
      fi
    fi
  done

  rm -rf "$tmp_dir"
  hash -r 2>/dev/null || true

  return 0
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
  if HAVE go && go_version_at_least "$REQUIRED_GO_VERSION"; then
    return 0
  fi

  if declare -F ensure_apt >/dev/null 2>&1; then
    ensure_apt golang-go || true
  else
    ensure_pkg_cmd golang-go go
  fi

  if HAVE go && go_version_at_least "$REQUIRED_GO_VERSION"; then
    return 0
  fi

  if install_go_tarball_linux "$REQUIRED_GO_VERSION"; then
    if HAVE go && go_version_at_least "$REQUIRED_GO_VERSION"; then
      return 0
    fi
  fi

  echo "[warn] Unable to install Go ${REQUIRED_GO_VERSION} automatically" >&2
  return 1
}

ensure_go_macos() {
  if HAVE go && go_version_at_least "$REQUIRED_GO_VERSION"; then
    return 0
  fi

  if HAVE brew; then
    if declare -F ensure_brew >/dev/null 2>&1; then
      ensure_brew go
    else
      if _truthy "${AUTO_INSTALL:-}"; then
        echo "[auto] Install or upgrade Go via Homebrew (AUTO_INSTALL=1)"
        brew install go || brew upgrade go || true
      elif ask "Install or upgrade Go via Homebrew?"; then
        brew install go || brew upgrade go || true
      else
        echo "[skip] Go install via Homebrew declined"
      fi
    fi
  fi

  if HAVE go && go_version_at_least "$REQUIRED_GO_VERSION"; then
    return 0
  fi

  echo "[warn] Go ${REQUIRED_GO_VERSION}+ is required; please install it manually." >&2
  return 1
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

  local packages=(
    github.com/sourcegraph/zoekt/cmd/zoekt
    github.com/sourcegraph/zoekt/cmd/zoekt-archive-index
    github.com/sourcegraph/zoekt/cmd/zoekt-dynamic-indexserver
    github.com/sourcegraph/zoekt/cmd/zoekt-git-clone
    github.com/sourcegraph/zoekt/cmd/zoekt-git-index
    github.com/sourcegraph/zoekt/cmd/zoekt-index
    github.com/sourcegraph/zoekt/cmd/zoekt-indexserver
    github.com/sourcegraph/zoekt/cmd/zoekt-merge-index
    github.com/sourcegraph/zoekt/cmd/zoekt-mirror-bitbucket-server
    github.com/sourcegraph/zoekt/cmd/zoekt-mirror-gerrit
    github.com/sourcegraph/zoekt/cmd/zoekt-mirror-gitea
    github.com/sourcegraph/zoekt/cmd/zoekt-mirror-github
    github.com/sourcegraph/zoekt/cmd/zoekt-mirror-gitiles
    github.com/sourcegraph/zoekt/cmd/zoekt-mirror-gitlab
    github.com/sourcegraph/zoekt/cmd/zoekt-repo-index
    github.com/sourcegraph/zoekt/cmd/zoekt-sourcegraph-indexserver
    github.com/sourcegraph/zoekt/cmd/zoekt-test
    github.com/sourcegraph/zoekt/cmd/zoekt-webserver
  )

  local pkg
  local any_installed=0
  local had_fail=0

  echo "[info] Building Zoekt binaries from github.com/sourcegraph/zoekt"
  for pkg in "${packages[@]}"; do
    echo "[info]   go install ${pkg}@latest"
    if GO111MODULE=on GOTOOLCHAIN=auto GOBIN="$build_bin" go install "${pkg}@latest"; then
      any_installed=1
    else
      echo "[warn] go install failed for ${pkg}" >&2
      had_fail=1
    fi
  done

  if [ "$any_installed" -eq 0 ]; then
    echo "[warn] go install failed; Zoekt was not installed" >&2
    return 1
  fi

  if [ "$had_fail" -eq 1 ]; then
    echo "[warn] Some Zoekt binaries failed to build; proceeding with available commands" >&2
  fi

  local install_prefix="/usr/local"
  if [ "$OS" = "Darwin" ] && [ -d "/opt/homebrew/bin" ]; then
    install_prefix="/opt/homebrew"
  fi
  local install_bin="${install_prefix}/bin"

  local copied=0
  local bin_path
  if ! install -d -m 0755 "$install_bin" 2>/dev/null; then
    if [ -n "$SUDO_CMD" ]; then
      if ! $SUDO_CMD install -d -m 0755 "$install_bin"; then
        echo "[warn] Failed to create install directory $install_bin" >&2
        return 1
      fi
    else
      echo "[warn] Unable to create install directory $install_bin" >&2
      return 1
    fi
  fi
  for bin_path in "$build_bin"/*; do
    if [ -f "$bin_path" ]; then
      local dest="$install_bin/$(basename "$bin_path")"
      if install -m 0755 "$bin_path" "$dest" 2>/dev/null; then
        copied=1
        continue
      fi
      if [ -n "$SUDO_CMD" ]; then
        if $SUDO_CMD install -m 0755 "$bin_path" "$dest"; then
          copied=1
          continue
        fi
      fi
      echo "[warn] Failed to install $(basename "$bin_path") into $install_bin" >&2
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
      if ! go_version_at_least "$REQUIRED_GO_VERSION"; then
        if [[ "${ID:-}" == "debian" || "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" == *"debian"* || "${ID_LIKE:-}" == *"ubuntu"* ]]; then
          ensure_go_linux || true
        else
          install_go_tarball_linux "$REQUIRED_GO_VERSION" || true
        fi
      fi
      if go_version_at_least "$REQUIRED_GO_VERSION"; then
        if confirm_zoekt_install "Go toolchain (build from source)"; then
          install_via_go || echo "[warn] Automatic Zoekt install failed" >&2
        else
          echo "[skip] Zoekt install (user declined)"
        fi
      else
        echo "[warn] Go ${REQUIRED_GO_VERSION}+ is required to install Zoekt. Please install Go manually and re-run this script." >&2
      fi
      ;;
    Darwin)
      if ! go_version_at_least "$REQUIRED_GO_VERSION"; then
        ensure_go_macos || true
      fi
      if go_version_at_least "$REQUIRED_GO_VERSION"; then
        if confirm_zoekt_install "Go toolchain (build from source)"; then
          install_via_go || echo "[warn] Automatic Zoekt install failed" >&2
        else
          echo "[skip] Zoekt install (user declined)"
        fi
      else
        echo "[warn] Go ${REQUIRED_GO_VERSION}+ is required to install Zoekt. Please install Go (e.g., via Homebrew or https://go.dev/dl/) and re-run this script." >&2
      fi
      ;;
    *)
      echo "[info] Unsupported OS for automatic Zoekt install: $OS"
      echo "[info] Please install Zoekt manually: https://github.com/sourcegraph/zoekt"
      ;;
  esac
fi

echo "Zoekt installation script complete."
