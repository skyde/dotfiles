#!/bin/bash
# Simple dotfiles installer
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Change to script directory to ensure relative paths work
cd "$SCRIPT_DIR"

# Manually use apply.sh with --adopt to handle conflicts if required
# Pass through all command line arguments to apply.sh
./apply.sh "$@"

# Install packages
if [ -f "packages.txt" ]; then
  # Build package list with platform-specific names
  packages=$(grep -v '^[[:space:]]*$' packages.txt | grep -v '^[[:space:]]*#' | tr '\n' ' ')
  # Handle fd package name difference on Linux
  if [[ "$(uname)" == "Linux" ]]; then
    packages="${packages//fd/fd-find}"
    packages="${packages//delta/git-delta}"
  fi

  install_apps=$(get_user_confirmation "Install packages ($packages)? (y/N): ")
  if [[ "$install_apps" =~ ^[Yy] ]]; then
    echo "Installing packages..."
    case "$(uname)" in
    Darwin)
      command -v brew >/dev/null && brew install $packages || echo "Homebrew not found. Install it first: https://brew.sh"
      ;;
    Linux)
      command -v apt >/dev/null && sudo apt update && sudo apt install -y $packages
      ;;
    MINGW* | MSYS* | CYGWIN*)
      if command -v winget >/dev/null; then
        for pkg in $packages; do winget install "$pkg" --silent --accept-source-agreements --accept-package-agreements; done
      elif command -v choco >/dev/null; then
        choco install $packages -y
      else
        echo "Neither winget nor chocolatey found. Please install packages manually: $packages"
      fi
      ;;
    esac
  fi
fi

# Install VS Code extensions
if command -v code >/dev/null 2>&1; then
  if [ -f "vscode_extensions.txt" ]; then
    install_extensions=$(get_user_confirmation "Install VS Code extensions? (y/N): ")
    if [[ "$install_extensions" =~ ^[Yy] ]]; then
      echo "Installing VS Code extensions..."

      installed_extensions_output=""
      if installed_extensions_output=$(code --list-extensions 2>/dev/null); then
        :
      else
        echo "  ⚠️ Unable to list currently installed extensions; continuing without skip logic"
        installed_extensions_output=""
      fi

      failed_extensions=()

      while read -r ext; do
        if [ -n "$ext" ] && [[ ! "$ext" =~ ^[[:space:]]*# ]]; then
          if [ "${FORCE_VSCODE_EXTENSION_UPDATE:-0}" != "1" ] && \
            [ -n "$installed_extensions_output" ] && \
            grep -Fxq "$ext" <<<"$installed_extensions_output"; then
            echo "  Skipping (already installed): $ext"
            continue
          fi

          echo "  Installing: $ext"
          if ! code --install-extension "$ext" --force; then
            echo "  ⚠️ Failed to install or update $ext"
            failed_extensions+=("$ext")
          fi
        fi
      done <vscode_extensions.txt

      if [ ${#failed_extensions[@]} -gt 0 ]; then
        echo "⚠️ Some VS Code extensions could not be installed: ${failed_extensions[*]}"
      else
        echo "✅ VS Code extensions installed"
      fi
    else
      echo "Skipping VS Code extensions"
    fi
  fi
else
  echo "VS Code not found, skipping extensions"
fi

# Optional: Install Yazi with enhanced features (GitHub binary for Linux)
if [ -f "install-yazi.sh" ]; then
  install_yazi=$(get_user_confirmation "Install Yazi (may prompt again for install method)? (y/N): ")
  if [[ "$install_yazi" =~ ^[Yy] ]]; then
    echo "Running Yazi installation script..."
    ./install-yazi.sh
  else
    echo "Skipping enhanced Yazi installation"
  fi
fi

# Optional: Install Zoekt (Go-based code search)
if [ -f "install-zoekt.sh" ]; then
  install_zoekt=$(get_user_confirmation "Install Zoekt (may prompt again for install method)? (y/N): ")
  if [[ "$install_zoekt" =~ ^[Yy] ]]; then
    echo "Running Zoekt installation script..."
    ./install-zoekt.sh
  else
    echo "Skipping Zoekt installation"
  fi
fi

# Run platform-specific initialization
platform_init=$(get_user_confirmation "Run platform-specific setup? (y/N): ")
if [[ "$platform_init" =~ ^[Yy] ]]; then
  echo "Running platform-specific initialization..."
  case "$(uname)" in
  Darwin)
    if [ -f "init-macos.sh" ]; then
      echo "Running macOS-specific setup..."
      ./init-macos.sh
    else
      echo "init-macos.sh not found, skipping macOS setup"
    fi
    ;;
  Linux)
    if [ -f "init-linux.sh" ]; then
      echo "Running Linux-specific setup..."
      ./init-linux.sh
    else
      echo "init-linux.sh not found, skipping Linux setup"
    fi
    ;;
  MINGW* | MSYS* | CYGWIN*)
    if [ -f "init-windows.ps1" ]; then
      echo "Running Windows-specific setup..."
      powershell.exe -ExecutionPolicy Bypass -File "./init-windows.ps1"
    else
      echo "init-windows.ps1 not found, skipping Windows setup"
    fi
    ;;
  esac
else
  echo "Skipping platform-specific setup"
fi

echo "Done! 🎉"
