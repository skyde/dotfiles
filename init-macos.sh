#!/usr/bin/env bash
set -euo pipefail

# macOS-specific setup script
echo "🍎 Running macOS-specific setup..."

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper functions
source "${SCRIPT_DIR}/lib/run_ensure.sh"

echo "Installing macOS-specific packages and apps..."

# Install macOS-specific shell enhancements
ensure_brew zsh-autosuggestions
ensure_brew zsh-fast-syntax-highlighting

# Install macOS-specific apps via Homebrew casks
for cask in fluor hammerspoon alt-tab betterdisplay kitty font-jetbrains-mono-nerd-font; do
    read -r app_path home_app_path < <(cask_app_paths "$cask")
    if { [ -n "$app_path" ] && [ -d "$app_path" ]; } || { [ -n "$home_app_path" ] && [ -d "$home_app_path" ]; }; then
        echo "Skipping $cask (app already present)"
    else
        ensure_cask "$cask"
    fi
done

# Verify JetBrainsMono Nerd Font is installed in user Fonts directory
if [ -d "$HOME/Library/Fonts" ]; then
    if ! ls -1 "$HOME/Library/Fonts" 2>/dev/null | grep -qi "^JetBrainsMono.*Nerd\s*Font.*\.(ttf\|otf)$"; then
        echo "[warn] JetBrainsMono Nerd Font not detected in ~/Library/Fonts. If VS Code doesn't show the font, try re-running this script or manually running: brew install --cask font-jetbrains-mono-nerd-font" >&2
    fi
fi

# Fix fd linking issue on macOS if needed
if have brew && brew list fd >/dev/null 2>&1 && ! brew list --formula | grep -q "^fd$"; then
  if confirm_change "Link" "fd" 1; then
    brew link --overwrite fd || echo "Failed to link fd, continuing..."
  fi
fi

echo "Configuring macOS system preferences..."

# Configure key repeat behavior for Vim and general usage
echo "Setting macOS key repeat defaults..."
defaults write -g ApplePressAndHoldEnabled -bool false
# Shorter delay before key repeat starts (default is 68)
defaults write -g InitialKeyRepeat -int 15
# Faster repeat rate (default is 6)
defaults write -g KeyRepeat -int 2
echo "Key repeat settings applied. You may need to log out and back in for changes to take effect."

# Scroll direction: invert (disable Apple's 'natural' scrolling)
echo "Setting scroll direction (inverted; natural scrolling OFF)..."
defaults write -g com.apple.swipescrolldirection -bool false
echo "Scroll direction set to inverted. You may need to log out and back in for changes to take full effect."

# Disable system audio feedback
defaults write -g com.apple.sound.beep.volume -float 0
defaults write -g com.apple.sound.uiaudio.enabled -bool false
defaults write -g com.apple.sound.beep.feedback -bool false
echo "Disabled global audio bell. You may need to log out and back in for changes to take effect."

# Show hidden files in Finder
defaults write com.apple.finder AppleShowAllFiles -bool true
# Restart Finder; ignore error/no-op if Finder isn't running
killall Finder >/dev/null 2>&1 || true

# Configure Dock auto-hide behavior
echo "Setting Dock auto-hide preferences..."
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.15
killall Dock || true

# lazygit on macOS reads ~/Library/Application Support/lazygit/config.yml —
# not the stowed ~/.config/lazygit/config.yml — unless XDG_CONFIG_HOME is
# exported, which these dotfiles do not do. Link the Apple location to the
# stowed file so both resolve to the same config; otherwise a stale copy
# there keeps rendering with settings the repo no longer has, and nothing
# committed to the repo appears to change anything.
LAZYGIT_APP_SUPPORT="$HOME/Library/Application Support/lazygit"
mkdir -p "$LAZYGIT_APP_SUPPORT"
ln -sf "$HOME/.config/lazygit/config.yml" "$LAZYGIT_APP_SUPPORT/config.yml"
echo "Linked lazygit's Application Support config to ~/.config/lazygit/config.yml"

echo "✅ macOS-specific setup complete!"
