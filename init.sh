#!/bin/bash
# Simple dotfiles installer
set -e

# Function to get user confirmation with auto-install support
get_user_confirmation() {
    local prompt="$1"
    local response
    
    if [ "${AUTO_INSTALL:-}" = "1" ]; then
        response="y"
    elif [ "${AUTO_INSTALL:-}" = "0" ]; then
        response="n"
    else
        read -r -p "$prompt" response
    fi
    
    echo "$response"
}

echo "Installing dotfiles..."

# Use apply.sh with --adopt to handle conflicts
./apply.sh --adopt

# Install packages
packages="ripgrep fzf bat git neovim tmux delta eza lazygit"

# Add platform-specific fd package
case "$(uname)" in
    Darwin) packages="$packages fd" ;;
    Linux) packages="$packages fd-find" ;;  # Note: binary is called 'fdfind' on Debian/Ubuntu
esac

install_apps=$(get_user_confirmation "Install packages ($packages)? (y/N): ")
if [[ "$install_apps" =~ ^[Yy] ]]; then
    case "$(uname)" in
        Darwin)
            if command -v brew >/dev/null 2>&1; then
                echo "Installing packages..."
                brew install $packages
            else
                echo "Homebrew not found. Install it first: https://brew.sh"
            fi
            ;;
        Linux)
            if command -v apt >/dev/null 2>&1; then
                echo "Installing packages..."
                sudo apt update && sudo apt install -y $packages
            fi
            ;;
    esac
fi

# Install VS Code extensions
if command -v code >/dev/null 2>&1; then
    if [ -f "vscode_extensions.txt" ]; then
        install_extensions=$(get_user_confirmation "Install VS Code extensions? (y/N): ")
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

echo "Done! 🎉"