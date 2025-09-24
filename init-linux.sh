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
source "${SCRIPT_DIR}/lib/run_ensure.sh"

echo "Installing Linux-specific packages..."

# Install zsh shell enhancements and fonts not in packages.txt
ensure_apt zsh
ensure_apt zsh-autosuggestions
ensure_apt zsh-syntax-highlighting
ensure_apt fonts-jetbrains-mono

# Install kitty term info to ensure we can ssh properly
curl -LO https://raw.githubusercontent.com/kovidgoyal/kitty/master/terminfo/kitty.terminfo tic -x -o ~/.terminfo kitty.terminfo

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
