#!/usr/bin/env bash
set -euo pipefail

# Linux setup script
echo "🐧 Running Linux setup..."

# Use sudo only if not running as root
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper functions
source "${SCRIPT_DIR}/lib/run_ensure.sh"

# Read common apps from packages.txt
if [ -f "${SCRIPT_DIR}/packages.txt" ]; then
    COMMON_APPS=($(grep -v '^[[:space:]]*$' "${SCRIPT_DIR}/packages.txt" | grep -v '^[[:space:]]*#' | tr '\n' ' '))
else
    COMMON_APPS=()
fi

echo "Installing packages using apt..."

# Map package names from packages.txt to their apt package names when they differ
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
ensure_apt zsh-autosuggestions
ensure_apt zsh-syntax-highlighting
ensure_apt fonts-jetbrains-mono

if have zsh; then
    ZSH_PATH=$(command -v zsh)
    TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"
    if getent passwd "$TARGET_USER" >/dev/null 2>&1; then
        CURRENT_SHELL=$(getent passwd "$TARGET_USER" | cut -d: -f7)
        if [ -n "$CURRENT_SHELL" ] && [ "$CURRENT_SHELL" != "$ZSH_PATH" ]; then
            if confirm_change "Change default shell to $ZSH_PATH" "$TARGET_USER" 1; then
                $SUDO chsh -s "$ZSH_PATH" "$TARGET_USER" || true
            fi
        fi
    else
        echo "Skipping default shell change: user '$TARGET_USER' not found in /etc/passwd."
    fi
fi

echo "✅ Linux setup complete using apt!"
