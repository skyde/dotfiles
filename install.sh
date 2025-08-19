#!/usr/bin/env bash
set -euo pipefail

# Load helpers
source "$(dirname "$0")/install_helpers.sh"
initialize_backup_dir

# ------------------------------
# Auto-discover packages by layout
# ------------------------------

discover_and_stow() {
  local root="$1"
  [ -d "$root" ] || return 0
  while IFS= read -r -d '' dir; do
    restow_package "$dir" "$HOME"
  done < <(find "$root" -mindepth 1 -maxdepth 1 -type d -print0)
}

discover_and_stow "dotfiles/common"

case "$(uname -s)" in
  Darwin)
    discover_and_stow "dotfiles/mac"
    ;;
  Linux)
    discover_and_stow "dotfiles/linux"
    ;;
  *)
    echo "Unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

# ------------------------------
# Cross-OS bridges (reusable via data)
# ------------------------------

if [ "$(uname -s)" = Darwin ]; then
  mkdir -p "$HOME/.config/Code/User"
  mkdir -p "$HOME/Library/Application Support/Code/User"

  # Link the entire VS Code User directory to avoid per-file special casing
  process_symlink_pairs \
    "$HOME/.config/Code/User::$HOME/Library/Application Support/Code/User"
fi
