#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kitty_conf="$root/common/.config/kitty/kitty.conf"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

assert_token() {
  local description="$1"
  local token="$2"

  if [[ " $clipboard_control " != *" $token "* ]]; then
    fail "$description"
  fi

  pass "$description"
}

assert_no_token() {
  local description="$1"
  local token="$2"

  if [[ " $clipboard_control " == *" $token "* ]]; then
    fail "$description"
  fi

  pass "$description"
}

clipboard_control="$(
  sed -n 's/^clipboard_control[[:space:]]\{1,\}//p' "$kitty_conf"
)"

if [[ -z "$clipboard_control" ]]; then
  fail "kitty clipboard_control is configured"
fi
pass "kitty clipboard_control is configured"

if [[ "$(printf '%s\n' "$clipboard_control" | wc -l | tr -d '[:space:]')" != "1" ]]; then
  fail "kitty has one clipboard_control line"
fi
pass "kitty has one clipboard_control line"

assert_token "kitty permits OSC52 clipboard writes" "write-clipboard"
assert_token "kitty permits OSC52 primary writes" "write-primary"
assert_token "kitty asks before OSC52 clipboard reads" "read-clipboard-ask"
assert_token "kitty asks before OSC52 primary reads" "read-primary-ask"
assert_token "kitty keeps append disabled for clipboard writes" "no-append"
assert_no_token "kitty avoids unprompted clipboard reads" "read-clipboard"
assert_no_token "kitty avoids unprompted primary reads" "read-primary"
