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

# border-native hands the border to tmux, which draws it from
# popup-border-style / popup-border-lines in ~/.tmux.conf — the rounded blue
# that marks a floating window in Neovim, yazi and lazygit. Without it fzf
# passes -B to display-popup and, since FZF_DEFAULT_OPTS asks for
# --style=minimal, nothing draws a border at all and the picker bleeds into
# the pane behind it. Needs fzf 0.58+, which --style=minimal already does.
chosen=$(echo "$candidates" | fzf --tmux center,80%,40%,border-native --exit-0 --no-preview --prompt="Open> " || true)

if [[ -z "$chosen" ]]; then
  exit 0
fi

"$open" "$chosen"
