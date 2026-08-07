#!/usr/bin/env bash
set -euo pipefail

socket_is_live() {
  [[ -S "${1:-}" ]] && nc -z -U "$1" >/dev/null 2>&1
}

resolve_vscode_socket() {
  if socket_is_live "${VSCODE_IPC_HOOK_CLI:-}"; then
    return 0
  fi
  local socket
  for socket in $(ls -t "/run/user/$UID"/vscode-ipc-*.sock 2>/dev/null); do
    if socket_is_live "$socket"; then
      export VSCODE_IPC_HOOK_CLI="$socket"
      return 0
    fi
  done
  return 0
}

# Both resolvers return success even when they find nothing: they are optional
# upgrades, and the fallbacks below handle their absence. Written as `[[ ... ]]
# && export`, a miss would make the function itself fail, and under `set -e`
# that aborted the script before it ever opened or copied anything — which is
# exactly the case that matters on a box with no VS Code server at all.
resolve_vscode_browser() {
  if [[ -x "${BROWSER:-}" ]]; then
    return 0
  fi
  local helper
  # `|| true` because with `set -o pipefail` a no-match `ls` makes the whole
  # substitution fail, and a failing assignment aborts the script under
  # `set -e` — before either fallback below gets a chance to run.
  helper=$(ls -tr "$HOME"/.vscode-server/cli/servers/*/server/bin/helpers/browser.sh 2>/dev/null | tail -n 1 || true)
  if [[ -n "$helper" ]]; then
    export BROWSER="$helper"
  fi
  return 0
}

copy_or_fail() {
  local value="$1" label="$2"
  if command -v osc-copy >/dev/null 2>&1; then
    printf '%s' "$value" | osc-copy
    # Callers other than the tmux keybinding use this too — lazygit's
    # os.openLink, for one — and `tmux display-message` outside tmux fails,
    # which under `set -e` would turn a successful copy into an error.
    if [[ -n "${TMUX:-}" ]]; then
      tmux display-message "Copied $label to clipboard"
    else
      echo "Copied $label to clipboard"
    fi
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
