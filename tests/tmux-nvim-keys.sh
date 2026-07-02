#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmux_bin="$(command -v tmux || true)"
nvim_bin="$(command -v nvim || true)"

skip() {
  printf 'skip - %s\n' "$1"
}

assert_eq() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$actual" != "$expected" ]]; then
    printf 'not ok - %s\n' "$name" >&2
    printf 'expected:\n%s\n' "$expected" >&2
    printf 'actual:\n%s\n' "$actual" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

wait_for_file() {
  local path="$1"

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -s "$path" ]] && return 0
    sleep 0.1
  done

  printf 'timed out waiting for %s\n' "$path" >&2
  return 1
}

wait_for_pane_command() {
  local socket="$1"
  local pane_id="$2"
  local expected="$3"
  local actual

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    actual="$("$tmux_bin" -L "$socket" display-message -p -t "$pane_id" '#{pane_current_command}')"
    [[ "$actual" == "$expected" ]] && return 0
    sleep 0.1
  done

  printf 'timed out waiting for pane %s command %s, got %s\n' "$pane_id" "$expected" "$actual" >&2
  return 1
}

if [[ -z "$tmux_bin" ]]; then
  skip "tmux Neovim key path (tmux unavailable)"
  exit 0
fi

if [[ -z "$nvim_bin" ]]; then
  skip "tmux Neovim key path (nvim unavailable)"
  exit 0
fi

socket_name="dotfiles-nvim-keys-$$"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/tmux-nvim-keys.XXXXXX")"

cleanup() {
  "$tmux_bin" -L "$socket_name" kill-server >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

cat >"$tmp/init.lua" <<'LUA'
local root = assert(os.getenv("DOTFILES_ROOT"))

vim.g.mapleader = " "
package.path = root
  .. "/common/.config/nvim/lua/?.lua;"
  .. root
  .. "/common/.config/nvim/lua/?/init.lua;"
  .. package.path

require("config.keymaps")

vim.o.hlsearch = true
vim.fn.setreg("/", "manual")
LUA

printf 'manual\n' >"$tmp/search.txt"

printf -v nvim_command 'DOTFILES_ROOT=%q %q -n -i NONE -u %q --noplugin %q' \
  "$root" \
  "$nvim_bin" \
  "$tmp/init.lua" \
  "$tmp/search.txt"

TERM=xterm-256color TERM_PROGRAM=vscode "$tmux_bin" -L "$socket_name" -f "$root/common/.tmux.conf" \
  new-session -d -s nvim-keys "$nvim_command"

pane_id="$("$tmux_bin" -L "$socket_name" display-message -p '#{pane_id}')"
wait_for_pane_command "$socket_name" "$pane_id" "$(basename "$nvim_bin")"

shift_f9_sequence="$(printf '\033[20;2~')"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_f9_sequence"

result="$tmp/result.log"
lua_result="${result//\\/\\\\}"
lua_result="${lua_result//\"/\\\"}"
lua_command="lua vim.fn.writefile({\"TMUX_NVIM_SHIFT_F9_HLSEARCH_OFF:\" .. tostring(not vim.o.hlsearch)}, \"$lua_result\"); vim.cmd(\"qa!\")"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$lua_command" Enter

wait_for_file "$result"
assert_eq "tmux passes VS Code Shift-F9 bytes to Neovim" "TMUX_NVIM_SHIFT_F9_HLSEARCH_OFF:true" "$(cat "$result")"
