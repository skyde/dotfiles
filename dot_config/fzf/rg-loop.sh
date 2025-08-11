#!/usr/bin/env bash
set -Eeuo pipefail

# Persistent ripgrep + fzf searcher. Keeps terminal open and jumps to matches in VS Code.
# Usage: rg-loop.sh [root_dir]

root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$root"

export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:-} --ansi --height=100% --layout=reverse --border --prompt 'ripgrep> ' --preview-window=right:66%:wrap"

while true; do
  line="$(
    fzf --phony --query "" \
        --bind "change:reload:rg --column --line-number --no-heading --smart-case --color=always {q} || true" \
        --delimiter : \
        --preview 'bat --style=numbers --color=always --line-range :200 {1} --highlight-line {2}'
  )" || break

  file="$(cut -d: -f1 <<< "$line")"
  lineno="$(cut -d: -f2 <<< "$line")"
  [[ -n "${file:-}" ]] && command -v code >/dev/null 2>&1 && code -g "$file:$lineno"
done
