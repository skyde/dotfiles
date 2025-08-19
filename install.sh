#!/usr/bin/env bash
set -euo pipefail

# Load helpers
source "$(dirname "$0")/install_helpers.sh"
initialize_backup_dir

# ------------------------------
# Packages to stow
# ------------------------------

packages=(bash zsh tmux git kitty lazygit starship lf nvim vsvim visual_studio vimium_c)

case "$(uname -s)" in
  Darwin)
    packages+=(hammerspoon Code Code-mac)
    ;;
  Linux)
    packages+=(Code)
    ;;
  *)
    echo "Unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

for pkg in "${packages[@]}"; do
  restow_package "$pkg" "$HOME"
done

# ------------------------------
# Cross-OS bridges (reusable via data)
# ------------------------------

if [ "$(uname -s)" = Darwin ]; then
  mkdir -p "$HOME/.config/Code/User"
  mkdir -p "$HOME/Library/Application Support/Code/User"

  # Ensure source files exist so links are not broken
  ensure_file_exists "$HOME/.config/Code/User/settings.json"
  ensure_file_exists "$HOME/.config/Code/User/keybindings.json"
  ensure_file_exists "$HOME/.config/Code/User/tasks.json"

  declare -a mac_links=(
    "$HOME/.config/Code/User/settings.json::$HOME/Library/Application Support/Code/User/settings.json"
    "$HOME/.config/Code/User/keybindings.json::$HOME/Library/Application Support/Code/User/keybindings.json"
    "$HOME/.config/Code/User/tasks.json::$HOME/Library/Application Support/Code/User/tasks.json"
  )

  process_symlink_pairs "${mac_links[@]}"
fi
