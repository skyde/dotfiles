#!/usr/bin/env bash
set -euo pipefail

# macOS-specific setup script
echo "🍎 Running macOS-specific setup..."

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper functions
source "${SCRIPT_DIR}/lib/run_ensure.sh"
source "${SCRIPT_DIR}/lib/cask_app_map.sh"

echo "Installing macOS-specific packages and apps..."

# Install macOS-specific shell enhancements
ensure_brew zsh-autosuggestions
ensure_brew zsh-syntax-highlighting

# Install macOS-specific apps via Homebrew casks
for cask in fluor hammerspoon alt-tab betterdisplay font-jetbrains-mono-nerd-font; do
    read -r app_path home_app_path < <(cask_app_paths "$cask")
    if { [ -n "$app_path" ] && [ -d "$app_path" ]; } || { [ -n "$home_app_path" ] && [ -d "$home_app_path" ]; }; then
        echo "Skipping $cask (app already present)"
    else
        ensure_cask "$cask"
    fi
done

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

# Disable system audio feedback
defaults write -g com.apple.sound.beep.volume -float 0
defaults write -g com.apple.sound.uiaudio.enabled -bool false
defaults write -g com.apple.sound.beep.feedback -bool false
echo "Disabled global audio bell. You may need to log out and back in for changes to take effect."

# Configure Dock auto-hide behavior
echo "Setting Dock auto-hide preferences..."
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.15
killall Dock || true

echo "✅ macOS-specific setup complete!"
