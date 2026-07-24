#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

config_root="$repo_root/common/.config/nvim/lua"
lazy_root="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy"

for plugin in plenary.nvim diffview-plus.nvim; do
  if [[ ! -d "$lazy_root/$plugin" ]]; then
    printf 'required pinned plugin is missing: %s\n' "$lazy_root/$plugin" >&2
    exit 1
  fi
done

init="$test_root/init.lua"
cat >"$init" <<LUA
vim.opt.runtimepath:prepend([[$lazy_root/plenary.nvim]])
vim.opt.runtimepath:prepend([[$lazy_root/diffview-plus.nvim]])
package.path = [[$config_root/?.lua;$config_root/?/init.lua;]] .. package.path
require("diffview").setup({})
LUA

if XDG_CACHE_HOME="$test_root/cache" nvim --headless -u "$init" -i NONE \
  -c 'lua require("config.diff_tool").open("files", { "/definitely/missing/left", "/definitely/missing/right" })' \
  +qa >"$test_root/stdout" 2>"$test_root/stderr"; then
  printf 'invalid diff-tool inputs unexpectedly exited zero\n' >&2
  exit 1
fi

grep -F "Diffview rejected the supplied paths" "$test_root/stderr" >/dev/null || {
  printf 'invalid diff-tool failure did not explain the rejected paths\n' >&2
  sed -n '1,120p' "$test_root/stderr" >&2
  exit 1
}

printf 'nvim direct diff-tool failure tests passed\n'
