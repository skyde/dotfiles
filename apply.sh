#!/bin/bash
# Stow wrapper for dotfiles management
set -e

# Parse arguments to detect dry-run mode
DRY_RUN=false
ARGS=("$@")  # Pass through all arguments

for arg in "$@"; do
    case $arg in
        --no-act|--no|--simulate|-n)
            DRY_RUN=true
            ;;
    esac
done

# Install stow if needed
if ! command -v stow >/dev/null; then
# Check for dotfiles-local and run its apply script if present
if [ -x "$HOME/dotfiles-local/apply.sh" ]; then
    echo "🔗 Found dotfiles-local, applying..."
    "$HOME/dotfiles-local/apply.sh" "${ARGS[@]}"
fi

    if $DRY_RUN; then
        echo "[DRY RUN] Would install stow"
    else
        echo "Installing stow..."
        case "$(uname)" in
            Darwin) brew install stow ;;
            Linux) sudo apt install stow ;;
        esac
    fi
fi

# Go to script directory
cd "$(dirname "$0")"

stow_package() {
    local pkg="$1"
    shift
    [ -d "$pkg" ] || return 0
    echo "📦 Installing $pkg package"

    # Pre-create directories safely (never remove or replace existing paths)
    if [ -d "$pkg" ]; then
        echo "  Ensuring directories exist for $pkg..."
        find "$pkg" -type d -mindepth 1 | sort | while read -r dir; do
            rel_path="${dir#$pkg/}"
            target_path="$HOME/$rel_path"

            # If anything already exists at the target path (dir, file, or symlink),
            # do nothing.
            if [ -e "$target_path" ] || [ -L "$target_path" ]; then
                continue
            fi

            if $DRY_RUN; then
                echo "  [DRY RUN] Would create directory $target_path"
            else
                mkdir -p -- "$target_path"
            fi
        done
    fi

    # Use restow to handle any conflicts or missing symlinks
    stow --target="$HOME" --verbose=1 "${ARGS[@]}" "$pkg"

    # Skip verification in dry-run mode
# Check for dotfiles-local and run its apply script if present
if [ -x "$HOME/dotfiles-local/apply.sh" ]; then
    echo "🔗 Found dotfiles-local, applying..."
    "$HOME/dotfiles-local/apply.sh" "${ARGS[@]}"
fi

    if $DRY_RUN; then
        echo "  [DRY RUN] Skipping verification"
        return 0
    fi

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
stow_package common

# Stow platform-specific packages
case "$(uname)" in
    Darwin)
        echo "🍎 macOS detected"
        stow_package mac
        ;;
    Linux)
        echo "🐧 Linux detected"
        # Linux uses common package for VS Code (already stowed above)
        ;;
    MINGW*|MSYS*|CYGWIN*)
        echo "🪟 Windows detected"
        stow_package windows
        ;;
    *)
        echo "ℹ️ Unknown platform - common package only"
        ;;
esac

# Check for dotfiles-local and run its apply script if present
if [ -x "$HOME/dotfiles-local/apply.sh" ]; then
    echo "🔗 Found dotfiles-local, applying..."
    "$HOME/dotfiles-local/apply.sh" "${ARGS[@]}"
fi

if $DRY_RUN; then
    echo "✅ Dry run completed - no changes were made"
else
    echo "✅ Stow operation completed"
fi
