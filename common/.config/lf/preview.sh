#!/usr/bin/env sh
# lf passes: $1=file, $2=width, $3=height, $4=x, $5=y
# Basic text preview with bat; ignore x/y and use width for wrapping.

# JSON goes through json-pretty (see ~/.local/bin/json-pretty) so the preview
# matches yazi's and `json-view`'s: escaped newlines become real line breaks,
# JSON embedded in strings is expanded, long values wrap. Falls through to bat
# when json-pretty is not installed.
case "$1" in
  *.json | *.jsonl | *.ndjson | *.geojson)
    if command -v json-pretty >/dev/null 2>&1; then
      exec json-pretty --color=always --width "${2:-80}" -- "$1"
    elif [ -x "$HOME/.local/bin/json-pretty" ]; then
      exec "$HOME/.local/bin/json-pretty" --color=always --width "${2:-80}" -- "$1"
    fi
    ;;
esac

exec bat --color=always --style=numbers,changes --paging=never \
         --terminal-width="${2:-80}" -- "$1"
