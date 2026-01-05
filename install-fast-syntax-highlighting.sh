#!/usr/bin/env bash
set -euo pipefail

# Install zsh-fast-syntax-highlighting
# - On macOS with Homebrew: Installs via brew
# - On Linux/Other: Installs via git clone to ~/.local/share

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper functions if available
if [ -f "$SCRIPT_DIR/lib/run_ensure.sh" ]; then
  source "$SCRIPT_DIR/lib/run_ensure.sh"
fi

HAVE() { command -v "$1" >/dev/null 2>&1; }

echo "Checking zsh-fast-syntax-highlighting..."

OS="$(uname -s)"
TARGET_DIR="$HOME/.local/share/zsh-fast-syntax-highlighting"

case "$OS" in
Darwin)
  if HAVE brew; then
    echo "Detected macOS with Homebrew."
    if brew list --formula | grep -q "^zsh-fast-syntax-highlighting$"; then
      echo "zsh-fast-syntax-highlighting is already installed via Homebrew."
    else
      echo "Installing zsh-fast-syntax-highlighting via Homebrew..."
      brew install zsh-fast-syntax-highlighting
    fi
  else
    # Fallback for macOS without Homebrew
    if [ ! -d "$TARGET_DIR" ]; then
      echo "Homebrew not found. Installing via git clone..."
      mkdir -p "$(dirname "$TARGET_DIR")"
      git clone --depth 1 https://github.com/zdharma-continuum/fast-syntax-highlighting.git "$TARGET_DIR"
      echo "Installed to $TARGET_DIR"
    else
      echo "zsh-fast-syntax-highlighting already exists at $TARGET_DIR"
    fi
  fi
  ;;
Linux | *)
  # Linux or other OS
  if [ ! -d "$TARGET_DIR" ]; then
    echo "Installing via git clone..."
    if ! HAVE git; then
      echo "Error: git is required but not found." >&2
      exit 1
    fi
    mkdir -p "$(dirname "$TARGET_DIR")"
    git clone --depth 1 https://github.com/zdharma-continuum/fast-syntax-highlighting.git "$TARGET_DIR"
    echo "Installed to $TARGET_DIR"
  else
    echo "zsh-fast-syntax-highlighting already exists at $TARGET_DIR"
    # Optional: Update if it exists
    # cd "$TARGET_DIR" && git pull && echo "Updated."
  fi
  ;;
esac
