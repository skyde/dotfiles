#!/usr/bin/env bash
# Drive the C++ language server against a REAL Chromium checkout, through the
# real Neovim config. tests/check-nvim-lsp.sh proves the machinery works on a
# fixture; this proves it works at the scale it was written for -- a 400 MB+
# compilation database, 70k translation units, a build directory whose
# generated sources are named relative to it, and platform files the mac build
# never compiles.
#
#   tests/check-nvim-lsp-chromium.sh            # against the installed config
#   tests/check-nvim-lsp-chromium.sh /path/dir  # against a checkout's common/.config
#
# Skips itself, loudly but successfully, when there is nothing to test against:
# no checkout, no compilation database, no clangd. Nothing is written to the
# checkout except what the automation itself regenerates.
#
# The checkout is found via CHROMIUM_SRC, else the usual locations. To point it
# somewhere else:  CHROMIUM_SRC=/path/to/src tests/check-nvim-lsp-chromium.sh
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
if ! command -v clangd >/dev/null 2>&1 && [[ -z "${CHROMIUM_SRC:-}" ]]; then
  echo "SKIP: clangd not found (this check drives a real language server)"
  exit 0
fi

src="${CHROMIUM_SRC:-}"
if [[ -z "$src" ]]; then
  for candidate in "$HOME/chrome/src" "$HOME/chromium/src" "$HOME/src/chromium/src"; do
    if [[ -d "$candidate" && -d "$candidate/base" ]]; then
      src="$candidate"
      break
    fi
  done
fi

if [[ -z "$src" || ! -d "$src/base" ]]; then
  echo "SKIP: no Chromium checkout found (set CHROMIUM_SRC to run this)"
  exit 0
fi
if [[ ! -e "$src/compile_commands.json" ]]; then
  echo "SKIP: $src has no compile_commands.json"
  echo "      generate one with:  gn gen out/Default &&"
  echo "      python3 tools/clang/scripts/generate_compdb.py -p out/Default -o compile_commands.json"
  exit 0
fi

report="$(mktemp)"
trap 'rm -f "$report"' EXIT

export CHROMIUM_SRC="$src"
export NVIM_CHROMIUM_REPORT="$report"

echo "Chromium checkout: $src"

cd "$src" || exit 1
# VeryLazy is normally fired by UIEnter, which never happens headless.
nvim --headless \
  -c 'doautocmd User VeryLazy' \
  -c "luafile $here/tests/nvim_lsp_chromium_check.lua" \
  -c 'qa!' </dev/null
status=$?

echo
cat "$report" 2>/dev/null
if [[ -f "$report" ]] && ! grep -q 'failed 0$' "$report"; then
  status=1
fi
exit "$status"
