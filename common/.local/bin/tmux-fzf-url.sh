#!/usr/bin/env bash
set -euo pipefail

bin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
extract="$bin_dir/tmux-fzf-url-helper.py"
open="$bin_dir/tmux-open-helper.sh"

candidates=$(tmux capture-pane -J -p -S -2000 | "$extract")

if [[ -z "$candidates" ]]; then
  tmux display-message "No URLs or file paths found"
  exit 0
fi

chosen=$(echo "$candidates" | fzf --tmux center,80%,40% --exit-0 --no-preview --prompt="Open> " || true)

if [[ -z "$chosen" ]]; then
  exit 0
fi

"$open" "$chosen"
