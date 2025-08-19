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
    packages+=(hammerspoon Code)
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

  # Link the entire VS Code User directory to avoid per-file special casing
  process_symlink_pairs \
    "$HOME/.config/Code/User::$HOME/Library/Application Support/Code/User"
fi
