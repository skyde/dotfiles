#!/usr/bin/env bash
set -euo pipefail

# Simple dotfiles installer using stow
# Much simpler than the complex install.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=${DRY_RUN:-0}

echo "=== Installing dotfiles with stow ==="

# Check if stow is installed
if ! command -v stow >/dev/null 2>&1; then
    echo "Error: GNU Stow is not installed."
    echo "Install it with:"
    echo "  macOS: brew install stow"
    echo "  Linux: sudo apt install stow"
    echo "  Windows: winget install stefansundin.gnu-stow"
    exit 1
fi

# Function to stow packages from a directory
stow_packages() {
    local dir="$1"
    local target="${2:-$HOME}"
    
    if [[ ! -d "$dir" ]]; then
        echo "Directory $dir not found, skipping"
        return 0
    fi
    
    echo "Installing packages from $dir..."
    cd "$dir"
    
    for package in */; do
        package=${package%/}  # Remove trailing slash
        echo "  Installing $package"
        
        if [[ "$DRY_RUN" == "1" ]]; then
            echo "    DRY_RUN: stow --target=\"$target\" \"$package\""
        else
            stow --target="$target" "$package" || {
                echo "    Warning: Failed to stow $package (may already exist)"
            }
        fi
    done
    
    cd "$SCRIPT_DIR"
}

# Install common packages (all platforms)
stow_packages "$SCRIPT_DIR/dotfiles/common"

# Install platform-specific packages
case "$(uname -s)" in
    Darwin)
        echo "Detected macOS"
        stow_packages "$SCRIPT_DIR/dotfiles/mac"
        
        # Create macOS-specific VS Code symlink
        if [[ "$DRY_RUN" == "1" ]]; then
            echo "DRY_RUN: Would create VS Code symlinks for macOS"
        else
            mkdir -p "$HOME/Library/Application Support/Code/User"
            if [[ -d "$HOME/.config/Code/User" && ! -L "$HOME/Library/Application Support/Code/User" ]]; then
                rm -rf "$HOME/Library/Application Support/Code/User"
                ln -sf "$HOME/.config/Code/User" "$HOME/Library/Application Support/Code/User"
                echo "Created VS Code symlink for macOS"
            fi
        fi
        ;;
    Linux)
        echo "Detected Linux"
        stow_packages "$SCRIPT_DIR/dotfiles/linux"
        ;;
    *)
        echo "Unsupported OS: $(uname -s)"
        exit 1
        ;;
esac

echo "=== Installation complete! ==="
echo "Tip: Use 'DRY_RUN=1 $0' to preview changes"
