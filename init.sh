#!/bin/bash
# Simple dotfiles installer
set -e

echo "Installing dotfiles..."

# Use apply.sh with --adopt to handle conflicts
./apply.sh --adopt

# Install VS Code extensions
if command -v code >/dev/null 2>&1; then
    if [ -f "vscode_extensions.txt" ]; then
        if [ "${AUTO_INSTALL:-}" = "1" ]; then
            install_extensions="y"
        elif [ "${AUTO_INSTALL:-}" = "0" ]; then
            install_extensions="n"
        else
            read -r -p "Install VS Code extensions? (y/N): " install_extensions
        fi
        if [[ "$install_extensions" =~ ^[Yy] ]]; then
            echo "Installing VS Code extensions..."
            while read -r ext; do
                if [ -n "$ext" ] && [[ ! "$ext" =~ ^[[:space:]]*# ]]; then
                    echo "  Installing: $ext"
                    code --install-extension "$ext" --force >/dev/null 2>&1
                fi
            done < vscode_extensions.txt
            echo "✅ VS Code extensions installed"
        else
            echo "Skipping VS Code extensions"
        fi
    fi
else
    echo "VS Code not found, skipping extensions"
fi

# Install common apps
if [ "${AUTO_INSTALL:-}" = "1" ]; then
    install_apps="y"
elif [ "${AUTO_INSTALL:-}" = "0" ]; then
    install_apps="n"
else
    read -r -p "Install common development tools? (y/N): " install_apps
fi
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