#!/usr/bin/env bash
set -euo pipefail
has() { command -v "$1" >/dev/null 2>&1; }
dry() { [ -n "${DOT_DRYRUN:-}" ]; }
log() { echo "[shell-fonts] $*"; }

# Fonts
if [ "$DOT_OS" = darwin ]; then
  FONT_DIR="$DOT_TARGET/Library/Fonts"
elif [ "$DOT_OS" = linux ]; then
  FONT_DIR="$DOT_TARGET/.local/share/fonts"
else
  FONT_DIR=
fi
if [ -n "$FONT_DIR" ]; then
  mkdir -p "$FONT_DIR"
  SRC="$DOT_REPO/fonts"
  if [ -d "$SRC" ]; then
    dry || for f in "$SRC"/*.ttf; do [ -f "$f" ] && cp -f "$f" "$FONT_DIR/"; done
    if [ "$DOT_OS" = linux ] && has fc-cache && ! dry; then fc-cache -fv "$FONT_DIR" >/dev/null 2>&1 || true; fi
    log "Fonts ensured in $FONT_DIR"
  fi
fi

# Shell rc include
line='[ -f "$HOME/.config/shell/00-editor.sh" ] && . "$HOME/.config/shell/00-editor.sh"'
for rc in "$DOT_TARGET/.bashrc" "$DOT_TARGET/.zshrc" "$DOT_TARGET/.zprofile"; do
  [ -f "$rc" ] || dry || touch "$rc"
  if ! grep -Fq "$line" "$rc" 2>/dev/null; then
    dry || echo "$line" >>"$rc"
  fi
done

# Git editor
if has git && ! dry; then
  git config --global core.editor "nvim" || true
  git config --global sequence.editor "nvim" || true
fi

