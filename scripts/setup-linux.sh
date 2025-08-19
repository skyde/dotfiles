#!/usr/bin/env bash
set -euo pipefail

# Linux setup: installs common tools via apt and sets zsh default if available

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$repo_dir/lib/run_ensure.sh"

# Load app list
mapfile -t COMMON_APPS < <(grep -v '^[[:space:]]*$' "$repo_dir/common_apps.txt")

SUDO=""
if [ "$(id -u)" -ne 0 ] && have sudo; then SUDO="sudo"; fi

if [ -r /etc/os-release ]; then . /etc/os-release; fi

if [ "${ID:-}" = "debian" ] || [ "${ID_LIKE:-}" = "debian" ] || command -v apt-get >/dev/null 2>&1; then
  echo "Installing packages using apt..."
  declare -A APT_PACKAGE_MAP=(
    [fd]=fd-find
    [delta]=git-delta
    [nvim]=neovim
  )
  for pkg in "${COMMON_APPS[@]}"; do
    apt_pkg="${APT_PACKAGE_MAP[$pkg]:-$pkg}"
    if apt-cache show "$apt_pkg" >/dev/null 2>&1; then
      ensure_apt "$apt_pkg"
    else
      echo "Skipping unavailable package: $apt_pkg"
    fi
  done
  ensure_apt zsh
  ensure_apt zsh-autosuggestions || true
  ensure_apt zsh-syntax-highlighting || true
  ensure_apt fonts-jetbrains-mono || true

  if have zsh; then
    ZSH_PATH=$(command -v zsh)
    TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"
    CURRENT_SHELL=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f7 || true)
    if [ -n "$CURRENT_SHELL" ] && [ "$CURRENT_SHELL" != "$ZSH_PATH" ]; then
      if confirm_change "Change default shell to $ZSH_PATH" "$TARGET_USER" 1; then
        $SUDO chsh -s "$ZSH_PATH" "$TARGET_USER" || true
      fi
    fi
  fi
else
  echo "Non-apt distro detected; extend setup-linux.sh as needed."
fi

echo "Linux setup complete."
