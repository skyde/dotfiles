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

stow_package() {
    local pkg="$1"
    shift
    [ -d "$pkg" ] || return 0
    echo "📦 Installing $pkg package"
    stow --target="$HOME" --verbose "$@" "$pkg"
}

# Stow common package (always)
stow_package common "$@"

# Stow platform-specific packages
case "$(uname)" in
    Darwin)
        echo "🍎 macOS detected"
        stow_package mac "$@"
        ;;
    Linux)
        echo "🐧 Linux detected"
        stow_package linux "$@"
        ;;
    *)
        echo "ℹ️ Unknown platform - common package only"
        ;;
esac

echo "✅ Stow operation completed"
