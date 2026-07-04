#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_contains() {
  local name="$1"
  local haystack="$2"
  local needle="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'not ok - %s\n' "$name" >&2
    printf 'missing:\n%s\n' "$needle" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

assert_not_contains() {
  local name="$1"
  local haystack="$2"
  local needle="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'not ok - %s\n' "$name" >&2
    printf 'unexpected:\n%s\n' "$needle" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

vim_docs="$(<"$root/docs/vim-bindings.md")"
vscode_docs="$(<"$root/docs/vscode-keybindings.md")"
nvim_keymaps="$(<"$root/common/.config/nvim/lua/config/keymaps.lua")"
tmux_conf="$(<"$root/common/.tmux.conf")"

assert_contains "vim docs keep Shift-F9 search toggle" "$vim_docs" "toggle search   – Shift+F9"
assert_contains "vim docs reserve Shift-F10 for tmux prefix" "$vim_docs" "tmux prefix     – Shift+F10"
assert_not_contains "vim docs do not document stale Shift-F10 eye toggle" "$vim_docs" "toggle eye      – Shift+F10"

assert_contains "VS Code docs pass Shift-F9 to terminal Neovim" \
  "$vscode_docs" \
  'Shift+F9` – passed through to terminal Neovim to toggle search highlighting'
assert_contains "VS Code docs pass Shift-F10 to tmux" \
  "$vscode_docs" \
  'Shift+F10` – passed through to tmux as the secondary prefix key'
assert_contains "VS Code docs explain terminal clipboard behavior" \
  "$vscode_docs" \
  "terminal auto-copy-on-selection is disabled"
assert_contains "VS Code docs describe terminal Insert clipboard keys" \
  "$vscode_docs" \
  "Ctrl+Insert\` / \`Shift+Insert\` / \`Shift+Delete"

assert_contains "Neovim config documents Shift-F10 reservation" \
  "$nvim_keymaps" \
  "Shift+F10 is reserved by tmux"
assert_not_contains "Neovim keymaps avoid stale remap TODO" \
  "$nvim_keymaps" \
  "TODO: Use the vim.keymap.set style remap"
assert_contains "vim docs describe Ctrl-u as movement" "$vim_docs" "<C-u>\` – move up 16 lines"
assert_contains "VS Code docs describe Vim Ctrl-u as movement" "$vscode_docs" "<C-u>\` – move up 16 lines (\`16k\`)"
assert_not_contains "VS Code keybindings avoid workaround typo" "$(<"$root/common/.config/Code/User/keybindings.json")" "workround"
assert_not_contains "VS Code keybindings avoid exactly typo" "$(<"$root/common/.config/Code/User/keybindings.json")" "exacty"
assert_contains "tmux config binds Shift-F10 as prefix table" \
  "$tmux_conf" \
  "bind-key -n S-F10 switch-client -T prefix"
assert_not_contains "tmux config avoids vague escape-time typo" "$tmux_conf" "vsmall"
assert_not_contains "tmux config avoids stale Ctrl-s issue comment" "$tmux_conf" "some issue here"
