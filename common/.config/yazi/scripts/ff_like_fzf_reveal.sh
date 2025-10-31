#!/usr/bin/env bash
set -euo pipefail

_preview() {
  local path="$1"
  if [ -d "$path" ]; then
    if command -v eza >/dev/null 2>&1; then
      eza -la --group-directories-first --color=always "$path"
    else
      ls -la "$path"
    fi
    return
  fi

  local mime
  mime="$(file -Lb --mime-type -- "$path" || echo '')"
  case "$mime" in
    image/*)
      if command -v chafa >/dev/null 2>&1; then
        chafa --size=90% "$path"
      else
        echo "[image] $path"
      fi
      ;;
    application/pdf)
      if command -v pdftotext >/dev/null 2>&1; then
        pdftotext -f 1 -l 10 -layout "$path" -
      else
        echo "[pdf] $path"
      fi
      ;;
    video/*|audio/*)
      if command -v mediainfo >/dev/null 2>&1; then
        mediainfo "$path"
      else
        echo "[media] $path"
      fi
      ;;
    *)
      if command -v bat >/dev/null 2>&1; then
        bat --style=plain --color=always --line-range=:500 "$path"
      else
        sed -n '1,200p' "$path"
      fi
      ;;
  esac
}

export -f _preview

if command -v fd >/dev/null 2>&1; then
  mapfile -t candidates < <(fd --hidden --follow --strip-cwd-prefix --exclude .git .)
else
  mapfile -t candidates < <(rg --files --hidden --glob '!.git/*' || true)
fi

selection="$(
  printf '%s\n' "${candidates[@]}" |
    fzf --ansi --height=90% --layout=reverse --border --multi \
        --bind "tab:toggle+down,shift-tab:toggle+up,ctrl-/:toggle-preview" \
        --preview 'bash -lc "_preview {1}"' \
        --preview-window=right,60%,wrap
)"

[ -z "${selection:-}" ] && exit 0

first="$(printf '%s\n' "$selection" | head -n1)"

if [ -d "$first" ]; then
  ya emit cd "$first"
else
  ya emit reveal "$first"
fi
