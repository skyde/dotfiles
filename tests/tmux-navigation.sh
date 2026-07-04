#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
real_tmux="$(command -v tmux)"
socket_name="dotfiles-nav-test-$$"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/tmux-navigation.XXXXXX")"
fake_home="$tmp/home"
mock_ssh_server_pids=()

wait_for_pid_exit() {
  local pid="$1"

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$pid" >/dev/null 2>&1 || return 0
    sleep 0.1
  done
}

kill_tmp_processes() {
  local pid command

  while read -r pid command; do
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    [[ "$pid" != "$$" ]] || continue
    [[ "$command" == *"$tmp"* ]] || continue
    kill "$pid" >/dev/null 2>&1 || true
    wait_for_pid_exit "$pid"
  done < <(ps -axo pid=,command= 2>/dev/null || true)
}

cleanup() {
  "$real_tmux" -L "$socket_name" kill-server >/dev/null 2>&1 || true
  for mock_ssh_server_pid in "${mock_ssh_server_pids[@]+"${mock_ssh_server_pids[@]}"}"; do
    kill "$mock_ssh_server_pid" >/dev/null 2>&1 || true
    wait "$mock_ssh_server_pid" 2>/dev/null || true
    wait_for_pid_exit "$mock_ssh_server_pid"
  done
  kill_tmp_processes
  rm -rf "$tmp"
}
trap cleanup EXIT

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

assert_file_absent() {
  local name="$1"
  local path="$2"

  if [[ -e "$path" ]]; then
    printf 'not ok - %s\n' "$name" >&2
    printf 'unexpected file exists: %s\n' "$path" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

wait_for_file() {
  local path="$1"

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -s "$path" ]] && return 0
    sleep 0.1
  done

  printf 'timed out waiting for %s\n' "$path" >&2
  return 1
}

free_tcp_port() {
  python3 - <<'PY'
import socket

sock = socket.socket()
sock.bind(("127.0.0.1", 0))
print(sock.getsockname()[1])
sock.close()
PY
}

start_mock_ssh_server() {
  local ready_path="$1"
  local port actual_pid

  port="$(free_tcp_port)"
  python3 - "$port" "$ready_path" >/dev/null 2>&1 <<'PY' &
import os
import socket
import sys
import time

port = int(sys.argv[1])
ready_path = sys.argv[2]
server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", port))
server.listen(1)
with open(ready_path + ".pid", "w", encoding="utf-8") as pid_file:
    pid_file.write(str(os.getpid()) + "\n")
with open(ready_path, "w", encoding="utf-8") as ready_file:
    ready_file.write("ready\n")

connection, _ = server.accept()
with connection:
    connection.sendall(b"SSH-2.0-dotfiles-mock\r\n")
    time.sleep(30)
PY
  mock_ssh_server_pids+=("$!")
  wait_for_file "$ready_path"
  if [[ -s "$ready_path.pid" ]]; then
    actual_pid="$(cat "$ready_path.pid")"
    [[ -n "$actual_pid" ]] && mock_ssh_server_pids+=("$actual_pid")
  fi
  printf '%s\n' "$port"
}

wait_for_pane_command() {
  local pane_id="$1"
  local expected="$2"
  local actual

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    actual="$("$real_tmux" -L "$socket_name" display-message -p -t "$pane_id" '#{pane_current_command}')"
    [[ "$actual" == "$expected" ]] && return 0
    sleep 0.1
  done

  printf 'timed out waiting for pane %s command %s, got %s\n' "$pane_id" "$expected" "$actual" >&2
  return 1
}

active_pane_in_window() {
  local window="$1"

  "$real_tmux" -L "$socket_name" list-panes -t "$window" -F '#{pane_active} #{pane_id}' |
    awk '$1 == 1 { print $2; exit }'
}

mkdir -p "$fake_home/.local/bin"
cat >"$fake_home/.local/bin/tmux-pane-should-passthrough" <<'SH'
#!/usr/bin/env bash
printf 'local:%s|%s\n' "${1:-}" "${2:-}" >>"$HOME/helper.log"
exit 0
SH
chmod +x "$fake_home/.local/bin/tmux-pane-should-passthrough"

mkdir -p "$fake_home/dotfiles/common/.local/bin"
cat >"$fake_home/dotfiles/common/.local/bin/tmux-pane-should-passthrough" <<'SH'
#!/usr/bin/env bash
printf 'repo:%s|%s\n' "${1:-}" "${2:-}" >>"$HOME/helper.log"
exit 0
SH
chmod +x "$fake_home/dotfiles/common/.local/bin/tmux-pane-should-passthrough"

cd "$tmp"
HOME="$fake_home" "$real_tmux" -L "$socket_name" -f "$root/common/.tmux.conf" new-session -d -s nav-test 'sleep 60'
home_marker="\$HOME/.local/bin"
repo_marker="\$HOME/dotfiles/common/.local/bin"
home_guard="[ -n \\\"\\\${HOME:-}\\\" ]"
# shellcheck disable=SC2016
home_guard_raw='[ -n "${HOME:-}" ]'

for key in C-h C-j C-k C-l "C-\\"; do
  binding="$("$real_tmux" -L "$socket_name" list-keys -T root "$key")"
  assert_contains "navigation passthrough uses helper for $key" "$binding" "tmux-pane-should-passthrough"
  assert_contains "navigation passthrough uses explicit home for $key" "$binding" "$home_marker"
  assert_contains "navigation passthrough has repo fallback for $key" "$binding" "$repo_marker"
  assert_contains "navigation passthrough has PATH fallback for $key" "$binding" "command -v tmux-pane-should-passthrough"
  assert_contains "navigation passthrough guards unset HOME for $key" "$binding" "$home_guard"
  assert_contains "navigation passthrough shell-quotes current command for $key" "$binding" '#{q:pane_current_command}'
  assert_contains "navigation passthrough shell-quotes pane tty for $key" "$binding" '#{q:pane_tty}'
done

# shellcheck disable=SC2016
HOME="$fake_home" "$real_tmux" -L "$socket_name" if-shell 'if [ -n "${HOME:-}" ]; then for helper in "$HOME/.local/bin/tmux-pane-should-passthrough" "$HOME/dotfiles/common/.local/bin/tmux-pane-should-passthrough"; do [ -x "$helper" ] && exec "$helper" #{q:pane_current_command} #{q:pane_tty}; done; fi; helper="$(command -v tmux-pane-should-passthrough 2>/dev/null)" && exec "$helper" #{q:pane_current_command} #{q:pane_tty}; exit 1' \
  'display-message helper-yes' \
  'display-message helper-no'
sleep 0.2
helper_invocation="$(cat "$fake_home/helper.log")"
assert_contains "navigation helper receives current command" "$helper_invocation" "local:sleep|"
assert_contains "navigation helper receives pane tty" "$helper_invocation" "|/dev/"

rm -f "$fake_home/.local/bin/tmux-pane-should-passthrough"
# shellcheck disable=SC2016
HOME="$fake_home" "$real_tmux" -L "$socket_name" if-shell 'if [ -n "${HOME:-}" ]; then for helper in "$HOME/.local/bin/tmux-pane-should-passthrough" "$HOME/dotfiles/common/.local/bin/tmux-pane-should-passthrough"; do [ -x "$helper" ] && exec "$helper" #{q:pane_current_command} #{q:pane_tty}; done; fi; helper="$(command -v tmux-pane-should-passthrough 2>/dev/null)" && exec "$helper" #{q:pane_current_command} #{q:pane_tty}; exit 1' \
  'display-message helper-yes' \
  'display-message helper-no'
sleep 0.2
helper_invocation="$(cat "$fake_home/helper.log")"
assert_contains "navigation helper falls back to repo copy" "$helper_invocation" "repo:sleep|"

rm -f "$fake_home/dotfiles/common/.local/bin/tmux-pane-should-passthrough" "$fake_home/helper.log"
nav_path_bin="$tmp/nav-path-bin"
nav_path_log="$tmp/nav-path.log"
mkdir -p "$nav_path_bin"
cat >"$nav_path_bin/tmux-pane-should-passthrough" <<'SH'
#!/usr/bin/env bash
printf 'path:%s|%s\n' "${1:-}" "${2:-}" >>"${TMUX_NAV_PATH_LOG:?}"
exit 0
SH
chmod +x "$nav_path_bin/tmux-pane-should-passthrough"
HOME="$fake_home" "$real_tmux" -L "$socket_name" set-environment -g PATH "$nav_path_bin:/usr/bin:/bin:/usr/sbin:/sbin"
HOME="$fake_home" "$real_tmux" -L "$socket_name" set-environment -g TMUX_NAV_PATH_LOG "$nav_path_log"
HOME="$fake_home" "$real_tmux" -L "$socket_name" set-environment -gu HOME
# shellcheck disable=SC2016
HOME="$fake_home" "$real_tmux" -L "$socket_name" if-shell 'if [ -n "${HOME:-}" ]; then for helper in "$HOME/.local/bin/tmux-pane-should-passthrough" "$HOME/dotfiles/common/.local/bin/tmux-pane-should-passthrough"; do [ -x "$helper" ] && exec "$helper" #{q:pane_current_command} #{q:pane_tty}; done; fi; helper="$(command -v tmux-pane-should-passthrough 2>/dev/null)" && exec "$helper" #{q:pane_current_command} #{q:pane_tty}; exit 1' \
  'display-message helper-yes' \
  'display-message helper-no'
wait_for_file "$nav_path_log"
assert_contains "navigation helper falls back to PATH when HOME is unset" "$(cat "$nav_path_log")" "path:sleep|"
HOME="$fake_home" "$real_tmux" -L "$socket_name" set-environment -g HOME "$fake_home"
HOME="$fake_home" "$real_tmux" -L "$socket_name" set-environment -g PATH "$PATH"
rm -f "$nav_path_bin/tmux-pane-should-passthrough"

rm -f "$fake_home/.local/bin/tmux-pane-should-passthrough" "$fake_home/helper.log"
ln -s "$root/common/.local/bin/tmux-pane-should-passthrough" "$fake_home/.local/bin/tmux-pane-should-passthrough"
# shellcheck disable=SC2016
nav_if_shell='if [ -n "${HOME:-}" ]; then for helper in "$HOME/.local/bin/tmux-pane-should-passthrough" "$HOME/dotfiles/common/.local/bin/tmux-pane-should-passthrough"; do [ -x "$helper" ] && exec "$helper" #{q:pane_current_command} #{q:pane_tty}; done; fi; helper="$(command -v tmux-pane-should-passthrough 2>/dev/null)" && exec "$helper" #{q:pane_current_command} #{q:pane_tty}; exit 1'

HOME="$fake_home" "$real_tmux" -L "$socket_name" new-window -d -t =nav-test -n plain-nav 'sleep 60'
plain_left_pane="$(HOME="$fake_home" "$real_tmux" -L "$socket_name" list-panes -t =plain-nav -F '#{pane_id}')"
HOME="$fake_home" "$real_tmux" -L "$socket_name" split-window -h -t "$plain_left_pane" 'sleep 60'
plain_right_pane="$(HOME="$fake_home" "$real_tmux" -L "$socket_name" list-panes -t =plain-nav -F '#{pane_id}' | tail -n 1)"
HOME="$fake_home" "$real_tmux" -L "$socket_name" select-pane -t "$plain_right_pane"
HOME="$fake_home" "$real_tmux" -L "$socket_name" if-shell -t "$plain_right_pane" "$nav_if_shell" \
  "send-keys -t $plain_right_pane C-h" \
  "select-pane -t $plain_right_pane -L"
sleep 0.2
assert_eq "navigation selects left from a plain shell pane" "$plain_left_pane" "$(active_pane_in_window '=plain-nav')"

mock_ssh_ready="$tmp/mock-ssh.ready"
mock_ssh_port="$(start_mock_ssh_server "$mock_ssh_ready")"

HOME="$fake_home" "$real_tmux" -L "$socket_name" new-window -d -t =nav-test -n mock-ssh-nav 'sleep 60'
ssh_left_pane="$(HOME="$fake_home" "$real_tmux" -L "$socket_name" list-panes -t =mock-ssh-nav -F '#{pane_id}')"
HOME="$fake_home" "$real_tmux" -L "$socket_name" split-window -h -t "$ssh_left_pane" \
  "exec /usr/bin/ssh -F /dev/null -oBatchMode=yes -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oConnectTimeout=10 -p $mock_ssh_port 127.0.0.1"
ssh_right_pane="$(HOME="$fake_home" "$real_tmux" -L "$socket_name" list-panes -t =mock-ssh-nav -F '#{pane_id}' | tail -n 1)"
wait_for_pane_command "$ssh_right_pane" ssh
HOME="$fake_home" "$real_tmux" -L "$socket_name" select-pane -t "$ssh_right_pane"
HOME="$fake_home" "$real_tmux" -L "$socket_name" if-shell -t "$ssh_right_pane" "$nav_if_shell" \
  "send-keys -t $ssh_right_pane C-h" \
  "select-pane -t $ssh_right_pane -L"
sleep 0.2
assert_eq "navigation passes C-h through to a local mock ssh pane" "$ssh_right_pane" "$(active_pane_in_window '=mock-ssh-nav')"

mock_ssh_tunnel_ready="$tmp/mock-ssh-tunnel.ready"
mock_ssh_tunnel_server_port="$(start_mock_ssh_server "$mock_ssh_tunnel_ready")"
mock_ssh_tunnel_local_port="$(free_tcp_port)"

HOME="$fake_home" "$real_tmux" -L "$socket_name" new-window -d -t =nav-test -n mock-ssh-tunnel-nav 'sleep 60'
ssh_tunnel_left_pane="$(HOME="$fake_home" "$real_tmux" -L "$socket_name" list-panes -t =mock-ssh-tunnel-nav -F '#{pane_id}')"
HOME="$fake_home" "$real_tmux" -L "$socket_name" split-window -h -t "$ssh_tunnel_left_pane" \
  "exec /usr/bin/ssh -F /dev/null -oBatchMode=yes -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oConnectTimeout=10 -N -L $mock_ssh_tunnel_local_port:localhost:80 -p $mock_ssh_tunnel_server_port 127.0.0.1"
ssh_tunnel_right_pane="$(HOME="$fake_home" "$real_tmux" -L "$socket_name" list-panes -t =mock-ssh-tunnel-nav -F '#{pane_id}' | tail -n 1)"
wait_for_pane_command "$ssh_tunnel_right_pane" ssh
HOME="$fake_home" "$real_tmux" -L "$socket_name" select-pane -t "$ssh_tunnel_right_pane"
HOME="$fake_home" "$real_tmux" -L "$socket_name" if-shell -t "$ssh_tunnel_right_pane" "$nav_if_shell" \
  "send-keys -t $ssh_tunnel_right_pane C-h" \
  "select-pane -t $ssh_tunnel_right_pane -L"
sleep 0.2
assert_eq "navigation selects left from a local mock ssh tunnel pane" "$ssh_tunnel_left_pane" "$(active_pane_in_window '=mock-ssh-tunnel-nav')"

script_path="$(command -v script || true)"
if [[ -n "$script_path" ]] && "$script_path" -q "$tmp/script-probe.log" /bin/sh -c 'exit 0' >/dev/null 2>&1; then
  script_mock_ssh_ready="$tmp/script-mock-ssh.ready"
  script_mock_ssh_port="$(start_mock_ssh_server "$script_mock_ssh_ready")"
  HOME="$fake_home" "$real_tmux" -L "$socket_name" new-window -d -t =nav-test -n script-ssh-nav 'sleep 60'
  script_left_pane="$(HOME="$fake_home" "$real_tmux" -L "$socket_name" list-panes -t =script-ssh-nav -F '#{pane_id}')"
  printf -v script_ssh_command \
    'exec %q -q /dev/null /usr/bin/ssh -F /dev/null -oBatchMode=yes -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oConnectTimeout=10 -p %s 127.0.0.1' \
    "$script_path" \
    "$script_mock_ssh_port"
  HOME="$fake_home" "$real_tmux" -L "$socket_name" split-window -h -t "$script_left_pane" "$script_ssh_command"
  script_right_pane="$(HOME="$fake_home" "$real_tmux" -L "$socket_name" list-panes -t =script-ssh-nav -F '#{pane_id}' | tail -n 1)"
  wait_for_pane_command "$script_right_pane" "$(basename "$script_path")"
  HOME="$fake_home" "$real_tmux" -L "$socket_name" select-pane -t "$script_right_pane"
  HOME="$fake_home" "$real_tmux" -L "$socket_name" if-shell -t "$script_right_pane" "$nav_if_shell" \
    "send-keys -t $script_right_pane C-h" \
    "select-pane -t $script_right_pane -L"
  sleep 0.2
  assert_eq "navigation passes C-h through to a script-wrapped local mock ssh pane" "$script_right_pane" "$(active_pane_in_window '=script-ssh-nav')"
else
  printf 'ok - navigation skips script-wrapped local mock ssh pane when script command form is unavailable\n'
fi

new_window_binding="$("$real_tmux" -L "$socket_name" list-keys -T prefix c)"
assert_contains "new-window uses current pane path" "$new_window_binding" '-c "#{pane_current_path}"'

horizontal_split_binding="$("$real_tmux" -L "$socket_name" list-keys -T prefix %)"
assert_contains "standard horizontal split uses current pane path" "$horizontal_split_binding" '-c "#{pane_current_path}"'

vertical_split_binding="$("$real_tmux" -L "$socket_name" list-keys -T prefix '"')"
assert_contains "standard vertical split uses current pane path" "$vertical_split_binding" '-c "#{pane_current_path}"'

move_window_left_binding="$("$real_tmux" -L "$socket_name" list-keys -T prefix '<')"
assert_contains "window move left uses native swap" "$move_window_left_binding" "swap-window -d -t :-1"
assert_not_contains "window move left avoids run-shell" "$move_window_left_binding" "run-shell"

move_window_right_binding="$("$real_tmux" -L "$socket_name" list-keys -T prefix '>')"
assert_contains "window move right uses native swap" "$move_window_right_binding" "swap-window -d -t :+1"
assert_not_contains "window move right avoids run-shell" "$move_window_right_binding" "run-shell"

HOME="$fake_home" "$real_tmux" -L "$socket_name" new-session -d -s swap-nav -n one 'sleep 60'
HOME="$fake_home" "$real_tmux" -L "$socket_name" new-window -d -t =swap-nav -n two 'sleep 60'
HOME="$fake_home" "$real_tmux" -L "$socket_name" new-window -d -t =swap-nav -n three 'sleep 60'
two_window_id="$(
  HOME="$fake_home" "$real_tmux" -L "$socket_name" list-windows -t =swap-nav -F '#{window_name}:#{window_id}' |
    awk -F: '$1 == "two" { print $2; exit }'
)"
HOME="$fake_home" "$real_tmux" -L "$socket_name" select-window -t "$two_window_id"
HOME="$fake_home" "$real_tmux" -L "$socket_name" swap-window -d -t:-1
assert_eq \
  "window move left keeps moved window active" \
  "$two_window_id" \
  "$(HOME="$fake_home" "$real_tmux" -L "$socket_name" display-message -p '#{window_id}')"
assert_contains \
  "window move left moves active window earlier" \
  "$(HOME="$fake_home" "$real_tmux" -L "$socket_name" list-windows -t =swap-nav -F '#{window_index}:#{window_name}:#{window_active}')" \
  "1:two:1"
HOME="$fake_home" "$real_tmux" -L "$socket_name" swap-window -d -t:+1
assert_eq \
  "window move right keeps moved window active" \
  "$two_window_id" \
  "$(HOME="$fake_home" "$real_tmux" -L "$socket_name" display-message -p '#{window_id}')"
assert_contains \
  "window move right moves active window later" \
  "$(HOME="$fake_home" "$real_tmux" -L "$socket_name" list-windows -t =swap-nav -F '#{window_index}:#{window_name}:#{window_active}')" \
  "2:two:1"

paste_binding="$("$real_tmux" -L "$socket_name" list-keys -T prefix p)"
assert_contains "paste binding uses helper" "$paste_binding" "tmux-paste-helper"
assert_contains "paste binding uses explicit home" "$paste_binding" "$home_marker"
assert_contains "paste binding has repo fallback" "$paste_binding" "$repo_marker"
assert_contains "paste binding has PATH fallback" "$paste_binding" "command -v tmux-paste-helper"
assert_contains "paste binding guards unset HOME" "$paste_binding" "$home_guard"
assert_contains "paste binding targets current pane" "$paste_binding" '#{pane_id}'
assert_contains "paste binding displays missing helper" "$paste_binding" "display-message"
assert_contains "paste binding reports missing helper to stderr" "$paste_binding" ">&2; exit 127"
assert_contains "paste binding exits non-zero without helper" "$paste_binding" "exit 127"

paste_binding_log="$fake_home/paste-binding.log"
cat >"$fake_home/.local/bin/tmux-paste-helper" <<'SH'
#!/usr/bin/env bash
printf 'args=%s\n' "$*" >"$HOME/paste-binding.log"
SH
chmod +x "$fake_home/.local/bin/tmux-paste-helper"
paste_binding_window="$(
  HOME="$fake_home" "$real_tmux" -L "$socket_name" new-window -d -t =nav-test -n paste-binding -P -F '#{window_id}' 'sleep 60'
)"
paste_binding_pane="$(
  HOME="$fake_home" "$real_tmux" -L "$socket_name" list-panes -t "$paste_binding_window" -F '#{pane_id}' |
    awk 'NR == 1 { print; exit }'
)"
# shellcheck disable=SC2016
paste_binding_run_shell='if [ -n "${HOME:-}" ]; then for helper in "$HOME/.local/bin/tmux-paste-helper" "$HOME/dotfiles/common/.local/bin/tmux-paste-helper"; do [ -x "$helper" ] && exec "$helper" "#{pane_id}"; done; fi; helper="$(command -v tmux-paste-helper 2>/dev/null)" && exec "$helper" "#{pane_id}"; command -v tmux >/dev/null 2>&1 && tmux display-message "tmux-paste-helper unavailable" 2>/dev/null; echo "tmux-paste-helper unavailable" >&2; exit 127'
HOME="$fake_home" "$real_tmux" -L "$socket_name" run-shell -b -t "$paste_binding_pane" "$paste_binding_run_shell"
wait_for_file "$paste_binding_log"
assert_eq \
  "paste binding live command passes current pane id to helper" \
  "args=$paste_binding_pane" \
  "$(cat "$paste_binding_log")"

rm -f "$fake_home/.local/bin/tmux-paste-helper"
path_paste_path="$tmp/path-paste-path"
path_paste_log="$tmp/path-paste.log"
mkdir -p "$path_paste_path"
cat >"$path_paste_path/tmux-paste-helper" <<'SH'
#!/usr/bin/env bash
printf 'args=%s\n' "$*" >"${TMUX_NAV_PATH_PASTE_LOG:?}"
SH
chmod +x "$path_paste_path/tmux-paste-helper"
HOME="$fake_home" "$real_tmux" -L "$socket_name" set-environment -g PATH "$path_paste_path:/usr/bin:/bin:/usr/sbin:/sbin"
HOME="$fake_home" "$real_tmux" -L "$socket_name" set-environment -g TMUX_NAV_PATH_PASTE_LOG "$path_paste_log"
HOME="$fake_home" "$real_tmux" -L "$socket_name" set-environment -gu HOME
HOME="$fake_home" "$real_tmux" -L "$socket_name" run-shell -b -t "$paste_binding_pane" "$paste_binding_run_shell"
wait_for_file "$path_paste_log"
assert_eq \
  "paste binding falls back to PATH when HOME is unset" \
  "args=$paste_binding_pane" \
  "$(cat "$path_paste_log")"
HOME="$fake_home" "$real_tmux" -L "$socket_name" set-environment -g HOME "$fake_home"

missing_paste_path="$tmp/missing-paste-path"
missing_paste_display_log="$tmp/missing-paste-display.log"
missing_paste_trace_log="$tmp/missing-paste-trace.log"
mkdir -p "$missing_paste_path"
ln -s "$(command -v bash)" "$missing_paste_path/bash"
cat >"$missing_paste_path/tmux" <<'SH'
#!/usr/bin/env bash
printf 'tmux %s\n' "$*" >>"${TMUX_NAV_MISSING_PASTE_TRACE_LOG:?}"
if [[ "${1:-}" == "display-message" ]]; then
  shift
  printf '%s\n' "$*" >"${TMUX_NAV_MISSING_PASTE_DISPLAY_LOG:?}"
  exit 0
fi
exit 2
SH
chmod +x "$missing_paste_path/tmux"
HOME="$fake_home" "$real_tmux" -L "$socket_name" set-environment -g PATH "$missing_paste_path"
HOME="$fake_home" "$real_tmux" -L "$socket_name" set-environment -g TMUX_NAV_MISSING_PASTE_DISPLAY_LOG "$missing_paste_display_log"
HOME="$fake_home" "$real_tmux" -L "$socket_name" set-environment -g TMUX_NAV_MISSING_PASTE_TRACE_LOG "$missing_paste_trace_log"
HOME="$fake_home" "$real_tmux" -L "$socket_name" run-shell -b -t "$paste_binding_pane" "$paste_binding_run_shell"
wait_for_file "$missing_paste_display_log"
assert_eq \
  "paste binding missing helper displays tmux message" \
  "tmux-paste-helper unavailable" \
  "$(cat "$missing_paste_display_log")"
assert_contains \
  "paste binding missing helper calls tmux display-message" \
  "$(cat "$missing_paste_trace_log")" \
  "tmux display-message tmux-paste-helper unavailable"

unset_home_paste_display_log="$tmp/unset-home-paste-display.log"
unset_home_paste_trace_log="$tmp/unset-home-paste-trace.log"
HOME="$fake_home" "$real_tmux" -L "$socket_name" set-environment -g TMUX_NAV_MISSING_PASTE_DISPLAY_LOG "$unset_home_paste_display_log"
HOME="$fake_home" "$real_tmux" -L "$socket_name" set-environment -g TMUX_NAV_MISSING_PASTE_TRACE_LOG "$unset_home_paste_trace_log"
HOME="$fake_home" "$real_tmux" -L "$socket_name" set-environment -gu HOME
HOME="$fake_home" "$real_tmux" -L "$socket_name" run-shell -b -t "$paste_binding_pane" "$paste_binding_run_shell"
wait_for_file "$unset_home_paste_display_log"
assert_eq \
  "paste binding with unset HOME displays missing helper" \
  "tmux-paste-helper unavailable" \
  "$(cat "$unset_home_paste_display_log")"
assert_contains \
  "paste binding with unset HOME calls tmux display-message" \
  "$(cat "$unset_home_paste_trace_log")" \
  "tmux display-message tmux-paste-helper unavailable"
HOME="$fake_home" "$real_tmux" -L "$socket_name" set-environment -g HOME "$fake_home"

for copy_table in copy-mode-vi copy-mode; do
  for copy_key in Enter y MouseDragEnd1Pane DoubleClick1Pane TripleClick1Pane; do
    copy_binding="$("$real_tmux" -L "$socket_name" list-keys -T "$copy_table" "$copy_key")"
    assert_contains "$copy_table $copy_key uses copy helper" "$copy_binding" "tmux-copy-helper"
    assert_contains "$copy_table $copy_key uses explicit home" "$copy_binding" "$home_marker"
    assert_contains "$copy_table $copy_key has repo fallback" "$copy_binding" "$repo_marker"
    assert_contains "$copy_table $copy_key has PATH fallback" "$copy_binding" "command -v tmux-copy-helper"
    assert_contains "$copy_table $copy_key guards unset HOME" "$copy_binding" "$home_guard"
    assert_contains "$copy_table $copy_key displays missing helper" "$copy_binding" "display-message"
  done
done

session_picker_binding="$("$real_tmux" -L "$socket_name" list-keys -T prefix s)"
assert_contains "session picker uses helper" "$session_picker_binding" "tmux-fzf-switch-session"
assert_contains "session picker uses explicit home" "$session_picker_binding" "$home_marker"
assert_contains "session picker has repo fallback" "$session_picker_binding" "$repo_marker"
assert_contains "session picker has PATH fallback" "$session_picker_binding" "command -v tmux-fzf-switch-session"
assert_contains "session picker guards unset HOME" "$session_picker_binding" "$home_guard"

git_popup_binding="$("$real_tmux" -L "$socket_name" list-keys -T prefix g)"
assert_contains "git popup uses helper" "$git_popup_binding" "tmux-popup-tool"
assert_contains "git popup uses explicit home" "$git_popup_binding" "$home_marker"
assert_contains "git popup has repo fallback" "$git_popup_binding" "$repo_marker"
assert_contains "git popup has PATH fallback" "$git_popup_binding" "command -v tmux-popup-tool"
assert_contains "git popup guards unset HOME" "$git_popup_binding" "$home_guard"
assert_contains "git popup shell-quotes current pane path" "$git_popup_binding" '#{q:pane_current_path}'
assert_contains "git popup prefers lazygit" "$git_popup_binding" "lazygit"
assert_contains "git popup falls back to gitui" "$git_popup_binding" "gitui"

file_popup_binding="$("$real_tmux" -L "$socket_name" list-keys -T prefix e)"
assert_contains "file popup uses helper" "$file_popup_binding" "tmux-popup-tool"
assert_contains "file popup uses explicit home" "$file_popup_binding" "$home_marker"
assert_contains "file popup has repo fallback" "$file_popup_binding" "$repo_marker"
assert_contains "file popup has PATH fallback" "$file_popup_binding" "command -v tmux-popup-tool"
assert_contains "file popup guards unset HOME" "$file_popup_binding" "$home_guard"
assert_contains "file popup shell-quotes current pane path" "$file_popup_binding" '#{q:pane_current_path}'
assert_contains "file popup prefers yazi" "$file_popup_binding" "yazi"
assert_contains "file popup falls back to lf" "$file_popup_binding" "lf"
assert_contains "file popup falls back to ranger" "$file_popup_binding" "ranger"
assert_contains "file popup falls back to nnn" "$file_popup_binding" "nnn"

url_picker_binding="$("$real_tmux" -L "$socket_name" list-keys -T prefix u)"
assert_contains "url picker uses helper" "$url_picker_binding" "tmux-fzf-url.sh"
assert_contains "url picker uses explicit home" "$url_picker_binding" "$home_marker"
assert_contains "url picker has repo fallback" "$url_picker_binding" "$repo_marker"
assert_contains "url picker has PATH fallback" "$url_picker_binding" "command -v tmux-fzf-url.sh"
assert_contains "url picker guards unset HOME" "$url_picker_binding" "$home_guard"

deep_url_picker_binding="$("$real_tmux" -L "$socket_name" list-keys -T prefix C-u)"
assert_contains "deep url picker uses helper" "$deep_url_picker_binding" "tmux-fzf-url.sh"
assert_contains "deep url picker uses explicit home" "$deep_url_picker_binding" "$home_marker"
assert_contains "deep url picker has repo fallback" "$deep_url_picker_binding" "$repo_marker"
assert_contains "deep url picker has PATH fallback" "$deep_url_picker_binding" "command -v tmux-fzf-url.sh"
assert_contains "deep url picker guards unset HOME" "$deep_url_picker_binding" "$home_guard"
assert_contains "deep url picker increases history" "$deep_url_picker_binding" "TMUX_FZF_URL_HISTORY_LINES=10000"
assert_not_contains "deep url picker avoids env launcher" "$deep_url_picker_binding" "exec env "

deep_url_log="$fake_home/deep-url.log"
no_env_path="$tmp/no-env-path"
mkdir -p "$no_env_path"
cat >"$fake_home/.local/bin/tmux-fzf-url.sh" <<'SH'
#!/bin/sh
printf 'history=%s\n' "${TMUX_FZF_URL_HISTORY_LINES-}" >"$HOME/deep-url.log"
SH
chmod +x "$fake_home/.local/bin/tmux-fzf-url.sh"
"$real_tmux" -L "$socket_name" set-environment -g PATH "$no_env_path"
# shellcheck disable=SC2016
deep_url_run_shell='if [ -n "${HOME:-}" ]; then for helper in "$HOME/.local/bin/tmux-fzf-url.sh" "$HOME/dotfiles/common/.local/bin/tmux-fzf-url.sh"; do [ -x "$helper" ] && TMUX_FZF_URL_HISTORY_LINES=10000 exec "$helper"; done; fi; helper="$(command -v tmux-fzf-url.sh 2>/dev/null)" && TMUX_FZF_URL_HISTORY_LINES=10000 exec "$helper"; tmux display-message "tmux-fzf-url unavailable"'
"$real_tmux" -L "$socket_name" run-shell -b "$deep_url_run_shell"
wait_for_file "$deep_url_log"
assert_eq "deep url picker runs without env in PATH" "history=10000" "$(cat "$deep_url_log")"
"$real_tmux" -L "$socket_name" set-environment -g PATH "$PATH"

project_session_binding="$("$real_tmux" -L "$socket_name" list-keys -T prefix S)"
assert_contains "project session binding uses tmux-session notify" "$project_session_binding" "tmux-session-notify"
assert_contains "project session binding passes start dir" "$project_session_binding" "--start-dir"
assert_contains "project session binding uses explicit home" "$project_session_binding" "$home_marker"
assert_contains "project session binding has repo fallback" "$project_session_binding" "$repo_marker"
assert_contains "project session binding has PATH fallback" "$project_session_binding" "command -v tmux-session-notify"
assert_contains "project session binding guards unset HOME" "$project_session_binding" "$home_guard"
assert_contains "project session binding shell-quotes current pane path" "$project_session_binding" '#{q:pane_current_path}'

project_resume_binding="$("$real_tmux" -L "$socket_name" list-keys -T prefix R)"
assert_contains "project resume binding uses tmux-session notify" "$project_resume_binding" "tmux-session-notify"
assert_contains "project resume binding passes window" "$project_resume_binding" "--window resume"
assert_contains "project resume binding uses explicit home" "$project_resume_binding" "$home_marker"
assert_contains "project resume binding has repo fallback" "$project_resume_binding" "$repo_marker"
assert_contains "project resume binding has PATH fallback" "$project_resume_binding" "command -v tmux-session-notify"
assert_contains "project resume binding guards unset HOME" "$project_resume_binding" "$home_guard"
assert_contains "project resume binding shell-quotes current pane path" "$project_resume_binding" '#{q:pane_current_path}'

project_ai_binding="$("$real_tmux" -L "$socket_name" list-keys -T prefix A)"
assert_contains "project ai binding uses tmux-session notify" "$project_ai_binding" "tmux-session-notify"
assert_contains "project ai binding passes window" "$project_ai_binding" "--window agent"
assert_contains "project ai binding uses explicit home" "$project_ai_binding" "$home_marker"
assert_contains "project ai binding has repo fallback" "$project_ai_binding" "$repo_marker"
assert_contains "project ai binding has PATH fallback" "$project_ai_binding" "command -v tmux-session-notify"
assert_contains "project ai binding guards unset HOME" "$project_ai_binding" "$home_guard"
assert_contains "project ai binding shell-quotes current pane path" "$project_ai_binding" '#{q:pane_current_path}'

project_terminal_binding="$("$real_tmux" -L "$socket_name" list-keys -T prefix T)"
assert_contains "project terminal binding uses tmux-session notify" "$project_terminal_binding" "tmux-session-notify"
assert_contains "project terminal binding passes window" "$project_terminal_binding" "--window terminal"
assert_contains "project terminal binding uses explicit home" "$project_terminal_binding" "$home_marker"
assert_contains "project terminal binding has repo fallback" "$project_terminal_binding" "$repo_marker"
assert_contains "project terminal binding has PATH fallback" "$project_terminal_binding" "command -v tmux-session-notify"
assert_contains "project terminal binding guards unset HOME" "$project_terminal_binding" "$home_guard"
assert_contains "project terminal binding shell-quotes current pane path" "$project_terminal_binding" '#{q:pane_current_path}'

automatic_rename_format="$("$real_tmux" -L "$socket_name" show-window-options -gv automatic-rename-format)"
assert_contains "automatic rename uses tmux-status helper" "$automatic_rename_format" "tmux-status-name.sh"
assert_contains "automatic rename uses explicit home" "$automatic_rename_format" "$home_marker"
assert_contains "automatic rename has repo fallback" "$automatic_rename_format" "$repo_marker"
assert_contains "automatic rename has PATH fallback" "$automatic_rename_format" "command -v tmux-status-name.sh"
assert_contains "automatic rename guards unset HOME" "$automatic_rename_format" "$home_guard_raw"
assert_contains "automatic rename shell-quotes current pane path" "$automatic_rename_format" '#{q:pane_current_path}'
assert_contains "automatic rename shell-quotes current command" "$automatic_rename_format" '#{q:pane_current_command}'

cat >"$fake_home/.local/bin/tmux-popup-tool" <<'SH'
#!/usr/bin/env bash
{
  printf 'argc=%s\n' "$#"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
  printf -- '---\n'
} >>"$HOME/popup.log"
SH
chmod +x "$fake_home/.local/bin/tmux-popup-tool"

weird_dir="$tmp/path with spaces \$(touch INJECTED) ' \" ; \$HOME"
mkdir -p "$weird_dir"
HOME="$fake_home" "$real_tmux" -L "$socket_name" new-window -d -t =nav-test -n weird -c "$weird_dir" 'sleep 60'
weird_pane="$(
  "$real_tmux" -L "$socket_name" list-panes -a -F $'#{window_name}\t#{pane_id}' |
    awk -F $'\t' '$1 == "weird" { print $2; exit }'
)"
actual_weird_dir="$("$real_tmux" -L "$socket_name" display-message -p -t "$weird_pane" '#{pane_current_path}')"
printf -v popup_helper_command '%q' "$fake_home/.local/bin/tmux-popup-tool"

# shellcheck disable=SC2016
HOME="$fake_home" "$real_tmux" -L "$socket_name" run-shell -b -t "$weird_pane" "$popup_helper_command --start-dir #{q:pane_current_path} --title git lazygit gitui"
wait_for_file "$fake_home/popup.log"
assert_eq \
  "quoted run-shell start-dir preserves metacharacter path" \
  "$(printf 'argc=6\narg=--start-dir\narg=%s\narg=--title\narg=git\narg=lazygit\narg=gitui\n---' "$actual_weird_dir")" \
  "$(cat "$fake_home/popup.log")"
assert_file_absent "quoted run-shell start-dir does not run command substitution" "$tmp/INJECTED"

rm -f "$fake_home/.local/bin/tmux-popup-tool" "$fake_home/popup.log"
cat >"$fake_home/dotfiles/common/.local/bin/tmux-popup-tool" <<'SH'
#!/usr/bin/env bash
{
  printf 'argc=%s\n' "$#"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
  printf -- '---\n'
} >>"$HOME/popup.log"
SH
chmod +x "$fake_home/dotfiles/common/.local/bin/tmux-popup-tool"

# shellcheck disable=SC2016
HOME="$fake_home" "$real_tmux" -L "$socket_name" run-shell -b -t "$weird_pane" 'if [ -n "${HOME:-}" ]; then for helper in "$HOME/.local/bin/tmux-popup-tool" "$HOME/dotfiles/common/.local/bin/tmux-popup-tool"; do [ -x "$helper" ] && exec "$helper" --start-dir #{q:pane_current_path} --title git lazygit gitui; done; fi; helper="$(command -v tmux-popup-tool 2>/dev/null)" && exec "$helper" --start-dir #{q:pane_current_path} --title git lazygit gitui; tmux display-message "tmux-popup-tool unavailable"'
wait_for_file "$fake_home/popup.log"
assert_eq \
  "quoted run-shell start-dir works through repo fallback" \
  "$(printf 'argc=6\narg=--start-dir\narg=%s\narg=--title\narg=git\narg=lazygit\narg=gitui\n---' "$actual_weird_dir")" \
  "$(cat "$fake_home/popup.log")"
assert_file_absent "repo fallback start-dir does not run command substitution" "$tmp/INJECTED"

resurrect_processes="$("$real_tmux" -L "$socket_name" show-options -gqv @resurrect-processes)"
for process in lazygit gitui tig lazydocker k9s btop yazi lf ranger nnn; do
  assert_contains "resurrect restores $process" "$resurrect_processes" "$process"
done
assert_not_contains "resurrect does not restore every process" "$resurrect_processes" ":all:"
