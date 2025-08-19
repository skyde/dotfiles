#!/usr/bin/env bash
set -euo pipefail

# macOS setup: installs common tools via Homebrew and configures system defaults

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$repo_dir/lib/run_ensure.sh"

# Load app list
mapfile -t COMMON_APPS < <(grep -v '^[[:space:]]*$' "$repo_dir/common_apps.txt")

echo "Running macOS setup using Homebrew..."

if ! have brew; then
  if ask "Install Homebrew?"; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    echo "Homebrew not installed; skipping package install."; exit 0
  fi
fi

if [[ $(uname -m) == "arm64" ]]; then
  # Ensure brew is on PATH in future shells
  if ! grep -q "/opt/homebrew/bin/brew shellenv" "$HOME/.zprofile" 2>/dev/null; then
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
  fi
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

brew update || true

for pkg in "${COMMON_APPS[@]}"; do
  ensure_brew "$pkg"
done

ensure_brew zsh-autosuggestions
ensure_brew zsh-syntax-highlighting

# Useful casks (skip if app already present)
for cask in fluor hammerspoon alt-tab betterdisplay font-jetbrains-mono-nerd-font; do
  ensure_cask "$cask"
done

# fd sometimes needs relinking if keg-only
if brew list fd >/dev/null 2>&1 && ! brew list --formula | grep -q "^fd$"; then
  if confirm_change "Link" "fd" 1; then
    brew link --overwrite fd || echo "Failed to link fd, continuing..."
  fi
fi

echo "Setting macOS key repeat defaults..."
defaults write -g ApplePressAndHoldEnabled -bool false || true
defaults write -g InitialKeyRepeat -int 15 || true
defaults write -g KeyRepeat -int 2 || true
defaults write -g com.apple.sound.beep.volume -float 0 || true
defaults write -g com.apple.sound.uiaudio.enabled -bool false || true
defaults write -g com.apple.sound.beep.feedback -bool false || true

echo "Setting Dock auto-hide preferences..."
defaults write com.apple.dock autohide -bool true || true
defaults write com.apple.dock autohide-delay -float 0 || true
defaults write com.apple.dock autohide-time-modifier -float 0.15 || true
killall Dock || true

echo "macOS setup complete."
