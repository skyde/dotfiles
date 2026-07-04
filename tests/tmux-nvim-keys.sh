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

  for _ in $(seq 1 50); do
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

  for _ in $(seq 1 50); do
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

terminal_mode_copy_setup_command() {
  local job_var="$1"
  local display="$2"
  local output_path="$3"

  printf "%s" "lua vim.cmd('enew'); vim.g.${job_var} = vim.fn.termopen({'sh', '-c', 'printf \"%s\" \"\$1\"; cat > \"\$2\"', 'sh', $(lua_string "$display"), $(lua_string "$output_path")}); assert(type(vim.g.${job_var}) == 'number' and vim.g.${job_var} > 0); assert(vim.wait(1000, function() return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'):find($(lua_string "$display"), 1, true) ~= nil end)); vim.g.dotfiles_tmux_copy_lines = {}; vim.g.dotfiles_tmux_copy_type = ''; vim.cmd('startinsert')"
}

terminal_mode_key_result_command() {
  local job_var="$1"
  local output_path="$2"
  local result_path="$3"

  printf "%s" "lua _G.dotfiles_tmux_write_terminal_key_result($(lua_string "$job_var"), $(lua_string "$output_path"), $(lua_string "$result_path"))"
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
vim.g.dotfiles_tmux_copy_lines = {}
vim.g.dotfiles_tmux_copy_type = ""
vim.g.clipboard = {
  name = "tmux-nvim-keys",
  copy = {
    ["+"] = function(lines, regtype)
      vim.g.dotfiles_tmux_copy_lines = lines
      vim.g.dotfiles_tmux_copy_type = regtype
    end,
    ["*"] = function(lines, regtype)
      vim.g.dotfiles_tmux_copy_lines = lines
      vim.g.dotfiles_tmux_copy_type = regtype
    end,
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

function _G.dotfiles_tmux_write_terminal_key_result(job_var, output_path, result_path)
  local ok, err = pcall(function()
    local job_id = vim.g[job_var]
    if type(job_id) == "number" then
      pcall(vim.fn.chanclose, job_id, "stdin")
      pcall(vim.fn.jobwait, { job_id }, 1000)
    end

    local lines = vim.api.nvim_buf_get_lines(0, 0, 1, false)
    local output = ""
    if vim.fn.filereadable(output_path) == 1 then
      output = table.concat(vim.fn.readfile(output_path), "|")
    end

    vim.fn.writefile({
      table.concat(vim.g.dotfiles_tmux_copy_lines, "|"),
      vim.g.dotfiles_tmux_copy_type,
      table.concat(lines, "|"),
      output,
    }, result_path)
  end)

  if not ok then
    vim.fn.writefile({ "ERROR", tostring(err) }, result_path)
  end
end
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

shift_f4_sequence="$(printf '\033[1;2S')"
shift_f5_sequence="$(printf '\033[15;2~')"
shift_f6_sequence="$(printf '\033[17;2~')"
ctrl_insert_sequence="$(printf '\033[2;5~')"
shift_insert_sequence="$(printf '\033[2;2~')"
shift_delete_sequence="$(printf '\033[3;2~')"
ctrl_backspace_sequence="$(printf '\033[127;5u')"
ctrl_left_sequence="$(printf '\033[1;5D')"
ctrl_right_sequence="$(printf '\033[1;5C')"
ctrl_delete_sequence="$(printf '\033[3;5~')"
nvim_terminal_normal_sequence="$(printf '\034\016')"
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

insert_copy_result="$tmp/insert-ctrl-insert-copy.log"
insert_copy_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'insert ctrl-insert copy', 'line 2'}); vim.g.dotfiles_tmux_copy_lines = {}; vim.g.dotfiles_tmux_copy_type = ''; vim.cmd('normal! gg$'); vim.cmd('startinsert!')"
insert_copy_write_command="lua vim.fn.writefile({table.concat(vim.g.dotfiles_tmux_copy_lines, '|'), vim.g.dotfiles_tmux_copy_type, table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '|')}, $(lua_string "$insert_copy_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$insert_copy_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$ctrl_insert_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "Z"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$insert_copy_write_command" Enter
wait_for_file "$insert_copy_result"
assert_eq "tmux passes Ctrl-Insert bytes to insert Neovim copy" \
  "$(printf 'insert ctrl-insert copy|\nV\ninsert ctrl-insert copyZ|line 2')" \
  "$(cat "$insert_copy_result")"

insert_cut_result="$tmp/insert-shift-delete-cut.log"
insert_cut_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'insert shift-delete cut', 'line 2', 'line 3'}); vim.g.dotfiles_tmux_copy_lines = {}; vim.g.dotfiles_tmux_copy_type = ''; vim.cmd('normal! gg$'); vim.cmd('startinsert!')"
insert_cut_write_command="lua vim.fn.writefile({table.concat(vim.g.dotfiles_tmux_copy_lines, '|'), vim.g.dotfiles_tmux_copy_type, table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '|')}, $(lua_string "$insert_cut_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$insert_cut_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_delete_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "Z"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$insert_cut_write_command" Enter
wait_for_file "$insert_cut_result"
assert_eq "tmux passes Shift-Delete bytes to insert Neovim cut" \
  "$(printf 'insert shift-delete cut|\nV\nline 2Z|line 3')" \
  "$(cat "$insert_cut_result")"

insert_ctrl_backspace_result="$tmp/insert-ctrl-backspace-word.log"
insert_ctrl_backspace_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'insert ctrl backspace alpha beta gamma'}); vim.cmd('normal! gg$'); vim.cmd('startinsert!')"
insert_ctrl_backspace_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line()}, $(lua_string "$insert_ctrl_backspace_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$insert_ctrl_backspace_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$ctrl_backspace_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "Z"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$insert_ctrl_backspace_write_command" Enter
wait_for_file "$insert_ctrl_backspace_result"
assert_eq "tmux passes Ctrl-Backspace bytes to insert Neovim delete-previous-word" \
  "insert ctrl backspace alpha beta Z" \
  "$(cat "$insert_ctrl_backspace_result")"

insert_ctrl_left_result="$tmp/insert-ctrl-left-word.log"
insert_ctrl_left_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'insert ctrl left alpha beta gamma'}); vim.cmd('normal! gg$'); vim.cmd('startinsert!')"
insert_ctrl_left_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line()}, $(lua_string "$insert_ctrl_left_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$insert_ctrl_left_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$ctrl_left_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "Z"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$insert_ctrl_left_write_command" Enter
wait_for_file "$insert_ctrl_left_result"
assert_eq "tmux passes Ctrl-Left bytes to insert Neovim previous-word motion" \
  "insert ctrl left alpha beta Zgamma" \
  "$(cat "$insert_ctrl_left_result")"

insert_ctrl_right_result="$tmp/insert-ctrl-right-word.log"
insert_ctrl_right_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'insert ctrl right alpha beta gamma'}); vim.cmd('normal! gg0'); vim.cmd('startinsert')"
insert_ctrl_right_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line()}, $(lua_string "$insert_ctrl_right_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$insert_ctrl_right_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$ctrl_right_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "Z"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$insert_ctrl_right_write_command" Enter
wait_for_file "$insert_ctrl_right_result"
assert_eq "tmux passes Ctrl-Right bytes to insert Neovim next-word motion" \
  "insertZ ctrl right alpha beta gamma" \
  "$(cat "$insert_ctrl_right_result")"

insert_ctrl_delete_result="$tmp/insert-ctrl-delete-word.log"
insert_ctrl_delete_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'insert ctrl delete alpha beta gamma'}); vim.fn.setreg('\"', 'KEEP-TMUX-INSERT-CTRL-DELETE', 'v'); vim.cmd('normal! gg04w'); vim.cmd('startinsert')"
insert_ctrl_delete_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line(), vim.fn.getreg('\"')}, $(lua_string "$insert_ctrl_delete_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$insert_ctrl_delete_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$ctrl_delete_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "Z"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$insert_ctrl_delete_write_command" Enter
wait_for_file "$insert_ctrl_delete_result"
assert_eq "tmux passes Ctrl-Delete bytes to insert Neovim delete-next-word" \
  "$(printf 'insert ctrl delete alpha Zgamma\nKEEP-TMUX-INSERT-CTRL-DELETE')" \
  "$(cat "$insert_ctrl_delete_result")"

normal_copy_result="$tmp/normal-ctrl-insert-copy.log"
normal_copy_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'ctrl-insert copy', 'line 2'}); vim.g.dotfiles_tmux_copy_lines = {}; vim.g.dotfiles_tmux_copy_type = ''; vim.cmd('normal! gg')"
normal_copy_write_command="lua vim.fn.writefile({table.concat(vim.g.dotfiles_tmux_copy_lines, '|'), vim.g.dotfiles_tmux_copy_type, table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '|')}, $(lua_string "$normal_copy_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$normal_copy_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$ctrl_insert_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$normal_copy_write_command" Enter
wait_for_file "$normal_copy_result"
assert_eq "tmux passes Ctrl-Insert bytes to normal Neovim copy" \
  "$(printf 'ctrl-insert copy|\nV\nctrl-insert copy|line 2')" \
  "$(cat "$normal_copy_result")"

normal_ctrl_backspace_result="$tmp/normal-ctrl-backspace-word.log"
normal_ctrl_backspace_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'normal ctrl backspace alpha beta gamma'}); vim.cmd('normal! gg$')"
normal_ctrl_backspace_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line()}, $(lua_string "$normal_ctrl_backspace_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$normal_ctrl_backspace_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$ctrl_backspace_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$normal_ctrl_backspace_write_command" Enter
wait_for_file "$normal_ctrl_backspace_result"
assert_eq "tmux passes Ctrl-Backspace bytes to normal Neovim delete-previous-word" \
  "normal ctrl backspace alpha beta " \
  "$(cat "$normal_ctrl_backspace_result")"

normal_ctrl_left_result="$tmp/normal-ctrl-left-word.log"
normal_ctrl_left_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'normal ctrl left alpha beta gamma'}); vim.cmd('normal! gg$')"
normal_ctrl_left_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line()}, $(lua_string "$normal_ctrl_left_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$normal_ctrl_left_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$ctrl_left_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "iZ"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$normal_ctrl_left_write_command" Enter
wait_for_file "$normal_ctrl_left_result"
assert_eq "tmux passes Ctrl-Left bytes to normal Neovim previous-word motion" \
  "normal ctrl left alpha beta Zgamma" \
  "$(cat "$normal_ctrl_left_result")"

normal_ctrl_right_result="$tmp/normal-ctrl-right-word.log"
normal_ctrl_right_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'normal ctrl right alpha beta gamma'}); vim.cmd('normal! gg0')"
normal_ctrl_right_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line()}, $(lua_string "$normal_ctrl_right_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$normal_ctrl_right_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$ctrl_right_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "aZ"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$normal_ctrl_right_write_command" Enter
wait_for_file "$normal_ctrl_right_result"
assert_eq "tmux passes Ctrl-Right bytes to normal Neovim next-word motion" \
  "normalZ ctrl right alpha beta gamma" \
  "$(cat "$normal_ctrl_right_result")"

normal_ctrl_delete_result="$tmp/normal-ctrl-delete-word.log"
normal_ctrl_delete_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'normal ctrl delete alpha beta gamma'}); vim.fn.setreg('\"', 'KEEP-TMUX-NORMAL-CTRL-DELETE', 'v'); vim.cmd('normal! gg04w')"
normal_ctrl_delete_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line(), vim.fn.getreg('\"')}, $(lua_string "$normal_ctrl_delete_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$normal_ctrl_delete_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$ctrl_delete_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$normal_ctrl_delete_write_command" Enter
wait_for_file "$normal_ctrl_delete_result"
assert_eq "tmux passes Ctrl-Delete bytes to normal Neovim delete-next-word" \
  "$(printf 'normal ctrl delete alpha gamma\nKEEP-TMUX-NORMAL-CTRL-DELETE')" \
  "$(cat "$normal_ctrl_delete_result")"

visual_copy_result="$tmp/visual-ctrl-insert-copy.log"
visual_copy_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'copy selection', 'line 2'}); vim.g.dotfiles_tmux_copy_lines = {}; vim.g.dotfiles_tmux_copy_type = ''; vim.cmd('normal! gg0')"
visual_copy_write_command="lua vim.fn.writefile({table.concat(vim.g.dotfiles_tmux_copy_lines, '|'), vim.g.dotfiles_tmux_copy_type, table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '|')}, $(lua_string "$visual_copy_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$visual_copy_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l 'v4l'
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$ctrl_insert_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$visual_copy_write_command" Enter
wait_for_file "$visual_copy_result"
assert_eq "tmux passes Ctrl-Insert bytes to visual Neovim copy" \
  "$(printf 'copy \nv\ncopy selection|line 2')" \
  "$(cat "$visual_copy_result")"

normal_cut_result="$tmp/normal-shift-delete-cut.log"
normal_cut_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'shift-delete cut', 'line 2', 'line 3'}); vim.g.dotfiles_tmux_copy_lines = {}; vim.g.dotfiles_tmux_copy_type = ''; vim.cmd('normal! gg')"
normal_cut_write_command="lua vim.fn.writefile({table.concat(vim.g.dotfiles_tmux_copy_lines, '|'), vim.g.dotfiles_tmux_copy_type, table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '|')}, $(lua_string "$normal_cut_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$normal_cut_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_delete_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$normal_cut_write_command" Enter
wait_for_file "$normal_cut_result"
assert_eq "tmux passes Shift-Delete bytes to normal Neovim cut" \
  "$(printf 'shift-delete cut|\nV\nline 2|line 3')" \
  "$(cat "$normal_cut_result")"

visual_cut_result="$tmp/visual-shift-delete-cut.log"
visual_cut_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'delete selection', 'line 2'}); vim.g.dotfiles_tmux_copy_lines = {}; vim.g.dotfiles_tmux_copy_type = ''; vim.cmd('normal! gg0')"
visual_cut_write_command="lua vim.fn.writefile({table.concat(vim.g.dotfiles_tmux_copy_lines, '|'), vim.g.dotfiles_tmux_copy_type, table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '|')}, $(lua_string "$visual_cut_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$visual_cut_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l 'v5l'
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_delete_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$visual_cut_write_command" Enter
wait_for_file "$visual_cut_result"
assert_eq "tmux passes Shift-Delete bytes to visual Neovim cut" \
  "$(printf 'delete\nv\n selection|line 2')" \
  "$(cat "$visual_cut_result")"

terminal_normal_copy_result="$tmp/terminal-normal-ctrl-insert-copy.log"
terminal_normal_copy_command="lua vim.cmd('enew'); vim.g.dotfiles_tmux_terminal_copy_job = vim.fn.termopen({'sh', '-c', 'printf \"terminal normal copy via tmux\\\\nsecond line\\\\n\"; cat >/dev/null'}); assert(type(vim.g.dotfiles_tmux_terminal_copy_job) == 'number' and vim.g.dotfiles_tmux_terminal_copy_job > 0); assert(vim.wait(1000, function() return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'):find('second line', 1, true) ~= nil end)); vim.g.dotfiles_tmux_copy_lines = {}; vim.g.dotfiles_tmux_copy_type = ''"
terminal_normal_copy_write_command="lua local lines = vim.api.nvim_buf_get_lines(0, 0, 2, false); vim.fn.writefile({table.concat(vim.g.dotfiles_tmux_copy_lines, '|'), vim.g.dotfiles_tmux_copy_type, table.concat(lines, '|')}, $(lua_string "$terminal_normal_copy_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$terminal_normal_copy_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$ctrl_insert_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$terminal_normal_copy_write_command" Enter
wait_for_file "$terminal_normal_copy_result"
assert_eq "tmux passes Ctrl-Insert bytes to terminal-normal Neovim copy" \
  "$(printf 'terminal normal copy via tmux|\nV\nterminal normal copy via tmux|second line')" \
  "$(cat "$terminal_normal_copy_result")"
terminal_normal_copy_cleanup="$tmp/terminal-normal-ctrl-insert-copy-cleanup.log"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' \
  "lua vim.fn.chanclose(vim.g.dotfiles_tmux_terminal_copy_job, 'stdin'); vim.cmd('enew!'); vim.fn.writefile({'ok'}, $(lua_string "$terminal_normal_copy_cleanup"))" Enter
wait_for_file "$terminal_normal_copy_cleanup"

terminal_visual_copy_result="$tmp/terminal-visual-ctrl-insert-copy.log"
terminal_visual_copy_ready="$tmp/terminal-visual-ctrl-insert-copy-ready.log"
terminal_visual_copy_command="lua vim.cmd('enew'); vim.g.dotfiles_tmux_terminal_visual_copy_job = vim.fn.termopen({'sh', '-c', 'printf \"terminal visual copy via tmux\\\\nsecond line\\\\n\"; cat >/dev/null'}); assert(type(vim.g.dotfiles_tmux_terminal_visual_copy_job) == 'number' and vim.g.dotfiles_tmux_terminal_visual_copy_job > 0); assert(vim.wait(1000, function() return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'):find('second line', 1, true) ~= nil end)); vim.g.dotfiles_tmux_copy_lines = {}; vim.g.dotfiles_tmux_copy_type = ''"
terminal_visual_copy_wait_command="lua assert(vim.wait(1000, function() return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'):find('second line', 1, true) ~= nil end)); vim.fn.writefile({'ok'}, $(lua_string "$terminal_visual_copy_ready"))"
terminal_visual_copy_write_command="lua local lines = vim.api.nvim_buf_get_lines(0, 0, 2, false); vim.fn.writefile({table.concat(vim.g.dotfiles_tmux_copy_lines, '|'), vim.g.dotfiles_tmux_copy_type, table.concat(lines, '|')}, $(lua_string "$terminal_visual_copy_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$terminal_visual_copy_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$terminal_visual_copy_wait_command" Enter
wait_for_file "$terminal_visual_copy_ready"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l 'gg0v$'
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$ctrl_insert_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$nvim_terminal_normal_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$terminal_visual_copy_write_command" Enter
wait_for_file "$terminal_visual_copy_result"
assert_eq "tmux passes Ctrl-Insert bytes to terminal-visual Neovim copy" \
  "$(printf 'terminal visual copy via tmux|\nv\nterminal visual copy via tmux|second line')" \
  "$(cat "$terminal_visual_copy_result")"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' \
  "lua vim.fn.chanclose(vim.g.dotfiles_tmux_terminal_visual_copy_job, 'stdin'); vim.cmd('enew!')" Enter

terminal_normal_cut_result="$tmp/terminal-normal-shift-delete-cut.log"
terminal_normal_cut_command="lua vim.cmd('enew'); vim.g.dotfiles_tmux_terminal_cut_job = vim.fn.termopen({'sh', '-c', 'printf \"terminal normal cut via tmux\\\\nsecond line\\\\n\"; cat >/dev/null'}); assert(type(vim.g.dotfiles_tmux_terminal_cut_job) == 'number' and vim.g.dotfiles_tmux_terminal_cut_job > 0); assert(vim.wait(1000, function() return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'):find('second line', 1, true) ~= nil end)); vim.g.dotfiles_tmux_copy_lines = {}; vim.g.dotfiles_tmux_copy_type = ''"
terminal_normal_cut_write_command="lua local lines = vim.api.nvim_buf_get_lines(0, 0, 2, false); vim.fn.writefile({table.concat(vim.g.dotfiles_tmux_copy_lines, '|'), vim.g.dotfiles_tmux_copy_type, table.concat(lines, '|')}, $(lua_string "$terminal_normal_cut_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$terminal_normal_cut_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_delete_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$terminal_normal_cut_write_command" Enter
wait_for_file "$terminal_normal_cut_result"
assert_eq "tmux passes Shift-Delete bytes to terminal-normal Neovim copy-only cut" \
  "$(printf 'terminal normal cut via tmux|\nV\nterminal normal cut via tmux|second line')" \
  "$(cat "$terminal_normal_cut_result")"
terminal_normal_cut_cleanup="$tmp/terminal-normal-shift-delete-cut-cleanup.log"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' \
  "lua vim.fn.chanclose(vim.g.dotfiles_tmux_terminal_cut_job, 'stdin'); vim.cmd('enew!'); vim.fn.writefile({'ok'}, $(lua_string "$terminal_normal_cut_cleanup"))" Enter
wait_for_file "$terminal_normal_cut_cleanup"

terminal_visual_cut_result="$tmp/terminal-visual-shift-delete-cut.log"
terminal_visual_cut_ready="$tmp/terminal-visual-shift-delete-cut-ready.log"
terminal_visual_cut_command="lua vim.cmd('enew'); vim.g.dotfiles_tmux_terminal_visual_cut_job = vim.fn.termopen({'sh', '-c', 'printf \"terminal visual cut via tmux\\\\nsecond line\\\\n\"; cat >/dev/null'}); assert(type(vim.g.dotfiles_tmux_terminal_visual_cut_job) == 'number' and vim.g.dotfiles_tmux_terminal_visual_cut_job > 0); assert(vim.wait(1000, function() return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'):find('second line', 1, true) ~= nil end)); vim.g.dotfiles_tmux_copy_lines = {}; vim.g.dotfiles_tmux_copy_type = ''"
terminal_visual_cut_wait_command="lua assert(vim.wait(1000, function() return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'):find('second line', 1, true) ~= nil end)); vim.fn.writefile({'ok'}, $(lua_string "$terminal_visual_cut_ready"))"
terminal_visual_cut_write_command="lua local lines = vim.api.nvim_buf_get_lines(0, 0, 2, false); vim.fn.writefile({table.concat(vim.g.dotfiles_tmux_copy_lines, '|'), vim.g.dotfiles_tmux_copy_type, table.concat(lines, '|')}, $(lua_string "$terminal_visual_cut_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$terminal_visual_cut_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$terminal_visual_cut_wait_command" Enter
wait_for_file "$terminal_visual_cut_ready"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l 'gg0v$'
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_delete_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$nvim_terminal_normal_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$terminal_visual_cut_write_command" Enter
wait_for_file "$terminal_visual_cut_result"
assert_eq "tmux passes Shift-Delete bytes to terminal-visual Neovim copy-only cut" \
  "$(printf 'terminal visual cut via tmux|\nv\nterminal visual cut via tmux|second line')" \
  "$(cat "$terminal_visual_cut_result")"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' \
  "lua vim.fn.chanclose(vim.g.dotfiles_tmux_terminal_visual_cut_job, 'stdin'); vim.cmd('enew!')" Enter

normal_shift_insert_result="$tmp/normal-shift-insert-paste.log"
normal_shift_insert_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'normal counted paste'}); vim.g.dotfiles_tmux_paste = ' plus'; vim.cmd('normal! gg$')"
normal_shift_insert_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line()}, $(lua_string "$normal_shift_insert_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$normal_shift_insert_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l '2'
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_insert_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$normal_shift_insert_write_command" Enter
wait_for_file "$normal_shift_insert_result"
assert_eq "tmux passes Shift-Insert bytes to normal Neovim paste with count" \
  "normal counted paste plus plus" \
  "$(cat "$normal_shift_insert_result")"

visual_shift_insert_result="$tmp/visual-shift-insert-paste.log"
visual_shift_insert_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'AAA old ZZZ'}); vim.g.dotfiles_tmux_paste = 'new'; vim.fn.setreg('\"', 'unnamed keep', 'v'); vim.cmd('normal! gg04l')"
visual_shift_insert_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line(), vim.fn.getreg('\"'), vim.fn.getregtype('\"')}, $(lua_string "$visual_shift_insert_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$visual_shift_insert_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l 'v2l'
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_insert_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$visual_shift_insert_write_command" Enter
wait_for_file "$visual_shift_insert_result"
assert_eq "tmux passes Shift-Insert bytes to visual Neovim paste without clobbering unnamed register" \
  "$(printf 'AAA new ZZZ\nunnamed keep\nv')" \
  "$(cat "$visual_shift_insert_result")"

shift_insert_result="$tmp/shift-insert-paste.log"
shift_insert_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'shift-insert '}); vim.g.dotfiles_tmux_paste = 'paste via tmux'; vim.cmd('startinsert!')"
shift_insert_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line()}, $(lua_string "$shift_insert_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$shift_insert_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_insert_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$shift_insert_write_command" Enter
wait_for_file "$shift_insert_result"
assert_eq "tmux passes Shift-Insert bytes to insert Neovim paste" "shift-insert paste via tmux" "$(cat "$shift_insert_result")"

cmdline_shift_insert_result="$tmp/cmdline-shift-insert-paste.log"
cmdline_shift_insert_setup="lua vim.g.dotfiles_tmux_paste = 'cmdline shift-insert via tmux'"
cmdline_shift_insert_write_command="lua vim.fn.writefile({tostring(vim.g.dotfiles_tmux_cmdline_paste)}, $(lua_string "$cmdline_shift_insert_result"))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$cmdline_shift_insert_setup" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "let g:dotfiles_tmux_cmdline_paste = '"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_insert_sequence"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" "'" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$cmdline_shift_insert_write_command" Enter
wait_for_file "$cmdline_shift_insert_result"
assert_eq "tmux passes Shift-Insert bytes to command-line Neovim paste" \
  "cmdline shift-insert via tmux" \
  "$(cat "$cmdline_shift_insert_result")"

terminal_normal_shift_insert_output="$tmp/terminal-normal-shift-insert-paste.log"
terminal_normal_shift_insert_command="lua vim.cmd('enew'); vim.g.dotfiles_tmux_terminal_paste_job = vim.fn.termopen({'sh', '-c', 'cat > \"\$1\"', 'sh', $(lua_string "$terminal_normal_shift_insert_output")}); assert(type(vim.g.dotfiles_tmux_terminal_paste_job) == 'number' and vim.g.dotfiles_tmux_terminal_paste_job > 0); vim.g.dotfiles_tmux_paste = 'terminal-normal shift-insert via tmux\n'"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$terminal_normal_shift_insert_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_insert_sequence"
wait_for_file_content "$terminal_normal_shift_insert_output" "terminal-normal shift-insert via tmux"
assert_eq "tmux passes Shift-Insert bytes to terminal-normal Neovim paste" \
  "terminal-normal shift-insert via tmux" \
  "$(cat "$terminal_normal_shift_insert_output")"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' \
  "lua vim.fn.chanclose(vim.g.dotfiles_tmux_terminal_paste_job, 'stdin'); vim.cmd('enew!')" Enter

terminal_visual_shift_insert_output="$tmp/terminal-visual-shift-insert-paste.log"
terminal_visual_shift_insert_command="lua vim.cmd('enew'); vim.g.dotfiles_tmux_terminal_visual_paste_job = vim.fn.termopen({'sh', '-c', 'printf \"terminal visual selection\\\\n\"; cat > \"\$1\"', 'sh', $(lua_string "$terminal_visual_shift_insert_output")}); assert(type(vim.g.dotfiles_tmux_terminal_visual_paste_job) == 'number' and vim.g.dotfiles_tmux_terminal_visual_paste_job > 0); vim.g.dotfiles_tmux_paste = 'terminal-visual shift-insert via tmux\n'"
terminal_visual_wait_command="lua assert(vim.wait(1000, function() return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'):find('terminal visual selection', 1, true) ~= nil end))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$terminal_visual_shift_insert_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$terminal_visual_wait_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l 'gg0v$'
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_insert_sequence"
wait_for_file_content "$terminal_visual_shift_insert_output" "terminal-visual shift-insert via tmux"
assert_eq "tmux passes Shift-Insert bytes to terminal-visual Neovim paste" \
  "terminal-visual shift-insert via tmux" \
  "$(cat "$terminal_visual_shift_insert_output")"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' \
  "lua vim.fn.chanclose(vim.g.dotfiles_tmux_terminal_visual_paste_job, 'stdin'); vim.cmd('enew!')" Enter

terminal_mode_shift_insert_output="$tmp/terminal-mode-shift-insert-paste.log"
terminal_mode_shift_insert_command="lua vim.cmd('enew'); vim.g.dotfiles_tmux_terminal_mode_paste_job = vim.fn.termopen({'sh', '-c', 'cat > \"\$1\"', 'sh', $(lua_string "$terminal_mode_shift_insert_output")}); assert(type(vim.g.dotfiles_tmux_terminal_mode_paste_job) == 'number' and vim.g.dotfiles_tmux_terminal_mode_paste_job > 0); vim.g.dotfiles_tmux_paste = 'terminal-mode shift-insert via tmux\n'; vim.cmd('startinsert')"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$terminal_mode_shift_insert_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_insert_sequence"
wait_for_file_content "$terminal_mode_shift_insert_output" "terminal-mode shift-insert via tmux"
assert_eq "tmux passes Shift-Insert bytes to terminal-mode Neovim paste" \
  "terminal-mode shift-insert via tmux" \
  "$(cat "$terminal_mode_shift_insert_output")"
terminal_mode_shift_insert_cleanup="$tmp/terminal-mode-shift-insert-paste-cleanup.log"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" "C-\\" C-n
sleep 0.2
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' \
  "lua vim.fn.chanclose(vim.g.dotfiles_tmux_terminal_mode_paste_job, 'stdin'); vim.cmd('enew!'); vim.fn.writefile({'ok'}, $(lua_string "$terminal_mode_shift_insert_cleanup"))" Enter
wait_for_file "$terminal_mode_shift_insert_cleanup"

terminal_mode_ctrl_insert_result="$tmp/terminal-mode-ctrl-insert-copy.log"
terminal_mode_ctrl_insert_output="$tmp/terminal-mode-ctrl-insert-copy-output.log"
terminal_mode_ctrl_insert_command="$(terminal_mode_copy_setup_command \
  "dotfiles_tmux_terminal_mode_copy_job" \
  "terminal mode copy via tmux" \
  "$terminal_mode_ctrl_insert_output")"
terminal_mode_ctrl_insert_write_command="$(terminal_mode_key_result_command \
  "dotfiles_tmux_terminal_mode_copy_job" \
  "$terminal_mode_ctrl_insert_output" \
  "$terminal_mode_ctrl_insert_result")"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$terminal_mode_ctrl_insert_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$ctrl_insert_sequence"
sleep 0.2
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" "C-\\" C-n
sleep 0.2
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$terminal_mode_ctrl_insert_write_command" Enter
wait_for_file "$terminal_mode_ctrl_insert_result"
assert_eq "tmux passes Ctrl-Insert bytes to terminal-mode Neovim copy without leaking to job" \
  "$(printf 'terminal mode copy via tmux|\nV\nterminal mode copy via tmux\n')" \
  "$(cat "$terminal_mode_ctrl_insert_result")"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' 'enew!' Enter

terminal_mode_shift_delete_result="$tmp/terminal-mode-shift-delete-cut.log"
terminal_mode_shift_delete_output="$tmp/terminal-mode-shift-delete-cut-output.log"
terminal_mode_shift_delete_command="$(terminal_mode_copy_setup_command \
  "dotfiles_tmux_terminal_mode_cut_job" \
  "terminal mode cut via tmux" \
  "$terminal_mode_shift_delete_output")"
terminal_mode_shift_delete_write_command="$(terminal_mode_key_result_command \
  "dotfiles_tmux_terminal_mode_cut_job" \
  "$terminal_mode_shift_delete_output" \
  "$terminal_mode_shift_delete_result")"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$terminal_mode_shift_delete_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_delete_sequence"
sleep 0.2
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" "C-\\" C-n
sleep 0.2
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$terminal_mode_shift_delete_write_command" Enter
wait_for_file "$terminal_mode_shift_delete_result"
assert_eq "tmux passes Shift-Delete bytes to terminal-mode Neovim copy-only cut without leaking to job" \
  "$(printf 'terminal mode cut via tmux|\nV\nterminal mode cut via tmux\n')" \
  "$(cat "$terminal_mode_shift_delete_result")"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' 'enew!' Enter

if python3_path="$(command -v python3 2>/dev/null)"; then
  send_attached_client_key() {
    local name="$1"
    local sequence="$2"

    if ! TERM=xterm-256color TERM_PROGRAM=vscode "$python3_path" - "$tmux_bin" "$socket_name" "nvim-keys" "$sequence" <<'PY'
import os
import pty
import select
import subprocess
import sys
import time

tmux_path, socket_name, session_name, sequence = sys.argv[1:]
env = os.environ.copy()
env.update({
    "TERM": "xterm-256color",
    "TERM_PROGRAM": "vscode",
})
sequence_bytes = sequence.encode("utf-8")

master, slave = pty.openpty()
try:
    proc = subprocess.Popen(
        [tmux_path, "-L", socket_name, "attach-session", "-t", session_name],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
finally:
    os.close(slave)

try:
    deadline = time.time() + 5
    sent = False
    while time.time() < deadline:
        ready, _, _ = select.select([master], [], [], 0.05)
        if ready:
            try:
                os.read(master, 4096)
            except OSError:
                break

        if not sent and time.time() > deadline - 4.5:
            os.write(master, sequence_bytes)
            # Keep the transient client alive long enough for tmux's async
            # if-shell key callbacks to resolve on slower CI runners.
            settle_deadline = time.time() + 1.0
            while time.time() < settle_deadline:
                ready, _, _ = select.select([master], [], [], 0.05)
                if ready:
                    try:
                        os.read(master, 4096)
                    except OSError:
                        break
            sys.exit(0)

    print("timeout sending attached tmux key sequence")
    sys.exit(1)
finally:
    proc.terminate()
    try:
        proc.wait(timeout=1)
    except subprocess.TimeoutExpired:
        proc.kill()
    os.close(master)
PY
    then
      printf 'not ok - %s\n' "$name" >&2
      exit 1
    fi
  }

  attached_shift_insert_result="$tmp/attached-shift-insert-paste.log"
  attached_shift_insert_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'attached shift-insert '}); vim.g.dotfiles_tmux_paste = 'paste via attached tmux'; vim.cmd('startinsert!')"
  attached_shift_insert_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line()}, $(lua_string "$attached_shift_insert_result"))"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_shift_insert_command" Enter
  send_attached_client_key "tmux attached client sends Shift-Insert bytes" "$shift_insert_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_shift_insert_write_command" Enter
  wait_for_file "$attached_shift_insert_result"
  assert_eq "tmux attached client passes Shift-Insert bytes through to Neovim paste" \
    "attached shift-insert paste via attached tmux" \
    "$(cat "$attached_shift_insert_result")"

  attached_cmdline_shift_insert_result="$tmp/attached-cmdline-shift-insert-paste.log"
  attached_cmdline_shift_insert_setup="lua vim.g.dotfiles_tmux_paste = 'attached cmdline shift-insert via tmux'"
  attached_cmdline_shift_insert_write_command="lua vim.fn.writefile({tostring(vim.g.dotfiles_tmux_attached_cmdline_paste)}, $(lua_string "$attached_cmdline_shift_insert_result"))"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_cmdline_shift_insert_setup" Enter
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "let g:dotfiles_tmux_attached_cmdline_paste = '"
  send_attached_client_key "tmux attached client sends Shift-Insert bytes to command-line Neovim" "$shift_insert_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" "'" Enter
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_cmdline_shift_insert_write_command" Enter
  wait_for_file "$attached_cmdline_shift_insert_result"
  assert_eq "tmux attached client passes Shift-Insert bytes through to command-line Neovim paste" \
    "attached cmdline shift-insert via tmux" \
    "$(cat "$attached_cmdline_shift_insert_result")"

  attached_normal_shift_insert_result="$tmp/attached-normal-shift-insert-paste.log"
  attached_normal_shift_insert_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'attached normal paste'}); vim.g.dotfiles_tmux_paste = ' plus'; vim.cmd('normal! gg$')"
  attached_normal_shift_insert_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line()}, $(lua_string "$attached_normal_shift_insert_result"))"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_normal_shift_insert_command" Enter
  send_attached_client_key "tmux attached client sends Shift-Insert bytes to normal Neovim" "$shift_insert_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_normal_shift_insert_write_command" Enter
  wait_for_file "$attached_normal_shift_insert_result"
  assert_eq "tmux attached client passes Shift-Insert bytes through to normal Neovim paste" \
    "attached normal paste plus" \
    "$(cat "$attached_normal_shift_insert_result")"

  attached_visual_shift_insert_result="$tmp/attached-visual-shift-insert-paste.log"
  attached_visual_shift_insert_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'AAA old ZZZ'}); vim.g.dotfiles_tmux_paste = 'new'; vim.fn.setreg('\"', 'attached unnamed keep', 'v'); vim.cmd('normal! gg04l')"
  attached_visual_shift_insert_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line(), vim.fn.getreg('\"'), vim.fn.getregtype('\"')}, $(lua_string "$attached_visual_shift_insert_result"))"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_visual_shift_insert_command" Enter
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l 'v2l'
  send_attached_client_key "tmux attached client sends Shift-Insert bytes to visual Neovim" "$shift_insert_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_visual_shift_insert_write_command" Enter
  wait_for_file "$attached_visual_shift_insert_result"
  assert_eq "tmux attached client passes Shift-Insert bytes through to visual Neovim paste without clobbering unnamed register" \
    "$(printf 'AAA new ZZZ\nattached unnamed keep\nv')" \
    "$(cat "$attached_visual_shift_insert_result")"

  attached_terminal_shift_insert_output="$tmp/attached-terminal-shift-insert-paste.log"
  attached_terminal_shift_insert_command="lua vim.cmd('enew'); vim.g.dotfiles_tmux_attached_terminal_paste_job = vim.fn.termopen({'sh', '-c', 'cat > \"\$1\"', 'sh', $(lua_string "$attached_terminal_shift_insert_output")}); assert(type(vim.g.dotfiles_tmux_attached_terminal_paste_job) == 'number' and vim.g.dotfiles_tmux_attached_terminal_paste_job > 0); vim.g.dotfiles_tmux_paste = 'attached terminal shift-insert via tmux\n'"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_terminal_shift_insert_command" Enter
  send_attached_client_key "tmux attached client sends Shift-Insert bytes to terminal Neovim" "$shift_insert_sequence"
  wait_for_file_content "$attached_terminal_shift_insert_output" "attached terminal shift-insert via tmux"
  assert_eq "tmux attached client passes Shift-Insert bytes through to terminal Neovim paste" \
    "attached terminal shift-insert via tmux" \
    "$(cat "$attached_terminal_shift_insert_output")"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' \
    "lua vim.fn.chanclose(vim.g.dotfiles_tmux_attached_terminal_paste_job, 'stdin'); vim.cmd('enew!')" Enter

  attached_terminal_mode_shift_insert_output="$tmp/attached-terminal-mode-shift-insert-paste.log"
  attached_terminal_mode_shift_insert_command="lua vim.cmd('enew'); vim.g.dotfiles_tmux_attached_terminal_mode_paste_job = vim.fn.termopen({'sh', '-c', 'cat > \"\$1\"', 'sh', $(lua_string "$attached_terminal_mode_shift_insert_output")}); assert(type(vim.g.dotfiles_tmux_attached_terminal_mode_paste_job) == 'number' and vim.g.dotfiles_tmux_attached_terminal_mode_paste_job > 0); vim.g.dotfiles_tmux_paste = 'attached terminal-mode shift-insert via tmux\n'; vim.cmd('startinsert')"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_terminal_mode_shift_insert_command" Enter
  send_attached_client_key "tmux attached client sends Shift-Insert bytes to terminal-mode Neovim" "$shift_insert_sequence"
  wait_for_file_content "$attached_terminal_mode_shift_insert_output" "attached terminal-mode shift-insert via tmux"
  assert_eq "tmux attached client passes Shift-Insert bytes through to terminal-mode Neovim paste" \
    "attached terminal-mode shift-insert via tmux" \
    "$(cat "$attached_terminal_mode_shift_insert_output")"
  attached_terminal_mode_shift_insert_cleanup="$tmp/attached-terminal-mode-shift-insert-paste-cleanup.log"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" "C-\\" C-n
  sleep 0.2
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' \
    "lua vim.fn.chanclose(vim.g.dotfiles_tmux_attached_terminal_mode_paste_job, 'stdin'); vim.cmd('enew!'); vim.fn.writefile({'ok'}, $(lua_string "$attached_terminal_mode_shift_insert_cleanup"))" Enter
  wait_for_file "$attached_terminal_mode_shift_insert_cleanup"

  attached_terminal_mode_ctrl_insert_result="$tmp/attached-terminal-mode-ctrl-insert-copy.log"
  attached_terminal_mode_ctrl_insert_output="$tmp/attached-terminal-mode-ctrl-insert-copy-output.log"
  attached_terminal_mode_ctrl_insert_command="$(terminal_mode_copy_setup_command \
    "dotfiles_tmux_attached_terminal_mode_copy_job" \
    "attached terminal mode ctrl-insert copy via tmux" \
    "$attached_terminal_mode_ctrl_insert_output")"
  attached_terminal_mode_ctrl_insert_write_command="$(terminal_mode_key_result_command \
    "dotfiles_tmux_attached_terminal_mode_copy_job" \
    "$attached_terminal_mode_ctrl_insert_output" \
    "$attached_terminal_mode_ctrl_insert_result")"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_terminal_mode_ctrl_insert_command" Enter
  send_attached_client_key "tmux attached client sends Ctrl-Insert bytes to terminal-mode Neovim" "$ctrl_insert_sequence"
  sleep 0.2
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" "C-\\" C-n
  sleep 0.2
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_terminal_mode_ctrl_insert_write_command" Enter
  wait_for_file "$attached_terminal_mode_ctrl_insert_result"
  assert_eq "tmux attached client passes Ctrl-Insert bytes through to terminal-mode Neovim copy without leaking to job" \
    "$(printf 'attached terminal mode ctrl-insert copy via tmux|\nV\nattached terminal mode ctrl-insert copy via tmux\n')" \
    "$(cat "$attached_terminal_mode_ctrl_insert_result")"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' 'enew!' Enter

  attached_terminal_mode_shift_delete_result="$tmp/attached-terminal-mode-shift-delete-cut.log"
  attached_terminal_mode_shift_delete_output="$tmp/attached-terminal-mode-shift-delete-cut-output.log"
  attached_terminal_mode_shift_delete_command="$(terminal_mode_copy_setup_command \
    "dotfiles_tmux_attached_terminal_mode_cut_job" \
    "attached terminal mode shift-delete cut via tmux" \
    "$attached_terminal_mode_shift_delete_output")"
  attached_terminal_mode_shift_delete_write_command="$(terminal_mode_key_result_command \
    "dotfiles_tmux_attached_terminal_mode_cut_job" \
    "$attached_terminal_mode_shift_delete_output" \
    "$attached_terminal_mode_shift_delete_result")"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_terminal_mode_shift_delete_command" Enter
  send_attached_client_key "tmux attached client sends Shift-Delete bytes to terminal-mode Neovim" "$shift_delete_sequence"
  sleep 0.2
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" "C-\\" C-n
  sleep 0.2
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_terminal_mode_shift_delete_write_command" Enter
  wait_for_file "$attached_terminal_mode_shift_delete_result"
  assert_eq "tmux attached client passes Shift-Delete bytes through to terminal-mode Neovim copy-only cut without leaking to job" \
    "$(printf 'attached terminal mode shift-delete cut via tmux|\nV\nattached terminal mode shift-delete cut via tmux\n')" \
    "$(cat "$attached_terminal_mode_shift_delete_result")"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' 'enew!' Enter

  attached_terminal_ctrl_insert_result="$tmp/attached-terminal-ctrl-insert-copy.log"
  attached_terminal_ctrl_insert_command="lua vim.cmd('enew'); vim.g.dotfiles_tmux_attached_terminal_copy_job = vim.fn.termopen({'sh', '-c', 'printf \"attached terminal ctrl-insert copy via tmux\\\\nsecond line\\\\n\"; cat >/dev/null'}); assert(type(vim.g.dotfiles_tmux_attached_terminal_copy_job) == 'number' and vim.g.dotfiles_tmux_attached_terminal_copy_job > 0); assert(vim.wait(1000, function() return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'):find('second line', 1, true) ~= nil end)); vim.g.dotfiles_tmux_copy_lines = {}; vim.g.dotfiles_tmux_copy_type = ''"
  attached_terminal_ctrl_insert_write_command="lua local lines = vim.api.nvim_buf_get_lines(0, 0, 2, false); vim.fn.writefile({table.concat(vim.g.dotfiles_tmux_copy_lines, '|'), vim.g.dotfiles_tmux_copy_type, table.concat(lines, '|')}, $(lua_string "$attached_terminal_ctrl_insert_result"))"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_terminal_ctrl_insert_command" Enter
  send_attached_client_key "tmux attached client sends Ctrl-Insert bytes to terminal-normal Neovim" "$ctrl_insert_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_terminal_ctrl_insert_write_command" Enter
  wait_for_file "$attached_terminal_ctrl_insert_result"
  assert_eq "tmux attached client passes Ctrl-Insert bytes through to terminal-normal Neovim copy" \
    "$(printf 'attached terminal ctrl-insert copy via tmux|\nV\nattached terminal ctrl-insert copy via tmux|second line')" \
    "$(cat "$attached_terminal_ctrl_insert_result")"
  attached_terminal_ctrl_insert_cleanup="$tmp/attached-terminal-ctrl-insert-copy-cleanup.log"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' \
    "lua vim.fn.chanclose(vim.g.dotfiles_tmux_attached_terminal_copy_job, 'stdin'); vim.cmd('enew!'); vim.fn.writefile({'ok'}, $(lua_string "$attached_terminal_ctrl_insert_cleanup"))" Enter
  wait_for_file "$attached_terminal_ctrl_insert_cleanup"

  attached_terminal_visual_ctrl_insert_result="$tmp/attached-terminal-visual-ctrl-insert-copy.log"
  attached_terminal_visual_ctrl_insert_ready="$tmp/attached-terminal-visual-ctrl-insert-copy-ready.log"
  attached_terminal_visual_ctrl_insert_command="lua vim.cmd('enew'); vim.g.dotfiles_tmux_attached_terminal_visual_copy_job = vim.fn.termopen({'sh', '-c', 'printf \"attached terminal visual ctrl-insert copy via tmux\\\\nsecond line\\\\n\"; cat >/dev/null'}); assert(type(vim.g.dotfiles_tmux_attached_terminal_visual_copy_job) == 'number' and vim.g.dotfiles_tmux_attached_terminal_visual_copy_job > 0); assert(vim.wait(1000, function() return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'):find('second line', 1, true) ~= nil end)); vim.g.dotfiles_tmux_copy_lines = {}; vim.g.dotfiles_tmux_copy_type = ''"
  attached_terminal_visual_ctrl_insert_wait_command="lua assert(vim.wait(1000, function() return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'):find('second line', 1, true) ~= nil end)); vim.fn.writefile({'ok'}, $(lua_string "$attached_terminal_visual_ctrl_insert_ready"))"
  attached_terminal_visual_ctrl_insert_write_command="lua local lines = vim.api.nvim_buf_get_lines(0, 0, 2, false); vim.fn.writefile({table.concat(vim.g.dotfiles_tmux_copy_lines, '|'), vim.g.dotfiles_tmux_copy_type, table.concat(lines, '|')}, $(lua_string "$attached_terminal_visual_ctrl_insert_result"))"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_terminal_visual_ctrl_insert_command" Enter
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_terminal_visual_ctrl_insert_wait_command" Enter
  wait_for_file "$attached_terminal_visual_ctrl_insert_ready"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l 'gg0v$'
  send_attached_client_key "tmux attached client sends Ctrl-Insert bytes to terminal-visual Neovim" "$ctrl_insert_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$nvim_terminal_normal_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_terminal_visual_ctrl_insert_write_command" Enter
  wait_for_file "$attached_terminal_visual_ctrl_insert_result"
  assert_eq "tmux attached client passes Ctrl-Insert bytes through to terminal-visual Neovim copy" \
    "$(printf 'attached terminal visual ctrl-insert copy via tmux|\nv\nattached terminal visual ctrl-insert copy via tmux|second line')" \
    "$(cat "$attached_terminal_visual_ctrl_insert_result")"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' \
    "lua vim.fn.chanclose(vim.g.dotfiles_tmux_attached_terminal_visual_copy_job, 'stdin'); vim.cmd('enew!')" Enter

  attached_insert_ctrl_insert_result="$tmp/attached-insert-ctrl-insert-copy.log"
  attached_insert_ctrl_insert_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'attached insert ctrl-insert copy', 'line 2'}); vim.g.dotfiles_tmux_copy_lines = {}; vim.g.dotfiles_tmux_copy_type = ''; vim.cmd('normal! gg$'); vim.cmd('startinsert!')"
  attached_insert_ctrl_insert_write_command="lua vim.fn.writefile({table.concat(vim.g.dotfiles_tmux_copy_lines, '|'), vim.g.dotfiles_tmux_copy_type, table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '|')}, $(lua_string "$attached_insert_ctrl_insert_result"))"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_insert_ctrl_insert_command" Enter
  send_attached_client_key "tmux attached client sends Ctrl-Insert bytes to insert Neovim" "$ctrl_insert_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "Z"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_insert_ctrl_insert_write_command" Enter
  wait_for_file "$attached_insert_ctrl_insert_result"
  assert_eq "tmux attached client passes Ctrl-Insert bytes through to insert Neovim copy" \
    "$(printf 'attached insert ctrl-insert copy|\nV\nattached insert ctrl-insert copyZ|line 2')" \
    "$(cat "$attached_insert_ctrl_insert_result")"

  attached_insert_shift_delete_result="$tmp/attached-insert-shift-delete-cut.log"
  attached_insert_shift_delete_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'attached insert shift-delete cut', 'line 2', 'line 3'}); vim.g.dotfiles_tmux_copy_lines = {}; vim.g.dotfiles_tmux_copy_type = ''; vim.cmd('normal! gg$'); vim.cmd('startinsert!')"
  attached_insert_shift_delete_write_command="lua vim.fn.writefile({table.concat(vim.g.dotfiles_tmux_copy_lines, '|'), vim.g.dotfiles_tmux_copy_type, table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '|')}, $(lua_string "$attached_insert_shift_delete_result"))"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_insert_shift_delete_command" Enter
  send_attached_client_key "tmux attached client sends Shift-Delete bytes to insert Neovim" "$shift_delete_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "Z"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_insert_shift_delete_write_command" Enter
  wait_for_file "$attached_insert_shift_delete_result"
  assert_eq "tmux attached client passes Shift-Delete bytes through to insert Neovim cut" \
    "$(printf 'attached insert shift-delete cut|\nV\nline 2Z|line 3')" \
    "$(cat "$attached_insert_shift_delete_result")"

  attached_insert_ctrl_backspace_result="$tmp/attached-insert-ctrl-backspace-word.log"
  attached_insert_ctrl_backspace_ready="$tmp/attached-insert-ctrl-backspace-word-ready.log"
  attached_insert_ctrl_backspace_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'attached insert ctrl backspace alpha beta gamma'}); vim.cmd('normal! gg$'); vim.cmd('startinsert!'); vim.fn.writefile({'ok'}, $(lua_string "$attached_insert_ctrl_backspace_ready"))"
  attached_insert_ctrl_backspace_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line()}, $(lua_string "$attached_insert_ctrl_backspace_result"))"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_insert_ctrl_backspace_command" Enter
  wait_for_file "$attached_insert_ctrl_backspace_ready"
  send_attached_client_key "tmux attached client sends Ctrl-Backspace bytes to insert Neovim" "$ctrl_backspace_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "Z"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_insert_ctrl_backspace_write_command" Enter
  wait_for_file "$attached_insert_ctrl_backspace_result"
  assert_eq "tmux attached client passes Ctrl-Backspace bytes through to insert Neovim delete-previous-word" \
    "attached insert ctrl backspace alpha beta Z" \
    "$(cat "$attached_insert_ctrl_backspace_result")"

  attached_insert_ctrl_left_result="$tmp/attached-insert-ctrl-left-word.log"
  attached_insert_ctrl_left_ready="$tmp/attached-insert-ctrl-left-word-ready.log"
  attached_insert_ctrl_left_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'attached insert ctrl left alpha beta gamma'}); vim.cmd('normal! gg$'); vim.cmd('startinsert!'); vim.fn.writefile({'ok'}, $(lua_string "$attached_insert_ctrl_left_ready"))"
  attached_insert_ctrl_left_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line()}, $(lua_string "$attached_insert_ctrl_left_result"))"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_insert_ctrl_left_command" Enter
  wait_for_file "$attached_insert_ctrl_left_ready"
  send_attached_client_key "tmux attached client sends Ctrl-Left bytes to insert Neovim" "$ctrl_left_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "Z"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_insert_ctrl_left_write_command" Enter
  wait_for_file "$attached_insert_ctrl_left_result"
  assert_eq "tmux attached client passes Ctrl-Left bytes through to insert Neovim previous-word motion" \
    "attached insert ctrl left alpha beta Zgamma" \
    "$(cat "$attached_insert_ctrl_left_result")"

  attached_insert_ctrl_right_result="$tmp/attached-insert-ctrl-right-word.log"
  attached_insert_ctrl_right_ready="$tmp/attached-insert-ctrl-right-word-ready.log"
  attached_insert_ctrl_right_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'attached insert ctrl right alpha beta gamma'}); vim.cmd('normal! gg0'); vim.cmd('startinsert'); vim.fn.writefile({'ok'}, $(lua_string "$attached_insert_ctrl_right_ready"))"
  attached_insert_ctrl_right_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line()}, $(lua_string "$attached_insert_ctrl_right_result"))"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_insert_ctrl_right_command" Enter
  wait_for_file "$attached_insert_ctrl_right_ready"
  send_attached_client_key "tmux attached client sends Ctrl-Right bytes to insert Neovim" "$ctrl_right_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "Z"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_insert_ctrl_right_write_command" Enter
  wait_for_file "$attached_insert_ctrl_right_result"
  assert_eq "tmux attached client passes Ctrl-Right bytes through to insert Neovim next-word motion" \
    "attachedZ insert ctrl right alpha beta gamma" \
    "$(cat "$attached_insert_ctrl_right_result")"

  attached_insert_ctrl_delete_result="$tmp/attached-insert-ctrl-delete-word.log"
  attached_insert_ctrl_delete_ready="$tmp/attached-insert-ctrl-delete-word-ready.log"
  attached_insert_ctrl_delete_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'attached insert ctrl delete alpha beta gamma'}); vim.cmd('normal! gg05w'); vim.cmd('startinsert'); vim.fn.writefile({'ok'}, $(lua_string "$attached_insert_ctrl_delete_ready"))"
  attached_insert_ctrl_delete_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line()}, $(lua_string "$attached_insert_ctrl_delete_result"))"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_insert_ctrl_delete_command" Enter
  wait_for_file "$attached_insert_ctrl_delete_ready"
  send_attached_client_key "tmux attached client sends Ctrl-Delete bytes to insert Neovim" "$ctrl_delete_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "Z"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_insert_ctrl_delete_write_command" Enter
  wait_for_file "$attached_insert_ctrl_delete_result"
  assert_eq "tmux attached client passes Ctrl-Delete bytes through to insert Neovim delete-next-word" \
    "attached insert ctrl delete alpha Zgamma" \
    "$(cat "$attached_insert_ctrl_delete_result")"

  attached_ctrl_insert_result="$tmp/attached-ctrl-insert-copy.log"
  attached_ctrl_insert_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'attached ctrl-insert copy', 'line 2'}); vim.g.dotfiles_tmux_copy_lines = {}; vim.g.dotfiles_tmux_copy_type = ''; vim.cmd('normal! gg')"
  attached_ctrl_insert_write_command="lua vim.fn.writefile({table.concat(vim.g.dotfiles_tmux_copy_lines, '|'), vim.g.dotfiles_tmux_copy_type, table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '|')}, $(lua_string "$attached_ctrl_insert_result"))"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_ctrl_insert_command" Enter
  send_attached_client_key "tmux attached client sends Ctrl-Insert bytes" "$ctrl_insert_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_ctrl_insert_write_command" Enter
  wait_for_file "$attached_ctrl_insert_result"
  assert_eq "tmux attached client passes Ctrl-Insert bytes through to Neovim copy" \
    "$(printf 'attached ctrl-insert copy|\nV\nattached ctrl-insert copy|line 2')" \
    "$(cat "$attached_ctrl_insert_result")"

  attached_ctrl_backspace_result="$tmp/attached-ctrl-backspace-word.log"
  attached_ctrl_backspace_ready="$tmp/attached-ctrl-backspace-word-ready.log"
  attached_ctrl_backspace_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'attached ctrl backspace alpha beta gamma'}); vim.cmd('normal! gg$'); vim.fn.writefile({'ok'}, $(lua_string "$attached_ctrl_backspace_ready"))"
  attached_ctrl_backspace_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line()}, $(lua_string "$attached_ctrl_backspace_result"))"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_ctrl_backspace_command" Enter
  wait_for_file "$attached_ctrl_backspace_ready"
  send_attached_client_key "tmux attached client sends Ctrl-Backspace bytes to normal Neovim" "$ctrl_backspace_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_ctrl_backspace_write_command" Enter
  wait_for_file "$attached_ctrl_backspace_result"
  assert_eq "tmux attached client passes Ctrl-Backspace bytes through to normal Neovim delete-previous-word" \
    "attached ctrl backspace alpha beta " \
    "$(cat "$attached_ctrl_backspace_result")"

  attached_ctrl_left_result="$tmp/attached-ctrl-left-word.log"
  attached_ctrl_left_ready="$tmp/attached-ctrl-left-word-ready.log"
  attached_ctrl_left_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'attached ctrl left alpha beta gamma'}); vim.cmd('normal! gg$'); vim.fn.writefile({'ok'}, $(lua_string "$attached_ctrl_left_ready"))"
  attached_ctrl_left_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line()}, $(lua_string "$attached_ctrl_left_result"))"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_ctrl_left_command" Enter
  wait_for_file "$attached_ctrl_left_ready"
  send_attached_client_key "tmux attached client sends Ctrl-Left bytes to normal Neovim" "$ctrl_left_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "iZ"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_ctrl_left_write_command" Enter
  wait_for_file "$attached_ctrl_left_result"
  assert_eq "tmux attached client passes Ctrl-Left bytes through to normal Neovim previous-word motion" \
    "attached ctrl left alpha beta Zgamma" \
    "$(cat "$attached_ctrl_left_result")"

  attached_ctrl_right_result="$tmp/attached-ctrl-right-word.log"
  attached_ctrl_right_ready="$tmp/attached-ctrl-right-word-ready.log"
  attached_ctrl_right_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'attached ctrl right alpha beta gamma'}); vim.cmd('normal! gg0'); vim.fn.writefile({'ok'}, $(lua_string "$attached_ctrl_right_ready"))"
  attached_ctrl_right_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line()}, $(lua_string "$attached_ctrl_right_result"))"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_ctrl_right_command" Enter
  wait_for_file "$attached_ctrl_right_ready"
  send_attached_client_key "tmux attached client sends Ctrl-Right bytes to normal Neovim" "$ctrl_right_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "aZ"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_ctrl_right_write_command" Enter
  wait_for_file "$attached_ctrl_right_result"
  assert_eq "tmux attached client passes Ctrl-Right bytes through to normal Neovim next-word motion" \
    "attachedZ ctrl right alpha beta gamma" \
    "$(cat "$attached_ctrl_right_result")"

  attached_ctrl_delete_result="$tmp/attached-ctrl-delete-word.log"
  attached_ctrl_delete_ready="$tmp/attached-ctrl-delete-word-ready.log"
  attached_ctrl_delete_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'attached ctrl delete alpha beta gamma'}); vim.cmd('normal! gg04w'); vim.fn.writefile({'ok'}, $(lua_string "$attached_ctrl_delete_ready"))"
  attached_ctrl_delete_write_command="lua vim.fn.writefile({vim.api.nvim_get_current_line()}, $(lua_string "$attached_ctrl_delete_result"))"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_ctrl_delete_command" Enter
  wait_for_file "$attached_ctrl_delete_ready"
  send_attached_client_key "tmux attached client sends Ctrl-Delete bytes to normal Neovim" "$ctrl_delete_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_ctrl_delete_write_command" Enter
  wait_for_file "$attached_ctrl_delete_result"
  assert_eq "tmux attached client passes Ctrl-Delete bytes through to normal Neovim delete-next-word" \
    "attached ctrl delete alpha gamma" \
    "$(cat "$attached_ctrl_delete_result")"

  attached_visual_ctrl_insert_result="$tmp/attached-visual-ctrl-insert-copy.log"
  attached_visual_ctrl_insert_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'attached visual ctrl-insert copy', 'line 2'}); vim.g.dotfiles_tmux_copy_lines = {}; vim.g.dotfiles_tmux_copy_type = ''; vim.cmd('normal! gg0')"
  attached_visual_ctrl_insert_write_command="lua vim.fn.writefile({table.concat(vim.g.dotfiles_tmux_copy_lines, '|'), vim.g.dotfiles_tmux_copy_type, table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '|')}, $(lua_string "$attached_visual_ctrl_insert_result"))"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_visual_ctrl_insert_command" Enter
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l 'v8l'
  send_attached_client_key "tmux attached client sends Ctrl-Insert bytes to visual Neovim" "$ctrl_insert_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_visual_ctrl_insert_write_command" Enter
  wait_for_file "$attached_visual_ctrl_insert_result"
  assert_eq "tmux attached client passes Ctrl-Insert bytes through to visual Neovim copy" \
    "$(printf 'attached \nv\nattached visual ctrl-insert copy|line 2')" \
    "$(cat "$attached_visual_ctrl_insert_result")"

  attached_shift_delete_result="$tmp/attached-shift-delete-cut.log"
  attached_shift_delete_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'attached shift-delete cut', 'line 2'}); vim.g.dotfiles_tmux_copy_lines = {}; vim.g.dotfiles_tmux_copy_type = ''; vim.cmd('normal! gg')"
  attached_shift_delete_write_command="lua vim.fn.writefile({table.concat(vim.g.dotfiles_tmux_copy_lines, '|'), vim.g.dotfiles_tmux_copy_type, table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '|')}, $(lua_string "$attached_shift_delete_result"))"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_shift_delete_command" Enter
  send_attached_client_key "tmux attached client sends Shift-Delete bytes" "$shift_delete_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_shift_delete_write_command" Enter
  wait_for_file "$attached_shift_delete_result"
  assert_eq "tmux attached client passes Shift-Delete bytes through to Neovim cut" \
    "$(printf 'attached shift-delete cut|\nV\nline 2')" \
    "$(cat "$attached_shift_delete_result")"

  attached_visual_shift_delete_result="$tmp/attached-visual-shift-delete-cut.log"
  attached_visual_shift_delete_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'attached visual shift-delete cut', 'line 2'}); vim.g.dotfiles_tmux_copy_lines = {}; vim.g.dotfiles_tmux_copy_type = ''; vim.cmd('normal! gg0')"
  attached_visual_shift_delete_write_command="lua vim.fn.writefile({table.concat(vim.g.dotfiles_tmux_copy_lines, '|'), vim.g.dotfiles_tmux_copy_type, table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '|')}, $(lua_string "$attached_visual_shift_delete_result"))"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_visual_shift_delete_command" Enter
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l 'v8l'
  send_attached_client_key "tmux attached client sends Shift-Delete bytes to visual Neovim" "$shift_delete_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_visual_shift_delete_write_command" Enter
  wait_for_file "$attached_visual_shift_delete_result"
  assert_eq "tmux attached client passes Shift-Delete bytes through to visual Neovim cut" \
    "$(printf 'attached \nv\nvisual shift-delete cut|line 2')" \
    "$(cat "$attached_visual_shift_delete_result")"

  attached_visual_shift_f4_result="$tmp/attached-visual-shift-f4.log"
  attached_visual_shift_f4_setup="lua local lines = {'attached visual shift-f line 1'}; for i = 2, 32 do lines[i] = 'attached visual shift-f line ' .. i end; vim.api.nvim_buf_set_lines(0, 0, -1, false, lines); vim.cmd('normal! gg')"
  attached_visual_shift_f4_write="lua local lines=vim.fn.getreg('\"', 1, true); vim.fn.writefile({lines[1] or '', lines[#lines] or '', tostring(#lines), vim.fn.getregtype('\"')}, $(lua_string "$attached_visual_shift_f4_result"))"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_visual_shift_f4_setup" Enter
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l '20G0V'
  send_attached_client_key "tmux attached client sends VS Code Shift-F4 bytes to visual Neovim" "$shift_f4_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" y
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_visual_shift_f4_write" Enter
  wait_for_file "$attached_visual_shift_f4_result"
  assert_eq "tmux attached client passes VS Code Shift-F4 bytes through to visual Neovim" \
    "$(printf 'attached visual shift-f line 4\nattached visual shift-f line 20\n17\nV')" \
    "$(cat "$attached_visual_shift_f4_result")"

  attached_visual_shift_f6_result="$tmp/attached-visual-shift-f6.log"
  attached_visual_shift_f6_setup="lua local lines = {'attached visual shift-f line 1'}; for i = 2, 32 do lines[i] = 'attached visual shift-f line ' .. i end; vim.api.nvim_buf_set_lines(0, 0, -1, false, lines); vim.cmd('normal! gg')"
  attached_visual_shift_f6_write="lua local lines=vim.fn.getreg('\"', 1, true); vim.fn.writefile({lines[1] or '', lines[#lines] or '', tostring(#lines), vim.fn.getregtype('\"')}, $(lua_string "$attached_visual_shift_f6_result"))"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_visual_shift_f6_setup" Enter
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l '12G0V'
  send_attached_client_key "tmux attached client sends VS Code Shift-F6 bytes to visual Neovim" "$shift_f6_sequence"
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" y
  "$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$attached_visual_shift_f6_write" Enter
  wait_for_file "$attached_visual_shift_f6_result"
  assert_eq "tmux attached client passes VS Code Shift-F6 bytes through to visual Neovim" \
    "$(printf 'attached visual shift-f line 12\nattached visual shift-f line 28\n17\nV')" \
    "$(cat "$attached_visual_shift_f6_result")"

  root_user_key_output="$tmp/root-user-key-output.bin"
  root_user_key_window="root-user-keys"
  root_user_key_reader='import sys,termios,tty; fd=sys.stdin.fileno(); old=termios.tcgetattr(fd); tty.setraw(fd); data=sys.stdin.buffer.read(13); termios.tcsetattr(fd, termios.TCSADRAIN, old); open(sys.argv[1], "wb").write(data)'
  printf -v root_user_key_command '%q -c %q %q' "$python3_path" "$root_user_key_reader" "$root_user_key_output"
  "$tmux_bin" -L "$socket_name" new-window -d -t "nvim-keys:" -n "$root_user_key_window" "$root_user_key_command"
  root_user_key_pane="$("$tmux_bin" -L "$socket_name" list-panes -t "nvim-keys:$root_user_key_window" -F '#{pane_id}')"
  root_user_key_current_command=""
  for _ in $(seq 1 50); do
    root_user_key_current_command="$("$tmux_bin" -L "$socket_name" display-message -p -t "$root_user_key_pane" '#{pane_current_command}')"
    case "$root_user_key_current_command" in
      Python | python3) break ;;
    esac
    sleep 0.1
  done
  case "$root_user_key_current_command" in
    Python | python3) ;;
    *)
      printf 'timed out waiting for root user-key pane Python reader, got %s\n' "$root_user_key_current_command" >&2
      exit 1
      ;;
  esac
  "$tmux_bin" -L "$socket_name" select-window -t "nvim-keys:$root_user_key_window"
  send_attached_client_key "tmux attached client sends VS Code Shift-F4/F6 bytes to a root pane" "$shift_f4_sequence$shift_f6_sequence"
  wait_for_file "$root_user_key_output"
  assert_eq "tmux root table passes VS Code Shift-F4/F6 bytes through to panes" \
    "1b5b313b32531b5b31373b327e" \
    "$(od -An -tx1 -v "$root_user_key_output" | tr -d ' \n')"
  "$tmux_bin" -L "$socket_name" kill-window -t "nvim-keys:$root_user_key_window" >/dev/null 2>&1 || true
  "$tmux_bin" -L "$socket_name" select-pane -t "$pane_id"

  copy_scroll_window="copy-scroll"
  # shellcheck disable=SC2016
  copy_scroll_command='for i in $(seq 1 100); do printf "copy scroll line %03d\n" "$i"; done; exec sleep 60'
  "$tmux_bin" -L "$socket_name" new-window -d -t "nvim-keys:" -n "$copy_scroll_window" "$copy_scroll_command"
  copy_scroll_pane="$("$tmux_bin" -L "$socket_name" list-panes -t "nvim-keys:$copy_scroll_window" -F '#{pane_id}')"
  wait_for_pane_command "$socket_name" "$copy_scroll_pane" "sleep"
  "$tmux_bin" -L "$socket_name" select-window -t "nvim-keys:$copy_scroll_window"
  "$tmux_bin" -L "$socket_name" copy-mode -t "$copy_scroll_pane"
  send_attached_client_key "tmux attached client sends VS Code Shift-F4 bytes to copy-mode" "$shift_f4_sequence"
  assert_eq "tmux copy-mode handles VS Code Shift-F4 scroll-up bytes" \
    "16" \
    "$("$tmux_bin" -L "$socket_name" display-message -p -t "$copy_scroll_pane" '#{scroll_position}')"
  send_attached_client_key "tmux attached client sends VS Code Shift-F6 bytes to copy-mode" "$shift_f6_sequence"
  assert_eq "tmux copy-mode handles VS Code Shift-F6 scroll-down bytes" \
    "0" \
    "$("$tmux_bin" -L "$socket_name" display-message -p -t "$copy_scroll_pane" '#{scroll_position}')"
  "$tmux_bin" -L "$socket_name" kill-window -t "nvim-keys:$copy_scroll_window"
  "$tmux_bin" -L "$socket_name" select-pane -t "$pane_id"
else
  skip "tmux attached client Insert/Delete Neovim copy-paste keys (python3 unavailable)"
fi

force_edit_search_command="lua vim.cmd('edit! ' .. vim.fn.fnameescape($(lua_string "$tmp/search.txt")))"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$force_edit_search_command" Enter

visual_save_expected="$(printf 'visual shift-f5 save\nline 2')"
visual_save_command="lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {'visual shift-f5 save', 'line 2'}); vim.cmd('normal! gg')"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$visual_save_command" Enter
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l 'gg0V'
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" -l "$shift_f5_sequence"
wait_for_file_content "$tmp/search.txt" "$visual_save_expected"
assert_eq "tmux passes VS Code Shift-F5 bytes to visual Neovim save" "$visual_save_expected" "$(cat "$tmp/search.txt")"

reset_lines_command="lua local lines = {'manual'}; for i = 2, 32 do lines[i] = 'line ' .. i end; vim.api.nvim_buf_set_lines(0, 0, -1, false, lines); vim.cmd('normal! gg')"
"$tmux_bin" -L "$socket_name" send-keys -t "$pane_id" Escape ':' "$reset_lines_command" Enter

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
