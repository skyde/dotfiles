#!/bin/bash
# Simple dotfiles installer
set -e

echo "Installing dotfiles..."

# Use update.sh with --adopt to handle conflicts
./update.sh --adopt

# Install VS Code extensions
if command -v code >/dev/null 2>&1; then
    if [ -f "vscode_extensions.txt" ]; then
        echo "Installing VS Code extensions..."
        while read -r ext; do
            [ -n "$ext" ] && [[ ! "$ext" =~ ^[[:space:]]*# ]] && code --install-extension "$ext" --force >/dev/null 2>&1
        done < vscode_extensions.txt
        echo "✅ VS Code extensions processed"
    fi
fi

# Install common apps
read -p "Install common development tools? (y/N): " install_apps
if [[ "$install_apps" =~ ^[Yy] ]]; then
    case "$(uname)" in
        Darwin)
            if command -v brew >/dev/null 2>&1; then
                echo "Installing common apps..."
                brew install ripgrep fd fzf bat delta eza neovim tmux git lazygit
            else
                echo "Homebrew not found. Install it first: https://brew.sh"
            fi
            ;;
        Linux)
            if command -v apt >/dev/null 2>&1; then
                echo "Installing common apps..."
                sudo apt update && sudo apt install -y ripgrep fd-find fzf bat git neovim tmux
            fi
            ;;
    esac
fi

echo "Done! 🎉"