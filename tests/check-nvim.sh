#!/usr/bin/env bash
# Every check for the Neovim config, in one command.
#
#   tests/check-nvim.sh          # the plugin-free ones: specs, format, types
#   tests/check-nvim.sh --all    # and the ones that need the plugins installed
#
# The default set is what a change to lua/ needs before it is committed, and it
# runs in well under a minute. `--all` adds the three that drive the config as
# actually assembled — they need the plugins, the tree-sitter parsers and a real
# terminal, and take a few minutes between them.
#
# A step whose tool is missing is reported as SKIP and does not fail the run,
# which is the right behaviour on a laptop that has not installed everything.
# CI runs the same scripts with NVIM_CHECKS_NO_SKIP=1, where a skip is a
# failure — see .github/workflows/neovim.yml.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

all=0
for arg in "$@"; do
  case "$arg" in
    --all) all=1 ;;
    -h | --help)
      sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

status=0
declare -a results=()

# Run one check, timing it, and remember what it said. A step that writes
# "SKIP" and exits 0 is reported as skipped rather than passed, so a missing
# tool is visible in the summary instead of looking like a clean run.
run_step() {
  local name="$1"
  shift
  printf '\n\033[1m=== %s ===\033[0m\n' "$name"
  local start out rc
  start=$SECONDS
  out="$("$@" 2>&1)"
  rc=$?
  printf '%s\n' "$out"
  local took=$((SECONDS - start))
  if [[ $rc -ne 0 ]]; then
    results+=("FAIL  ${name} (${took}s)")
    status=1
  elif grep -q '^SKIP' <<<"$out"; then
    results+=("SKIP  ${name} (${took}s)")
  else
    results+=("ok    ${name} (${took}s)")
  fi
}

# Format first: it is the fastest, and a reformat changes what everything else
# reads. Missing stylua is a skip, not a failure.
if command -v stylua >/dev/null 2>&1; then
  run_step "format (stylua)" stylua --check --config-path common/.config/nvim/stylua.toml common/.config/nvim tests
else
  results+=("SKIP  format (stylua not installed)")
  printf '\n\033[1m=== format (stylua) ===\033[0m\nSKIP: stylua not installed\n'
fi

run_step "specs" ./tests/run-nvim-specs.sh
run_step "types (lua-language-server)" ./tests/check-nvim-types.sh

if [[ $all -eq 1 ]]; then
  run_step "keymaps" ./tests/check-nvim-keymaps.sh
  run_step "syntax roles" ./tests/check-nvim-syntax-roles.sh
  run_step "footpedal keys" python3 tests/check-footpedal-keys.py
fi

printf '\n\033[1m=== summary ===\033[0m\n'
for line in "${results[@]}"; do
  printf '  %s\n' "$line"
done
if [[ $all -eq 0 ]]; then
  printf '\n  (--all also runs keymaps, syntax roles and the footpedal keys)\n'
fi

exit "$status"
