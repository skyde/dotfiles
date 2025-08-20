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

# Install VS Code extensions if VS Code is available
if command -v code >/dev/null 2>&1; then
    echo "Installing VS Code extensions..."
    if [ -f "vscode_extensions.txt" ]; then
        while read -r ext; do
            [ -n "$ext" ] && code --install-extension "$ext" --force
        done < vscode_extensions.txt
    fi
fi

# Install common apps (optional)
# Set INSTALL_APPS=1 to auto-install, or INSTALL_APPS=0 to skip
if [ -n "${INSTALL_APPS:-}" ]; then
    install_apps="$INSTALL_APPS"
else
    echo ""
    read -p "Install common development tools? (y/N): " install_apps
fi

if [[ "$install_apps" =~ ^[Yy1] ]]; then
    case "$(uname)" in
        Darwin)
            if command -v brew >/dev/null 2>&1; then
                echo "Installing common apps via Homebrew..."
                brew install ripgrep fd fzf bat delta eza neovim tmux git lazygit
            else
                echo "Homebrew not found. Install it first: https://brew.sh"
            fi
            ;;
        Linux)
            if command -v apt >/dev/null 2>&1; then
                echo "Installing common apps via apt..."
                sudo apt update && sudo apt install -y ripgrep fd-find fzf bat git neovim tmux
            else
                echo "Please install common tools manually"
            fi
            ;;
    esac
fi

echo "Done! Dotfiles installed with automation."
