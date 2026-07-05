#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/test-all-platforms.sh"
workflow="$root/.github/workflows/comprehensive-test.yml"

assert_contains() {
  local name="$1"
  local haystack="$2"
  local needle="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'not ok - %s\n' "$name" >&2
    printf 'missing: %s\n' "$needle" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

bash -n "$script"
printf 'ok - platform helper shell syntax\n'

help="$("$script" --help)"
assert_contains "platform helper documents default workflow" "$help" "comprehensive-test.yml"
assert_contains "platform helper documents dirty-tree behavior" "$help" "never stages, commits, or pushes"

if [[ ! -f "$workflow" ]]; then
  printf 'not ok - default workflow exists\n' >&2
  printf 'missing: %s\n' "$workflow" >&2
  exit 1
fi
printf 'ok - default workflow exists\n'

if grep -Eq '^[[:space:]]*git[[:space:]]+(add|commit|push)([[:space:]]|$)' "$script"; then
  printf 'not ok - platform helper avoids mutating git commands\n' >&2
  exit 1
fi
printf 'ok - platform helper avoids mutating git commands\n'
