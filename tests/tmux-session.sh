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
socket_name="dotfiles-test-$$"

cleanup() {
  "$real_tmux" -L "$socket_name" kill-server >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5; do
    rm -rf "$tmp" 2>/dev/null && return
    sleep 0.1
  done
  rm -rf "$tmp" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$tmp/bin" "$tmp/helper" "$tmp/work" "$tmp/home/tilde start" "$tmp/explicit start" "$tmp/relative start"

cat >"$tmp/bin/tmux" <<'SH'
#!/usr/bin/env bash
exec "$TMUX_TEST_REAL_TMUX" -L "$TMUX_TEST_SOCKET" "$@"
SH
chmod +x "$tmp/bin/tmux"

tmux_clean_env=(
  -u TMUX
  -u TMUX_PANE
  -u TMUX_SESSION_AGENT_CLI
  -u TMUX_SESSION_AGENT_COMMAND
  -u TMUX_SESSION_AGENT_RESUME_COMMAND
  -u TMUX_SESSION_AGENT_RESUME_WINDOW_NAME
  -u TMUX_SESSION_AGENT_WINDOW_NAME
  -u TMUX_SESSION_START_DIR
  -u TMUX_SESSION_TERMINAL_WINDOW_NAME
)

tmux_test() {
  HOME="$tmp/home" \
    PATH="$tmp/bin:$root/common/.local/bin:$PATH" \
    TMUX_TEST_REAL_TMUX="$real_tmux" \
    TMUX_TEST_SOCKET="$socket_name" \
    env "${tmux_clean_env[@]}" "$@"
}

tmux_direct_test() {
  HOME="$tmp/home" \
    PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    TMUX_TEST_REAL_TMUX="$real_tmux" \
    TMUX_TEST_SOCKET="$socket_name" \
    env "${tmux_clean_env[@]}" "$@"
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

wait_for_log_lines() {
  local name="$1"
  local path="$2"
  local expected_count="$3"
  local actual_count=""

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if [[ -f "$path" ]]; then
      actual_count="$(wc -l <"$path" | tr -d ' ')"
      if [[ "$actual_count" -ge "$expected_count" ]]; then
        printf 'ok - %s\n' "$name"
        return 0
      fi
    fi
    sleep 0.2
  done

  printf 'not ok - %s\n' "$name" >&2
  printf 'expected at least %s lines in %s, got %s\n' "$expected_count" "$path" "${actual_count:-0}" >&2
  [[ -f "$path" ]] && cat "$path" >&2
  return 1
}

wait_for_file() {
  local name="$1"
  local path="$2"

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if [[ -e "$path" ]]; then
      printf 'ok - %s\n' "$name"
      return 0
    fi
    sleep 0.2
  done

  printf 'not ok - %s\n' "$name" >&2
  printf 'expected file: %s\n' "$path" >&2
  return 1
}

make_fake_agent_cli() {
  local name="$1"

  make_fake_agent_cli_at "$tmp/bin/$name"
}

make_fake_agent_cli_at() {
  local path="$1"

cat >"$path" <<'SH'
#!/usr/bin/env bash
line="${0##*/}"
for arg in "$@"; do
  line="$line $arg"
done
printf '%s\n' "$line" >>"${TMUX_SESSION_AGENT_LOG:?}"
SH
  chmod +x "$path"
}

active_window() {
  local session_name="$1"

  tmux_test tmux list-windows -t "=$session_name" -F '#{?window_active,#{session_name}:#{window_index},}' |
    sed -n '/./p'
}

session="dotfiles-session-test"
tmux_session_source="$(<"$root/common/.local/bin/tmux-session")"
dollar='$'
assert_not_contains "tmux-session does not probe root-local helper fallback" \
  "$tmux_session_source" \
  "${dollar}{HOME:-}/.local/bin/"
assert_not_contains "tmux-session does not probe root dotfiles helper fallback" \
  "$tmux_session_source" \
  "${dollar}{HOME:-}/dotfiles/common/.local/bin/"
tmux_test tmux -f "$root/common/.tmux.conf" new-session -d -s dotfiles-test-bootstrap -n bootstrap -c "$tmp"

ln -s "$root/common/.local/bin/tmux-session" "$tmp/helper/tmux-session"
cat >"$tmp/helper/tmux-session-default-layout-local" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

: "${SESSION_NAME:?SESSION_NAME must be set}"

start_dir="${TMUX_SESSION_START_DIR:-$PWD}"
tmux new-session -d -s "$SESSION_NAME" -n local -c "$start_dir"
SH
chmod +x "$tmp/helper/tmux-session-default-layout-local"

local_session="${session}-local"
tmux_direct_test env \
  TMUX_SESSION_START_DIR="$tmp/work" \
  "$tmp/helper/tmux-session" "$local_session" --no-attach

local_windows="$(tmux_test tmux list-windows -t "=$local_session" -F '#{window_index}:#{window_name}:#{pane_current_path}')"
assert_eq \
  "direct path uses adjacent local default layout" \
  "1:local:$tmp/work" \
  "$local_windows"

path_shadow_bin="$tmp/path-shadow-bin"
path_shadow_session="${session}-path-shadow"
mkdir -p "$path_shadow_bin"

cat >"$tmp/helper/tmux-session-name" <<SH
#!/usr/bin/env bash
printf '%s\n' '$path_shadow_session'
SH
chmod +x "$tmp/helper/tmux-session-name"

cat >"$path_shadow_bin/tmux-session-name" <<'SH'
#!/usr/bin/env bash
printf '%s\n' stale-path-session
SH
chmod +x "$path_shadow_bin/tmux-session-name"

cat >"$path_shadow_bin/tmux-session-default-layout-local" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

: "${SESSION_NAME:?SESSION_NAME must be set}"

start_dir="${TMUX_SESSION_START_DIR:-$PWD}"
tmux new-session -d -s "$SESSION_NAME" -n stale-path -c "$start_dir"
SH
chmod +x "$path_shadow_bin/tmux-session-default-layout-local"

HOME="$tmp/home" \
  PATH="$tmp/bin:$path_shadow_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  TMUX_TEST_REAL_TMUX="$real_tmux" \
  TMUX_TEST_SOCKET="$socket_name" \
  "$tmp/helper/tmux-session" --start-dir "$tmp/work" --no-attach

path_shadow_windows="$(tmux_test tmux list-windows -t "=$path_shadow_session" -F '#{window_index}:#{window_name}:#{pane_current_path}')"
assert_eq \
  "direct path prefers adjacent helpers over PATH shadows" \
  "1:local:$tmp/work" \
  "$path_shadow_windows"

no_dirname_bin="$tmp/no-dirname-session-bin"
no_dirname_session="${session}-no-dirname"
mkdir -p "$no_dirname_bin"
for tool in bash env; do
  ln -s "$(command -v "$tool")" "$no_dirname_bin/$tool"
done
ln -s "$tmp/bin/tmux" "$no_dirname_bin/tmux"
HOME="$tmp/home" \
  PATH="$no_dirname_bin" \
  TMUX_TEST_REAL_TMUX="$real_tmux" \
  TMUX_TEST_SOCKET="$socket_name" \
  "$tmp/helper/tmux-session" "$no_dirname_session" --start-dir "$tmp/work" --no-attach

no_dirname_windows="$(tmux_test tmux list-windows -t "=$no_dirname_session" -F '#{window_index}:#{window_name}:#{pane_current_path}')"
assert_eq \
  "direct path resolves adjacent helper without dirname" \
  "1:local:$tmp/work" \
  "$no_dirname_windows"

isolated_helper_dir="$tmp/isolated-helper"
isolated_home="$tmp/isolated-home"
isolated_path_shadow="$tmp/isolated-path-shadow"
isolated_start="$tmp/isolated start"
isolated_session="${session}-isolated-fallback"
mkdir -p "$isolated_helper_dir" "$isolated_home/dotfiles/common/.local/bin" "$isolated_path_shadow" "$isolated_start"
ln -s "$root/common/.local/bin/tmux-session" "$isolated_helper_dir/tmux-session"

cat >"$isolated_home/dotfiles/common/.local/bin/tmux-session-name" <<SH
#!/usr/bin/env bash
printf '%s\n' '$isolated_session'
SH
chmod +x "$isolated_home/dotfiles/common/.local/bin/tmux-session-name"

cat >"$isolated_path_shadow/tmux-session-name" <<'SH'
#!/usr/bin/env bash
printf '%s\n' stale-isolated-path-session
SH
chmod +x "$isolated_path_shadow/tmux-session-name"

cat >"$isolated_home/dotfiles/common/.local/bin/tmux-session-default-layout" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

: "${SESSION_NAME:?SESSION_NAME must be set}"

start_dir="${TMUX_SESSION_START_DIR:-$PWD}"
tmux new-session -d -s "$SESSION_NAME" -n fallback -c "$start_dir"
SH
chmod +x "$isolated_home/dotfiles/common/.local/bin/tmux-session-default-layout"

cat >"$isolated_path_shadow/tmux-session-default-layout-local" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

: "${SESSION_NAME:?SESSION_NAME must be set}"

start_dir="${TMUX_SESSION_START_DIR:-$PWD}"
tmux new-session -d -s "$SESSION_NAME" -n stale-path -c "$start_dir"
SH
chmod +x "$isolated_path_shadow/tmux-session-default-layout-local"

HOME="$isolated_home" \
  PATH="$isolated_path_shadow:$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  TMUX_TEST_REAL_TMUX="$real_tmux" \
  TMUX_TEST_SOCKET="$socket_name" \
  "$isolated_helper_dir/tmux-session" --start-dir "$isolated_start" --no-attach

isolated_windows="$(tmux_test tmux list-windows -t "=$isolated_session" -F '#{window_index}:#{window_name}:#{pane_current_path}')"
assert_eq \
  "tmux-session resolves name and layout via home dotfiles fallback before PATH shadows" \
  "1:fallback:$isolated_start" \
  "$isolated_windows"

no_home_helper_dir="$tmp/no-home-helper"
no_home_path_bin="$tmp/no-home-path"
no_home_start="$tmp/no home start"
no_home_session="${session}-no-home-fallback"
mkdir -p "$no_home_helper_dir" "$no_home_path_bin" "$no_home_start"
ln -s "$root/common/.local/bin/tmux-session" "$no_home_helper_dir/tmux-session"
ln -s "$tmp/bin/tmux" "$no_home_path_bin/tmux"

cat >"$no_home_path_bin/tmux-session-name" <<SH
#!/usr/bin/env bash
printf '%s\n' '$no_home_session'
SH
chmod +x "$no_home_path_bin/tmux-session-name"

cat >"$no_home_path_bin/tmux-session-default-layout" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

: "${SESSION_NAME:?SESSION_NAME must be set}"

start_dir="${TMUX_SESSION_START_DIR:-$PWD}"
tmux new-session -d -s "$SESSION_NAME" -n path -c "$start_dir"
SH
chmod +x "$no_home_path_bin/tmux-session-default-layout"

env -u HOME \
  PATH="$no_home_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  TMUX_TEST_REAL_TMUX="$real_tmux" \
  TMUX_TEST_SOCKET="$socket_name" \
  "$no_home_helper_dir/tmux-session" --start-dir "$no_home_start" --no-attach

no_home_windows="$(tmux_test tmux list-windows -t "=$no_home_session" -F '#{window_index}:#{window_name}:#{pane_current_path}')"
assert_eq \
  "tmux-session resolves name and layout via PATH when HOME is unset" \
  "1:path:$no_home_start" \
  "$no_home_windows"

missing_helper_dir="$tmp/missing-helper"
missing_helper_home="$tmp/missing-helper-home"
mkdir -p "$missing_helper_dir" "$missing_helper_home"
ln -s "$root/common/.local/bin/tmux-session" "$missing_helper_dir/tmux-session"

missing_name_helper_log="$tmp/missing-session-name-helper.out"
if HOME="$missing_helper_home" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  TMUX_TEST_REAL_TMUX="$real_tmux" \
  TMUX_TEST_SOCKET="$socket_name" \
  "$missing_helper_dir/tmux-session" --start-dir "$tmp/work" --no-attach >"$missing_name_helper_log" 2>&1; then
  printf 'not ok - missing session name helper fails\n' >&2
  exit 1
fi
assert_eq \
  "missing session name helper lists searched locations" \
  "Error: tmux-session-name not found in adjacent, home local, home dotfiles, or PATH helper locations." \
  "$(cat "$missing_name_helper_log")"

missing_layout_helper_log="$tmp/missing-session-layout-helper.out"
if HOME="$missing_helper_home" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  TMUX_TEST_REAL_TMUX="$real_tmux" \
  TMUX_TEST_SOCKET="$socket_name" \
  "$missing_helper_dir/tmux-session" "${session}-missing-layout" --start-dir "$tmp/work" --no-attach >"$missing_layout_helper_log" 2>&1; then
  printf 'not ok - missing default layout helper fails\n' >&2
  exit 1
fi
assert_eq \
  "missing default layout helper lists searched locations" \
  "Error: tmux-session-default-layout not found in adjacent, home local, home dotfiles, or PATH helper locations." \
  "$(cat "$missing_layout_helper_log")"

missing_tmux_bin="$tmp/missing-tmux-bin"
missing_tmux_helper_dir="$tmp/missing-tmux-helper"
missing_tmux_log="$tmp/missing-tmux.out"
mkdir -p "$missing_tmux_bin" "$missing_tmux_helper_dir"
ln -s "$(command -v bash)" "$missing_tmux_bin/bash"
ln -s "$(command -v dirname)" "$missing_tmux_bin/dirname"
ln -s "$root/common/.local/bin/tmux-session" "$missing_tmux_helper_dir/tmux-session"
if HOME="$tmp/home" \
  PATH="$missing_tmux_bin" \
  "$missing_tmux_helper_dir/tmux-session" "${session}-missing-tmux" --start-dir "$tmp/work" --no-attach >"$missing_tmux_log" 2>&1; then
  printf 'not ok - missing tmux fails\n' >&2
  exit 1
fi
assert_eq \
  "tmux-session reports missing tmux" \
  "Error: tmux is not installed or not on PATH" \
  "$(cat "$missing_tmux_log")"

missing_layout_tmux_bin="$tmp/missing-layout-tmux-bin"
missing_layout_tmux_log="$tmp/missing-layout-tmux.out"
mkdir -p "$missing_layout_tmux_bin"
ln -s "$(command -v bash)" "$missing_layout_tmux_bin/bash"
if SESSION_NAME="${session}-missing-layout-tmux" \
  HOME="$tmp/home" \
  PATH="$missing_layout_tmux_bin" \
  TMUX_SESSION_START_DIR="$tmp/work" \
  "$root/common/.local/bin/tmux-session-default-layout" >"$missing_layout_tmux_log" 2>&1; then
  printf 'not ok - missing tmux in default layout fails\n' >&2
  exit 1
fi
assert_eq \
  "default layout reports missing tmux" \
  "Error: tmux is not installed or not on PATH" \
  "$(cat "$missing_layout_tmux_log")"

layout_cleanup_bin="$tmp/layout-cleanup-bin"
layout_cleanup_log="$tmp/layout-cleanup-tmux.log"
layout_cleanup_session="${session}-layout-cleanup"
mkdir -p "$layout_cleanup_bin"
cat >"$layout_cleanup_bin/tmux" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

printf 'args=%s\n' "$*" >>"${TMUX_SESSION_LAYOUT_CLEANUP_LOG:?}"

case "${1:-}" in
  new-session)
    printf '@1\n'
    ;;
  new-window)
    exit 88
    ;;
  kill-session)
    ;;
  display-message)
    exit 1
    ;;
  send-keys|select-window)
    ;;
  *)
    printf 'unexpected tmux command: %s\n' "$*" >&2
    exit 2
    ;;
esac
SH
chmod +x "$layout_cleanup_bin/tmux"

set +e
SESSION_NAME="$layout_cleanup_session" \
  PATH="$layout_cleanup_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  TMUX_SESSION_AGENT_RESUME_COMMAND='' \
  TMUX_SESSION_AGENT_COMMAND='' \
  TMUX_SESSION_LAYOUT_CLEANUP_LOG="$layout_cleanup_log" \
  TMUX_SESSION_START_DIR="$tmp/work" \
  "$root/common/.local/bin/tmux-session-default-layout" >"$tmp/layout-cleanup.out" 2>"$tmp/layout-cleanup.err"
layout_cleanup_status=$?
set -e
assert_eq "default layout preserves failing tmux status during cleanup" "88" "$layout_cleanup_status"
assert_contains \
  "default layout removes partial session after layout failure" \
  "$(cat "$layout_cleanup_log")" \
  "args=kill-session -t =$layout_cleanup_session"

layout_signal_bin="$tmp/layout-signal-bin"
layout_signal_log="$tmp/layout-signal-tmux.log"
layout_signal_ready="$tmp/layout-signal-ready"
layout_signal_release="$tmp/layout-signal-release"
layout_signal_session="${session}-layout-signal"
mkdir -p "$layout_signal_bin"
cat >"$layout_signal_bin/tmux" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

printf 'args=%s\n' "$*" >>"${TMUX_SESSION_LAYOUT_SIGNAL_LOG:?}"

case "${1:-}" in
  display-message)
    exit 1
    ;;
  new-session)
    printf '@1\n'
    ;;
  send-keys)
    : >"${TMUX_SESSION_LAYOUT_SIGNAL_READY:?}"
    while [[ ! -e "${TMUX_SESSION_LAYOUT_SIGNAL_RELEASE:?}" ]]; do
      sleep 0.05
    done
    ;;
  kill-session)
    ;;
  new-window|select-window)
    ;;
  *)
    printf 'unexpected tmux command: %s\n' "$*" >&2
    exit 2
    ;;
esac
SH
chmod +x "$layout_signal_bin/tmux"

set +e
SESSION_NAME="$layout_signal_session" \
  PATH="$layout_signal_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  TMUX_SESSION_AGENT_RESUME_COMMAND='echo resume' \
  TMUX_SESSION_AGENT_COMMAND='' \
  TMUX_SESSION_LAYOUT_SIGNAL_LOG="$layout_signal_log" \
  TMUX_SESSION_LAYOUT_SIGNAL_READY="$layout_signal_ready" \
  TMUX_SESSION_LAYOUT_SIGNAL_RELEASE="$layout_signal_release" \
  TMUX_SESSION_START_DIR="$tmp/work" \
  "$root/common/.local/bin/tmux-session-default-layout" >"$tmp/layout-signal.out" 2>"$tmp/layout-signal.err" &
layout_signal_pid=$!
set -e
wait_for_file "default layout signal test reaches first window command" "$layout_signal_ready"
kill -TERM "$layout_signal_pid"
touch "$layout_signal_release"
set +e
wait "$layout_signal_pid"
layout_signal_status=$?
set -e
assert_eq "default layout preserves signal status during cleanup" "143" "$layout_signal_status"
layout_signal_output="$(cat "$layout_signal_log")"
assert_contains \
  "default layout removes partial session after termination" \
  "$layout_signal_output" \
  "args=kill-session -t =$layout_signal_session"
assert_not_contains \
  "default layout stops creating windows after termination" \
  "$layout_signal_output" \
  "args=new-window"

tmux_test env \
  TMUX_SESSION_START_DIR="$tmp/work" \
  TMUX_SESSION_AGENT_RESUME_COMMAND= \
  TMUX_SESSION_AGENT_COMMAND= \
  tmux-session "$session" --no-attach

windows="$(tmux_test tmux list-windows -t "=$session" -F '#{window_index}:#{window_name}:#{pane_current_path}')"
assert_eq \
  "default layout creates three windows in start dir" \
  "$(printf '1:resume:%s\n2:AI:%s\n3:terminal:%s' "$tmp/work" "$tmp/work" "$tmp/work")" \
  "$windows"

selected="$(active_window "$session")"
assert_eq "default layout selects first window" "${session}:1" "$selected"

named_session="${session}-names"
tmux_test env \
  TMUX_SESSION_AGENT_RESUME_COMMAND= \
  TMUX_SESSION_AGENT_COMMAND= \
  TMUX_SESSION_AGENT_RESUME_WINDOW_NAME=continue \
  TMUX_SESSION_AGENT_WINDOW_NAME=agent \
  TMUX_SESSION_TERMINAL_WINDOW_NAME=shell \
  tmux-session "$named_session" --start-dir "$tmp/work" --no-attach

named_windows="$(tmux_test tmux list-windows -t "=$named_session" -F '#{window_index}:#{window_name}:#{pane_current_path}')"
assert_eq \
  "default layout accepts custom window names" \
  "$(printf '1:continue:%s\n2:agent:%s\n3:shell:%s' "$tmp/work" "$tmp/work" "$tmp/work")" \
  "$named_windows"

tmux_test env \
  tmux-session "$named_session" --window terminal --no-attach

selected="$(active_window "$named_session")"
assert_eq "terminal alias selects third custom-named window" "${named_session}:3" "$selected"

no_tr_session_bin="$tmp/no-tr-session-bin"
mkdir -p "$no_tr_session_bin"
for tool in bash env; do
  ln -s "$(command -v "$tool")" "$no_tr_session_bin/$tool"
done
ln -s "$tmp/bin/tmux" "$no_tr_session_bin/tmux"
HOME="$tmp/home" \
  PATH="$no_tr_session_bin" \
  TMUX_TEST_REAL_TMUX="$real_tmux" \
  TMUX_TEST_SOCKET="$socket_name" \
  "$root/common/.local/bin/tmux-session" "$named_session" TERMINAL --no-attach

selected="$(active_window "$named_session")"
assert_eq "uppercase terminal alias selects without tr" "${named_session}:3" "$selected"

no_agent_session="${session}-no-agent"
tmux_direct_test \
  "$root/common/.local/bin/tmux-session" "$no_agent_session" --start-dir "$tmp/work" --no-attach

no_agent_windows="$(tmux_test tmux list-windows -t "=$no_agent_session" -F '#{window_index}:#{window_name}:#{pane_current_path}')"
assert_eq \
  "default layout tolerates missing agent cli" \
  "$(printf '1:resume:%s\n2:AI:%s\n3:terminal:%s' "$tmp/work" "$tmp/work" "$tmp/work")" \
  "$no_agent_windows"

inherited_env_session="${session}-inherited-env"
TMUX_SESSION_AGENT_RESUME_WINDOW_NAME=leaked-resume \
  TMUX_SESSION_AGENT_WINDOW_NAME=leaked-ai \
  TMUX_SESSION_TERMINAL_WINDOW_NAME=leaked-terminal \
  tmux_direct_test \
    "$root/common/.local/bin/tmux-session" "$inherited_env_session" --start-dir "$tmp/work" --no-attach

inherited_env_windows="$(tmux_test tmux list-windows -t "=$inherited_env_session" -F '#{window_index}:#{window_name}:#{pane_current_path}')"
assert_eq \
  "tmux-session tests isolate inherited layout env" \
  "$(printf '1:resume:%s\n2:AI:%s\n3:terminal:%s' "$tmp/work" "$tmp/work" "$tmp/work")" \
  "$inherited_env_windows"

dash_session="--${session}-dash"
tmux_test env \
  TMUX_SESSION_AGENT_RESUME_COMMAND= \
  TMUX_SESSION_AGENT_COMMAND= \
  tmux-session --start-dir "$tmp/work" --no-attach -- "$dash_session"

dash_windows="$(tmux_test tmux list-windows -t "=$dash_session" -F '#{window_index}:#{window_name}:#{pane_current_path}')"
assert_eq \
  "delimiter allows dash-prefixed session name" \
  "$(printf '1:resume:%s\n2:AI:%s\n3:terminal:%s' "$tmp/work" "$tmp/work" "$tmp/work")" \
  "$dash_windows"

tmux_test env \
  tmux-session --no-attach -- "$dash_session" terminal

selected="$(active_window "$dash_session")"
assert_eq "delimiter dash-prefixed session selects window" "${dash_session}:3" "$selected"

spaced_agent_bin="$tmp/spaced agent bin"
mkdir -p "$spaced_agent_bin"
make_fake_agent_cli_at "$spaced_agent_bin/codex"

spaced_agent_log="$tmp/spaced-agent.log"
tmux_test tmux set-environment -g TMUX_SESSION_AGENT_LOG "$spaced_agent_log"
tmux_test env \
  PATH="$spaced_agent_bin:$tmp/bin:$root/common/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  tmux-session "${session}-spaced-agent" --start-dir "$tmp/work" --no-attach
wait_for_log_lines "default layout runs agent cli from spaced path" "$spaced_agent_log" 2
assert_eq \
  "default layout quotes spaced agent path" \
  "$(printf 'codex\ncodex resume --last')" \
  "$(LC_ALL=C sort "$spaced_agent_log")"

make_fake_agent_cli codex
make_fake_agent_cli codex.exe
make_fake_agent_cli CODEX.EXE
make_fake_agent_cli opencode.cmd
make_fake_agent_cli OPENCODE.CMD
make_fake_agent_cli opencode
make_fake_agent_cli gemini
make_fake_agent_cli claude
make_fake_agent_cli aider

auto_agent_log="$tmp/auto-agent.log"
tmux_test tmux set-environment -g TMUX_SESSION_AGENT_LOG "$auto_agent_log"
tmux_test env \
  tmux-session "${session}-auto-agent" --start-dir "$tmp/work" --no-attach
wait_for_log_lines "default layout starts preferred available agent cli" "$auto_agent_log" 2
assert_eq \
  "default layout prefers codex agent commands" \
  "$(printf 'codex\ncodex resume --last')" \
  "$(LC_ALL=C sort "$auto_agent_log")"

codex_exe_agent_log="$tmp/codex-exe-agent.log"
tmux_test tmux set-environment -g TMUX_SESSION_AGENT_LOG "$codex_exe_agent_log"
tmux_test env \
  TMUX_SESSION_AGENT_CLI=codex.exe \
  tmux-session "${session}-codex-exe-agent" --start-dir "$tmp/work" --no-attach
wait_for_log_lines "default layout recognizes codex.exe agent cli" "$codex_exe_agent_log" 2
assert_eq \
  "default layout uses codex.exe resume command" \
  "$(printf 'codex.exe\ncodex.exe resume --last')" \
  "$(LC_ALL=C sort "$codex_exe_agent_log")"

uppercase_codex_exe_agent_log="$tmp/uppercase-codex-exe-agent.log"
tmux_test tmux set-environment -g TMUX_SESSION_AGENT_LOG "$uppercase_codex_exe_agent_log"
tmux_test env \
  TMUX_SESSION_AGENT_CLI=CODEX.EXE \
  tmux-session "${session}-uppercase-codex-exe-agent" --start-dir "$tmp/work" --no-attach
wait_for_log_lines "default layout recognizes uppercase CODEX.EXE agent cli" "$uppercase_codex_exe_agent_log" 2
assert_eq \
  "default layout uses uppercase CODEX.EXE resume command" \
  "$(printf 'CODEX.EXE\nCODEX.EXE resume --last')" \
  "$(LC_ALL=C sort "$uppercase_codex_exe_agent_log")"

gemini_agent_log="$tmp/gemini-agent.log"
tmux_test tmux set-environment -g TMUX_SESSION_AGENT_LOG "$gemini_agent_log"
tmux_test env \
  TMUX_SESSION_AGENT_CLI=gemini \
  tmux-session "${session}-gemini-agent" --start-dir "$tmp/work" --no-attach
wait_for_log_lines "default layout starts selected gemini cli" "$gemini_agent_log" 2
assert_eq \
  "default layout uses valid gemini resume command" \
  "$(printf 'gemini --yolo\ngemini --yolo --resume latest')" \
  "$(LC_ALL=C sort "$gemini_agent_log")"

opencode_agent_log="$tmp/opencode-agent.log"
tmux_test tmux set-environment -g TMUX_SESSION_AGENT_LOG "$opencode_agent_log"
tmux_test env \
  TMUX_SESSION_AGENT_CLI=opencode \
  tmux-session "${session}-opencode-agent" --start-dir "$tmp/work" --no-attach
wait_for_log_lines "default layout starts selected opencode cli" "$opencode_agent_log" 2
assert_eq \
  "default layout uses valid opencode resume command" \
  "$(printf 'opencode\nopencode --continue')" \
  "$(LC_ALL=C sort "$opencode_agent_log")"

opencode_cmd_agent_log="$tmp/opencode-cmd-agent.log"
tmux_test tmux set-environment -g TMUX_SESSION_AGENT_LOG "$opencode_cmd_agent_log"
tmux_test env \
  TMUX_SESSION_AGENT_CLI=opencode.cmd \
  tmux-session "${session}-opencode-cmd-agent" --start-dir "$tmp/work" --no-attach
wait_for_log_lines "default layout recognizes opencode.cmd agent cli" "$opencode_cmd_agent_log" 2
assert_eq \
  "default layout uses opencode.cmd resume command" \
  "$(printf 'opencode.cmd\nopencode.cmd --continue')" \
  "$(LC_ALL=C sort "$opencode_cmd_agent_log")"

uppercase_opencode_cmd_agent_log="$tmp/uppercase-opencode-cmd-agent.log"
tmux_test tmux set-environment -g TMUX_SESSION_AGENT_LOG "$uppercase_opencode_cmd_agent_log"
tmux_test env \
  TMUX_SESSION_AGENT_CLI=OPENCODE.CMD \
  tmux-session "${session}-uppercase-opencode-cmd-agent" --start-dir "$tmp/work" --no-attach
wait_for_log_lines "default layout recognizes uppercase OPENCODE.CMD agent cli" "$uppercase_opencode_cmd_agent_log" 2
assert_eq \
  "default layout uses uppercase OPENCODE.CMD resume command" \
  "$(printf 'OPENCODE.CMD\nOPENCODE.CMD --continue')" \
  "$(LC_ALL=C sort "$uppercase_opencode_cmd_agent_log")"

claude_agent_log="$tmp/claude-agent.log"
tmux_test tmux set-environment -g TMUX_SESSION_AGENT_LOG "$claude_agent_log"
tmux_test env \
  TMUX_SESSION_AGENT_CLI=claude \
  tmux-session "${session}-claude-agent" --start-dir "$tmp/work" --no-attach
wait_for_log_lines "default layout starts selected claude cli" "$claude_agent_log" 2
assert_eq \
  "default layout uses valid claude resume command" \
  "$(printf 'claude\nclaude --continue')" \
  "$(LC_ALL=C sort "$claude_agent_log")"

aider_agent_log="$tmp/aider-agent.log"
tmux_test tmux set-environment -g TMUX_SESSION_AGENT_LOG "$aider_agent_log"
tmux_test env \
  TMUX_SESSION_AGENT_CLI=aider \
  tmux-session "${session}-aider-agent" --start-dir "$tmp/work" --no-attach
wait_for_log_lines "default layout starts selected aider cli" "$aider_agent_log" 2
assert_eq \
  "default layout uses plain aider commands" \
  "$(printf 'aider\naider')" \
  "$(LC_ALL=C sort "$aider_agent_log")"

explicit_session="${session}-explicit"
tmux_test env \
  TMUX_SESSION_AGENT_RESUME_COMMAND= \
  TMUX_SESSION_AGENT_COMMAND= \
  tmux-session "$explicit_session" --start-dir "$tmp/explicit start" --no-attach

explicit_windows="$(tmux_test tmux list-windows -t "=$explicit_session" -F '#{window_index}:#{window_name}:#{pane_current_path}')"
assert_eq \
  "start-dir option creates layout in explicit dir" \
  "$(printf '1:resume:%s\n2:AI:%s\n3:terminal:%s' "$tmp/explicit start" "$tmp/explicit start" "$tmp/explicit start")" \
  "$explicit_windows"

relative_session="${session}-relative-start"
(
  cd "$tmp"
  tmux_test env \
    TMUX_SESSION_AGENT_RESUME_COMMAND= \
    TMUX_SESSION_AGENT_COMMAND= \
    tmux-session "$relative_session" --start-dir "relative start" --no-attach
)

relative_windows="$(tmux_test tmux list-windows -t "=$relative_session" -F '#{window_index}:#{window_name}:#{pane_current_path}')"
assert_eq \
  "relative start-dir option creates layout in absolute dir" \
  "$(printf '1:resume:%s\n2:AI:%s\n3:terminal:%s' "$tmp/relative start" "$tmp/relative start" "$tmp/relative start")" \
  "$relative_windows"

tilde_session="${session}-tilde"
tmux_test env \
  TMUX_SESSION_AGENT_RESUME_COMMAND= \
  TMUX_SESSION_AGENT_COMMAND= \
  tmux-session "$tilde_session" "--start-dir=~/tilde start" --no-attach

tilde_windows="$(tmux_test tmux list-windows -t "=$tilde_session" -F '#{window_index}:#{window_name}:#{pane_current_path}')"
assert_eq \
  "start-dir equals option expands home" \
  "$(printf '1:resume:%s\n2:AI:%s\n3:terminal:%s' "$tmp/home/tilde start" "$tmp/home/tilde start" "$tmp/home/tilde start")" \
  "$tilde_windows"

derived_root="$tmp/derived app!"
mkdir -p "$derived_root/src"
touch "$derived_root/package.json"
derived_session="derived_app"

tmux_test env \
  TMUX_SESSION_AGENT_RESUME_COMMAND= \
  TMUX_SESSION_AGENT_COMMAND= \
  tmux-session --start-dir "$derived_root/src" --no-attach

derived_windows="$(tmux_test tmux list-windows -t "=$derived_session" -F '#{window_index}:#{window_name}:#{pane_current_path}')"
assert_eq \
  "omitted session name is derived from start-dir marker" \
  "$(printf '1:resume:%s\n2:AI:%s\n3:terminal:%s' "$derived_root/src" "$derived_root/src" "$derived_root/src")" \
  "$derived_windows"

tmux_test env \
  TMUX_SESSION_AGENT_RESUME_COMMAND= \
  TMUX_SESSION_AGENT_COMMAND= \
  tmux-session --start-dir "$derived_root/src" --window=agent --no-attach

selected="$(active_window "$derived_session")"
assert_eq "window alias selects derived session agent window" "${derived_session}:2" "$selected"

tmux_test env \
  TMUX_SESSION_AGENT_RESUME_COMMAND= \
  TMUX_SESSION_AGENT_COMMAND= \
  tmux-session --window resume --start-dir "$derived_root/src" --no-attach

selected="$(active_window "$derived_session")"
assert_eq "window alias selects derived session resume window" "${derived_session}:1" "$selected"

tmux_test env \
  TMUX_SESSION_AGENT_RESUME_COMMAND= \
  TMUX_SESSION_AGENT_COMMAND= \
  tmux-session --window terminal --start-dir "$derived_root/src" --no-attach

selected="$(active_window "$derived_session")"
assert_eq "window option selects derived session window name" "${derived_session}:3" "$selected"

invalid_start_dir_log="$tmp/tmux-session-invalid-start-dir.out"
if tmux_test tmux-session "${session}-invalid-dir" --start-dir "$tmp/missing start" --no-attach >"$invalid_start_dir_log" 2>&1; then
  printf 'not ok - invalid start-dir fails\n' >&2
  exit 1
fi
assert_eq \
  "invalid start-dir gets friendly error" \
  "Error: --start-dir is not a directory: $tmp/missing start" \
  "$(cat "$invalid_start_dir_log")"

windows_strict_start_dir_log="$tmp/tmux-session-windows-strict-start-dir.out"
if tmux_test tmux-session "${session}-windows-strict-dir" --start-dir 'C:\Users\sky\Project App' --no-attach >"$windows_strict_start_dir_log" 2>&1; then
  printf 'not ok - Windows start-dir outside Windows env fails\n' >&2
  exit 1
fi
printf 'ok - Windows start-dir outside Windows env fails\n'
assert_eq \
  "Windows start-dir outside Windows env is not made relative" \
  "Error: --start-dir is not a directory: C:/Users/sky/Project App" \
  "$(cat "$windows_strict_start_dir_log")"

windows_session_helper_dir="$tmp/windows-session-helper"
windows_session_bin="$tmp/windows-session-bin"
mkdir -p "$windows_session_helper_dir" "$windows_session_bin"
ln -s "$root/common/.local/bin/tmux-session" "$windows_session_helper_dir/tmux-session"

cat >"$windows_session_helper_dir/tmux-session-default-layout-local" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

printf 'session=%s\nstart=%s\n' "$SESSION_NAME" "$TMUX_SESSION_START_DIR" >"${TMUX_TEST_WINDOWS_LAYOUT_LOG:?}"
SH
chmod +x "$windows_session_helper_dir/tmux-session-default-layout-local"

cat >"$windows_session_bin/tmux" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

command="${1:-}"
case "$command" in
  display-message)
    exit 1
    ;;
  has-session)
    exit 1
    ;;
  *)
    printf 'unexpected tmux command: %s\n' "$command" >&2
    exit 2
    ;;
esac
SH
chmod +x "$windows_session_bin/tmux"

windows_drive_layout_log="$tmp/tmux-session-windows-drive-layout.log"
OS=Windows_NT \
  HOME="$tmp/home" \
  PATH="$windows_session_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  TMUX_TEST_WINDOWS_LAYOUT_LOG="$windows_drive_layout_log" \
  "$windows_session_helper_dir/tmux-session" "${session}-windows-drive" --start-dir 'C:\Users\sky\Project App' --no-attach
assert_eq \
  "tmux-session passes Windows drive start dir in Windows env" \
  "$(printf 'session=%s-windows-drive\nstart=C:/Users/sky/Project App' "$session")" \
  "$(cat "$windows_drive_layout_log")"

windows_unc_layout_log="$tmp/tmux-session-windows-unc-layout.log"
OS=Windows_NT \
  HOME="$tmp/home" \
  PATH="$windows_session_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  TMUX_TEST_WINDOWS_LAYOUT_LOG="$windows_unc_layout_log" \
  "$windows_session_helper_dir/tmux-session" "${session}-windows-unc" --start-dir '\\server\share\Project App' --no-attach
assert_eq \
  "tmux-session passes Windows UNC start dir in Windows env" \
  "$(printf 'session=%s-windows-unc\nstart=//server/share/Project App' "$session")" \
  "$(cat "$windows_unc_layout_log")"

windows_slash_unc_layout_log="$tmp/tmux-session-windows-slash-unc-layout.log"
OS=Windows_NT \
  HOME="$tmp/home" \
  PATH="$windows_session_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  TMUX_TEST_WINDOWS_LAYOUT_LOG="$windows_slash_unc_layout_log" \
  "$windows_session_helper_dir/tmux-session" "${session}-windows-slash-unc" --start-dir '//server/share/Project App' --no-attach
assert_eq \
  "tmux-session passes Windows slash UNC start dir in Windows env" \
  "$(printf 'session=%s-windows-slash-unc\nstart=//server/share/Project App' "$session")" \
  "$(cat "$windows_slash_unc_layout_log")"

windows_layout_bin="$tmp/windows-layout-bin"
mkdir -p "$windows_layout_bin"
cat >"$windows_layout_bin/tmux" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

command="${1:-}"
shift || true

case "$command" in
  display-message)
    exit 1
    ;;
  new-session|new-window)
    printf '%s' "$command" >>"${TMUX_TEST_WINDOWS_LAYOUT_TMUX_LOG:?}"
    print_window=0
    for arg in "$@"; do
      printf '\narg=%s' "$arg" >>"${TMUX_TEST_WINDOWS_LAYOUT_TMUX_LOG:?}"
      if [[ "$arg" == "-P" ]]; then
        print_window=1
      fi
    done
    printf '\n' >>"${TMUX_TEST_WINDOWS_LAYOUT_TMUX_LOG:?}"
    if [[ "$print_window" == "1" ]]; then
      case "$command" in
        new-session) printf '%%1\n' ;;
        new-window) printf '%%2\n' ;;
      esac
    fi
    ;;
  send-keys|select-window)
    printf '%s' "$command" >>"${TMUX_TEST_WINDOWS_LAYOUT_TMUX_LOG:?}"
    for arg in "$@"; do
      printf '\narg=%s' "$arg" >>"${TMUX_TEST_WINDOWS_LAYOUT_TMUX_LOG:?}"
    done
    printf '\n' >>"${TMUX_TEST_WINDOWS_LAYOUT_TMUX_LOG:?}"
    ;;
  *)
    printf 'unexpected tmux command: %s\n' "$command" >&2
    exit 2
    ;;
esac
SH
chmod +x "$windows_layout_bin/tmux"

windows_default_layout_drive_log="$tmp/default-layout-windows-drive-tmux.log"
OS=Windows_NT \
  HOME="$tmp/home" \
  PATH="$windows_layout_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  SESSION_NAME="${session}-windows-default-drive" \
  TMUX_SESSION_START_DIR='C:\Users\sky\Project App' \
  TMUX_TEST_WINDOWS_LAYOUT_TMUX_LOG="$windows_default_layout_drive_log" \
  "$root/common/.local/bin/tmux-session-default-layout"
assert_contains \
  "default layout passes Windows drive start dir in Windows env" \
  "$(cat "$windows_default_layout_drive_log")" \
  "arg=C:/Users/sky/Project App"

windows_default_layout_unc_log="$tmp/default-layout-windows-unc-tmux.log"
OS=Windows_NT \
  HOME="$tmp/home" \
  PATH="$windows_layout_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  SESSION_NAME="${session}-windows-default-unc" \
  TMUX_SESSION_START_DIR='\\server\share\Project App' \
  TMUX_TEST_WINDOWS_LAYOUT_TMUX_LOG="$windows_default_layout_unc_log" \
  "$root/common/.local/bin/tmux-session-default-layout"
assert_contains \
  "default layout passes Windows UNC start dir in Windows env" \
  "$(cat "$windows_default_layout_unc_log")" \
  "arg=//server/share/Project App"

windows_default_layout_slash_unc_log="$tmp/default-layout-windows-slash-unc-tmux.log"
OS=Windows_NT \
  HOME="$tmp/home" \
  PATH="$windows_layout_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  SESSION_NAME="${session}-windows-default-slash-unc" \
  TMUX_SESSION_START_DIR='//server/share/Project App' \
  TMUX_TEST_WINDOWS_LAYOUT_TMUX_LOG="$windows_default_layout_slash_unc_log" \
  "$root/common/.local/bin/tmux-session-default-layout"
assert_contains \
  "default layout passes Windows slash UNC start dir in Windows env" \
  "$(cat "$windows_default_layout_slash_unc_log")" \
  "arg=//server/share/Project App"

missing_window_option_log="$tmp/tmux-session-missing-window-option.out"
if tmux_test tmux-session "$session" --window >"$missing_window_option_log" 2>&1; then
  printf 'not ok - missing --window value fails\n' >&2
  exit 1
fi
assert_eq \
  "missing window option gets friendly error" \
  "$(printf 'Error: --window requires a window index or name\nUsage: tmux-session [--no-attach] [--start-dir DIR] [--window WINDOW] [--] [session_name] [window_index|window_name]')" \
  "$(sed "s#$(printf '%s' "$root/common/.local/bin/")##" "$missing_window_option_log")"

tmux_test tmux new-session -d -s "${session}-other" -n other -c "$tmp"
tmux_test env \
  TMUX_SESSION_START_DIR="$tmp/work" \
  TMUX_SESSION_AGENT_RESUME_COMMAND= \
  TMUX_SESSION_AGENT_COMMAND= \
  tmux-session "$session" 2 --no-attach

selected="$(active_window "$session")"
assert_eq "window selection targets exact session" "${session}:2" "$selected"

other_selected="$(active_window "${session}-other")"
assert_eq "similarly named session remains unchanged" "${session}-other:1" "$other_selected"

tmux_test env \
  TMUX_SESSION_START_DIR="$tmp/work" \
  TMUX_SESSION_AGENT_RESUME_COMMAND= \
  TMUX_SESSION_AGENT_COMMAND= \
  tmux-session "$session" terminal --no-attach

selected="$(active_window "$session")"
assert_eq "window selection accepts exact name" "${session}:3" "$selected"

missing_name_log="$tmp/tmux-session-missing-name.out"
missing_window_log="$tmp/tmux-session-missing-window.out"

if tmux_test tmux-session "$session" missing --no-attach >"$missing_name_log" 2>&1; then
  printf 'not ok - missing window name fails\n' >&2
  exit 1
fi
assert_eq \
  "missing window name gets friendly error" \
  "Error: session '$session' has no window index or name: missing" \
  "$(cat "$missing_name_log")"

if tmux_test tmux-session "$session" 99 --no-attach >"$missing_window_log" 2>&1; then
  printf 'not ok - missing window index fails\n' >&2
  exit 1
fi
assert_eq \
  "missing window index gets friendly error" \
  "Error: session '$session' has no window index or name: 99" \
  "$(cat "$missing_window_log")"

stale_tmux_bin="$tmp/stale-tmux-bin"
stale_tmux_log="$tmp/stale-tmux.log"
mkdir -p "$stale_tmux_bin"
cat >"$stale_tmux_bin/tmux" <<'SH'
#!/usr/bin/env bash
{
  printf 'tmux=%s\n' "${TMUX-<unset>}"
  printf 'args=%s\n' "$*"
  printf -- '---\n'
} >>"${TMUX_SESSION_FAKE_TMUX_LOG:?}"

case "${1:-}" in
  has-session)
    exit 0
    ;;
  display-message)
    exit 1
    ;;
  attach-session)
    exit 0
    ;;
  *)
    printf 'unexpected fake tmux command: %s\n' "$*" >&2
    exit 2
    ;;
esac
SH
chmod +x "$stale_tmux_bin/tmux"

TMUX="$tmp/stale-client" \
  TMUX_SESSION_FAKE_TMUX_LOG="$stale_tmux_log" \
  PATH="$stale_tmux_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/tmux-session" "${session}-stale"

assert_eq \
  "stale TMUX attaches with TMUX unset" \
  "$(printf 'tmux=%s\nargs=display-message -p #{pane_id}\n---\ntmux=<unset>\nargs=has-session -t =%s-stale\n---\ntmux=<unset>\nargs=attach-session -t =%s-stale\n---' "$tmp/stale-client" "$session" "$session")" \
  "$(cat "$stale_tmux_log")"

no_env_stale_tmux_bin="$tmp/no-env-stale-tmux-bin"
no_env_stale_tmux_log="$tmp/no-env-stale-tmux.log"
mkdir -p "$no_env_stale_tmux_bin"
ln -s "$(command -v bash)" "$no_env_stale_tmux_bin/bash"
ln -s "$stale_tmux_bin/tmux" "$no_env_stale_tmux_bin/tmux"

TMUX="$tmp/stale-client" \
  TMUX_SESSION_FAKE_TMUX_LOG="$no_env_stale_tmux_log" \
  PATH="$no_env_stale_tmux_bin" \
  "$root/common/.local/bin/tmux-session" "${session}-stale-no-env"

assert_eq \
  "stale TMUX attaches with TMUX unset without env" \
  "$(printf 'tmux=%s\nargs=display-message -p #{pane_id}\n---\ntmux=<unset>\nargs=has-session -t =%s-stale-no-env\n---\ntmux=<unset>\nargs=attach-session -t =%s-stale-no-env\n---' "$tmp/stale-client" "$session" "$session")" \
  "$(cat "$no_env_stale_tmux_log")"

stale_create_bin="$tmp/stale-create-bin"
stale_create_helper_dir="$tmp/stale-create-helper"
stale_create_home="$tmp/stale-create-home"
stale_create_log="$tmp/stale-create.log"
mkdir -p "$stale_create_bin" "$stale_create_helper_dir" "$stale_create_home"
ln -s "$root/common/.local/bin/tmux-session" "$stale_create_helper_dir/tmux-session"
cat >"$stale_create_bin/tmux" <<'SH'
#!/usr/bin/env bash
{
  printf 'tmux=%s\n' "${TMUX-<unset>}"
  printf 'args=%s\n' "$*"
  printf -- '---\n'
} >>"${TMUX_SESSION_CREATE_LOG:?}"

case "${1:-}" in
  display-message)
    exit 1
    ;;
  has-session)
    exit 1
    ;;
  *)
    printf 'unexpected fake tmux command: %s\n' "$*" >&2
    exit 2
    ;;
esac
SH
chmod +x "$stale_create_bin/tmux"

cat >"$stale_create_bin/tmux-session-default-layout" <<'SH'
#!/usr/bin/env bash
{
  printf 'layout-tmux=%s\n' "${TMUX-<unset>}"
  printf 'layout-session=%s\n' "${SESSION_NAME:?}"
  printf 'layout-start=%s\n' "${TMUX_SESSION_START_DIR:?}"
} >>"${TMUX_SESSION_CREATE_LOG:?}"
SH
chmod +x "$stale_create_bin/tmux-session-default-layout"

TMUX="$tmp/stale-client" \
  HOME="$stale_create_home" \
  TMUX_SESSION_CREATE_LOG="$stale_create_log" \
  PATH="$stale_create_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$stale_create_helper_dir/tmux-session" "${session}-stale-create" --start-dir "$tmp/work" --no-attach

assert_eq \
  "stale TMUX creates session with TMUX unset" \
  "$(printf 'tmux=%s\nargs=display-message -p #{pane_id}\n---\ntmux=<unset>\nargs=has-session -t =%s-stale-create\n---\nlayout-tmux=<unset>\nlayout-session=%s-stale-create\nlayout-start=%s\n' "$tmp/stale-client" "$session" "$session" "$tmp/work")" \
  "$(cat "$stale_create_log")"

no_env_stale_create_bin="$tmp/no-env-stale-create-bin"
no_env_stale_create_helper_dir="$tmp/no-env-stale-create-helper"
no_env_stale_create_home="$tmp/no-env-stale-create-home"
no_env_stale_create_log="$tmp/no-env-stale-create.log"
mkdir -p "$no_env_stale_create_bin" "$no_env_stale_create_helper_dir" "$no_env_stale_create_home"
ln -s "$(command -v bash)" "$no_env_stale_create_bin/bash"
ln -s "$root/common/.local/bin/tmux-session" "$no_env_stale_create_helper_dir/tmux-session"
ln -s "$stale_create_bin/tmux" "$no_env_stale_create_bin/tmux"
ln -s "$stale_create_bin/tmux-session-default-layout" "$no_env_stale_create_bin/tmux-session-default-layout"

TMUX="$tmp/stale-client" \
  HOME="$no_env_stale_create_home" \
  TMUX_SESSION_CREATE_LOG="$no_env_stale_create_log" \
  PATH="$no_env_stale_create_bin" \
  "$no_env_stale_create_helper_dir/tmux-session" "${session}-stale-create-no-env" --start-dir "$tmp/work" --no-attach

assert_eq \
  "stale TMUX creates session with TMUX unset without env" \
  "$(printf 'tmux=%s\nargs=display-message -p #{pane_id}\n---\ntmux=<unset>\nargs=has-session -t =%s-stale-create-no-env\n---\nlayout-tmux=<unset>\nlayout-session=%s-stale-create-no-env\nlayout-start=%s\n' "$tmp/stale-client" "$session" "$session" "$tmp/work")" \
  "$(cat "$no_env_stale_create_log")"

layout_stale_bin="$tmp/layout-stale-bin"
layout_stale_log="$tmp/layout-stale.log"
mkdir -p "$layout_stale_bin"
cat >"$layout_stale_bin/tmux" <<'SH'
#!/usr/bin/env bash
{
  printf 'tmux=%s\n' "${TMUX-<unset>}"
  printf 'args=%s\n' "$*"
  printf -- '---\n'
} >>"${TMUX_SESSION_LAYOUT_LOG:?}"

case "${1:-}" in
  display-message)
    exit 1
    ;;
  new-session)
    printf '@1\n'
    ;;
  new-window)
    for arg in "$@"; do
      if [[ "$arg" == "-P" ]]; then
        printf '@2\n'
        break
      fi
    done
    ;;
  send-keys|select-window)
    ;;
  *)
    printf 'unexpected fake tmux command: %s\n' "$*" >&2
    exit 2
    ;;
esac
SH
chmod +x "$layout_stale_bin/tmux"

TMUX="$tmp/stale-layout-client" \
  TMUX_SESSION_LAYOUT_LOG="$layout_stale_log" \
  PATH="$layout_stale_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  SESSION_NAME="${session}-layout-stale" \
  TMUX_SESSION_START_DIR="$tmp/work" \
  TMUX_SESSION_AGENT_RESUME_COMMAND="echo resume" \
  TMUX_SESSION_AGENT_COMMAND="echo agent" \
  "$root/common/.local/bin/tmux-session-default-layout"

assert_eq \
  "default layout clears stale TMUX for tmux commands" \
  "$(printf 'tmux=%s\nargs=display-message -p #{pane_id}\n---\ntmux=<unset>\nargs=new-session -d -s %s-layout-stale -n resume -c %s -P -F #{window_id}\n---\ntmux=<unset>\nargs=send-keys -t @1 echo resume C-m\n---\ntmux=<unset>\nargs=new-window -d -t =%s-layout-stale: -n AI -c %s -P -F #{window_id}\n---\ntmux=<unset>\nargs=send-keys -t @2 echo agent C-m\n---\ntmux=<unset>\nargs=new-window -d -t =%s-layout-stale: -n terminal -c %s\n---\ntmux=<unset>\nargs=select-window -t @1\n---' "$tmp/stale-layout-client" "$session" "$tmp/work" "$session" "$tmp/work" "$session" "$tmp/work")" \
  "$(cat "$layout_stale_log")"

layout_no_env_stale_bin="$tmp/layout-no-env-stale-bin"
layout_no_env_stale_log="$tmp/layout-no-env-stale.log"
mkdir -p "$layout_no_env_stale_bin"
ln -s "$(command -v bash)" "$layout_no_env_stale_bin/bash"
ln -s "$layout_stale_bin/tmux" "$layout_no_env_stale_bin/tmux"

TMUX="$tmp/stale-layout-client" \
  TMUX_SESSION_LAYOUT_LOG="$layout_no_env_stale_log" \
  PATH="$layout_no_env_stale_bin" \
  SESSION_NAME="${session}-layout-no-env-stale" \
  TMUX_SESSION_START_DIR="$tmp/work" \
  TMUX_SESSION_AGENT_RESUME_COMMAND="echo resume" \
  TMUX_SESSION_AGENT_COMMAND="echo agent" \
  "$root/common/.local/bin/tmux-session-default-layout"

assert_eq \
  "default layout clears stale TMUX without env for tmux commands" \
  "$(printf 'tmux=%s\nargs=display-message -p #{pane_id}\n---\ntmux=<unset>\nargs=new-session -d -s %s-layout-no-env-stale -n resume -c %s -P -F #{window_id}\n---\ntmux=<unset>\nargs=send-keys -t @1 echo resume C-m\n---\ntmux=<unset>\nargs=new-window -d -t =%s-layout-no-env-stale: -n AI -c %s -P -F #{window_id}\n---\ntmux=<unset>\nargs=send-keys -t @2 echo agent C-m\n---\ntmux=<unset>\nargs=new-window -d -t =%s-layout-no-env-stale: -n terminal -c %s\n---\ntmux=<unset>\nargs=select-window -t @1\n---' "$tmp/stale-layout-client" "$session" "$tmp/work" "$session" "$tmp/work" "$session" "$tmp/work")" \
  "$(cat "$layout_no_env_stale_log")"
