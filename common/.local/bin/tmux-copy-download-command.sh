#!/usr/bin/env bash
set -euo pipefail

bin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
extract="$bin_dir/tmux-fzf-url-helper.py"
copy_download="$bin_dir/copy-download-command"

candidates=$(
  tmux capture-pane -J -p -S -2000 \
    | "$extract" \
    | while IFS= read -r candidate; do
        [[ -e "$candidate" ]] && printf '%s\n' "$candidate"
      done
  true
)

if [[ -z "$candidates" ]]; then
  tmux display-message "No downloadable file paths found"
  exit 0
fi

chosen=$(printf '%s\n' "$candidates" | fzf --tmux center,80%,40% --exit-0 --no-preview --prompt="Download> " || true)

if [[ -z "$chosen" ]]; then
  exit 0
fi

if output=$("$copy_download" "$chosen" 2>&1); then
  tmux display-message "Copied download command"
  printf '%s\n' "$output"
else
  tmux display-message "Failed to copy download command: $output"
  printf '%s\n' "$output" >&2
  exit 1
fi
