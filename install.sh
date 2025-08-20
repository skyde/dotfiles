#!/bin/bash
# Ultra-simple dotfiles installer
set -e

echo "Installing dotfiles..."

# Install stow if needed
if ! command -v stow >/dev/null; then
    echo "Please install stow first:"
    echo "  macOS: brew install stow"
    echo "  Linux: sudo apt install stow"
    exit 1
fi

# Go to dotfiles directory
cd "$(dirname "$0")/dotfiles"

# Install common configs
cd common
for pkg in */; do
    echo "Installing ${pkg%/}..."
    stow --target="$HOME" "${pkg%/}" || echo "Warning: ${pkg%/} may already exist"
done

# Install platform-specific configs
cd ..
case "$(uname)" in
    Darwin) cd mac && stow --target="$HOME" */ 2>/dev/null || true ;;
    Linux)  echo "Linux-specific configs would go here" ;;
esac

echo "Done! Dotfiles installed."
