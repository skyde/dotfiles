#!/usr/bin/env bash
set -euo pipefail

packages=(bash zsh tmux git kitty lazygit starship lf nvim vsvim visual_studio vimium_c)

case "$(uname -s)" in
  Darwin)
    packages+=(hammerspoon Code-mac)
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
  if [ -d "$pkg" ]; then
    stow --restow --target="$HOME" "$pkg"
  fi
done
