#!/usr/bin/env bash
set -euo pipefail

# Linux-specific setup script
echo "🐧 Running Linux-specific setup..."

# Use sudo only if not running as root
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper functions
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/run_ensure.sh"

nvim_apt_packages=(build-essential cmake curl file ninja-build nodejs npm python3 python3-venv unzip)
dependency_test=${DOTFILES_INIT_LINUX_DEPENDENCY_TEST:-0}
if [[ $dependency_test == 1 ]]; then
  : "${DOTFILES_INIT_LINUX_DEPENDENCY_LOG:?set DOTFILES_INIT_LINUX_DEPENDENCY_LOG in dependency-test mode}"
  ensure_apt() {
    printf '%s\n' "$1" >>"$DOTFILES_INIT_LINUX_DEPENDENCY_LOG"
  }
fi

echo "Installing Linux-specific packages..."

# Install zsh shell enhancements and fonts not in packages.txt
if [[ $dependency_test != 1 ]]; then
  ensure_apt zsh
  ensure_apt zsh-autosuggestions
  ensure_apt zsh-syntax-highlighting
  ensure_apt fonts-jetbrains-mono
fi

# Runtime dependencies for the Neovim language, formatter, debugger, and AI
# tooling enabled by the common configuration.
for package in "${nvim_apt_packages[@]}"; do
  ensure_apt "$package"
done

if [[ $dependency_test == 1 ]]; then
  echo "✅ Linux Neovim dependency test complete!"
  exit 0
fi

# Install kitty term info to ensure we can ssh properly
$SUDO curl -LO https://raw.githubusercontent.com/kovidgoyal/kitty/master/terminfo/kitty.terminfo
tic -x -o ~/.terminfo kitty.terminfo
rm -f kitty.terminfo

# Change default shell to zsh
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

echo "✅ Linux-specific setup complete!"
