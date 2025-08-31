#!/usr/bin/env bash
set -euo pipefail
[ "$DOT_OS" = darwin ] || exit 0
[ -n "${DOT_DRYRUN:-}" ] && exit 0
/usr/bin/defaults write com.apple.PowerChime ChimeOnNoHardware -bool true || true
/usr/bin/killall PowerChime >/dev/null 2>&1 || true

