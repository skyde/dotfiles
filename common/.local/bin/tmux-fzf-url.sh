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

# --tmux draws the picker in a tmux popup, and is fzf 0.53 and later. An
# unknown option makes fzf exit rather than ignore it, so on an older build
# (Ubuntu 24.04 ships 0.44) this ran inline in the pane instead — which is
# exactly the fallback wanted here.
FZF_POPUP=()
if "$(cd "$(dirname "$0")" && pwd)/fzf-supports" 0.53; then
  FZF_POPUP=(--tmux center,80%,40%)
fi

chosen=$(echo "$candidates" | fzf "${FZF_POPUP[@]}" --exit-0 --no-preview --prompt="Open> " || true)

if [[ -z "$chosen" ]]; then
  exit 0
fi

"$open" "$chosen"
