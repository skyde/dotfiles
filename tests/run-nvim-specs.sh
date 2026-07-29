#!/usr/bin/env bash
# Run the Neovim specs. Each one is self-contained and needs no plugins.
#
#   tests/run-nvim-specs.sh            # all specs
#   tests/run-nvim-specs.sh vcs        # only specs whose name matches "vcs"
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
  if nvim --headless -u NONE -i NONE -l "$spec"; then
    printf '%s: OK\n' "$name"
  else
    printf '%s: FAILED\n' "$name" >&2
    status=1
  fi
done

exit "$status"
