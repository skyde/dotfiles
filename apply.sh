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
    stow --target="$HOME" --verbose=1 "$@" "$pkg"

    # Check only the directories that this package actually affects
    # Skip problematic directories like Library which can have massive cache data
    if [ -d "$pkg" ]; then
        echo "🔍 Checking stowed files for $pkg package..."
        for item in "$pkg"/*; do
            if [ -e "$item" ]; then
                item_name=$(basename "$item")
                target_path="$HOME/$item_name"
                
                # Skip Library and other problematic directories
                case "$item_name" in
                    Library|Caches|Cache|.cache)
                        echo "  Skipping $item_name (too large/problematic)"
                        continue
                        ;;
                esac
                
                if [ -e "$target_path" ]; then
                    echo "  Checking $target_path..."
                    # Only run chkstow on directories, files are handled by the directory check
                    if [ -d "$target_path" ]; then
                        # Broken symlinks
                        chkstow --badlinks -t "$target_path" 2>/dev/null || true
                        # Non-symlink "alien" files (things Stow doesn't manage) in the target
                        chkstow --aliens -t "$target_path" 2>/dev/null | head -20 || true
                        # What package owns each link
                        chkstow --list -t "$target_path" 2>/dev/null | head -10 || true
                    fi
                fi
            fi
        done
    fi
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
        # Linux uses common package for VS Code (already stowed above)
        ;;
    MINGW*|MSYS*|CYGWIN*)
        echo "🪟 Windows detected"
        stow_package windows "$@"
        ;;
    *)
        echo "ℹ️ Unknown platform - common package only"
        ;;
esac

echo "✅ Stow operation completed"
