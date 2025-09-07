#!/usr/bin/env bash
# Create a named tmux session to run a command once; if it exists, just attach.
# Usage:
#   tmux-run.sh <session-name> -- <command> [args...]
#   tmux-run.sh <session-name> <command> [args...]
# Examples:
#   tmux-run.sh fzf-rg -- fzf --reverse ...
#   tmux-run.sh build make -j16

set -Eeuo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

[[ $# -ge 2 ]] || die "Usage: $0 <session-name> -- <command> [args...]"

session="$1"
shift

# Optional separator for clarity.
if [[ "${1-}" == "--" ]]; then shift; fi
[[ $# -gt 0 ]] || die "No command provided."

# tmux forbids ':' in session names because of target syntax.
[[ "$session" == *:* ]] && die "Session name cannot contain ':'"

# Reconstruct an exact shell command from the remaining argv (preserves spaces/quotes).
# printf %q is a bash builtin that shell-escapes each token correctly.
escaped_cmd=$(printf ' %q' "$@")
escaped_cmd="${escaped_cmd# }"

if tmux has-session -t "$session" 2>/dev/null; then
  # Session exists: attach/switch without re-running the command.
  if [[ -n "${TMUX-}" ]]; then
    exec tmux switch-client -t "$session"
  else
    exec tmux attach -t "$session"
  fi
else
  # Create session and run the command exactly once.
  tmux new-session -d -s "$session"
  tmux send-keys -t "$session" "$escaped_cmd" C-m
  if [[ -n "${TMUX-}" ]]; then
    exec tmux switch-client -t "$session"
  else
    exec tmux attach -t "$session"
  fi
fi
