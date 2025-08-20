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

# Function to stow all packages in a directory
stow_dir() {
    local dir="$1"
    shift
    [ -d "$dir" ] || return 0
    cd "$dir"
    local packages=(*/); packages=("${packages[@]%/}")
    [ -d "${packages[0]}" ] || { cd ..; return 0; }
    echo "📦 Installing $dir packages: ${packages[*]}"
    stow --target="$HOME" --verbose "$@" "${packages[@]}"
    cd ..
}

# Stow common packages (always)
stow_dir "common" "$@"

# Stow platform-specific packages
case "$(uname)" in
    Darwin)
        echo "🍎 macOS detected"
        stow_dir "mac" "$@"
        ;;
    Linux)
        echo "🐧 Linux detected"
        stow_dir "linux" "$@"
        ;;
    *)
        echo "ℹ️ Unknown platform - common packages only"
        ;;
esac

echo "✅ Stow operation completed"
