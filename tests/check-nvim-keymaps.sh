#!/usr/bin/env bash
# Invoke every parity binding against the real Neovim config and report anything
# that raises. Unlike tests/run-nvim-specs.sh this needs the config and its
# plugins installed, so it checks the setup as actually assembled.
#
#   tests/check-nvim-keymaps.sh            # against the installed config
#   tests/check-nvim-keymaps.sh /path/dir  # against a checkout's common/.config
#
# Runs inside a throwaway git repository so the source-control bindings have
# something real to operate on, and never touches the working tree.
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

git init -q -b main "$sandbox/repo"
cd "$sandbox/repo" || exit 1
printf 'one\ntwo\n' > tracked.txt
git add -A
git -c user.email=t@example.com -c user.name=Test commit -qm initial
git update-ref refs/remotes/origin/main HEAD
git checkout -qb feature
printf 'one\nTWO\nthree\n' > tracked.txt
printf 'new\n' > untracked.txt

export NVIM_KEYMAP_REPORT="$sandbox/report.txt"

# VeryLazy is normally fired by UIEnter, which never happens headless.
nvim --headless \
  -c 'doautocmd User VeryLazy' \
  -c 'edit tracked.txt' \
  -c "luafile $here/tests/nvim_keymap_check.lua" \
  -c 'qa!'
status=$?

echo
cat "$NVIM_KEYMAP_REPORT" 2>/dev/null
exit "$status"
