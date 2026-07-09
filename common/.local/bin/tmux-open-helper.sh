#!/usr/bin/env bash
set -euo pipefail

socket_is_live() {
  [[ -S "${1:-}" ]] && nc -z -U "$1" >/dev/null 2>&1
}

resolve_vscode_socket() {
  socket_is_live "${VSCODE_IPC_HOOK_CLI:-}" && return
  local socket
  local newest
  local newest_index
  local index
  local -a sockets=()

  for socket in "/run/user/$UID"/vscode-ipc-*.sock; do
    [[ -S "$socket" ]] && sockets+=("$socket")
  done

  while (("${#sockets[@]}" > 0)); do
    newest_index=0
    for index in "${!sockets[@]}"; do
      if [[ "${sockets[$index]}" -nt "${sockets[$newest_index]}" ]]; then
        newest_index="$index"
      fi
    done

    newest="${sockets[$newest_index]}"
    unset 'sockets[newest_index]'
    sockets=("${sockets[@]}")

    socket="$newest"
    if socket_is_live "$socket"; then
      export VSCODE_IPC_HOOK_CLI="$socket"
      return
    fi
  done
}

resolve_vscode_browser() {
  [[ -x "${BROWSER:-}" ]] && return
  local helper
  local candidate
  helper=""
  for candidate in "$HOME"/.vscode-server/cli/servers/*/server/bin/helpers/browser.sh; do
    [[ -x "$candidate" ]] || continue
    if [[ -z "$helper" || "$candidate" -nt "$helper" ]]; then
      helper="$candidate"
    fi
  done
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
