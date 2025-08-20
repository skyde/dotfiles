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
if [ -f "packages.txt" ]; then
    # Read packages from file and handle platform-specific names
    packages=""
    while read -r pkg; do
        if [ -n "$pkg" ] && [[ ! "$pkg" =~ ^[[:space:]]*# ]]; then
            # Handle platform-specific package names
            case "$pkg" in
                fd)
                    case "$(uname)" in
                        Darwin|MINGW*|MSYS*|CYGWIN*) packages="$packages fd" ;;
                        Linux) packages="$packages fd-find" ;;  # Note: binary is called 'fdfind' on Debian/Ubuntu
                    esac
                    ;;
                *)
                    packages="$packages $pkg"
                    ;;
            esac
        fi
    done < packages.txt
    
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
            MINGW*|MSYS*|CYGWIN*)
                if command -v winget >/dev/null 2>&1; then
                    echo "Installing packages..."
                    for pkg in $packages; do
                        echo "  Installing: $pkg"
                        winget install "$pkg" --silent --accept-source-agreements --accept-package-agreements
                    done
                elif command -v choco >/dev/null 2>&1; then
                    echo "Installing packages..."
                    choco install $packages -y
                else
                    echo "Neither winget nor chocolatey found. Please install packages manually: $packages"
                fi
                ;;
        esac
    fi
else
    echo "packages.txt not found, skipping package installation"
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