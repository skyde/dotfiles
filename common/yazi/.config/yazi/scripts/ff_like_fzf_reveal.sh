#!/usr/bin/env bash
set -euo pipefail

_preview() {
  local p="$1"
  if [ -d "$p" ]; then
    if command -v eza >/dev/null 2>&1; then
      eza -la --group-directories-first --color=always -- "$p"
    else
      ls -la -- "$p"
    fi
    return
  fi

  local mt
  mt="$(file -Lb --mime-type -- "$p" || echo '')"
  case "$mt" in
    image/*)
      if command -v chafa >/dev/null 2>&1; then
        chafa --size=90% -- "$p"
      else
        printf '[image] %s\n' "$p"
      fi
      ;;
    application/pdf)
      if command -v pdftotext >/dev/null 2>&1; then
        pdftotext -f 1 -l 10 -layout -- "$p" -
      else
        printf '[pdf] %s\n' "$p"
      fi
      ;;
    video/*|audio/*)
      if command -v mediainfo >/dev/null 2>&1; then
        mediainfo -- "$p"
      else
        printf '[media] %s\n' "$p"
      fi
      ;;
    *)
      if command -v bat >/dev/null 2>&1; then
        bat --style=plain --color=always --line-range=:500 -- "$p"
      else
        sed -n '1,200p' -- "$p"
      fi
      ;;
  esac
}
export -f _preview

if command -v fd >/dev/null 2>&1; then
  mapfile -t candidates < <(fd --hidden --follow --strip-cwd-prefix --exclude .git .)
else
  mapfile -t candidates < <(
    {
      rg --files --hidden --glob '!.git/*' || true
      find . -mindepth 1 \
        \( -path './.git' -o -path './.git/*' \) -prune \
        -o -type d -print
    } | sed 's#^\./##' | sort -u
  )
fi

sel="$(
  printf '%s\n' "${candidates[@]}" |
  fzf --ansi --height=90% --layout=reverse --border --multi \
      --bind 'tab:toggle+down,shift-tab:toggle+up,ctrl-/:toggle-preview' \
      --preview 'bash -lc "_preview {1}"' \
      --preview-window=right,60%,wrap
)"

[ -z "${sel:-}" ] && exit 0
first="$(printf '%s\n' "$sel" | head -n1)"

if [ -d "$first" ]; then
  ya emit cd "$first"
else
  ya emit reveal "$first"
fi
