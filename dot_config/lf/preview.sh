#!/usr/bin/env bash
set -e

file="$1"
width="$2"
height="$3"

mimetype=$(file --mime-type -Lb "$file")

case "$mimetype" in
  text/*|application/json)
    if command -v bat >/dev/null 2>&1; then
      bat --style=numbers --color=always --line-range=:500 "$file"
    else
      cat "$file"
    fi
    ;;
  image/*)
    if command -v chafa >/dev/null 2>&1; then
      chafa -f sixel -s "${width}x${height}" "$file"
    else
      echo "$mimetype"
    fi
    ;;
  *)
    echo "$mimetype"
    ;;
esac
