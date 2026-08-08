#!/usr/bin/env bash
# What the changed-files view costs on a big listing.
#
#   tests/bench-nvim-vcs.sh          # 3000 changed files
#   tests/bench-nvim-vcs.sh 10000    # or as many as you like
#
# Informational: it prints timings and always exits 0. A shared CI runner is
# far too noisy to budget against, so nothing gates on these — they are here so
# a regression is visible in a log, the same way the startup cost is.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

if ! command -v nvim >/dev/null 2>&1; then
  echo "nvim not found" >&2
  exit 1
fi

export BENCH_FILES="${1:-3000}"
nvim --headless -u NONE -i NONE -l tests/bench-nvim-vcs.lua
