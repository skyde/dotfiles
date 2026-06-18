#!/usr/bin/env bash
set -euo pipefail

socket_is_live() {
  [[ -S "${1:-}" ]] && nc -z -U "$1" >/dev/null 2>&1
}

resolve_vscode_socket() {
  socket_is_live "${VSCODE_IPC_HOOK_CLI:-}" && return
  local socket
  for socket in $(ls -t "/run/user/$UID"/vscode-ipc-*.sock 2>/dev/null); do
    if socket_is_live "$socket"; then
      export VSCODE_IPC_HOOK_CLI="$socket"
      return
    fi
  done
}

resolve_vscode_browser() {
  [[ -x "${BROWSER:-}" ]] && return
  local helper
  helper=$(ls -tr "$HOME"/.vscode-server/cli/servers/*/server/bin/helpers/browser.sh 2>/dev/null | tail -n 1)
  [[ -n "$helper" ]] && export BROWSER="$helper"
}

copy_or_fail() {
  local value="$1" label="$2"
  if command -v osc-copy >/dev/null 2>&1; then
    printf '%s' "$value" | osc-copy
    tmux display-message "Copied $label to clipboard"
  else
    echo "Error: cannot open $label and osc-copy is unavailable" >&2
    exit 1
  fi
}

target="${1:?usage: tmux-open-helper.sh <url|path>}"

resolve_vscode_socket
resolve_vscode_browser

if [[ "$target" =~ ^(https?|ftp):// ]]; then
  if [[ -n "${BROWSER:-}" ]]; then
    "$BROWSER" "$target" >/dev/null 2>&1 &
  else
    copy_or_fail "$target" link
  fi
else
  path=$(realpath -m "$target")
  if [[ -n "${VSCODE_IPC_HOOK_CLI:-}" ]]; then
    code "$path"
  else
    copy_or_fail "$path" path
  fi
fi
