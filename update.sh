#!/bin/bash
# Update dotfiles from remote repository
set -e

echo "Updating dotfiles from remote..."

# Save current directory
ORIGINAL_DIR="$PWD"

# Go to dotfiles directory
SCRIPT_DIR="$(dirname "$0")"
cd "$SCRIPT_DIR"

# Pull latest changes
echo "Pulling latest changes..."
git pull

# Apply the updated dotfiles
echo "Applying updated dotfiles..."
# Pass through any additional arguments along with --restow
./apply.sh --restow "$@"

echo "✅ Dotfiles updated successfully!"

# Return to original directory
cd "$ORIGINAL_DIR"
