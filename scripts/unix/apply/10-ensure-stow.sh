#!/usr/bin/env bash
set -euo pipefail
has() { command -v "$1" >/dev/null 2>&1; }
echo "[ensure-stow] DOT_OS=$DOT_OS DOT_DRYRUN=${DOT_DRYRUN:-}"
[ -n "${DOT_DRYRUN:-}" ] && { echo "[ensure-stow] dry-run: skip install"; exit 0; }

if has stow; then
  echo "[ensure-stow] stow already present"
  exit 0
fi
echo "[ensure-stow] installing GNU Stow..."
if [ "$DOT_OS" = darwin ] && has brew; then
  brew install stow
elif [ "$DOT_OS" = linux ]; then
  if has apt-get; then sudo apt-get update -qq && sudo apt-get install -y stow
  elif has dnf; then sudo dnf install -y stow
  elif has pacman; then sudo pacman -Sy --noconfirm stow
  else echo "Please install 'stow' manually."; fi
fi

