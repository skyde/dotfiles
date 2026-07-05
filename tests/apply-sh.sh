#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/apply-sh.XXXXXX")"

cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

assert_eq() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$actual" != "$expected" ]]; then
    printf 'not ok - %s\n' "$name" >&2
    printf 'expected:\n%s\n' "$expected" >&2
    printf 'actual:\n%s\n' "$actual" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

assert_contains() {
  local name="$1"
  local haystack="$2"
  local needle="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'not ok - %s\nmissing: %s\noutput:\n%s\n' "$name" "$needle" "$haystack" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

assert_not_contains() {
  local name="$1"
  local haystack="$2"
  local needle="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'not ok - %s\nunexpected: %s\noutput:\n%s\n' "$name" "$needle" "$haystack" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

mkdir -p "$tmp/bin" "$tmp/home/dotfiles-local"

cat >"$tmp/bin/uname" <<'SH'
#!/usr/bin/env bash
printf 'Darwin\n'
SH
chmod +x "$tmp/bin/uname"

cat >"$tmp/bin/stow" <<'SH'
#!/usr/bin/env bash
{
  printf 'stow\n'
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
  printf -- '--\n'
} >>"${DOTFILES_APPLY_STOW_LOG:?}"
SH
chmod +x "$tmp/bin/stow"

cat >"$tmp/home/dotfiles-local/apply.sh" <<'SH'
#!/usr/bin/env bash
{
  printf 'call\n'
  printf 'argc=%s\n' "$#"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
} >>"${DOTFILES_APPLY_LOCAL_LOG:?}"
SH
chmod +x "$tmp/home/dotfiles-local/apply.sh"

local_log="$tmp/local.log"
stow_log="$tmp/stow.log"
output="$(
  HOME="$tmp/home" \
    PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    DOTFILES_APPLY_LOCAL_LOG="$local_log" \
    DOTFILES_APPLY_STOW_LOG="$stow_log" \
    "$root/apply.sh" --no --restow --yes "two words"
)"

assert_eq "dotfiles-local apply runs once after platform packages" \
  $'call\nargc=4\narg=--no\narg=--restow\narg=--yes\narg=two words' \
  "$(cat "$local_log")"

stow_output="$(cat "$stow_log")"
assert_eq "dry-run stow runs common and mac packages under Darwin" "2" "$(grep -c '^stow$' "$stow_log")"
assert_contains "stow receives common package" "$stow_output" "arg=common"
assert_contains "stow receives mac package" "$stow_output" "arg=mac"
assert_not_contains "stow still filters --yes" "$stow_output" "arg=--yes"
assert_contains "apply reports dotfiles-local once" "$output" "🔗 Found dotfiles-local, applying..."
