#!/usr/bin/env bash
# Ranger preview script (text/images)
set -Eeuo pipefail

FILE_PATH="$1"
WIDTH="${2:-80}"
HEIGHT="${3:-24}"
MAXLINES=$(( HEIGHT * 3 ))

mimetype=$(file --mime-type -Lb -- "$FILE_PATH")

case "$mimetype" in
  text/*|application/json|application/xml|application/x-sh|application/x-shellscript)
    if command -v bat >/dev/null 2>&1; then
      # Limit lines to reduce freezes on huge files
      bat --style=numbers --color=always --paging=never --wrap=never --line-range=1:$MAXLINES -- "$FILE_PATH" || true
    else
      sed -n "1,${MAXLINES}p" -- "$FILE_PATH" || true
    fi
    exit 0;;
  image/*)
    if command -v chafa >/dev/null 2>&1; then
      # Use symbols mode by default; sixel can flicker/freeze on some terminals
      chafa -f symbols -s "${WIDTH}x${HEIGHT}" -- "$FILE_PATH" || true
      exit 0
    fi
    echo "$mimetype"; exit 0;;
  *)
    echo "$mimetype"; exit 0;;
esac
