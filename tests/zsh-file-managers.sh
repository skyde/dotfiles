#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/zsh-file-managers.XXXXXX")"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

skip() {
  printf 'skip - %s\n' "$1"
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

if ! zsh_path="$(command -v zsh)"; then
  skip "zsh file-manager wrappers (zsh unavailable)"
  exit 0
fi

mkdir -p "$tmp/bin" "$tmp/min-bin" "$tmp/home" "$tmp/cache" "$tmp/start" "$tmp/target"

cat >"$tmp/bin/starship" <<'SH'
#!/usr/bin/env sh
if [ "${1:-}" = "init" ]; then
  exit 0
fi
exit 0
SH
chmod +x "$tmp/bin/starship"
cp "$tmp/bin/starship" "$tmp/min-bin/starship"

cat >"$tmp/bin/yazi" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

cwd_file=""
for arg in "$@"; do
  case "$arg" in
    --cwd-file=*) cwd_file="${arg#--cwd-file=}" ;;
  esac
done

if [[ -n "$cwd_file" ]]; then
  case "${YAZI_TEST_MODE:-same}" in
    change|fail) printf '%s\n' "${YAZI_TEST_TARGET:?}" >"$cwd_file" ;;
    same) printf '%s\n' "$PWD" >"$cwd_file" ;;
    empty) : >"$cwd_file" ;;
    delete) rm -f -- "$cwd_file" ;;
  esac
fi

case "${YAZI_TEST_MODE:-same}" in
  fail) exit 42 ;;
  *) exit 0 ;;
esac
SH
chmod +x "$tmp/bin/yazi"

cat >"$tmp/bin/lf" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

last_dir_file=""
while (($#)); do
  case "$1" in
    -last-dir-path)
      last_dir_file="${2:-}"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -n "$last_dir_file" ]]; then
  case "${LF_TEST_MODE:-same}" in
    change|fail) printf '%s\n' "${LF_TEST_TARGET:?}" >"$last_dir_file" ;;
    same) printf '%s\n' "$PWD" >"$last_dir_file" ;;
    empty) : >"$last_dir_file" ;;
    delete) rm -f -- "$last_dir_file" ;;
  esac
fi

case "${LF_TEST_MODE:-same}" in
  fail) exit 17 ;;
  *) exit 0 ;;
esac
SH
chmod +x "$tmp/bin/lf"

run_zsh() {
  local path="$1"
  local script="$2"
  shift 2

  DOTFILES_ZSHRC="$root/common/.zshrc" \
    HOME="$tmp/home" \
    PATH="$path:/usr/bin:/bin:/usr/sbin:/sbin" \
    YAZI_TEST_MODE="${YAZI_TEST_MODE:-}" \
    YAZI_TEST_TARGET="${YAZI_TEST_TARGET:-}" \
    LF_TEST_MODE="${LF_TEST_MODE:-}" \
    LF_TEST_TARGET="${LF_TEST_TARGET:-}" \
    START="$tmp/start" \
    TARGET="$tmp/target" \
    XDG_CACHE_HOME="$tmp/cache" \
    "$@" "$zsh_path" -fic 'source "$DOTFILES_ZSHRC"; cd "$START"; '"$script"
}

same_output="$(YAZI_TEST_MODE=same run_zsh "$tmp/bin" 'e; rc=$?; printf "rc=%s pwd=%s\n" "$rc" "$PWD"')"
assert_eq "e returns success when yazi stays in current dir" "rc=0 pwd=$tmp/start" "$same_output"

change_output="$(YAZI_TEST_MODE=change YAZI_TEST_TARGET="$tmp/target" run_zsh "$tmp/bin" 'e; rc=$?; printf "rc=%s pwd=%s\n" "$rc" "$PWD"')"
assert_eq "e changes to yazi cwd on success" "rc=0 pwd=$tmp/target" "$change_output"

fail_output="$(YAZI_TEST_MODE=fail YAZI_TEST_TARGET="$tmp/target" run_zsh "$tmp/bin" 'e; rc=$?; printf "rc=%s pwd=%s\n" "$rc" "$PWD"')"
assert_eq "e preserves yazi failure and cwd" "rc=42 pwd=$tmp/start" "$fail_output"

delete_output="$(YAZI_TEST_MODE=delete run_zsh "$tmp/bin" 'e; rc=$?; printf "rc=%s pwd=%s\n" "$rc" "$PWD"')"
assert_eq "e tolerates missing yazi cwd file" "rc=0 pwd=$tmp/start" "$delete_output"

if missing_output="$(run_zsh "$tmp/min-bin" 'e; rc=$?; printf "rc=%s pwd=%s\n" "$rc" "$PWD"' 2>&1)"; then
  :
fi
assert_contains "e reports missing yazi" "$missing_output" "e: yazi not found"
assert_contains "e returns 127 for missing yazi" "$missing_output" "rc=127 pwd=$tmp/start"

lf_same_output="$(LF_TEST_MODE=same run_zsh "$tmp/bin" 'lfcd; rc=$?; printf "rc=%s pwd=%s\n" "$rc" "$PWD"')"
assert_eq "lfcd returns success when lf stays in current dir" "rc=0 pwd=$tmp/start" "$lf_same_output"

lf_change_output="$(LF_TEST_MODE=change LF_TEST_TARGET="$tmp/target" run_zsh "$tmp/bin" 'lfcd; rc=$?; printf "rc=%s pwd=%s\n" "$rc" "$PWD"')"
assert_eq "lfcd changes to lf cwd on success" "rc=0 pwd=$tmp/target" "$lf_change_output"

lf_fail_output="$(LF_TEST_MODE=fail LF_TEST_TARGET="$tmp/target" run_zsh "$tmp/bin" 'lfcd; rc=$?; printf "rc=%s pwd=%s\n" "$rc" "$PWD"')"
assert_eq "lfcd preserves lf failure and cwd" "rc=17 pwd=$tmp/start" "$lf_fail_output"

lf_delete_output="$(LF_TEST_MODE=delete run_zsh "$tmp/bin" 'lfcd; rc=$?; printf "rc=%s pwd=%s\n" "$rc" "$PWD"')"
assert_eq "lfcd tolerates missing lf cwd file" "rc=0 pwd=$tmp/start" "$lf_delete_output"

if lf_missing_output="$(run_zsh "$tmp/min-bin" 'lfcd; rc=$?; printf "rc=%s pwd=%s\n" "$rc" "$PWD"' 2>&1)"; then
  :
fi
assert_contains "lfcd reports missing lf" "$lf_missing_output" "lfcd: lf not found"
assert_contains "lfcd returns 127 for missing lf" "$lf_missing_output" "rc=127 pwd=$tmp/start"
