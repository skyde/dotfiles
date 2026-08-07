#!/bin/bash
# Update dotfiles from remote repository
set -e

echo "Updating dotfiles from remote..."

# Go to dotfiles directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Pull latest changes.
#
# A failed pull must not stop the apply. Under `set -e` it did: offline, on a
# branch with no upstream, or with a conflicting local edit, the script exited
# before ./apply.sh ran and the update did nothing at all — including the
# restow that would have repaired broken symlinks, which is the part you
# usually wanted. Warn and carry on with whatever is checked out.
echo "Pulling latest changes..."
pull_failed=0
git pull || pull_failed=1
if [ "$pull_failed" -eq 1 ]; then
  echo "[warn] git pull failed; applying the currently checked-out dotfiles instead" >&2
fi

# Check for dotfiles-local and update if present.
#
# Also non-fatal, and for the same reason plus one more: dotfiles-local is a
# separate, optional repository, and a local-only one has no tracking branch at
# all, so this pull failed every single time and took the whole update with it.
#
# Its apply.sh is deliberately not run here — ./apply.sh below already does
# that, and calling it in both places ran the user's own script twice per
# update.
if [ -d "$HOME/dotfiles-local/.git" ]; then
  echo "Updating dotfiles-local from remote..."
  git -C "$HOME/dotfiles-local" pull \
    || echo "[warn] could not update dotfiles-local; continuing" >&2
fi

# Apply the updated dotfiles
echo "Applying updated dotfiles..."
# Pass through any additional arguments along with --restow
./apply.sh --restow "$@"

if [ "$pull_failed" -eq 1 ]; then
  echo "⚠️  Dotfiles applied, but the update could not be pulled — see the warning above."
  exit 1
fi

echo "✅ Dotfiles updated successfully!"
