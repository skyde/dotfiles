#!/usr/bin/env bash
set -euo pipefail

socket_is_live() {
  [[ -S "${1:-}" ]] && nc -z -U "$1" >/dev/null 2>&1
}

# Print the given paths newest-mtime-first, skipping any that do not exist.
#
# The callers pass an unexpanded glob; when nothing matches, bash hands the
# pattern through literally and the existence test drops it. That is the whole
# point of routing through here: the previous `ls -t <glob>` spelling made `ls`
# exit non-zero on no match, and under `set -o pipefail` that status propagated
# out of the command substitution and killed the script before it opened
# anything. On any machine without VS Code Remote — the exact case the fallback
# exists for — this helper did nothing at all and exited 2.
newest_first() {
  local -a found=()
  local path
  for path in "$@"; do
    if [[ -e "$path" ]]; then
      found+=("$path")
    fi
  done
  if ((${#found[@]} == 0)); then
    return 0
  fi
  ls -t -- "${found[@]}"
}

resolve_vscode_socket() {
  if socket_is_live "${VSCODE_IPC_HOOK_CLI:-}"; then
    return 0
  fi
  local socket
  while IFS= read -r socket; do
    if socket_is_live "$socket"; then
      export VSCODE_IPC_HOOK_CLI="$socket"
      return 0
    fi
  done < <(newest_first "/run/user/$UID"/vscode-ipc-*.sock)
  return 0
}

resolve_vscode_browser() {
  if [[ -x "${BROWSER:-}" ]]; then
    return 0
  fi
  local helper
  while IFS= read -r helper; do
    if [[ -x "$helper" ]]; then
      export BROWSER="$helper"
      return 0
    fi
  done < <(newest_first "$HOME"/.vscode-server/cli/servers/*/server/bin/helpers/browser.sh)
  return 0
}

# Best-effort: this runs from a tmux key binding, but it is also useful by hand
# outside tmux, where display-message would fail and abort the script.
notify() {
  if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
    tmux display-message "$1" 2>/dev/null || true
  else
    printf '%s\n' "$1"
  fi
}

copy_or_fail() {
  local value="$1" label="$2"
  if command -v osc-copy >/dev/null 2>&1; then
    printf '%s' "$value" | osc-copy
    notify "Copied $label to clipboard"
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
  if [[ -n "${VSCODE_IPC_HOOK_CLI:-}" ]] && command -v code >/dev/null 2>&1; then
    code "$path"
  else
    copy_or_fail "$path" path
  fi
fi
