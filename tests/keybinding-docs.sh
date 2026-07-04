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
readme="$(<"$root/README.md")"
nvim_keymaps="$(<"$root/common/.config/nvim/lua/config/keymaps.lua")"
tmux_conf="$(<"$root/common/.tmux.conf")"
zshrc="$(<"$root/common/.zshrc")"
bashrc_custom="$(<"$root/common/.bashrc-custom")"
kitty_conf="$(<"$root/common/.config/kitty/kitty.conf")"

assert_contains "vim docs keep Shift-F9 search toggle" "$vim_docs" "toggle search   – Shift+F9"
assert_contains "vim docs reserve Shift-F10 for tmux prefix" "$vim_docs" "tmux prefix     – Shift+F10"
assert_not_contains "vim docs do not document stale Shift-F10 eye toggle" "$vim_docs" "toggle eye      – Shift+F10"
assert_contains "README documents Shift-F10 as tmux prefix" "$readme" "tmux prefix - Shift F10"
assert_not_contains "README does not document stale Shift-F10 eye toggle" "$readme" "toggle eye mouse - Shift F10"

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
assert_contains "VS Code docs describe terminal-mode copy and cut" \
  "$vscode_docs" \
  "terminal-mode copy/cut of the visible terminal line"
assert_contains "VS Code docs describe tmux copy-mode Shift-Delete" \
  "$vscode_docs" \
  "tmux uses \`Ctrl+Insert\` and \`Shift+Delete\` in copy mode"
assert_contains "VS Code docs describe insert-mode copy and cut" \
  "$vscode_docs" \
  "insert-mode line copy/cut"
assert_contains "VS Code docs describe terminal-mode paste" \
  "$vscode_docs" \
  "terminal-normal, terminal-visual, and terminal-mode"
assert_contains "VS Code docs describe word delete keys" \
  "$vscode_docs" \
  "Ctrl+Backspace\` / \`Ctrl+Delete"
assert_contains "VS Code docs describe word motion keys" \
  "$vscode_docs" \
  "Ctrl+Left\` / \`Ctrl+Right"
assert_contains "VS Code docs describe tmux copy-mode Shift-F4/F6 scrolling" \
  "$vscode_docs" \
  "tmux copy mode uses Shift+F4/F6 to scroll 16 lines"

assert_contains "Neovim config documents Shift-F10 reservation" \
  "$nvim_keymaps" \
  "Shift+F10 is reserved by tmux"
assert_contains "Neovim config maps Ctrl-Left" \
  "$nvim_keymaps" \
  'for _, lhs in ipairs({ "<C-Left>", "\27[1;5D" }) do'
assert_contains "Neovim config maps Ctrl-Right" \
  "$nvim_keymaps" \
  'for _, lhs in ipairs({ "<C-Right>", "\27[1;5C" }) do'
assert_contains "Neovim config maps Ctrl-Backspace" \
  "$nvim_keymaps" \
  'for _, lhs in ipairs({ "<C-BS>", "\27[127;5u" }) do'
assert_contains "Neovim config maps Ctrl-Delete" \
  "$nvim_keymaps" \
  'for _, lhs in ipairs({ "<C-Del>", "\27[3;5~" }) do'
assert_contains "Neovim config maps Ctrl-Insert raw terminal bytes" \
  "$nvim_keymaps" \
  'for _, lhs in ipairs({ "<C-Insert>", "\27[2;5~" }) do'
assert_contains "Neovim config maps Shift-Delete raw terminal bytes" \
  "$nvim_keymaps" \
  'for _, lhs in ipairs({ "<S-Del>", "\27[3;2~" }) do'
assert_contains "Neovim config maps Shift-Insert raw terminal bytes" \
  "$nvim_keymaps" \
  'for _, lhs in ipairs({ "<S-Insert>", "\27[2;2~" }) do'
assert_contains "zshrc maps Ctrl-Right word motion" \
  "$zshrc" \
  "bindkey '^[[1;5C' forward-word"
assert_contains "zshrc maps Ctrl-Left word motion" \
  "$zshrc" \
  "bindkey '^[[1;5D' backward-word"
assert_contains "zshrc maps Ctrl-Backspace previous word delete" \
  "$zshrc" \
  "bindkey '^[[127;5u' backward-kill-word"
assert_not_contains "Neovim keymaps avoid stale remap TODO" \
  "$nvim_keymaps" \
  "TODO: Use the vim.keymap.set style remap"
assert_contains "zshrc maps Ctrl-Delete forward word delete" \
  "$zshrc" \
  "bindkey '^[[3;5~' kill-word"
assert_contains "bashrc maps Ctrl-Delete forward word delete" \
  "$bashrc_custom" \
  "bind '\"\\e[3;5~\": kill-word'"
assert_contains "bashrc maps Ctrl-Right word motion" \
  "$bashrc_custom" \
  "bind '\"\\e[1;5C\": forward-word'"
assert_contains "bashrc maps Ctrl-Left word motion" \
  "$bashrc_custom" \
  "bind '\"\\e[1;5D\": backward-word'"
assert_contains "bashrc maps Ctrl-Backspace previous word delete" \
  "$bashrc_custom" \
  "bind '\"\\e[127;5u\": backward-kill-word'"
assert_contains "kitty maps Ctrl-Right to xterm sequence" \
  "$kitty_conf" \
  "map ctrl+right send_text all \\x1b[1;5C"
assert_contains "kitty maps Ctrl-Left to xterm sequence" \
  "$kitty_conf" \
  "map ctrl+left send_text all \\x1b[1;5D"
assert_contains "kitty maps Ctrl-Backspace to CSI-u sequence" \
  "$kitty_conf" \
  "map ctrl+backspace send_text all \\x1b[127;5u"
assert_contains "kitty maps Ctrl-Delete to xterm sequence" \
  "$kitty_conf" \
  "map ctrl+delete send_text all \\x1b[3;5~"
assert_contains "kitty maps Ctrl-Insert to terminal copy sequence" \
  "$kitty_conf" \
  "map ctrl+insert send_text all \\x1b[2;5~"
assert_contains "kitty maps Shift-Insert to terminal paste sequence" \
  "$kitty_conf" \
  "map shift+insert send_text all \\x1b[2;2~"
assert_contains "kitty maps Shift-Delete to terminal cut sequence" \
  "$kitty_conf" \
  "map shift+delete send_text all \\x1b[3;2~"
assert_contains "vim docs describe Ctrl-u as movement" "$vim_docs" "<C-u>\` – move up 16 lines"
assert_contains "VS Code docs describe Vim Ctrl-u as movement" "$vscode_docs" "<C-u>\` – move up 16 lines (\`16k\`)"
assert_not_contains "VS Code keybindings avoid workaround typo" "$(<"$root/common/.config/Code/User/keybindings.json")" "workround"
assert_not_contains "VS Code keybindings avoid exactly typo" "$(<"$root/common/.config/Code/User/keybindings.json")" "exacty"
assert_contains "tmux config binds Shift-F10 as prefix table" \
  "$tmux_conf" \
  "bind-key -n S-F10 switch-client -T prefix"
assert_contains "tmux config maps VS Code Shift-F4 bytes for copy-mode" \
  "$tmux_conf" \
  "set-option -sq 'user-keys[90]' \"\\033[1;2S\""
assert_contains "tmux config maps VS Code Shift-F6 bytes for copy-mode" \
  "$tmux_conf" \
  "set-option -sq 'user-keys[91]' \"\\033[17;2~\""
assert_contains "tmux root table passes VS Code Shift-F4 bytes to panes" \
  "$tmux_conf" \
  "bind-key -T root User90 send-keys -H 1b 5b 31 3b 32 53"
assert_contains "tmux root table passes VS Code Shift-F6 bytes to panes" \
  "$tmux_conf" \
  "bind-key -T root User91 send-keys -H 1b 5b 31 37 3b 32 7e"
assert_contains "tmux root table passes native Shift-F4 to panes" \
  "$tmux_conf" \
  "bind-key -T root S-F4 send-keys -H 1b 5b 31 3b 32 53"
assert_contains "tmux root table passes native Shift-F6 to panes" \
  "$tmux_conf" \
  "bind-key -T root S-F6 send-keys -H 1b 5b 31 37 3b 32 7e"
assert_contains "tmux copy-mode scrolls up on VS Code Shift-F4 bytes" \
  "$tmux_conf" \
  "bind-key -T copy-mode-vi User90 send-keys -X -N 16 scroll-up"
assert_contains "tmux copy-mode scrolls down on VS Code Shift-F6 bytes" \
  "$tmux_conf" \
  "bind-key -T copy-mode-vi User91 send-keys -X -N 16 scroll-down"
assert_contains "tmux config passes Ctrl-Left to panes" \
  "$tmux_conf" \
  "bind-key -n C-Left send-keys C-Left"
assert_contains "tmux config passes Ctrl-Right to panes" \
  "$tmux_conf" \
  "bind-key -n C-Right send-keys C-Right"
assert_contains "tmux config passes Ctrl-Backspace to panes" \
  "$tmux_conf" \
  "bind-key -n C-BSpace send-keys C-BSpace"
assert_contains "tmux config passes Ctrl-Delete to panes" \
  "$tmux_conf" \
  "bind-key -n C-Delete send-keys C-Delete"
assert_not_contains "tmux config avoids vague escape-time typo" "$tmux_conf" "vsmall"
assert_not_contains "tmux config avoids stale Ctrl-s issue comment" "$tmux_conf" "some issue here"
