#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/work" "$tmp/home/project"

cat >"$tmp/bin/tmux" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

command="${1:-}"
shift || true

case "$command" in
  list-commands)
    if [[ "${TMUX_TEST_HAS_POPUP:-1}" == "1" ]]; then
      printf 'display-popup\n'
    fi
    printf 'display-message\nnew-window\n'
    ;;
  display-message)
    if [[ "${1:-}" == "-p" ]]; then
      if [[ -n "${TMUX_TEST_STALE_CLIENT:-}" && "${2:-}" == '#{pane_id}' ]]; then
        exit 1
      elif [[ "${2:-}" == '#{pane_id}' ]]; then
        printf '%%1\n'
      else
        printf '%s\n' "${TMUX_TEST_CURRENT_PATH:?}"
      fi
    else
      if [[ -n "${TMUX_TEST_DISPLAY_ENV_LOG:-}" ]]; then
        printf '%s\n' "${TMUX-<unset>}" >>"$TMUX_TEST_DISPLAY_ENV_LOG"
      fi
      printf '%s\n' "$*" >>"${TMUX_TEST_DISPLAY_LOG:?}"
    fi
    ;;
  display-popup)
    printf 'display-popup' >>"${TMUX_TEST_LOG:?}"
    for arg in "$@"; do
      printf '\narg=%s' "$arg" >>"${TMUX_TEST_LOG:?}"
    done
    printf '\n' >>"${TMUX_TEST_LOG:?}"
    exit "${TMUX_TEST_POPUP_STATUS:-0}"
    ;;
  new-window)
    printf 'new-window' >>"${TMUX_TEST_LOG:?}"
    printf '\ntmux=%s' "${TMUX-<unset>}" >>"${TMUX_TEST_LOG:?}"
    for arg in "$@"; do
      printf '\narg=%s' "$arg" >>"${TMUX_TEST_LOG:?}"
    done
    printf '\n' >>"${TMUX_TEST_LOG:?}"
    exit "${TMUX_TEST_NEW_WINDOW_STATUS:-0}"
    ;;
  *)
    printf 'unexpected tmux command: %s %s\n' "$command" "$*" >&2
    exit 2
    ;;
esac
SH
chmod +x "$tmp/bin/tmux"

cat >"$tmp/bin/lazygit" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$tmp/bin/lazygit"

cat >"$tmp/bin/gitui" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$tmp/bin/gitui"

cat >"$tmp/bin/yazi" <<'SH'
#!/usr/bin/env bash
exit 77
SH
chmod +x "$tmp/bin/yazi"

assert_contains() {
  local name="$1"
  local haystack="$2"
  local needle="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'not ok - %s\n' "$name" >&2
    printf 'missing:\n%s\n' "$needle" >&2
    printf 'actual:\n%s\n' "$haystack" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

assert_not_contains() {
  local name="$1"
  local haystack="$2"
  local needle="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'not ok - %s\n' "$name" >&2
    printf 'unexpected:\n%s\n' "$needle" >&2
    printf 'actual:\n%s\n' "$haystack" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

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

run_helper() {
  HOME="$tmp/home" \
    TMUX=fake \
    TMUX_TEST_CURRENT_PATH="$tmp/work" \
    TMUX_TEST_DISPLAY_LOG="${TMUX_TEST_DISPLAY_LOG:-$tmp/display.log}" \
    TMUX_TEST_LOG="${TMUX_TEST_LOG:-$tmp/tmux.log}" \
    TMUX_TEST_STALE_CLIENT="${TMUX_TEST_STALE_CLIENT:-}" \
    PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$root/common/.local/bin/tmux-popup-tool" "$@"
}

tmux_log="$tmp/tmux.log"
display_log="$tmp/display.log"
: >"$display_log"
run_helper --start-dir "$tmp/work" --title git lazygit gitui
popup_output="$(cat "$tmux_log")"
assert_contains "popup helper opens tmux popup" "$popup_output" "display-popup"
assert_contains "popup helper closes on exit" "$popup_output" $'arg=-E'
assert_contains "popup helper starts in requested directory" "$popup_output" "arg=$tmp/work"
assert_contains "popup helper sets title" "$popup_output" "arg= git "
assert_contains "popup helper uses lazygit first" "$popup_output" "arg=$tmp/bin/lazygit"
assert_eq "popup helper is quiet on success" "" "$(cat "$display_log")"

no_grep_bin="$tmp/no-grep-bin"
no_grep_log="$tmp/no-grep-tmux.log"
no_grep_display_log="$tmp/no-grep-display.log"
mkdir -p "$no_grep_bin"
ln -s "$(command -v bash)" "$no_grep_bin/bash"
ln -s "$tmp/bin/tmux" "$no_grep_bin/tmux"
ln -s "$tmp/bin/lazygit" "$no_grep_bin/lazygit"
ln -s "$root/common/.local/bin/tmux-popup-tool" "$no_grep_bin/tmux-popup-tool"
: >"$no_grep_display_log"
HOME="$tmp/home" \
  TMUX=fake \
  TMUX_TEST_CURRENT_PATH="$tmp/work" \
  TMUX_TEST_DISPLAY_LOG="$no_grep_display_log" \
  TMUX_TEST_LOG="$no_grep_log" \
  PATH="$no_grep_bin" \
  "$no_grep_bin/tmux-popup-tool" --start-dir "$tmp/work" --title git lazygit
no_grep_output="$(cat "$no_grep_log")"
assert_contains "popup helper detects display-popup without grep" "$no_grep_output" "display-popup"
assert_not_contains "popup helper without grep avoids fallback window" "$no_grep_output" "new-window"
assert_eq "popup helper without grep is quiet" "" "$(cat "$no_grep_display_log")"

fallback_log="$tmp/fallback-tmux.log"
fallback_display_log="$tmp/fallback-display.log"
TMUX_TEST_LOG="$fallback_log" \
  TMUX_TEST_DISPLAY_LOG="$fallback_display_log" \
  run_helper missing-tool gitui
fallback_output="$(cat "$fallback_log")"
assert_contains "popup helper falls back to later tool" "$fallback_output" "arg=$tmp/bin/gitui"

adjacent_tool_log="$tmp/adjacent-tool-tmux.log"
adjacent_tool_display_log="$tmp/adjacent-tool-display.log"
TMUX_TEST_LOG="$adjacent_tool_log" \
  TMUX_TEST_DISPLAY_LOG="$adjacent_tool_display_log" \
  run_helper yazi
assert_contains \
  "popup helper falls back to adjacent repo tool before PATH shadow" \
  "$(cat "$adjacent_tool_log")" \
  "arg=$root/common/.local/bin/yazi"

mkdir -p "$tmp/home/.local/bin"
cat >"$tmp/home/.local/bin/yazi" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$tmp/home/.local/bin/yazi"
home_tool_log="$tmp/home-tool-tmux.log"
home_tool_display_log="$tmp/home-tool-display.log"
TMUX_TEST_LOG="$home_tool_log" \
  TMUX_TEST_DISPLAY_LOG="$home_tool_display_log" \
  run_helper yazi
assert_contains \
  "popup helper prefers home local tool before adjacent and PATH shadows" \
  "$(cat "$home_tool_log")" \
  "arg=$tmp/home/.local/bin/yazi"

rm -f "$tmp/home/.local/bin/yazi"
mkdir -p "$tmp/home/dotfiles/common/.local/bin"
cat >"$tmp/home/dotfiles/common/.local/bin/yazi" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$tmp/home/dotfiles/common/.local/bin/yazi"
home_dotfiles_tool_log="$tmp/home-dotfiles-tool-tmux.log"
home_dotfiles_tool_display_log="$tmp/home-dotfiles-tool-display.log"
TMUX_TEST_LOG="$home_dotfiles_tool_log" \
  TMUX_TEST_DISPLAY_LOG="$home_dotfiles_tool_display_log" \
  run_helper yazi
assert_contains \
  "popup helper falls back to home dotfiles tool before adjacent and PATH shadows" \
  "$(cat "$home_dotfiles_tool_log")" \
  "arg=$tmp/home/dotfiles/common/.local/bin/yazi"
rm -f "$tmp/home/dotfiles/common/.local/bin/yazi"

current_path_log="$tmp/current-path-tmux.log"
current_path_display_log="$tmp/current-path-display.log"
TMUX_TEST_LOG="$current_path_log" \
  TMUX_TEST_DISPLAY_LOG="$current_path_display_log" \
  run_helper --title current lazygit
assert_contains "popup helper reads current pane path" "$(cat "$current_path_log")" "arg=$tmp/work"

tilde_log="$tmp/tilde-tmux.log"
tilde_display_log="$tmp/tilde-display.log"
# shellcheck disable=SC2088 # Intentional literal tilde to test helper-side expansion.
tilde_project="$(printf '~/%s' project)"
TMUX_TEST_LOG="$tilde_log" \
  TMUX_TEST_DISPLAY_LOG="$tilde_display_log" \
  run_helper --start-dir "$tilde_project" lazygit
assert_contains "popup helper expands tilde start dir" "$(cat "$tilde_log")" "arg=$tmp/home/project"

windows_drive_popup_log="$tmp/windows-drive-popup-tmux.log"
windows_drive_popup_display_log="$tmp/windows-drive-popup-display.log"
OS=Windows_NT \
  TMUX_TEST_LOG="$windows_drive_popup_log" \
  TMUX_TEST_DISPLAY_LOG="$windows_drive_popup_display_log" \
  run_helper --start-dir 'C:\Users\sky\Project App' lazygit
assert_contains \
  "popup helper accepts Windows drive start dir in Windows env" \
  "$(cat "$windows_drive_popup_log")" \
  "arg=C:/Users/sky/Project App"

windows_unc_popup_log="$tmp/windows-unc-popup-tmux.log"
windows_unc_popup_display_log="$tmp/windows-unc-popup-display.log"
OS=Windows_NT \
  TMUX_TEST_LOG="$windows_unc_popup_log" \
  TMUX_TEST_DISPLAY_LOG="$windows_unc_popup_display_log" \
  run_helper --start-dir '\\server\share\Project App' lazygit
assert_contains \
  "popup helper accepts Windows UNC start dir in Windows env" \
  "$(cat "$windows_unc_popup_log")" \
  "arg=//server/share/Project App"

windows_slash_unc_popup_log="$tmp/windows-slash-unc-popup-tmux.log"
windows_slash_unc_popup_display_log="$tmp/windows-slash-unc-popup-display.log"
OS=Windows_NT \
  TMUX_TEST_LOG="$windows_slash_unc_popup_log" \
  TMUX_TEST_DISPLAY_LOG="$windows_slash_unc_popup_display_log" \
  run_helper --start-dir '//server/share/Project App' lazygit
assert_contains \
  "popup helper accepts Windows slash UNC start dir in Windows env" \
  "$(cat "$windows_slash_unc_popup_log")" \
  "arg=//server/share/Project App"

missing_tool_log="$tmp/missing-tool-tmux.log"
missing_tool_display_log="$tmp/missing-tool-display.log"
if TMUX_TEST_LOG="$missing_tool_log" \
  TMUX_TEST_DISPLAY_LOG="$missing_tool_display_log" \
  run_helper missing-a missing-b 2>"$tmp/missing-tool-stderr.txt"; then
  printf 'not ok - popup helper exits non-zero when tools are missing\n' >&2
  exit 1
fi
printf 'ok - popup helper exits non-zero when tools are missing\n'
assert_contains "popup helper reports missing tools to stderr" \
  "$(cat "$tmp/missing-tool-stderr.txt")" \
  "No popup command found: missing-a, missing-b"
assert_contains "popup helper reports missing tools to tmux" \
  "$(cat "$missing_tool_display_log")" \
  "No popup command found: missing-a, missing-b"

bad_dir_display_log="$tmp/bad-dir-display.log"
if TMUX_TEST_LOG="$tmp/bad-dir-tmux.log" \
  TMUX_TEST_DISPLAY_LOG="$bad_dir_display_log" \
  run_helper --start-dir "$tmp/nope" lazygit 2>"$tmp/bad-dir-stderr.txt"; then
  printf 'not ok - popup helper exits non-zero for invalid directory\n' >&2
  exit 1
fi
printf 'ok - popup helper exits non-zero for invalid directory\n'
assert_contains "popup helper reports invalid directory" \
  "$(cat "$bad_dir_display_log")" \
  "Popup start directory is not a directory"

popup_failure_log="$tmp/popup-failure-tmux.log"
popup_failure_display_log="$tmp/popup-failure-display.log"
if TMUX_TEST_LOG="$popup_failure_log" \
  TMUX_TEST_DISPLAY_LOG="$popup_failure_display_log" \
  TMUX_TEST_POPUP_STATUS=7 \
  run_helper lazygit 2>"$tmp/popup-failure-stderr.txt"; then
  printf 'not ok - popup helper exits non-zero when display-popup fails\n' >&2
  exit 1
fi
printf 'ok - popup helper exits non-zero when display-popup fails\n'
assert_contains "popup helper reports popup failure to stderr" \
  "$(cat "$tmp/popup-failure-stderr.txt")" \
  "Unable to open popup: lazygit"
assert_contains "popup helper reports popup failure to tmux" \
  "$(cat "$popup_failure_display_log")" \
  "Unable to open popup: lazygit"

no_popup_log="$tmp/no-popup-tmux.log"
no_popup_display_log="$tmp/no-popup-display.log"
: >"$no_popup_display_log"
TMUX_TEST_LOG="$no_popup_log" \
  TMUX_TEST_DISPLAY_LOG="$no_popup_display_log" \
  TMUX_TEST_HAS_POPUP=0 \
  run_helper --start-dir "$tmp/work" --title git lazygit
no_popup_output="$(cat "$no_popup_log")"
assert_contains "popup helper falls back to new window without display-popup" "$no_popup_output" "new-window"
assert_contains "popup helper fallback keeps live TMUX client" "$no_popup_output" "tmux=fake"
assert_contains "popup helper fallback starts in requested directory" "$no_popup_output" "arg=$tmp/work"
assert_contains "popup helper fallback sets title" "$no_popup_output" "arg=git"
assert_contains "popup helper fallback runs selected command" "$no_popup_output" "arg=$tmp/bin/lazygit"
assert_eq "popup helper fallback is quiet on success" "" "$(cat "$no_popup_display_log")"

stale_client_log="$tmp/stale-client-tmux.log"
stale_client_display_log="$tmp/stale-client-display.log"
: >"$stale_client_display_log"
TMUX_TEST_LOG="$stale_client_log" \
  TMUX_TEST_DISPLAY_LOG="$stale_client_display_log" \
  TMUX_TEST_STALE_CLIENT=1 \
  run_helper --start-dir "$tmp/work" --title git lazygit
stale_client_output="$(cat "$stale_client_log")"
assert_contains "stale TMUX popup helper falls back to new window" "$stale_client_output" "new-window"
assert_contains "stale TMUX popup helper clears TMUX for fallback" "$stale_client_output" "tmux=<unset>"
assert_not_contains "stale TMUX popup helper avoids display-popup" "$stale_client_output" "display-popup"
assert_contains "stale TMUX popup helper keeps start directory" "$stale_client_output" "arg=$tmp/work"
assert_eq "stale TMUX popup helper fallback is quiet" "" "$(cat "$stale_client_display_log")"

no_env_stale_bin="$tmp/no-env-stale-bin"
no_env_stale_log="$tmp/no-env-stale-tmux.log"
no_env_stale_display_log="$tmp/no-env-stale-display.log"
mkdir -p "$no_env_stale_bin"
ln -s "$(command -v bash)" "$no_env_stale_bin/bash"
ln -s "$tmp/bin/tmux" "$no_env_stale_bin/tmux"
ln -s "$tmp/bin/lazygit" "$no_env_stale_bin/lazygit"
ln -s "$root/common/.local/bin/tmux-popup-tool" "$no_env_stale_bin/tmux-popup-tool"
: >"$no_env_stale_display_log"
HOME="$tmp/home" \
  TMUX=fake \
  TMUX_TEST_CURRENT_PATH="$tmp/work" \
  TMUX_TEST_DISPLAY_LOG="$no_env_stale_display_log" \
  TMUX_TEST_LOG="$no_env_stale_log" \
  TMUX_TEST_STALE_CLIENT=1 \
  PATH="$no_env_stale_bin" \
  "$no_env_stale_bin/tmux-popup-tool" --start-dir "$tmp/work" --title git lazygit
no_env_stale_output="$(cat "$no_env_stale_log")"
assert_contains "stale TMUX popup helper works without env" "$no_env_stale_output" "new-window"
assert_contains "stale TMUX popup helper clears TMUX without env" "$no_env_stale_output" "tmux=<unset>"
assert_not_contains "stale TMUX popup helper without env avoids display-popup" "$no_env_stale_output" "display-popup"
assert_eq "stale TMUX popup helper without env is quiet" "" "$(cat "$no_env_stale_display_log")"

stale_failure_log="$tmp/stale-failure-tmux.log"
stale_failure_display_log="$tmp/stale-failure-display.log"
stale_failure_env_log="$tmp/stale-failure-env.log"
if TMUX_TEST_LOG="$stale_failure_log" \
  TMUX_TEST_DISPLAY_LOG="$stale_failure_display_log" \
  TMUX_TEST_DISPLAY_ENV_LOG="$stale_failure_env_log" \
  TMUX_TEST_STALE_CLIENT=1 \
  TMUX_TEST_NEW_WINDOW_STATUS=7 \
  run_helper --start-dir "$tmp/work" lazygit 2>"$tmp/stale-failure-stderr.txt"; then
  printf 'not ok - stale TMUX popup helper exits non-zero when fallback window fails\n' >&2
  exit 1
fi
printf 'ok - stale TMUX popup helper exits non-zero when fallback window fails\n'
assert_contains "stale TMUX popup helper reports fallback failure to stderr" \
  "$(cat "$tmp/stale-failure-stderr.txt")" \
  "Unable to open fallback window: lazygit"
assert_contains "stale TMUX popup helper reports fallback failure to tmux" \
  "$(cat "$stale_failure_display_log")" \
  "Unable to open fallback window: lazygit"
assert_eq "stale TMUX popup helper clears TMUX for failure display" \
  "<unset>" \
  "$(cat "$stale_failure_env_log")"

no_popup_failure_log="$tmp/no-popup-failure-tmux.log"
no_popup_failure_display_log="$tmp/no-popup-failure-display.log"
if TMUX_TEST_LOG="$no_popup_failure_log" \
  TMUX_TEST_DISPLAY_LOG="$no_popup_failure_display_log" \
  TMUX_TEST_HAS_POPUP=0 \
  TMUX_TEST_NEW_WINDOW_STATUS=7 \
  run_helper lazygit 2>"$tmp/no-popup-failure-stderr.txt"; then
  printf 'not ok - popup helper exits non-zero when fallback window fails\n' >&2
  exit 1
fi
printf 'ok - popup helper exits non-zero when fallback window fails\n'
assert_contains "popup helper reports fallback failure to stderr" \
  "$(cat "$tmp/no-popup-failure-stderr.txt")" \
  "Unable to open fallback window: lazygit"
assert_contains "popup helper reports fallback failure to tmux" \
  "$(cat "$no_popup_failure_display_log")" \
  "Unable to open fallback window: lazygit"
