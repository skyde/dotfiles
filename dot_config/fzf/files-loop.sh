#!/usr/bin/env bash
set -Eeuo pipefail

# Persistent fzf file picker that keeps the terminal open and caches file list per-repo.
# Usage: files-loop.sh [root_dir]

root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/fzf"
mkdir -p "$cache_dir"

# Keyed by repo/workspace path to avoid rescanning giant trees every time
if command -v sha1sum >/dev/null 2>&1; then
  key="$(printf "%s" "$root" | sha1sum | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  key="$(printf "%s" "$root" | shasum | awk '{print $1}')"
else
  key="$(printf "%s" "$root" | tr '/:\\ ' '_' )"
fi
cache_file="$cache_dir/files-$key.txt"

gen_list() {
  if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    (cd "$root" && git ls-files -co --exclude-standard)
  elif command -v fd >/dev/null 2>&1; then
    fd --type f --hidden --follow --exclude .git "$root"
  elif command -v rg >/dev/null 2>&1; then
    rg --files --hidden --follow --glob '!.git' "$root"
  else
    find "$root" -type f -not -path '*/.git/*'
  fi
}

# Warm cache on first run
[[ -s "$cache_file" ]] || gen_list > "$cache_file" 2>/dev/null || true

export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:-} --ansi --height=100% --layout=reverse --border --prompt 'files> ' \
  --preview 'bat --style=numbers --color=always --line-range :200 {}' \
  --preview-window=right:66%:wrap --bind 'alt-p:toggle-preview'"

# Persistent loop: pick -> open in current Code window -> loop again
while true; do
  sel="$(cat "$cache_file" | fzf)" || break
  [[ -z "${sel:-}" ]] && continue
  if command -v code >/dev/null 2>&1; then
    code -r "$sel"
  fi
  # Refresh cache in the background for next time
  (gen_list > "$cache_file".tmp && mv "$cache_file".tmp "$cache_file") >/dev/null 2>&1 &
done
