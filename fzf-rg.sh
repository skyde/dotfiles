#!/usr/bin/env bash
# Minimal wrapper: always delegate to tmux-run.sh with a fixed session name and fzf+rg config.
# Usage:
#   fzf-rg.sh [tmux-run-flags] [-- <extra-fzf-args>]
# For tmux-run flags see: tmux-run.sh -h (supports -d -r -v -h)
exec ./tmux-run.sh fp -- fzf --bind 'enter:execute-silent(code -r -g {1}:{2})+execute-silent([ -n "$TMUX" ] && tmux detach-client)'
# ./tmux-run.sh -v fzf-persist -- fzf \
#   --reverse \
#   --ansi \
#   --style=minimal \
#   --tiebreak=index \
#   --info=inline \
#   --no-cycle \
#   --color=prompt:#80a0ff,pointer:#ff5000,marker:#afff5f \
#   --bind 'start:reload:rg --column --color=always --smart-case -- {q} || :' \
#   --bind 'change:reload:rg --column --color=always --smart-case -- {q} || :' \
#   --delimiter : \
#   --preview 'bat --style=numbers --color=always --highlight-line {2} {1}' \
#   --preview-window 'down,30%,+{2}/2' \
#   --bind 'enter:execute-silent(code -r -g {1}:{2})' \
#   --bind 'esc:clear-query' \
#   "${extra_fzf[@]}"

# set -euo pipefail
#
# SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# TMUX_RUN="$SCRIPT_DIR/tmux-run.sh"
# [[ -x "$TMUX_RUN" ]] || { echo "Error: tmux-run.sh not found at $TMUX_RUN" >&2; exit 1; }
#
# session_name="${FZF_RG_SESSION:-fzf-rg}"

# # Collect passthrough tmux-run flags until --
# passthrough=()
# while [[ $# -gt 0 ]]; do
#   case "$1" in
#     -d|-r|-v|-h) passthrough+=("$1"); shift ;;
#     --) shift; break ;;
#     -*) echo "Unknown flag: $1" >&2; exit 2 ;;
#     *) break ;;
#   esac
# done
#
# extra_fzf=("$@")
#
# # Base command (tokens). Quote color arg so zsh doesn't glob / nomatch.
# cmd=(
#   fzf
#   --reverse
#   --ansi
#   --style=minimal
#   --tiebreak=index
#   --info inline
#   --no-cycle
#   --color=prompt:#80a0ff,pointer:#ff5000,marker:#afff5f
#   --bind 'start:reload:rg --column --color=always --smart-case {q}||true'
#   --bind 'change:reload:rg --column --color=always --smart-case {q}||true'
#   --delimiter :
#   --preview 'bat --style=numbers --color=always --highlight-line {2} {1}'
#   --preview-window 'bottom,30%,+{2}/2'
#   --bind 'enter:execute-silent(code -r -g {1}:{2})'
#   --bind 'esc:clear-query'
#   "${extra_fzf[@]}"
# )
#
# # Use bash -lc inside tmux so zsh rc / globbing in pane shell doesn't interfere.
# escaped=$(printf ' %q' "${cmd[@]}"); escaped=${escaped# }
# exec "$TMUX_RUN" "${passthrough[@]}" "$session_name" -- bash -lc "$escaped"
