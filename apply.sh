#!/bin/bash
# Stow wrapper for dotfiles management
set -e

# Install stow if needed
if ! command -v stow >/dev/null; then
    echo "Installing stow..."
    case "$(uname)" in
        Darwin) brew install stow ;;
        Linux) sudo apt install stow ;;
    esac
fi

# Go to dotfiles directory
cd "$(dirname "$0")/dotfiles"

# Pass all arguments directly to stow with sensible defaults
stow --target="$HOME" --verbose "$@" -- */

echo "✅ Stow operation completed"
