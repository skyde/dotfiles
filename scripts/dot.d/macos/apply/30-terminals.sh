#!/usr/bin/env bash
set -euo pipefail
has() { command -v "$1" >/dev/null 2>&1; }
dry() { [ -n "${DOT_DRYRUN:-}" ]; }
echo "[macos-terminals]"
[ "$DOT_OS" = darwin ] || exit 0

# kitty
if ! has kitty && [ ! -d "/Applications/kitty.app" ] && [ ! -d "$HOME/Applications/kitty.app" ]; then
  if has brew && ! dry; then brew install --cask kitty || true; fi
fi

# wezterm
if ! has wezterm && [ ! -d "/Applications/WezTerm.app" ] && [ ! -d "$HOME/Applications/WezTerm.app" ]; then
  if has brew && ! dry; then brew install --cask wezterm || true; fi
fi

