#!/bin/bash
# Update dotfiles from remote repository
set -e

echo "Updating dotfiles from remote..."

PREVIEW_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --no | --dry-run | --preview)
      PREVIEW_ONLY=true
      ;;
  esac
done

# Save current directory
ORIGINAL_DIR="$PWD"

# Go to dotfiles directory
SCRIPT_DIR="$(dirname "$0")"
cd "$SCRIPT_DIR"

# Pull latest changes
echo "Pulling latest changes..."
if [ "$PREVIEW_ONLY" = true ]; then
  git pull --dry-run
else
  git pull
fi

# Check for dotfiles-local and update if present
if [ -d "$HOME/dotfiles-local/.git" ]; then
  echo "Updating dotfiles-local from remote..."
  if [ "$PREVIEW_ONLY" = true ]; then
    git -C "$HOME/dotfiles-local" pull --dry-run
  else
    git -C "$HOME/dotfiles-local" pull
  fi
  if [ -f "$HOME/dotfiles-local/apply.sh" ]; then
    echo "Running dotfiles-local apply script..."
    "$HOME/dotfiles-local/apply.sh" --restow "$@"
  fi
fi

# Apply the updated dotfiles
echo "Applying updated dotfiles..."
# Pass through any additional arguments along with --restow
./apply.sh --restow "$@"

echo "✅ Dotfiles updated successfully!"

# Return to original directory
cd "$ORIGINAL_DIR"
