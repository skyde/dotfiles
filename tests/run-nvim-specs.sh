#!/usr/bin/env bash
# Run the Neovim specs. Each one is self-contained and needs no plugins.
#
#   tests/run-nvim-specs.sh            # all specs
#   tests/run-nvim-specs.sh vcs        # only specs whose name matches "vcs"
#
# They run several at a time, because three of them account for nearly all the
# wall clock and each builds its own repositories in its own tempdir — there is
# nothing to share and nothing to collide over. Output is buffered per spec and
# printed in file order regardless of who finishes first, so a run reads the
# same as a serial one. NVIM_SPECS_JOBS=1 makes it serial again, which is what
# to reach for when a spec is misbehaving and the interleaving matters.
#
# NVIM_CHECKS_NO_SKIP=1 turns a skipped block into a failure. CI sets it: it
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

jobs="${NVIM_SPECS_JOBS:-}"
if [[ -z "$jobs" ]]; then
  jobs="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
  # Past four there is nothing left to win: the longest single spec is the
  # floor, and every extra process is more git subprocesses competing for the
  # same disk.
  [[ "$jobs" -gt 4 ]] && jobs=4
fi

specs=()
for spec in tests/*_spec.lua; do
  name="$(basename "$spec" .lua)"
  if [[ -n "$filter" && "$name" != *"$filter"* ]]; then
    continue
  fi
  specs+=("$spec")
done

if [[ ${#specs[@]} -eq 0 ]]; then
  echo "no specs matched ${filter}" >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# `wait -n` — reap whichever finishes first — needs bash 4.3, and macOS still
# ships 3.2. Probed rather than assumed, because its failure is indistinguishable
# from a job exiting non-zero: without the probe, the first failing spec would
# quietly turn the rest of the run serial. Where it is missing, waiting for the
# whole batch is correct and only a little slower.
have_wait_n=0
if (
  sleep 0 &
  wait -n
) 2>/dev/null; then
  have_wait_n=1
fi

running=0
for i in "${!specs[@]}"; do
  (
    nvim --headless -u NONE -i NONE -l "${specs[$i]}" >"$work/$i.out" 2>&1
    echo $? >"$work/$i.rc"
  ) &
  running=$((running + 1))
  if [[ $running -ge $jobs ]]; then
    if [[ $have_wait_n -eq 1 ]]; then
      wait -n || true
      running=$((running - 1))
    else
      wait
      running=0
    fi
  fi
done
wait

for i in "${!specs[@]}"; do
  name="$(basename "${specs[$i]}" .lua)"
  printf '\n=== %s ===\n' "$name"
  cat "$work/$i.out"
  rc="$(cat "$work/$i.rc" 2>/dev/null || echo 1)"
  if [[ "$rc" -ne 0 ]]; then
    printf '%s: FAILED\n' "$name" >&2
    status=1
  elif [[ "${NVIM_CHECKS_NO_SKIP:-}" == "1" ]] && grep -q '^SKIP ' "$work/$i.out"; then
    printf '%s: FAILED (skipped a block with NVIM_CHECKS_NO_SKIP=1)\n' "$name" >&2
    grep '^SKIP ' "$work/$i.out" >&2
    status=1
  else
    printf '%s: OK\n' "$name"
  fi
done

exit "$status"
