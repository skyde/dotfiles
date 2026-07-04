#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="$root/common/.config/lazygit/config.yml"
tmp="$(mktemp -d)"
fake_bin="$tmp/bin"
mkdir -p "$fake_bin"

cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

assert_eq() {
  local description="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$expected" != "$actual" ]]; then
    printf 'not ok - %s\nexpected: %s\nactual: %s\n' "$description" "$expected" "$actual" >&2
    exit 1
  fi

  printf 'ok - %s\n' "$description"
}

assert_files_equal() {
  local description="$1"
  local expected="$2"
  local actual="$3"

  if ! cmp -s "$expected" "$actual"; then
    printf 'not ok - %s\n' "$description" >&2
    printf 'expected bytes:\n' >&2
    od -An -tx1 "$expected" >&2
    printf 'actual bytes:\n' >&2
    od -An -tx1 "$actual" >&2
    exit 1
  fi

  printf 'ok - %s\n' "$description"
}

copy_cmd="$(
  sed -n 's/^[[:space:]]*copyToClipboardCmd:[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$config"
)"
read_cmd="$(
  sed -n 's/^[[:space:]]*readFromClipboardCmd:[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$config"
)"

assert_eq "lazygit copy command uses osc-copy" "printf '%s' {{text}} | osc-copy" "$copy_cmd"
assert_eq "lazygit paste command uses osc-paste" "osc-paste" "$read_cmd"

if [[ "$copy_cmd" == echo* || "$copy_cmd" == *" echo "* ]]; then
  fail "lazygit copy command avoids echo"
fi
pass "lazygit copy command avoids echo"

cat >"$fake_bin/osc-copy" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cat >"${LAZYGIT_CLIPBOARD_TEST_COPY_LOG:?}"
SH
chmod +x "$fake_bin/osc-copy"

cat >"$fake_bin/osc-paste" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s' "${LAZYGIT_CLIPBOARD_TEST_PASTE_TEXT:-}"
SH
chmod +x "$fake_bin/osc-paste"

run_copy_case() {
  local description="$1"
  local payload="$2"
  local quoted="$payload"
  local rendered_cmd
  local expected="$tmp/$description.expected"
  local actual="$tmp/$description.actual"

  printf '%s' "$payload" >"$expected"
  quoted="${quoted//\\/\\\\}"
  quoted="${quoted//\"/\\\"}"
  quoted="${quoted//\$/\\$}"
  quoted="${quoted//\`/\\\`}"
  quoted="\"$quoted\""
  rendered_cmd="${copy_cmd//'{{text}}'/$quoted}"

  PATH="$fake_bin:$PATH" LAZYGIT_CLIPBOARD_TEST_COPY_LOG="$actual" bash -c "$rendered_cmd"
  assert_files_equal "$description" "$expected" "$actual"
}

run_copy_case "lazygit copy preserves plain text" "plain text"
run_copy_case "lazygit copy preserves leading dash text" "-n"
run_copy_case "lazygit copy preserves backslashes" 'a\tb\c'
# shellcheck disable=SC2016
run_copy_case "lazygit copy preserves shell metacharacters" '$(touch should-not-run) `echo nope` $HOME "quoted"'
run_copy_case "lazygit copy preserves empty text" ""
run_copy_case "lazygit copy preserves trailing newlines" $'line one\nline two\n'

paste_expected="$tmp/paste.expected"
paste_actual="$tmp/paste.actual"
paste_text=$'paste text\nwith newline'
printf '%s' "$paste_text" >"$paste_expected"
PATH="$fake_bin:$PATH" LAZYGIT_CLIPBOARD_TEST_PASTE_TEXT="$paste_text" bash -c "$read_cmd" >"$paste_actual"
assert_files_equal "lazygit paste reads through osc-paste" "$paste_expected" "$paste_actual"
