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
      # Use bat with paging disabled and plain style for less flicker
      bat --style=numbers --color=always --paging=never --line-range="${start}:${end}" -- "$file"
    else
      # sed is inclusive too
      sed -n "${start},${end}p" -- "$file"
    fi
    ;;

  image/*)
    if command -v chafa >/dev/null 2>&1; then
      # Use terminal size and avoid unnecessary options that can cause flicker
      chafa --size="${width}x${height}" --animate=off -- "$file"
    elif command -v identify >/dev/null 2>&1; then
      # Fallback to image info if chafa not available
      identify "$file"
    else
      printf '%s\n' "$mimetype"
    fi
    ;;

  application/pdf)
    if command -v pdftotext >/dev/null 2>&1; then
      # Quick text preview for PDFs
      pdftotext -l 1 "$file" - | head -n "$height"
    else
      printf '%s\n' "$mimetype"
    fi
    ;;

  *)
    # Try to show a preview for other file types
    if command -v bat >/dev/null 2>&1; then
      bat --style=plain --color=always --paging=never --line-range=":$height" -- "$file" 2>/dev/null || printf '%s\n' "$mimetype"
    else
      head -n "$height" "$file" 2>/dev/null || printf '%s\n' "$mimetype"
    fi
    ;;
esac

# Exit successfully to allow caching and reduce flicker
exit 0
