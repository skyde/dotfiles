#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"
mkdir -p "$tmp/home"
ln -s "$root/common/.local/bin/tmux-session-notify" "$tmp/bin/tmux-session-notify"

dollar='$'
notify_source="$(<"$root/common/.local/bin/tmux-session-notify")"

if [[ "$notify_source" == *"${dollar}{HOME:-}/.local/bin/tmux-session"* ]]; then
  printf 'not ok - notify wrapper does not probe root-local helper fallback\n' >&2
  exit 1
fi
printf 'ok - notify wrapper does not probe root-local helper fallback\n'

if [[ "$notify_source" == *"${dollar}{HOME:-}/dotfiles/common/.local/bin/tmux-session"* ]]; then
  printf 'not ok - notify wrapper does not probe root dotfiles helper fallback\n' >&2
  exit 1
fi
printf 'ok - notify wrapper does not probe root dotfiles helper fallback\n'

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

cat >"$tmp/bin/tmux" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "display-message" ]]; then
  if [[ "${2:-}" == "-p" ]]; then
    exit "${TMUX_SESSION_NOTIFY_LIVE_STATUS:-0}"
  fi
  if [[ "${TMUX_SESSION_NOTIFY_TMUX_FAIL:-}" == "1" ]]; then
    exit 1
  fi
  if [[ -n "${TMUX_SESSION_NOTIFY_TMUX_ENV_LOG:-}" ]]; then
    printf '%s\n' "${TMUX-<unset>}" >>"$TMUX_SESSION_NOTIFY_TMUX_ENV_LOG"
  fi
  shift
  printf '%s\n' "$*" >>"${TMUX_SESSION_NOTIFY_DISPLAY_LOG:?}"
  exit 0
fi
printf 'unexpected tmux command: %s\n' "$*" >&2
exit 2
SH
chmod +x "$tmp/bin/tmux"

cat >"$tmp/bin/tmux-session" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${TMUX_SESSION_NOTIFY_ARGS_LOG:?}"
case "${TMUX_SESSION_NOTIFY_MODE:-success}" in
  success)
    printf 'attached\n'
    ;;
  fail)
    printf 'line one\n' >&2
    printf 'specific failure\n' >&2
    exit 42
    ;;
  empty-fail)
    exit 43
    ;;
esac
SH
chmod +x "$tmp/bin/tmux-session"

success_args_log="$tmp/success.args"
success_display_log="$tmp/success.display"
success_output="$(
  TMUX=fake \
    HOME="$tmp/home" \
    TMUX_SESSION_NOTIFY_ARGS_LOG="$success_args_log" \
    TMUX_SESSION_NOTIFY_DISPLAY_LOG="$success_display_log" \
    PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$tmp/bin/tmux-session-notify" --window terminal --start-dir "$tmp" 2>&1
)"
assert_eq "notify wrapper passes args" "--window terminal --start-dir $tmp" "$(cat "$success_args_log")"
assert_eq "notify wrapper preserves success output" "attached" "$success_output"
if [[ -e "$success_display_log" ]]; then
  printf 'not ok - notify wrapper is quiet on success\n' >&2
  cat "$success_display_log" >&2
  exit 1
fi
printf 'ok - notify wrapper is quiet on success\n'

fail_args_log="$tmp/fail.args"
fail_display_log="$tmp/fail.display"
fail_stderr="$tmp/fail.stderr"
if TMUX=fake \
  HOME="$tmp/home" \
  TMUX_SESSION_NOTIFY_ARGS_LOG="$fail_args_log" \
  TMUX_SESSION_NOTIFY_DISPLAY_LOG="$fail_display_log" \
  TMUX_SESSION_NOTIFY_MODE=fail \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$tmp/bin/tmux-session-notify" --window missing >"$tmp/fail.stdout" 2>"$fail_stderr"; then
  printf 'not ok - notify wrapper fails with helper\n' >&2
  exit 1
fi
assert_eq "notify wrapper reports final stderr line" \
  "tmux-session failed: specific failure" \
  "$(cat "$fail_display_log")"
assert_eq "notify wrapper preserves failure stderr" \
  "$(printf 'line one\nspecific failure')" \
  "$(cat "$fail_stderr")"

no_summary_tools_bin="$tmp/no-summary-tools-bin"
no_summary_display_log="$tmp/no-summary-tools.display"
no_summary_stderr="$tmp/no-summary-tools.stderr"
mkdir -p "$no_summary_tools_bin"
ln -s "$(command -v bash)" "$no_summary_tools_bin/bash"
ln -s "$tmp/bin/tmux" "$no_summary_tools_bin/tmux"
ln -s "$tmp/bin/tmux-session" "$no_summary_tools_bin/tmux-session"
ln -s "$root/common/.local/bin/tmux-session-notify" "$no_summary_tools_bin/tmux-session-notify"
if TMUX=fake \
  HOME="$tmp/home" \
  TMUX_SESSION_NOTIFY_ARGS_LOG="$tmp/no-summary-tools.args" \
  TMUX_SESSION_NOTIFY_DISPLAY_LOG="$no_summary_display_log" \
  TMUX_SESSION_NOTIFY_MODE=fail \
  PATH="$no_summary_tools_bin" \
  "$no_summary_tools_bin/tmux-session-notify" --window missing >"$tmp/no-summary-tools.stdout" 2>"$no_summary_stderr"; then
  printf 'not ok - notify wrapper fails without summary tools\n' >&2
  exit 1
fi
assert_eq "notify wrapper summarizes failure without sed or tail" \
  "tmux-session failed: specific failure" \
  "$(cat "$no_summary_display_log")"
assert_eq "notify wrapper preserves stderr without sed or tail" \
  "$(printf 'line one\nspecific failure')" \
  "$(cat "$no_summary_stderr")"

empty_display_log="$tmp/empty.display"
if TMUX=fake \
  HOME="$tmp/home" \
  TMUX_SESSION_NOTIFY_ARGS_LOG="$tmp/empty.args" \
  TMUX_SESSION_NOTIFY_DISPLAY_LOG="$empty_display_log" \
  TMUX_SESSION_NOTIFY_MODE=empty-fail \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$tmp/bin/tmux-session-notify" >"$tmp/empty.stdout" 2>"$tmp/empty.stderr"; then
  printf 'not ok - notify wrapper fails on empty helper error\n' >&2
  exit 1
fi
assert_eq "notify wrapper reports empty failure status" \
  "tmux-session failed: exit 43" \
  "$(cat "$empty_display_log")"

stale_display_log="$tmp/stale.display"
stale_env_log="$tmp/stale.env"
if TMUX="$tmp/stale-client" \
  HOME="$tmp/home" \
  TMUX_SESSION_NOTIFY_ARGS_LOG="$tmp/stale.args" \
  TMUX_SESSION_NOTIFY_DISPLAY_LOG="$stale_display_log" \
  TMUX_SESSION_NOTIFY_TMUX_ENV_LOG="$stale_env_log" \
  TMUX_SESSION_NOTIFY_LIVE_STATUS=1 \
  TMUX_SESSION_NOTIFY_MODE=fail \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$tmp/bin/tmux-session-notify" --window missing >"$tmp/stale.stdout" 2>"$tmp/stale.stderr"; then
  printf 'not ok - notify wrapper fails with stale TMUX helper error\n' >&2
  exit 1
fi
assert_eq "stale TMUX notify clears TMUX for display message" \
  "<unset>" \
  "$(cat "$stale_env_log")"
assert_eq "stale TMUX notify reports final stderr line" \
  "tmux-session failed: specific failure" \
  "$(cat "$stale_display_log")"

no_env_stale_bin="$tmp/no-env-stale-bin"
no_env_stale_display_log="$tmp/no-env-stale.display"
no_env_stale_env_log="$tmp/no-env-stale.env"
mkdir -p "$no_env_stale_bin"
ln -s "$(command -v bash)" "$no_env_stale_bin/bash"
ln -s "$tmp/bin/tmux" "$no_env_stale_bin/tmux"
ln -s "$tmp/bin/tmux-session" "$no_env_stale_bin/tmux-session"
ln -s "$root/common/.local/bin/tmux-session-notify" "$no_env_stale_bin/tmux-session-notify"
if TMUX="$tmp/stale-client" \
  HOME="$tmp/home" \
  TMUX_SESSION_NOTIFY_ARGS_LOG="$tmp/no-env-stale.args" \
  TMUX_SESSION_NOTIFY_DISPLAY_LOG="$no_env_stale_display_log" \
  TMUX_SESSION_NOTIFY_TMUX_ENV_LOG="$no_env_stale_env_log" \
  TMUX_SESSION_NOTIFY_LIVE_STATUS=1 \
  TMUX_SESSION_NOTIFY_MODE=fail \
  PATH="$no_env_stale_bin" \
  "$no_env_stale_bin/tmux-session-notify" --window missing >"$tmp/no-env-stale.stdout" 2>"$tmp/no-env-stale.stderr"; then
  printf 'not ok - notify wrapper fails with stale TMUX without env\n' >&2
  exit 1
fi
assert_eq "stale TMUX notify clears TMUX without env for display message" \
  "<unset>" \
  "$(cat "$no_env_stale_env_log")"
assert_eq "stale TMUX notify reports final stderr line without env" \
  "tmux-session failed: specific failure" \
  "$(cat "$no_env_stale_display_log")"

mkdir -p "$tmp/path-fallback-bin"
ln -s "$root/common/.local/bin/tmux-session-notify" "$tmp/path-fallback-bin/tmux-session-notify"
ln -s "$tmp/bin/tmux" "$tmp/path-fallback-bin/tmux"
path_fallback_args_log="$tmp/path-fallback.args"
path_fallback_output="$(
  TMUX=fake \
    HOME="$tmp/home" \
    TMUX_SESSION_NOTIFY_ARGS_LOG="$path_fallback_args_log" \
    TMUX_SESSION_NOTIFY_DISPLAY_LOG="$tmp/path-fallback.display" \
    PATH="$tmp/path-fallback-bin:$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$tmp/path-fallback-bin/tmux-session-notify" --window agent 2>&1
)"
assert_eq "notify wrapper falls back to PATH helper" "--window agent" "$(cat "$path_fallback_args_log")"
assert_eq "notify wrapper preserves PATH fallback output" "attached" "$path_fallback_output"

mkdir -p "$tmp/no-home-bin"
ln -s "$root/common/.local/bin/tmux-session-notify" "$tmp/no-home-bin/tmux-session-notify"
ln -s "$tmp/bin/tmux" "$tmp/no-home-bin/tmux"
no_home_args_log="$tmp/no-home.args"
no_home_output="$(
  env -u HOME \
    TMUX=fake \
    TMUX_SESSION_NOTIFY_ARGS_LOG="$no_home_args_log" \
    TMUX_SESSION_NOTIFY_DISPLAY_LOG="$tmp/no-home.display" \
    PATH="$tmp/no-home-bin:$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$tmp/no-home-bin/tmux-session-notify" --window terminal 2>&1
)"
assert_eq "notify wrapper falls back to PATH helper when HOME is unset" "--window terminal" "$(cat "$no_home_args_log")"
assert_eq "notify wrapper preserves no-HOME PATH fallback output" "attached" "$no_home_output"

mkdir -p "$tmp/home-local-bin" "$tmp/home-local-path-bin" "$tmp/home-local/.local/bin"
ln -s "$root/common/.local/bin/tmux-session-notify" "$tmp/home-local-bin/tmux-session-notify"
ln -s "$tmp/bin/tmux" "$tmp/home-local-bin/tmux"
ln -s "$tmp/bin/tmux-session" "$tmp/home-local/.local/bin/tmux-session"
cat >"$tmp/home-local-path-bin/tmux-session" <<'SH'
#!/usr/bin/env bash
printf 'path shadow tmux-session should not run\n' >&2
exit 97
SH
chmod +x "$tmp/home-local-path-bin/tmux-session"
home_local_args_log="$tmp/home-local.args"
home_local_output="$(
  TMUX=fake \
    HOME="$tmp/home-local" \
    TMUX_SESSION_NOTIFY_ARGS_LOG="$home_local_args_log" \
    TMUX_SESSION_NOTIFY_DISPLAY_LOG="$tmp/home-local.display" \
    PATH="$tmp/home-local-path-bin:$tmp/home-local-bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$tmp/home-local-bin/tmux-session-notify" --window resume 2>&1
)"
assert_eq "notify wrapper falls back to home helper before PATH shadow" "--window resume" "$(cat "$home_local_args_log")"
assert_eq "notify wrapper preserves home fallback output" "attached" "$home_local_output"

mkdir -p "$tmp/home-dotfiles-bin" "$tmp/home-dotfiles-path-bin" "$tmp/home-dotfiles/dotfiles/common/.local/bin"
ln -s "$root/common/.local/bin/tmux-session-notify" "$tmp/home-dotfiles-bin/tmux-session-notify"
ln -s "$tmp/bin/tmux" "$tmp/home-dotfiles-bin/tmux"
ln -s "$tmp/bin/tmux-session" "$tmp/home-dotfiles/dotfiles/common/.local/bin/tmux-session"
cat >"$tmp/home-dotfiles-path-bin/tmux-session" <<'SH'
#!/usr/bin/env bash
printf 'path shadow tmux-session should not run\n' >&2
exit 97
SH
chmod +x "$tmp/home-dotfiles-path-bin/tmux-session"
home_dotfiles_args_log="$tmp/home-dotfiles.args"
home_dotfiles_output="$(
  TMUX=fake \
    HOME="$tmp/home-dotfiles" \
    TMUX_SESSION_NOTIFY_ARGS_LOG="$home_dotfiles_args_log" \
    TMUX_SESSION_NOTIFY_DISPLAY_LOG="$tmp/home-dotfiles.display" \
    PATH="$tmp/home-dotfiles-path-bin:$tmp/home-dotfiles-bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$tmp/home-dotfiles-bin/tmux-session-notify" --window terminal 2>&1
)"
assert_eq "notify wrapper falls back to home dotfiles helper before PATH shadow" "--window terminal" "$(cat "$home_dotfiles_args_log")"
assert_eq "notify wrapper preserves home dotfiles fallback output" "attached" "$home_dotfiles_output"

mkdir -p "$tmp/missing-bin"
ln -s "$root/common/.local/bin/tmux-session-notify" "$tmp/missing-bin/tmux-session-notify"
ln -s "$tmp/bin/tmux" "$tmp/missing-bin/tmux"
missing_display_log="$tmp/missing.display"
if TMUX=fake \
  HOME="$tmp/home" \
  TMUX_SESSION_NOTIFY_DISPLAY_LOG="$missing_display_log" \
  PATH="$tmp/missing-bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$tmp/missing-bin/tmux-session-notify" >"$tmp/missing.stdout" 2>"$tmp/missing.stderr"; then
  printf 'not ok - notify wrapper fails when helper is missing\n' >&2
  exit 1
fi
assert_eq "notify wrapper reports missing helper" \
  "tmux-session failed: helper is unavailable" \
  "$(cat "$missing_display_log")"

fallback_stderr="$tmp/fallback.stderr"
if TMUX=fake \
  HOME="$tmp/home" \
  TMUX_SESSION_NOTIFY_ARGS_LOG="$tmp/fallback.args" \
  TMUX_SESSION_NOTIFY_DISPLAY_LOG="$tmp/fallback.display" \
  TMUX_SESSION_NOTIFY_MODE=fail \
  TMUX_SESSION_NOTIFY_TMUX_FAIL=1 \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$tmp/bin/tmux-session-notify" --window missing >"$tmp/fallback.stdout" 2>"$fallback_stderr"; then
  printf 'not ok - notify wrapper falls back when tmux display fails\n' >&2
  exit 1
fi
assert_eq "notify wrapper falls back to stderr when tmux display fails" \
  "$(printf 'tmux-session failed: specific failure\nline one\nspecific failure')" \
  "$(cat "$fallback_stderr")"
