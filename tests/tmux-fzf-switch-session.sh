#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
real_tmux="$(command -v tmux)"
tmp="$(mktemp -d)"
if command -v realpath >/dev/null 2>&1; then
  tmp="$(realpath "$tmp")"
else
  tmp="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$tmp")"
fi
socket_name="dotfiles-switch-test-$$"

cleanup() {
  "$real_tmux" -L "$socket_name" kill-server >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5; do
    rm -rf "$tmp" 2>/dev/null && return
    sleep 0.1
  done
  rm -rf "$tmp" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$tmp/bin" "$tmp/alpha" "$tmp/beta" "$tmp/gamma" "$tmp/home"

cat >"$tmp/bin/tmux" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${TMUX_TEST_ATTACH_LOG:-}" && "${1:-}" == "attach-session" ]]; then
  if [[ -n "${TMUX_TEST_ATTACH_ENV_LOG:-}" ]]; then
    printf '%s\n' "${TMUX-<unset>}" >"$TMUX_TEST_ATTACH_ENV_LOG"
  fi
  for arg in "$@"; do
    printf '%s\n' "$arg"
  done >"$TMUX_TEST_ATTACH_LOG"
  exit 0
fi

if [[ -n "${TMUX_TEST_LIST_ENV_LOG:-}" && "${1:-}" == "list-sessions" ]]; then
  printf '%s\n' "${TMUX-<unset>}" >>"$TMUX_TEST_LIST_ENV_LOG"
fi

if [[ -n "${TMUX_TEST_SWITCH_LOG:-}" && "${1:-}" == "switch-client" ]]; then
  for arg in "$@"; do
    printf '%s\n' "$arg"
  done >"$TMUX_TEST_SWITCH_LOG"
  exit 0
fi

if [[ -n "${TMUX_TEST_CHOOSE_TREE_LOG:-}" && "${1:-}" == "choose-tree" ]]; then
  for arg in "$@"; do
    printf '%s\n' "$arg"
  done >"$TMUX_TEST_CHOOSE_TREE_LOG"
  exit "${TMUX_TEST_CHOOSE_TREE_STATUS:-0}"
fi

if [[ -n "${TMUX_TEST_POPUP_LOG:-}" && "${1:-}" == "display-popup" ]]; then
  for arg in "$@"; do
    printf '%s\n' "$arg"
  done >"$TMUX_TEST_POPUP_LOG"
  exit "${TMUX_TEST_POPUP_STATUS:-0}"
fi

if [[ "${1:-}" == "list-commands" && -n "${TMUX_TEST_NOISY_LIST_COMMANDS:-}" ]]; then
  printf 'display-popup\n'
  for i in {1..4000}; do
    printf 'fake-command-%04d\n' "$i"
  done
  exit 0
fi

if [[ -n "${TMUX_TEST_DISPLAY_LOG:-}" && "${1:-}" == "display-message" && "${2:-}" != "-p" ]]; then
  shift
  printf '%s\n' "$*" >>"$TMUX_TEST_DISPLAY_LOG"
  exit 0
fi

if [[ -n "${TMUX_TEST_STALE_DISPLAY:-}" && "${1:-}" == "display-message" && "${2:-}" == "-p" ]]; then
  exit 1
fi

exec "$TMUX_TEST_REAL_TMUX" -L "$TMUX_TEST_SOCKET" "$@"
SH
chmod +x "$tmp/bin/tmux"

cat >"$tmp/bin/fzf" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
  printf '%s\n' "${TMUX_TEST_FZF_HELP:---read0 --header-lines --highlight-line --track --tabstop --tmux SIZE_THRESHOLD}"
  exit 0
fi

: "${TMUX_TEST_FZF_ARGS:?}"
: "${TMUX_TEST_FZF_STDIN:?}"
: "${TMUX_TEST_FZF_OUTPUT:?}"

for arg in "$@"; do
  printf '%s\n' "$arg"
done >"$TMUX_TEST_FZF_ARGS"
cat >"$TMUX_TEST_FZF_STDIN"
printf '%s\n' "$TMUX_TEST_FZF_OUTPUT"
SH
chmod +x "$tmp/bin/fzf"

tmux_test() {
  HOME="$tmp/home" \
    PATH="$tmp/bin:$root/common/.local/bin:$PATH" \
    TMUX_TEST_REAL_TMUX="$real_tmux" \
    TMUX_TEST_SOCKET="$socket_name" \
    "$@"
}

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

assert_line_count() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$actual" != "$expected" ]]; then
    printf 'not ok - %s\n' "$name" >&2
    printf 'expected lines: %s\nactual lines: %s\n' "$expected" "$actual" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

picker="$root/common/.local/bin/tmux-fzf-switch-session"

no_tmux_bin="$tmp/no-tmux-bin"
mkdir -p "$no_tmux_bin"
ln -s "$(command -v bash)" "$no_tmux_bin/bash"
if HOME="$tmp/home" PATH="$no_tmux_bin" "$picker" >"$tmp/no-tmux.out" 2>"$tmp/no-tmux.err"; then
  printf 'not ok - session picker exits non-zero when tmux is missing\n' >&2
  exit 1
fi
assert_contains \
  "session picker reports missing tmux" \
  "$(cat "$tmp/no-tmux.err")" \
  "tmux is required for tmux session switching"

tmux_test tmux -f "$root/common/.tmux.conf" new-session -d -s alpha -n editor -c "$tmp/alpha"
tmux_test tmux new-window -d -t =alpha: -n shell -c "$tmp/alpha"
tmux_test tmux new-session -d -s beta -n logs -c "$tmp/beta"
tmux_test tmux new-session -d -s gamma -n scratch -c "$tmp/gamma"

alpha_id="$(tmux_test tmux list-sessions -F $'#{session_id}\t#{session_name}' | awk -F '\t' '$2 == "alpha" { print $1; exit }')"
beta_id="$(tmux_test tmux list-sessions -F $'#{session_id}\t#{session_name}' | awk -F '\t' '$2 == "beta" { print $1; exit }')"

list_output="$(tmux_test "$picker" --list)"
assert_line_count "list emits one row per session" "3" "$(printf '%s\n' "$list_output" | wc -l | tr -d ' ')"
assert_contains "list includes alpha session" "$list_output" $'alpha'
assert_contains "list includes beta session" "$list_output" $'beta'
assert_contains "list includes gamma session" "$list_output" $'gamma'
assert_contains "list reports alpha window count" "$list_output" $'2 windows'

no_list_filter_bin="$tmp/no-list-filter-bin"
mkdir -p "$no_list_filter_bin"
ln -s "$(command -v bash)" "$no_list_filter_bin/bash"
ln -s "$tmp/bin/tmux" "$no_list_filter_bin/tmux"
no_filter_list_output="$(
  HOME="$tmp/home" \
    PATH="$no_list_filter_bin" \
    TMUX_TEST_REAL_TMUX="$real_tmux" \
    TMUX_TEST_SOCKET="$socket_name" \
    "$picker" --list
)"
assert_line_count "list emits rows without awk sort cut or date" "3" "$(printf '%s\n' "$no_filter_list_output" | wc -l | tr -d ' ')"
assert_contains "list without awk sort cut or date includes alpha" "$no_filter_list_output" $'alpha'
assert_contains "list without awk sort cut or date includes beta" "$no_filter_list_output" $'beta'
assert_contains "list without awk sort cut or date reports alpha window count" "$no_filter_list_output" $'2 windows'

header_output="$(tmux_test "$picker" --list-with-header)"
assert_contains "header includes session columns" "$header_output" $'ID\t \tSESSION'
assert_line_count "header list includes header plus sessions" "4" "$(printf '%s\n' "$header_output" | wc -l | tr -d ' ')"

list0_output="$(tmux_test "$picker" --list0 | python3 -c 'import sys; data=sys.stdin.buffer.read(); print(data.count(b"\0"))')"
if [[ "$list0_output" != "3" ]]; then
  printf 'not ok - list0 emits nul per row\n' >&2
  printf 'expected: 3\nactual: %s\n' "$list0_output" >&2
  exit 1
fi
printf 'ok - list0 emits nul per row\n'

list0_header_output="$(tmux_test "$picker" --list0-with-header | python3 -c 'import sys; data=sys.stdin.buffer.read(); print(data.count(b"\0"))')"
assert_eq "list0 with header emits header plus sessions" "4" "$list0_header_output"

preview_output="$(tmux_test "$picker" --preview "$alpha_id")"
assert_contains "preview includes alpha summary" "$preview_output" "alpha - 2 windows"
assert_contains "preview includes windows section" "$preview_output" "Windows"
assert_contains "preview includes editor window" "$preview_output" "1: editor"
assert_contains "preview includes panes section" "$preview_output" "Panes"
assert_contains "preview includes alpha cwd" "$preview_output" "$tmp/alpha"
assert_contains "preview includes active pane output section" "$preview_output" "Active Pane Output"

tmux_test tmux send-keys -t =alpha:editor "printf '%s\\n' preview_keep_01 '' preview_keep_02" Enter
for _ in {1..50}; do
  if tmux_test tmux capture-pane -p -t =alpha:editor | grep -qx 'preview_keep_02'; then
    break
  fi
  sleep 0.1
done
no_preview_filter_bin="$tmp/no-preview-filter-bin"
mkdir -p "$no_preview_filter_bin"
for tool in bash env; do
  ln -s "$(command -v "$tool")" "$no_preview_filter_bin/$tool"
done
ln -s "$tmp/bin/tmux" "$no_preview_filter_bin/tmux"
preview_no_filter="$(
  HOME="$tmp/home" \
    PATH="$no_preview_filter_bin" \
    TMUX_TEST_REAL_TMUX="$real_tmux" \
    TMUX_TEST_SOCKET="$socket_name" \
    "$picker" --preview "$alpha_id"
)"
assert_contains \
  "preview keeps pane output without sed or tail" \
  "$preview_no_filter" \
  "  preview_keep_02"
assert_not_contains \
  "preview without sed or tail avoids empty-output fallback" \
  "$preview_no_filter" \
  "  (no visible output)"

missing_id="\$999"
missing_preview="$(tmux_test "$picker" --preview "$missing_id")"
assert_contains "missing preview is friendly" "$missing_preview" "Session no longer exists: $missing_id"

resolved_id_only="$(printf '%s\n' "$alpha_id" | tmux_test "$picker" --resolve-selected-id)"
assert_eq "resolver accepts id-only fzf output" "$alpha_id" "$resolved_id_only"

display_row="$(printf ' \t%s   \t%s\n' beta '1 window')"
resolved_display_row="$(printf '%s' "$display_row" | tmux_test "$picker" --resolve-selected-id)"
assert_eq "resolver accepts transformed display row" "$beta_id" "$resolved_display_row"

beta_row="$(printf '%s\n' "$list_output" | awk -F '\t' -v id="$beta_id" '$1 == id { print; exit }')"
fzf_args="$tmp/fzf.args"
fzf_stdin="$tmp/fzf.stdin"
attach_log="$tmp/attach.log"

TMUX_TEST_FZF_ARGS="$fzf_args" \
  TMUX_TEST_FZF_STDIN="$fzf_stdin" \
  TMUX_TEST_FZF_OUTPUT="$beta_row" \
  TMUX_TEST_ATTACH_LOG="$attach_log" \
  tmux_test "$picker"

assert_eq "interactive picker attaches selected session outside tmux" \
  $'attach-session\n-t\n'"$beta_id" \
  "$(cat "$attach_log")"
fzf_args_output="$(cat "$fzf_args")"
assert_contains "interactive picker enables read0" "$fzf_args_output" "--read0"
assert_contains "interactive picker enables header lines" "$fzf_args_output" "--header-lines=1"
assert_contains "interactive picker wires reload to header list" "$fzf_args_output" "--list0-with-header"
assert_eq "interactive picker passes nul-delimited header and sessions" \
  "4" \
  "$(python3 -c 'import sys; print(sys.stdin.buffer.read().count(b"\0"))' <"$fzf_stdin")"
assert_contains "interactive picker passes header to fzf" \
  "$(tr '\0' '\n' <"$fzf_stdin")" \
  $'ID\t \tSESSION'

no_tr_bin="$tmp/no-tr-bin"
no_tr_fzf_args="$tmp/no-tr-fzf.args"
no_tr_fzf_stdin="$tmp/no-tr-fzf.stdin"
no_tr_attach_log="$tmp/no-tr-attach.log"
mkdir -p "$no_tr_bin"
for tool in bash awk cat cut date env sort; do
  ln -s "$(command -v "$tool")" "$no_tr_bin/$tool"
done
ln -s "$tmp/bin/fzf" "$no_tr_bin/fzf"
ln -s "$tmp/bin/tmux" "$no_tr_bin/tmux"
TMUX_TEST_FZF_ARGS="$no_tr_fzf_args" \
  TMUX_TEST_FZF_STDIN="$no_tr_fzf_stdin" \
  TMUX_TEST_FZF_OUTPUT="$beta_row" \
  TMUX_TEST_ATTACH_LOG="$no_tr_attach_log" \
  HOME="$tmp/home" \
  PATH="$no_tr_bin" \
  TMUX_TEST_REAL_TMUX="$real_tmux" \
  TMUX_TEST_SOCKET="$socket_name" \
  "$picker"
assert_eq "interactive picker attaches selected session without wc or tr" \
  $'attach-session\n-t\n'"$beta_id" \
  "$(cat "$no_tr_attach_log")"
assert_contains "interactive picker without wc or tr still enables read0" "$(cat "$no_tr_fzf_args")" "--read0"
assert_eq "interactive picker without wc or tr passes nul input" \
  "4" \
  "$(python3 -c 'import sys; print(sys.stdin.buffer.read().count(b"\0"))' <"$no_tr_fzf_stdin")"

switch_log="$tmp/switch.log"
rm -f "$fzf_args" "$fzf_stdin"
TMUX="$tmp/fake-client,1,0" \
  TMUX_TEST_FZF_ARGS="$fzf_args" \
  TMUX_TEST_FZF_STDIN="$fzf_stdin" \
  TMUX_TEST_FZF_OUTPUT="$beta_row" \
  TMUX_TEST_SWITCH_LOG="$switch_log" \
  tmux_test "$picker"

assert_eq "interactive picker switches selected session inside tmux" \
  $'switch-client\n-t\n'"$beta_id" \
  "$(cat "$switch_log")"
fzf_args_output="$(cat "$fzf_args")"
assert_contains "interactive picker uses fzf tmux popup when inside tmux" "$fzf_args_output" "--tmux"
assert_contains "interactive picker sizes fzf tmux popup" "$fzf_args_output" "center,90%,70%,border-native"

stale_tmux_attach_log="$tmp/stale-tmux-attach.log"
stale_tmux_attach_env_log="$tmp/stale-tmux-attach.env"
stale_tmux_list_env_log="$tmp/stale-tmux-list.env"
rm -f "$fzf_args" "$fzf_stdin"
TMUX="$tmp/stale-client,1,0" \
  TMUX_TEST_STALE_DISPLAY=1 \
  TMUX_TEST_FZF_ARGS="$fzf_args" \
  TMUX_TEST_FZF_STDIN="$fzf_stdin" \
  TMUX_TEST_FZF_OUTPUT="$beta_row" \
  TMUX_TEST_ATTACH_LOG="$stale_tmux_attach_log" \
  TMUX_TEST_ATTACH_ENV_LOG="$stale_tmux_attach_env_log" \
  TMUX_TEST_LIST_ENV_LOG="$stale_tmux_list_env_log" \
  tmux_test "$picker"

assert_eq "stale TMUX picker attaches selected session" \
  $'attach-session\n-t\n'"$beta_id" \
  "$(cat "$stale_tmux_attach_log")"
assert_eq "stale TMUX picker unsets TMUX before attach" "<unset>" "$(cat "$stale_tmux_attach_env_log")"
assert_eq "stale TMUX picker unsets TMUX before listing sessions" "<unset>" "$(sort -u "$stale_tmux_list_env_log")"
assert_not_contains "stale TMUX picker avoids fzf tmux popup" "$(cat "$fzf_args")" "--tmux"

no_env_switch_bin="$tmp/no-env-switch-bin"
no_env_stale_tmux_attach_log="$tmp/no-env-stale-tmux-attach.log"
no_env_stale_tmux_attach_env_log="$tmp/no-env-stale-tmux-attach.env"
no_env_stale_tmux_list_env_log="$tmp/no-env-stale-tmux-list.env"
mkdir -p "$no_env_switch_bin"
ln -s "$(command -v bash)" "$no_env_switch_bin/bash"
ln -s "$(command -v cat)" "$no_env_switch_bin/cat"
ln -s "$tmp/bin/tmux" "$no_env_switch_bin/tmux"
ln -s "$tmp/bin/fzf" "$no_env_switch_bin/fzf"
rm -f "$fzf_args" "$fzf_stdin"
TMUX="$tmp/stale-client,1,0" \
  HOME="$tmp/home" \
  PATH="$no_env_switch_bin" \
  TMUX_TEST_REAL_TMUX="$real_tmux" \
  TMUX_TEST_SOCKET="$socket_name" \
  TMUX_TEST_STALE_DISPLAY=1 \
  TMUX_TEST_FZF_ARGS="$fzf_args" \
  TMUX_TEST_FZF_STDIN="$fzf_stdin" \
  TMUX_TEST_FZF_OUTPUT="$beta_row" \
  TMUX_TEST_ATTACH_LOG="$no_env_stale_tmux_attach_log" \
  TMUX_TEST_ATTACH_ENV_LOG="$no_env_stale_tmux_attach_env_log" \
  TMUX_TEST_LIST_ENV_LOG="$no_env_stale_tmux_list_env_log" \
  "$picker"

assert_eq "stale TMUX picker attaches selected session without env" \
  $'attach-session\n-t\n'"$beta_id" \
  "$(cat "$no_env_stale_tmux_attach_log")"
assert_eq "stale TMUX picker unsets TMUX before attach without env" \
  "<unset>" \
  "$(cat "$no_env_stale_tmux_attach_env_log")"
assert_eq "stale TMUX picker unsets TMUX before listing sessions without env" \
  "<unset>" \
  "$(sort -u "$no_env_stale_tmux_list_env_log")"
assert_not_contains "stale TMUX picker without env avoids fzf tmux popup" "$(cat "$fzf_args")" "--tmux"

old_fzf_popup_log="$tmp/old-fzf-popup.log"
old_fzf_display_log="$tmp/old-fzf-popup.display"
: >"$old_fzf_display_log"
TMUX="$tmp/fake-client,1,0" \
  TMUX_TEST_FZF_HELP='--read0 --header-lines --highlight-line --track --tabstop SIZE_THRESHOLD' \
  TMUX_TEST_POPUP_LOG="$old_fzf_popup_log" \
  TMUX_TEST_NOISY_LIST_COMMANDS=1 \
  TMUX_TEST_DISPLAY_LOG="$old_fzf_display_log" \
  tmux_test "$picker"
old_fzf_popup_output="$(cat "$old_fzf_popup_log")"
assert_contains "old fzf falls back to tmux display-popup" "$old_fzf_popup_output" "display-popup"
assert_contains "old fzf popup uses session title" "$old_fzf_popup_output" " sessions "
assert_contains "old fzf popup launches helper in popup mode" "$old_fzf_popup_output" "TMUX_FZF_SWITCH_POPUP=1"
assert_not_contains "old fzf popup avoids env launcher" "$old_fzf_popup_output" "env TMUX_FZF_SWITCH_POPUP=1"
assert_contains "old fzf popup relaunches current picker" "$old_fzf_popup_output" "$picker"
assert_contains "session popup detection tolerates noisy list-commands output" "$old_fzf_popup_output" "display-popup"
assert_eq "successful session popup fallback does not show errors" "" "$(cat "$old_fzf_display_log")"

bare_switch_dir="$tmp/bare-switch"
bare_switch_shadow_dir="$tmp/bare-switch-shadow"
bare_switch_popup_log="$tmp/bare-switch-popup.log"
mkdir -p "$bare_switch_dir" "$bare_switch_shadow_dir"
ln -s "$picker" "$bare_switch_dir/tmux-fzf-switch-session"
cat >"$bare_switch_shadow_dir/tmux-fzf-switch-session" <<'SH'
#!/usr/bin/env bash
printf 'PATH shadow tmux-fzf-switch-session should not run\n' >&2
exit 94
SH
chmod +x "$bare_switch_shadow_dir/tmux-fzf-switch-session"

TMUX="$tmp/fake-client,1,0" \
  TMUX_TEST_FZF_HELP='--read0 --header-lines --highlight-line --track --tabstop SIZE_THRESHOLD' \
  TMUX_TEST_POPUP_LOG="$bare_switch_popup_log" \
  TMUX_TEST_NOISY_LIST_COMMANDS=1 \
  HOME="$tmp/home" \
  PATH="$bare_switch_shadow_dir:$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  TMUX_TEST_REAL_TMUX="$real_tmux" \
  TMUX_TEST_SOCKET="$socket_name" \
  bash -c 'cd "$1" && bash tmux-fzf-switch-session' _ "$bare_switch_dir"
bare_switch_popup_output="$(cat "$bare_switch_popup_log")"
assert_contains "bare session picker popup relaunches current helper" "$bare_switch_popup_output" "$bare_switch_dir/tmux-fzf-switch-session"
assert_not_contains "bare session picker popup avoids PATH shadow" "$bare_switch_popup_output" "$bare_switch_shadow_dir/tmux-fzf-switch-session"

old_fzf_popup_fail_log="$tmp/old-fzf-popup-fail.log"
old_fzf_popup_fail_display_log="$tmp/old-fzf-popup-fail.display"
if TMUX="$tmp/fake-client,1,0" \
  TMUX_TEST_FZF_HELP='--read0 --header-lines --highlight-line --track --tabstop SIZE_THRESHOLD' \
  TMUX_TEST_POPUP_LOG="$old_fzf_popup_fail_log" \
  TMUX_TEST_POPUP_STATUS=78 \
  TMUX_TEST_NOISY_LIST_COMMANDS=1 \
  TMUX_TEST_DISPLAY_LOG="$old_fzf_popup_fail_display_log" \
  tmux_test "$picker"; then
  printf 'not ok - session popup failure exits non-zero\n' >&2
  exit 1
fi
assert_contains "session popup failure attempted display-popup" "$(cat "$old_fzf_popup_fail_log")" "display-popup"
assert_contains "session popup failure is visible" \
  "$(cat "$old_fzf_popup_fail_display_log")" \
  "Unable to open tmux session popup"

mkdir -p "$tmp/no-fzf-bin"
ln -s "$(command -v bash)" "$tmp/no-fzf-bin/bash"
ln -s "$tmp/bin/tmux" "$tmp/no-fzf-bin/tmux"

choose_tree_log="$tmp/choose-tree.log"
choose_tree_display_log="$tmp/choose-tree.display"
TMUX="$tmp/fake-client,1,0" \
  TMUX_TEST_CHOOSE_TREE_LOG="$choose_tree_log" \
  TMUX_TEST_DISPLAY_LOG="$choose_tree_display_log" \
  HOME="$tmp/home" \
  PATH="$tmp/no-fzf-bin:$root/common/.local/bin" \
  TMUX_TEST_REAL_TMUX="$real_tmux" \
  TMUX_TEST_SOCKET="$socket_name" \
  "$picker"

assert_eq "missing fzf falls back to choose-tree inside tmux" \
  $'choose-tree\n-sZ\n-O\ntime' \
  "$(cat "$choose_tree_log")"
assert_contains "missing fzf fallback is announced" \
  "$(cat "$choose_tree_display_log")" \
  "fzf unavailable; opening tmux choose-tree"

choose_tree_fail_log="$tmp/choose-tree-fail.log"
choose_tree_fail_display_log="$tmp/choose-tree-fail.display"
if TMUX="$tmp/fake-client,1,0" \
  TMUX_TEST_CHOOSE_TREE_LOG="$choose_tree_fail_log" \
  TMUX_TEST_CHOOSE_TREE_STATUS=77 \
  TMUX_TEST_DISPLAY_LOG="$choose_tree_fail_display_log" \
  HOME="$tmp/home" \
  PATH="$tmp/no-fzf-bin:$root/common/.local/bin" \
  TMUX_TEST_REAL_TMUX="$real_tmux" \
  TMUX_TEST_SOCKET="$socket_name" \
  "$picker"; then
  printf 'not ok - choose-tree failure exits non-zero\n' >&2
  exit 1
fi
assert_eq "choose-tree failure records attempted fallback" \
  $'choose-tree\n-sZ\n-O\ntime' \
  "$(cat "$choose_tree_fail_log")"
assert_contains "choose-tree failure is visible" \
  "$(cat "$choose_tree_fail_display_log")" \
  "Unable to open tmux choose-tree"

tmux_test tmux kill-session -t "$beta_id"
tmux_test tmux kill-session -t =gamma
no_count_bin="$tmp/no-count-bin"
no_count_attach_log="$tmp/no-count-attach.log"
mkdir -p "$no_count_bin"
for tool in bash awk sort cut date env; do
  ln -s "$(command -v "$tool")" "$no_count_bin/$tool"
done
ln -s "$tmp/bin/tmux" "$no_count_bin/tmux"
TMUX_TEST_ATTACH_LOG="$no_count_attach_log" \
  HOME="$tmp/home" \
  PATH="$no_count_bin" \
  TMUX_TEST_REAL_TMUX="$real_tmux" \
  TMUX_TEST_SOCKET="$socket_name" \
  "$picker"
assert_eq "single outside session attaches without wc or tr" \
  $'attach-session\n-t\n'"$alpha_id" \
  "$(cat "$no_count_attach_log")"

single_attach_log="$tmp/single-attach.log"
TMUX_TEST_ATTACH_LOG="$single_attach_log" tmux_test "$picker"
assert_eq "single outside session attaches without fzf" \
  $'attach-session\n-t\n'"$alpha_id" \
  "$(cat "$single_attach_log")"
