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
# that marks a floating window in Neovim, yazi and lazygit, on the bg_dark
# fill that gives it depth.
#
# Without it, fzf passes -B to display-popup and draws its own border instead,
# in the dim bg_highlight that FZF_DEFAULT_OPTS sets for `border` and with no
# background of its own — so the popup reads as a rectangle ruled onto the
# pane rather than as a window floating above it. Needs fzf 0.58+, which
# --style=minimal in FZF_DEFAULT_OPTS already does.
chosen=$(echo "$candidates" | fzf --tmux center,80%,40%,border-native --exit-0 --no-preview --prompt="Open> " || true)

if [[ -z "$chosen" ]]; then
  exit 0
fi

"$open" "$chosen"
