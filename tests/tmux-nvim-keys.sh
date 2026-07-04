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

wait_for_file_content() {
  local path="$1"
  local expected="$2"
  local actual=""

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    actual="$(cat "$path" 2>/dev/null || true)"
    [[ "$actual" == "$expected" ]] && return 0
    sleep 0.1
  done

  printf 'timed out waiting for %s content\nexpected:\n%s\nactual:\n%s\n' "$path" "$expected" "$actual" >&2
  return 1
}

lua_string() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
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

vim.g.dotfiles_tmux_paste = ""
vim.g.clipboard = {
  name = "tmux-nvim-keys",
  copy = {
    ["+"] = function() end,
    ["*"] = function() end,
  },
  paste = {
    ["+"] = function()
      return { vim.g.dotfiles_tmux_paste }, "v"
    end,
    ["*"] = function()
      return { vim.g.dotfiles_tmux_paste }, "v"
    end,
  },
  cache_enabled = 0,
}

vim.o.hlsearch = true
vim.fn.setreg("/", "manual")
LUA

for i in $(seq 1 32); do
  if [[ "$i" -eq 1 ]]; then
    printf 'manual\n'
  else
    printf 'line %s\n' "$i"
  fi
done >"$tmp/search.txt"
printf 'alternate buffer\n' >"$tmp/other.txt"

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
lua_command="lua vim.fn.writefile({\"TMUX_NVIM_SHIFT_F9_HLSEARCH_OFF:\" .. tostring(not vim.o.hlsearch)}, $(lua_string "$result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$lua_command" Enter

wait_for_file "$result"
assert_eq "tmux passes VS Code Shift-F9 bytes to Neovim" "TMUX_NVIM_SHIFT_F9_HLSEARCH_OFF:true" "$(cat "$result")"

shift_f1_sequence="$(printf '\033[1;2P')"
shift_f12_sequence="$(printf '\033[24;2~')"
normal_previous_buffer_result="$tmp/normal-previous-buffer.log"
normal_next_buffer_result="$tmp/normal-next-buffer.log"
insert_next_buffer_result="$tmp/insert-next-buffer.log"
insert_previous_buffer_result="$tmp/insert-previous-buffer.log"
edit_other_command="lua vim.cmd('edit ' .. vim.fn.fnameescape($(lua_string "$tmp/other.txt")))"
edit_search_command="lua vim.cmd('edit ' .. vim.fn.fnameescape($(lua_string "$tmp/search.txt")))"
write_normal_previous_command="lua vim.fn.writefile({vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t')}, $(lua_string "$normal_previous_buffer_result"))"
write_normal_next_command="lua vim.fn.writefile({vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t')}, $(lua_string "$normal_next_buffer_result"))"
write_insert_next_command="lua vim.fn.writefile({vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t')}, $(lua_string "$insert_next_buffer_result"))"
write_insert_previous_command="lua vim.fn.writefile({vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t')}, $(lua_string "$insert_previous_buffer_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$edit_other_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_f1_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$write_normal_previous_command" Enter
wait_for_file "$normal_previous_buffer_result"
assert_eq "tmux passes VS Code Shift-F1 bytes to normal Neovim previous buffer" "search.txt" "$(cat "$normal_previous_buffer_result")"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_f12_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$write_normal_next_command" Enter
wait_for_file "$normal_next_buffer_result"
assert_eq "tmux passes VS Code Shift-F12 bytes to normal Neovim next buffer" "other.txt" "$(cat "$normal_next_buffer_result")"

"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$edit_search_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' 'startinsert' Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_f12_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$write_insert_next_command" Enter
wait_for_file "$insert_next_buffer_result"
assert_eq "tmux passes VS Code Shift-F12 bytes to insert Neovim next buffer" "other.txt" "$(cat "$insert_next_buffer_result")"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' 'startinsert' Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_f1_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$write_insert_previous_command" Enter
wait_for_file "$insert_previous_buffer_result"
assert_eq "tmux passes VS Code Shift-F1 bytes to insert Neovim previous buffer" "search.txt" "$(cat "$insert_previous_buffer_result")"

shift_f5_sequence="$(printf '\033[15;2~')"
shift_insert_sequence="$(printf '\033[2;2~')"
normal_save_expected="$(printf 'normal shift-f5 save\nline 2')"
normal_save_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'normal shift-f5 save', 'line 2'}); vim.cmd('normal! gg')"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$normal_save_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_f5_sequence"
wait_for_file_content "$tmp/search.txt" "$normal_save_expected"
assert_eq "tmux passes VS Code Shift-F5 bytes to normal Neovim save" "$normal_save_expected" "$(cat "$tmp/search.txt")"

insert_save_expected="$(printf 'insert shift-f5 save\nline 2')"
insert_save_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'insert shift-f5 save', 'line 2'}); vim.cmd('startinsert')"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$insert_save_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_f5_sequence"
wait_for_file_content "$tmp/search.txt" "$insert_save_expected"
assert_eq "tmux passes VS Code Shift-F5 bytes to insert Neovim save" "$insert_save_expected" "$(cat "$tmp/search.txt")"

shift_insert_result="$tmp/shift-insert-paste.log"
shift_insert_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'shift-insert '}); vim.g.dotfiles_tmux_paste = 'paste via tmux'; vim.cmd('startinsert!')"
shift_insert_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line()}, $(lua_string "$shift_insert_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$shift_insert_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_insert_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$shift_insert_write_command" Enter
wait_for_file "$shift_insert_result"
assert_eq "tmux passes Shift-Insert bytes to insert Neovim paste" "shift-insert paste via tmux" "$(cat "$shift_insert_result")"

visual_save_expected="$(printf 'visual shift-f5 save\nline 2')"
visual_save_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'visual shift-f5 save', 'line 2'}); vim.cmd('normal! gg')"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$visual_save_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l 'gg0V'
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_f5_sequence"
wait_for_file_content "$tmp/search.txt" "$visual_save_expected"
assert_eq "tmux passes VS Code Shift-F5 bytes to visual Neovim save" "$visual_save_expected" "$(cat "$tmp/search.txt")"

reset_lines_command="lua local lines = {'manual'}; for i = 2, 32 do lines[i] = 'line ' .. i end; vim.api.nvim_buf_set_lines(0, 0, -1, false, lines); vim.cmd('normal! gg')"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$reset_lines_command" Enter

shift_f4_sequence="$(printf '\033[1;2S')"
shift_f6_sequence="$(printf '\033[17;2~')"

visual_up_result="$tmp/visual-up.log"
visual_up_command="lua local lines=vim.fn.getreg('\"', 1, true); vim.fn.writefile({lines[1] or '', lines[#lines] or '', tostring(#lines), vim.fn.getregtype('\"')}, $(lua_string "$visual_up_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l '20G0V'
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_f4_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" y
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$visual_up_command" Enter
wait_for_file "$visual_up_result"
assert_eq "tmux passes VS Code Shift-F4 bytes to visual Neovim" \
  "$(printf 'line 4\nline 20\n17\nV')" \
  "$(cat "$visual_up_result")"

visual_down_result="$tmp/visual-down.log"
visual_down_command="lua local lines=vim.fn.getreg('\"', 1, true); vim.fn.writefile({lines[1] or '', lines[#lines] or '', tostring(#lines), vim.fn.getregtype('\"')}, $(lua_string "$visual_down_result")); vim.cmd('qa!')"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l '12G0V'
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_f6_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" y
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$visual_down_command" Enter
wait_for_file "$visual_down_result"
assert_eq "tmux passes VS Code Shift-F6 bytes to visual Neovim" \
  "$(printf 'line 12\nline 28\n17\nV')" \
  "$(cat "$visual_down_result")"
