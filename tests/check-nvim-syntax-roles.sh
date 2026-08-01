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

# `timeout` is GNU coreutils; macOS ships neither it nor a BSD equivalent, so
# this script aborted with "timeout: command not found" before running a single
# check — on the very platform it is usually run from. Prefer whichever of the
# two names exists (Homebrew coreutils installs it as gtimeout), and just run
# nvim directly when neither does. The timeout is a guard against a hang, not a
# part of the check, so losing it degrades the run rather than invalidating it.
timeout_cmd=()
if command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout 120)
elif command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout 120)
fi

# VeryLazy is normally fired by UIEnter, which never happens headless.
"${timeout_cmd[@]}" nvim --headless \
  -c 'doautocmd User VeryLazy' \
  -c "luafile $here/tests/nvim_syntax_roles.lua" \
  -c 'qa!'
status=$?

cat "$NVIM_SYNTAX_REPORT" 2>/dev/null
exit "$status"
