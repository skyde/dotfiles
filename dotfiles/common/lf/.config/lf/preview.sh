#!/usr/bin/env bash
set -Eeuo pipefail

file="$1"
width="${2:-80}"
height="${3:-20}"

# Per-file scroll state
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/lf/preview"
mkdir -p "$cache_dir"
key="$(printf '%s' "$file" | sha1sum | awk '{print $1}')"
state="$cache_dir/$key.scroll"

# Read current offset (lines)
offset="$(cat "$state" 2>/dev/null || printf '0')"
[[ "$offset" =~ ^[0-9]+$ ]] || offset=0

mimetype="$(file --mime-type -Lb -- "$file")"

case "$mimetype" in
  text/*|application/json|application/xml|application/x-sh|application/x-shellscript)
    # Clamp offset so we don't scroll past EOF
    total_lines="$(wc -l < "$file" 2>/dev/null || echo 0)"
    if [ "$total_lines" -gt 0 ]; then
      max_off=$(( total_lines > height ? total_lines - height : 0 ))
      [ "$offset" -gt "$max_off" ] && offset="$max_off"
    fi
    start=$(( offset + 1 ))
    end=$(( offset + height ))

    if command -v bat >/dev/null 2>&1; then
      # bat's line-range is inclusive
      bat --style=numbers --color=always --line-range="${start}:${end}" -- "$file"
    else
      # sed is inclusive too
      sed -n "${start},${end}p" -- "$file"
    fi
    ;;

  image/*)
    if command -v chafa >/dev/null 2>&1; then
      chafa -f sixel -s "${width}x${height}" -- "$file"
    else
      printf '%s\n' "$mimetype"
    fi
    ;;

  *)
    printf '%s\n' "$mimetype"
    ;;
esac

# IMPORTANT: exit non-zero so lf doesn't cache the preview for this file.
# That way, when the offset changes we actually re-run the script.
exit 1
