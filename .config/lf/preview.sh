#!/usr/bin/env bash
set -e

file="$1"
width="$2"
height="$3"

if command -v file >/dev/null 2>&1; then
  mimetype=$(file --mime-type -Lb "$file")
else
  mimetype="application/octet-stream"
fi

case "$mimetype" in
  text/*|application/json)
    if command -v bat >/dev/null 2>&1; then
      bat --style=numbers --color=always --line-range=:500 "$file"
    elif command -v batcat >/dev/null 2>&1; then
      batcat --style=numbers --color=always --line-range=:500 "$file"
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
