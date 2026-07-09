#!/bin/bash
# Interactive dotfiles bootstrapper.
set -eo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BAT_COMMAND="${DOTFILES_BAT_COMMAND:-bat}"

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

    printf '%s\n' "$response"
}

read_packages() {
    local package
    packages=()

    while IFS= read -r package || [ -n "$package" ]; do
        package="${package#"${package%%[![:space:]]*}"}"
        package="${package%"${package##*[![:space:]]}"}"
        case "$package" in
            ''|\#*)
                continue
                ;;
        esac

        if [ "$(uname -s)" = "Linux" ]; then
            case "$package" in
                fd) package="fd-find" ;;
                delta) package="git-delta" ;;
            esac
        fi

        packages+=("$package")
    done < "$SCRIPT_DIR/packages.txt"
}

echo "Installing dotfiles..."
cd "$SCRIPT_DIR"

# Apply the dotfiles first, forwarding preview/restow/adopt options unchanged.
./apply.sh "$@"

if [ -f "$SCRIPT_DIR/packages.txt" ]; then
    packages=()
    read_packages

    if [ "${#packages[@]}" -gt 0 ]; then
        install_apps="$(get_user_confirmation "Install packages (${packages[*]})? (y/N): ")"
        if [[ "$install_apps" =~ ^[Yy] ]]; then
            echo "Installing packages..."
            case "$(uname -s)" in
                Darwin)
                    if ! command -v brew >/dev/null 2>&1; then
                        echo "Homebrew not found. Install it first: https://brew.sh" >&2
                        exit 1
                    fi
                    brew install "${packages[@]}"
                    ;;
                Linux)
                    if command -v apt-get >/dev/null 2>&1; then
                        sudo apt-get update
                        sudo apt-get install -y "${packages[@]}"
                    elif command -v apt >/dev/null 2>&1; then
                        sudo apt update
                        sudo apt install -y "${packages[@]}"
                    else
                        echo "No supported package manager found." >&2
                        exit 1
                    fi
                    ;;
                MINGW*|MSYS*|CYGWIN*)
                    if command -v winget >/dev/null 2>&1; then
                        for package in "${packages[@]}"; do
                            winget install "$package" --silent --accept-source-agreements --accept-package-agreements
                        done
                    elif command -v choco >/dev/null 2>&1; then
                        choco install "${packages[@]}" -y
                    else
                        echo "Neither winget nor Chocolatey was found. Install packages manually: ${packages[*]}" >&2
                    fi
                    ;;
            esac
        fi
    fi
fi

if [ -f "$SCRIPT_DIR/install-tmux-plugins.sh" ]; then
    install_tmux_plugins="$(get_user_confirmation "Install tmux plugin manager (TPM) and plugins? (y/N): ")"
    if [[ "$install_tmux_plugins" =~ ^[Yy] ]]; then
        echo "Setting up tmux plugin manager (TPM) and plugins..."
        "$SCRIPT_DIR/install-tmux-plugins.sh"
    else
        echo "Skipping tmux plugin manager setup"
    fi
fi

if command -v code >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/vscode_extensions.txt" ]; then
    install_extensions="$(get_user_confirmation "Install VS Code extensions? (y/N): ")"
    if [[ "$install_extensions" =~ ^[Yy] ]]; then
        echo "Installing VS Code extensions..."
        while IFS= read -r extension || [ -n "$extension" ]; do
            if [ -n "$extension" ] && [[ ! "$extension" =~ ^[[:space:]]*# ]]; then
                echo "  Installing: $extension"
                code --install-extension "$extension" --force
            fi
        done < "$SCRIPT_DIR/vscode_extensions.txt"
        echo "✅ VS Code extensions installed"
    else
        echo "Skipping VS Code extensions"
    fi
else
    echo "VS Code not found, skipping extensions"
fi

if [ -f "$SCRIPT_DIR/install-nvim.sh" ] && [ "$(uname -s)" = "Linux" ]; then
    install_nvim="$(get_user_confirmation "Install Neovim AppImage to ~/.local/bin? (y/N): ")"
    if [[ "$install_nvim" =~ ^[Yy] ]]; then
        echo "Running Neovim installation script..."
        "$SCRIPT_DIR/install-nvim.sh"
    else
        echo "Skipping Neovim installation"
    fi
fi

if [ -f "$SCRIPT_DIR/install-yazi.sh" ]; then
    install_yazi="$(get_user_confirmation "Install Yazi (may prompt again for install method)? (y/N): ")"
    if [[ "$install_yazi" =~ ^[Yy] ]]; then
        echo "Running Yazi installation script..."
        "$SCRIPT_DIR/install-yazi.sh"
    else
        echo "Skipping enhanced Yazi installation"
    fi
fi

if [ -f "$SCRIPT_DIR/install-zoekt.sh" ]; then
    install_zoekt="$(get_user_confirmation "Install Zoekt (may prompt again for install method)? (y/N): ")"
    if [[ "$install_zoekt" =~ ^[Yy] ]]; then
        echo "Running Zoekt installation script..."
        "$SCRIPT_DIR/install-zoekt.sh"
    else
        echo "Skipping Zoekt installation"
    fi
fi

if [ -f "$SCRIPT_DIR/install-fast-syntax-highlighting.sh" ]; then
    install_fsh="$(get_user_confirmation "Install zsh-fast-syntax-highlighting? (y/N): ")"
    if [[ "$install_fsh" =~ ^[Yy] ]]; then
        echo "Running zsh-fast-syntax-highlighting installation script..."
        "$SCRIPT_DIR/install-fast-syntax-highlighting.sh"
    else
        echo "Skipping zsh-fast-syntax-highlighting"
    fi
fi

platform_init="$(get_user_confirmation "Run platform-specific setup? (y/N): ")"
if [[ "$platform_init" =~ ^[Yy] ]]; then
    echo "Running platform-specific initialization..."
    case "$(uname -s)" in
        Darwin)
            if [ -f "$SCRIPT_DIR/init-macos.sh" ]; then
                "$SCRIPT_DIR/init-macos.sh"
            else
                echo "init-macos.sh not found, skipping macOS setup"
            fi
            ;;
        Linux)
            if [ -f "$SCRIPT_DIR/init-linux.sh" ]; then
                "$SCRIPT_DIR/init-linux.sh"
            else
                echo "init-linux.sh not found, skipping Linux setup"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            if [ -f "$SCRIPT_DIR/init-windows.ps1" ]; then
                powershell.exe -ExecutionPolicy Bypass -File "$SCRIPT_DIR/init-windows.ps1"
            else
                echo "init-windows.ps1 not found, skipping Windows setup"
            fi
            ;;
    esac
else
    echo "Skipping platform-specific setup"
fi

if command -v "$BAT_COMMAND" >/dev/null 2>&1; then
    echo "Building bat cache for custom theme..."
    "$BAT_COMMAND" cache --build
else
    echo "bat not found, skipping custom theme cache"
fi

LOCAL_INIT_SCRIPT="$HOME/dotfiles-local/init.sh"
if [ -f "$LOCAL_INIT_SCRIPT" ]; then
    run_local="$(get_user_confirmation "Run local dotfiles initialization? (y/N): ")"
    if [[ "$run_local" =~ ^[Yy] ]]; then
        echo "Running local initialization script..."
        "$LOCAL_INIT_SCRIPT"
    fi
fi

echo "Init complete!"
