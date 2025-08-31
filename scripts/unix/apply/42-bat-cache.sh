#!/usr/bin/env bash
set -euo pipefail
has() { command -v "$1" >/dev/null 2>&1; }
dry() { [ -n "${DOT_DRYRUN:-}" ]; }
echo "[bat-cache] rebuild"
if dry; then exit 0; fi
if has bat; then bat cache --build || true; elif has batcat; then batcat cache --build || true; fi

