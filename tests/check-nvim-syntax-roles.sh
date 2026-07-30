#!/usr/bin/env bash
# Check that C++ and Python colour the same construct the same way, against the
# real Neovim config. Like tests/check-nvim-keymaps.sh this needs the config and
# its plugins installed; it skips cleanly when the tree-sitter parsers are not.
#
#   tests/check-nvim-syntax-roles.sh            # against the installed config
#   tests/check-nvim-syntax-roles.sh /path/dir  # against a checkout's common/.config
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
here="$PWD"

if [[ $# -ge 1 ]]; then
  export XDG_CONFIG_HOME="$1/common/.config"
fi

if ! command -v nvim >/dev/null 2>&1; then
  echo "nvim not found" >&2
  exit 1
fi

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
export NVIM_SYNTAX_REPORT="$sandbox/report.txt"

# VeryLazy is normally fired by UIEnter, which never happens headless.
timeout 120 nvim --headless \
  -c 'doautocmd User VeryLazy' \
  -c "luafile $here/tests/nvim_syntax_roles.lua" \
  -c 'qa!'
status=$?

cat "$NVIM_SYNTAX_REPORT" 2>/dev/null
exit "$status"
