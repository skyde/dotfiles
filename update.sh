#!/bin/bash
# Update dotfiles from their remotes and restow them.
set -euo pipefail

ORIGINAL_DIR="$PWD"
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

restore_original_dir() {
    cd "$ORIGINAL_DIR" 2>/dev/null || true
}
trap restore_original_dir EXIT

cd "$SCRIPT_DIR"
echo "Updating dotfiles from remote..."

echo "Pulling latest changes..."
git pull --ff-only

LOCAL_DOTFILES="$HOME/dotfiles-local"
if [ -e "$LOCAL_DOTFILES/.git" ]; then
    echo "Updating dotfiles-local from remote..."
    git -C "$LOCAL_DOTFILES" pull --ff-only
fi

echo "Applying updated dotfiles..."
./apply.sh --restow "$@"

echo "✅ Dotfiles updated successfully!"
