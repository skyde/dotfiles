#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/yazi-wrapper.XXXXXX")"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

assert_eq() {
  local description="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$actual" != "$expected" ]]; then
    printf 'not ok - %s\nexpected:\n%s\nactual:\n%s\n' "$description" "$expected" "$actual" >&2
    exit 1
  fi

  pass "$description"
}

assert_contains() {
  local description="$1"
  local haystack="$2"
  local needle="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'not ok - %s\nmissing: %s\noutput:\n%s\n' "$description" "$needle" "$haystack" >&2
    exit 1
  fi

  pass "$description"
}

assert_not_exists() {
  local description="$1"
  local path="$2"

  if [[ -e "$path" ]]; then
    printf 'not ok - %s\nstill exists: %s\n' "$description" "$path" >&2
    exit 1
  fi

  pass "$description"
}

mkdir -p "$tmp/real-bin" "$tmp/home-no-local" "$tmp/home-local"

cat >"$tmp/real-bin/yazi" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

{
  printf 'argc=%s\n' "$#"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
  printf 'config=%s\n' "${YAZI_CONFIG_HOME-<unset>}"
} >"${YAZI_TEST_LOG:?}"

if [[ -n "${YAZI_CONFIG_HOME:-}" ]]; then
  printf '%s\n' "$YAZI_CONFIG_HOME" >"${YAZI_TEST_CONFIG_PATH:?}"
  [[ -f "$YAZI_CONFIG_HOME/keymap.toml" ]] && cp "$YAZI_CONFIG_HOME/keymap.toml" "${YAZI_TEST_KEYMAP_COPY:?}"
  [[ -L "$YAZI_CONFIG_HOME/yazi.toml" ]] && readlink "$YAZI_CONFIG_HOME/yazi.toml" >"${YAZI_TEST_LINK_TARGET:?}"
fi

exit "${YAZI_TEST_STATUS:-0}"
SH
chmod +x "$tmp/real-bin/yazi"

test_path="$root/common/.local/bin:$tmp/real-bin:/usr/bin:/bin:/usr/sbin:/sbin"

YAZI_TEST_LOG="$tmp/no-local.log" \
  HOME="$tmp/home-no-local" \
  PATH="$test_path" \
  "$root/common/.local/bin/yazi" --cwd-file "$tmp/cwd file" "name with spaces"
no_local_output="$(cat "$tmp/no-local.log")"
assert_contains "yazi wrapper skips itself and delegates to real yazi" "$no_local_output" "arg=name with spaces"
assert_contains "yazi wrapper leaves config untouched without local keymap" "$no_local_output" "config=<unset>"

config_root="$tmp/config"
mkdir -p "$config_root/yazi" "$config_root/yazi-local"
printf 'base-keymap\n' >"$config_root/yazi/keymap.toml"
printf 'settings\n' >"$config_root/yazi/yazi.toml"
printf 'local-keymap\n' >"$config_root/yazi-local/keymap.toml"

local_status=0
if YAZI_TEST_LOG="$tmp/local.log" \
  YAZI_TEST_CONFIG_PATH="$tmp/local-config-path" \
  YAZI_TEST_KEYMAP_COPY="$tmp/local-keymap-copy" \
  YAZI_TEST_LINK_TARGET="$tmp/local-link-target" \
  YAZI_TEST_STATUS=23 \
  HOME="$tmp/home-local" \
  XDG_CONFIG_HOME="$config_root" \
  PATH="$test_path" \
  "$root/common/.local/bin/yazi" --select "$tmp/file"; then
  printf 'not ok - yazi wrapper propagates real yazi failure\n' >&2
  exit 1
else
  local_status=$?
fi
assert_eq "yazi wrapper propagates real yazi failure" "23" "$local_status"
assert_eq "yazi wrapper merges tracked and local keymaps" $'base-keymap\n\nlocal-keymap' "$(cat "$tmp/local-keymap-copy")"
assert_eq "yazi wrapper links non-keymap config files" "$config_root/yazi/yazi.toml" "$(cat "$tmp/local-link-target")"
assert_not_exists "yazi wrapper removes temporary config after failure" "$(cat "$tmp/local-config-path")"

override_config="$tmp/override-config"
override_local="$tmp/override-local/keymap.toml"
mkdir -p "$override_config" "$(dirname "$override_local")"
printf 'override-base\n' >"$override_config/keymap.toml"
printf 'override-settings\n' >"$override_config/yazi.toml"
printf 'override-local\n' >"$override_local"

YAZI_TEST_LOG="$tmp/override.log" \
  YAZI_TEST_CONFIG_PATH="$tmp/override-config-path" \
  YAZI_TEST_KEYMAP_COPY="$tmp/override-keymap-copy" \
  YAZI_TEST_LINK_TARGET="$tmp/override-link-target" \
  HOME="$tmp/home-local" \
  YAZI_CONFIG_HOME="$override_config" \
  YAZI_LOCAL_KEYMAP="$override_local" \
  PATH="$test_path" \
  "$root/common/.local/bin/yazi"
assert_eq "yazi wrapper respects config override" $'override-base\n\noverride-local' "$(cat "$tmp/override-keymap-copy")"
assert_eq "yazi wrapper respects local keymap override" "$override_config/yazi.toml" "$(cat "$tmp/override-link-target")"
assert_not_exists "yazi wrapper removes temporary config after success" "$(cat "$tmp/override-config-path")"

mkdir -p "$tmp/wrapper-only"
cp "$root/common/.local/bin/yazi" "$tmp/wrapper-only/yazi"
if HOME="$tmp/home-no-local" \
  PATH="$tmp/wrapper-only:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$tmp/wrapper-only/yazi" 2>"$tmp/missing-stderr"; then
  printf 'not ok - yazi wrapper exits non-zero when real yazi is missing\n' >&2
  exit 1
else
  missing_status=$?
fi
assert_eq "yazi wrapper returns 127 when real yazi is missing" "127" "$missing_status"
assert_contains "yazi wrapper reports missing real yazi" "$(cat "$tmp/missing-stderr")" "could not find the real yazi binary"
