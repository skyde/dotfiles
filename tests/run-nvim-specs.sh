#!/usr/bin/env bash
# Run the Neovim specs. Each one is self-contained and needs no plugins.
#
#   tests/run-nvim-specs.sh            # all specs
#   tests/run-nvim-specs.sh vcs        # only specs whose name matches "vcs"
#
# NVIM_SPECS_NO_SKIP=1 turns a skipped block into a failure. CI sets it: it
# installs every tool the specs reach for, so a skip there means the tool went
# missing from the runner image and a whole backend stopped being covered —
# which is silent, and looks exactly like passing.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

if ! command -v nvim >/dev/null 2>&1; then
  echo "nvim not found" >&2
  exit 1
fi

filter="${1:-}"
status=0

for spec in tests/*_spec.lua; do
  name="$(basename "$spec" .lua)"
  if [[ -n "$filter" && "$name" != *"$filter"* ]]; then
    continue
  fi
  printf '\n=== %s ===\n' "$name"
  out="$(nvim --headless -u NONE -i NONE -l "$spec" 2>&1)"
  rc=$?
  printf '%s\n' "$out"
  if [[ $rc -ne 0 ]]; then
    printf '%s: FAILED\n' "$name" >&2
    status=1
  elif [[ "${NVIM_SPECS_NO_SKIP:-}" == "1" ]] && grep -q '^SKIP ' <<<"$out"; then
    printf '%s: FAILED (skipped a block with NVIM_SPECS_NO_SKIP=1)\n' "$name" >&2
    grep '^SKIP ' <<<"$out" >&2
    status=1
  else
    printf '%s: OK\n' "$name"
  fi
done

exit "$status"
