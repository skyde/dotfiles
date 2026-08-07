#!/usr/bin/env bash
set -euo pipefail

bin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
extract="$bin_dir/tmux-fzf-url-helper.py"
copy_download="$bin_dir/copy-download-command"

candidates=$(
  tmux capture-pane -J -p -S -2000 \
    | "$extract" --paths-newest-first \
    | while IFS= read -r candidate; do
        [[ -e "$candidate" ]] && printf '%s\n' "$candidate"
      done
  true
)

if [[ -z "$candidates" ]]; then
  tmux display-message "No downloadable file paths found"
  exit 0
fi

# fzf truncates overlong lines on the right, which hides the file name - the
# part that matters most. Truncate on the left ourselves instead and keep the
# untouched path in a second field so the selection stays exact.
client_width=$(tmux display-message -p '#{client_width}' 2>/dev/null || true)
[[ "$client_width" =~ ^[0-9]+$ ]] || client_width=80
# The popup is 80% of the client width; leave room for its border, fzf's
# pointer and marker columns, and the leading ellipsis.
display_width=$((client_width * 80 / 100 - 8))
((display_width < 20)) && display_width=20

rows=$(
  while IFS= read -r candidate; do
    display=$candidate
    if ((${#display} > display_width)); then
      display="…${candidate: ${#candidate} - display_width + 1}"
    fi
    printf '%s\t%s\n' "$display" "$candidate"
  done <<<"$candidates"
)

# --tmux draws the picker in a tmux popup, and is fzf 0.53 and later. An
# unknown option makes fzf exit rather than ignore it, so on an older build
# (Ubuntu 24.04 ships 0.44) this ran inline in the pane instead — which is
# exactly the fallback wanted here.
FZF_POPUP=()
if "$(cd "$(dirname "$0")" && pwd)/fzf-supports" 0.53; then
  FZF_POPUP=(--tmux center,80%,40%)
fi

chosen=$(printf '%s\n' "$rows" | fzf "${FZF_POPUP[@]}" --exit-0 --no-preview --no-sort --layout=reverse --delimiter=$'\t' --with-nth=1 --nth=2 --prompt="Download> " || true)

if [[ -z "$chosen" ]]; then
  exit 0
fi

chosen=${chosen#*$'\t'}

if ! output=$("$copy_download" "$chosen" 2>&1); then
  tmux display-message "Failed to copy download command: $output"
  printf '%s\n' "$output" >&2
  exit 1
fi
