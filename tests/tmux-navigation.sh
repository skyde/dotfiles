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

assert_contains_home_guard() {
  local name="$1"
  local haystack="$2"

  if [[ "$haystack" == *"$home_guard"* || "$haystack" == *"$home_guard_tmux34"* ]]; then
    printf 'ok - %s\n' "$name"
    return 0
  fi

  printf 'not ok - %s\n' "$name" >&2
  printf 'missing one of:\n%s\n%s\n' "$home_guard" "$home_guard_tmux34" >&2
  printf 'actual:\n%s\n' "$haystack" >&2
  return 1
}

assert_contains_home_guard_raw() {
  local name="$1"
  local haystack="$2"

  if [[ "$haystack" == *"$home_guard_raw"* || "$haystack" == *"$home_guard_raw_escaped"* ]]; then
    printf 'ok - %s\n' "$name"
    return 0
  fi

  printf 'not ok - %s\n' "$name" >&2
  printf 'missing one of:\n%s\n%s\n' "$home_guard_raw" "$home_guard_raw_escaped" >&2
  printf 'actual:\n%s\n' "$haystack" >&2
  return 1
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
home_guard_tmux34="[ -n \\\"\\\\\${HOME:-}\\\" ]"
# shellcheck disable=SC2016
home_guard_raw='[ -n "${HOME:-}" ]'
# shellcheck disable=SC2016
home_guard_raw_escaped='[ -n "\${HOME:-}" ]'

for key in C-h C-j C-k C-l "C-\\"; do
  binding="$("$real_tmux" -L "$socket_name" list-keys -T root "$key")"
  case "$key" in
    C-h) router_action="nav-left" ;;
    C-j) router_action="nav-down" ;;
    C-k) router_action="nav-up" ;;
    C-l) router_action="nav-right" ;;
    "C-\\") router_action="nav-last" ;;
  esac
  assert_contains "navigation passthrough uses key router for $key" "$binding" "tmux-pane-key-router"
  assert_contains "navigation passthrough uses explicit router home for $key" "$binding" "$home_marker"
  assert_contains "navigation passthrough has router repo fallback for $key" "$binding" "$repo_marker"
  assert_contains "navigation passthrough has router PATH fallback for $key" "$binding" "command -v tmux-pane-key-router"
  assert_contains_home_guard "navigation passthrough guards unset HOME for $key" "$binding"
  assert_contains "navigation passthrough passes router action for $key" "$binding" "$router_action"
  assert_contains "navigation passthrough passes current pane for $key" "$binding" '#{pane_id}'
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

mock_ssh_ctrl_insert_log="$tmp/mock-ssh-ctrl-insert.log"
mock_ssh_shift_delete_log="$tmp/mock-ssh-shift-delete.log"
printf -v mock_ssh_ctrl_insert_log_q '%q' "$mock_ssh_ctrl_insert_log"
printf -v mock_ssh_shift_delete_log_q '%q' "$mock_ssh_shift_delete_log"
HOME="$fake_home" "$real_tmux" -L "$socket_name" if-shell -t "$ssh_right_pane" "$nav_if_shell" \
  "run-shell -b \"printf '%s\n' copy-passthrough > $mock_ssh_ctrl_insert_log_q\"" \
  "select-pane -t $ssh_right_pane -L"
wait_for_file "$mock_ssh_ctrl_insert_log"
assert_eq "Ctrl-Insert copy helper selects passthrough for a local mock ssh pane" "copy-passthrough" "$(cat "$mock_ssh_ctrl_insert_log")"
assert_eq "Ctrl-Insert copy decision keeps local mock ssh pane active" "$ssh_right_pane" "$(active_pane_in_window '=mock-ssh-nav')"
HOME="$fake_home" "$real_tmux" -L "$socket_name" if-shell -t "$ssh_right_pane" "$nav_if_shell" \
  "run-shell -b \"printf '%s\n' cut-passthrough > $mock_ssh_shift_delete_log_q\"" \
  "select-pane -t $ssh_right_pane -L"
wait_for_file "$mock_ssh_shift_delete_log"
assert_eq "Shift-Delete cut helper selects passthrough for a local mock ssh pane" "cut-passthrough" "$(cat "$mock_ssh_shift_delete_log")"
assert_eq "Shift-Delete cut decision keeps local mock ssh pane active" "$ssh_right_pane" "$(active_pane_in_window '=mock-ssh-nav')"

mock_ssh_shift_insert_log="$tmp/mock-ssh-shift-insert.log"
cat >"$fake_home/.local/bin/tmux-paste-helper" <<'SH'
#!/usr/bin/env bash
printf 'args=%s\n' "$*" >"${TMUX_NAV_MOCK_SSH_PASTE_LOG:?}"
SH
chmod +x "$fake_home/.local/bin/tmux-paste-helper"
HOME="$fake_home" "$real_tmux" -L "$socket_name" set-environment -g TMUX_NAV_MOCK_SSH_PASTE_LOG "$mock_ssh_shift_insert_log"
# shellcheck disable=SC2016
shift_insert_if_shell='if [ -n "${HOME:-}" ]; then for helper in "$HOME/.local/bin/tmux-pane-should-passthrough" "$HOME/dotfiles/common/.local/bin/tmux-pane-should-passthrough"; do [ -x "$helper" ] && exec "$helper" --paste-key #{q:pane_current_command} #{q:pane_tty}; done; fi; helper="$(command -v tmux-pane-should-passthrough 2>/dev/null)" && exec "$helper" --paste-key #{q:pane_current_command} #{q:pane_tty}; exit 1'
HOME="$fake_home" "$real_tmux" -L "$socket_name" if-shell -t "$ssh_right_pane" "$shift_insert_if_shell" \
  "select-pane -t $ssh_right_pane -L" \
  "run-shell -b -t $ssh_right_pane '\$HOME/.local/bin/tmux-paste-helper #{pane_id}'"
wait_for_file "$mock_ssh_shift_insert_log"
assert_eq "Shift-Insert paste-key helper selects tmux paste helper for a local mock ssh pane" "args=$ssh_right_pane" "$(cat "$mock_ssh_shift_insert_log")"
assert_eq "Shift-Insert paste decision keeps local mock ssh pane active" "$ssh_right_pane" "$(active_pane_in_window '=mock-ssh-nav')"
rm -f "$fake_home/.local/bin/tmux-paste-helper"

container_router_path="$tmp/container-router-path"
container_router_paste_log="$tmp/container-router-paste.log"
container_router_ps_log="$tmp/container-router-ps.log"
container_router_tmux_log="$tmp/container-router-tmux.log"
mkdir -p "$container_router_path"
cat >"$container_router_path/ps" <<'SH'
#!/usr/bin/env bash
printf 'ps %s\n' "$*" >"${TMUX_NAV_CONTAINER_ROUTER_PS_LOG:?}"
printf '%s\n' \
  'S+ /bin/zsh /bin/zsh' \
  'S+ /usr/local/bin/docker /usr/local/bin/docker attach app'
SH
chmod +x "$container_router_path/ps"
cat >"$container_router_path/tmux" <<'SH'
#!/usr/bin/env bash
{
  printf 'tmux'
  printf ' %s' "$@"
  printf '\n'
} >>"${TMUX_NAV_CONTAINER_ROUTER_TMUX_LOG:?}"
SH
chmod +x "$container_router_path/tmux"
cat >"$fake_home/.local/bin/tmux-paste-helper" <<'SH'
#!/usr/bin/env bash
printf 'args=%s\n' "$*" >"${TMUX_NAV_CONTAINER_ROUTER_PASTE_LOG:?}"
SH
chmod +x "$fake_home/.local/bin/tmux-paste-helper"

env \
  HOME="$fake_home" \
  PATH="$container_router_path:/usr/bin:/bin" \
  TMUX_NAV_CONTAINER_ROUTER_PASTE_LOG="$container_router_paste_log" \
  TMUX_NAV_CONTAINER_ROUTER_PS_LOG="$container_router_ps_log" \
  TMUX_NAV_CONTAINER_ROUTER_TMUX_LOG="$container_router_tmux_log" \
  "$root/common/.local/bin/tmux-pane-key-router" shift-insert %container zsh /dev/ttys001
wait_for_file "$container_router_paste_log"
assert_eq \
  "Shift-Insert router uses tmux paste helper for foreground docker attach" \
  "args=%container" \
  "$(cat "$container_router_paste_log")"
assert_contains \
  "Shift-Insert router inspects foreground docker attach pane tty" \
  "$(cat "$container_router_ps_log")" \
  "-t ttys001"
assert_not_contains \
  "Shift-Insert router avoids raw Shift-Insert bytes for foreground docker attach" \
  "$(cat "$container_router_tmux_log" 2>/dev/null || true)" \
  "send-keys -t %container -H 1b 5b 32 3b 32 7e"

rm -f "$container_router_paste_log" "$container_router_ps_log" "$container_router_tmux_log"
env \
  HOME="$fake_home" \
  PATH="$container_router_path:/usr/bin:/bin" \
  TMUX_NAV_CONTAINER_ROUTER_PASTE_LOG="$container_router_paste_log" \
  TMUX_NAV_CONTAINER_ROUTER_PS_LOG="$container_router_ps_log" \
  TMUX_NAV_CONTAINER_ROUTER_TMUX_LOG="$container_router_tmux_log" \
  "$root/common/.local/bin/tmux-pane-key-router" nav-left %container zsh /dev/ttys001
wait_for_file "$container_router_tmux_log"
assert_contains \
  "navigation router passes C-h through to foreground docker attach" \
  "$(cat "$container_router_tmux_log")" \
  "tmux send-keys -t %container C-h"
assert_file_absent \
  "navigation router does not use paste helper for foreground docker attach" \
  "$container_router_paste_log"
rm -f "$fake_home/.local/bin/tmux-paste-helper"

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
assert_contains_home_guard "paste binding guards unset HOME" "$paste_binding"
assert_contains "paste binding targets current pane" "$paste_binding" '#{pane_id}'
assert_contains "paste binding displays missing helper" "$paste_binding" "display-message"
assert_contains "paste binding reports missing helper to stderr" "$paste_binding" ">&2; exit 127"
assert_contains "paste binding exits non-zero without helper" "$paste_binding" "exit 127"

shift_insert_paste_binding="$("$real_tmux" -L "$socket_name" list-keys -T root S-IC)"
assert_contains "Shift-Insert paste binding uses key router" "$shift_insert_paste_binding" "tmux-pane-key-router"
assert_contains "Shift-Insert paste binding passes router action" "$shift_insert_paste_binding" "shift-insert"
assert_contains "Shift-Insert paste binding uses explicit home" "$shift_insert_paste_binding" "$home_marker"
assert_contains "Shift-Insert paste binding has repo fallback" "$shift_insert_paste_binding" "$repo_marker"
assert_contains "Shift-Insert paste binding has PATH fallback" "$shift_insert_paste_binding" "command -v tmux-pane-key-router"
assert_contains_home_guard "Shift-Insert paste binding guards unset HOME" "$shift_insert_paste_binding"
assert_contains "Shift-Insert paste binding targets current pane" "$shift_insert_paste_binding" '#{pane_id}'
assert_contains "Shift-Insert paste binding uses async router" "$shift_insert_paste_binding" 'run-shell -b'
assert_contains "Shift-Insert paste binding shell-quotes current command" "$shift_insert_paste_binding" '#{q:pane_current_command}'
assert_contains "Shift-Insert paste binding shell-quotes pane tty" "$shift_insert_paste_binding" '#{q:pane_tty}'

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

ctrl_insert_binding="$("$real_tmux" -L "$socket_name" list-keys -T root C-IC)"
assert_contains "Ctrl-Insert root binding uses key router" "$ctrl_insert_binding" "tmux-pane-key-router"
assert_contains "Ctrl-Insert root binding passes router action" "$ctrl_insert_binding" "ctrl-insert"
assert_not_contains "Ctrl-Insert root binding does not use paste-key mode" "$ctrl_insert_binding" "--paste-key"
assert_contains "Ctrl-Insert root binding uses explicit home" "$ctrl_insert_binding" "$home_marker"
assert_contains "Ctrl-Insert root binding has repo fallback" "$ctrl_insert_binding" "$repo_marker"
assert_contains "Ctrl-Insert root binding has PATH fallback" "$ctrl_insert_binding" "command -v tmux-pane-key-router"
assert_contains_home_guard "Ctrl-Insert root binding guards unset HOME" "$ctrl_insert_binding"
assert_contains "Ctrl-Insert root binding uses async router" "$ctrl_insert_binding" 'run-shell -b'
assert_contains "Ctrl-Insert root binding shell-quotes current command" "$ctrl_insert_binding" '#{q:pane_current_command}'
assert_contains "Ctrl-Insert root binding shell-quotes pane tty" "$ctrl_insert_binding" '#{q:pane_tty}'
assert_contains "Ctrl-Insert root binding avoids raw shell input fallback" "$ctrl_insert_binding" "display-message"

shift_delete_binding="$("$real_tmux" -L "$socket_name" list-keys -T root S-DC)"
assert_contains "Shift-Delete root binding uses key router" "$shift_delete_binding" "tmux-pane-key-router"
assert_contains "Shift-Delete root binding passes router action" "$shift_delete_binding" "shift-delete"
assert_not_contains "Shift-Delete root binding does not use paste-key mode" "$shift_delete_binding" "--paste-key"
assert_contains "Shift-Delete root binding uses explicit home" "$shift_delete_binding" "$home_marker"
assert_contains "Shift-Delete root binding has repo fallback" "$shift_delete_binding" "$repo_marker"
assert_contains "Shift-Delete root binding has PATH fallback" "$shift_delete_binding" "command -v tmux-pane-key-router"
assert_contains_home_guard "Shift-Delete root binding guards unset HOME" "$shift_delete_binding"
assert_contains "Shift-Delete root binding uses async router" "$shift_delete_binding" 'run-shell -b'
assert_contains "Shift-Delete root binding shell-quotes current command" "$shift_delete_binding" '#{q:pane_current_command}'
assert_contains "Shift-Delete root binding shell-quotes pane tty" "$shift_delete_binding" '#{q:pane_tty}'
assert_contains "Shift-Delete root binding avoids raw shell input fallback" "$shift_delete_binding" "display-message"

key_router_script="$(cat "$root/common/.local/bin/tmux-pane-key-router")"
assert_contains "key router checks passthrough helper" "$key_router_script" "tmux-pane-should-passthrough"
assert_contains "key router uses paste helper for plain Shift-Insert panes" "$key_router_script" "tmux-paste-helper"
assert_contains "key router sends Ctrl-Insert bytes" "$key_router_script" "send_hex 1b 5b 32 3b 35 7e"
assert_contains "key router sends Shift-Insert bytes" "$key_router_script" "send_hex 1b 5b 32 3b 32 7e"
assert_contains "key router sends Shift-Delete bytes" "$key_router_script" "send_hex 1b 5b 33 3b 32 7e"
assert_contains "key router points plain Shift-Delete panes at copy mode" "$key_router_script" "Shift-Delete: use copy mode or a pane-aware app to cut"
assert_contains "key router targets pane selection fallbacks" "$key_router_script" "tmux select-pane -t"

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

assert_copy_binding_uses_helper() {
  local copy_table="$1"
  local copy_key="$2"
  local copy_binding

  copy_binding="$("$real_tmux" -L "$socket_name" list-keys -T "$copy_table" "$copy_key")"
  assert_contains "$copy_table $copy_key uses copy helper" "$copy_binding" "tmux-copy-helper"
  assert_contains "$copy_table $copy_key uses explicit home" "$copy_binding" "$home_marker"
  assert_contains "$copy_table $copy_key has repo fallback" "$copy_binding" "$repo_marker"
  assert_contains "$copy_table $copy_key has PATH fallback" "$copy_binding" "command -v tmux-copy-helper"
  assert_contains_home_guard "$copy_table $copy_key guards unset HOME" "$copy_binding"
  assert_contains "$copy_table $copy_key displays missing helper" "$copy_binding" "display-message"
}

for copy_table in copy-mode-vi copy-mode; do
  for copy_key in Enter y C-IC S-DC MouseDragEnd1Pane DoubleClick1Pane TripleClick1Pane; do
    assert_copy_binding_uses_helper "$copy_table" "$copy_key"
  done
done

for copy_key in D C-j; do
  assert_copy_binding_uses_helper copy-mode-vi "$copy_key"
done

for copy_key in M-w C-w C-k; do
  assert_copy_binding_uses_helper copy-mode "$copy_key"
done

session_picker_binding="$("$real_tmux" -L "$socket_name" list-keys -T prefix s)"
assert_contains "session picker uses helper" "$session_picker_binding" "tmux-fzf-switch-session"
assert_contains "session picker uses explicit home" "$session_picker_binding" "$home_marker"
assert_contains "session picker has repo fallback" "$session_picker_binding" "$repo_marker"
assert_contains "session picker has PATH fallback" "$session_picker_binding" "command -v tmux-fzf-switch-session"
assert_contains_home_guard "session picker guards unset HOME" "$session_picker_binding"

git_popup_binding="$("$real_tmux" -L "$socket_name" list-keys -T prefix g)"
assert_contains "git popup uses helper" "$git_popup_binding" "tmux-popup-tool"
assert_contains "git popup uses explicit home" "$git_popup_binding" "$home_marker"
assert_contains "git popup has repo fallback" "$git_popup_binding" "$repo_marker"
assert_contains "git popup has PATH fallback" "$git_popup_binding" "command -v tmux-popup-tool"
assert_contains_home_guard "git popup guards unset HOME" "$git_popup_binding"
assert_contains "git popup shell-quotes current pane path" "$git_popup_binding" '#{q:pane_current_path}'
assert_contains "git popup prefers lazygit" "$git_popup_binding" "lazygit"
assert_contains "git popup falls back to gitui" "$git_popup_binding" "gitui"

file_popup_binding="$("$real_tmux" -L "$socket_name" list-keys -T prefix e)"
assert_contains "file popup uses helper" "$file_popup_binding" "tmux-popup-tool"
assert_contains "file popup uses explicit home" "$file_popup_binding" "$home_marker"
assert_contains "file popup has repo fallback" "$file_popup_binding" "$repo_marker"
assert_contains "file popup has PATH fallback" "$file_popup_binding" "command -v tmux-popup-tool"
assert_contains_home_guard "file popup guards unset HOME" "$file_popup_binding"
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
assert_contains_home_guard "url picker guards unset HOME" "$url_picker_binding"

deep_url_picker_binding="$("$real_tmux" -L "$socket_name" list-keys -T prefix C-u)"
assert_contains "deep url picker uses helper" "$deep_url_picker_binding" "tmux-fzf-url.sh"
assert_contains "deep url picker uses explicit home" "$deep_url_picker_binding" "$home_marker"
assert_contains "deep url picker has repo fallback" "$deep_url_picker_binding" "$repo_marker"
assert_contains "deep url picker has PATH fallback" "$deep_url_picker_binding" "command -v tmux-fzf-url.sh"
assert_contains_home_guard "deep url picker guards unset HOME" "$deep_url_picker_binding"
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
assert_contains_home_guard "project session binding guards unset HOME" "$project_session_binding"
assert_contains "project session binding shell-quotes current pane path" "$project_session_binding" '#{q:pane_current_path}'

project_resume_binding="$("$real_tmux" -L "$socket_name" list-keys -T prefix R)"
assert_contains "project resume binding uses tmux-session notify" "$project_resume_binding" "tmux-session-notify"
assert_contains "project resume binding passes window" "$project_resume_binding" "--window resume"
assert_contains "project resume binding uses explicit home" "$project_resume_binding" "$home_marker"
assert_contains "project resume binding has repo fallback" "$project_resume_binding" "$repo_marker"
assert_contains "project resume binding has PATH fallback" "$project_resume_binding" "command -v tmux-session-notify"
assert_contains_home_guard "project resume binding guards unset HOME" "$project_resume_binding"
assert_contains "project resume binding shell-quotes current pane path" "$project_resume_binding" '#{q:pane_current_path}'

project_ai_binding="$("$real_tmux" -L "$socket_name" list-keys -T prefix A)"
assert_contains "project ai binding uses tmux-session notify" "$project_ai_binding" "tmux-session-notify"
assert_contains "project ai binding passes window" "$project_ai_binding" "--window agent"
assert_contains "project ai binding uses explicit home" "$project_ai_binding" "$home_marker"
assert_contains "project ai binding has repo fallback" "$project_ai_binding" "$repo_marker"
assert_contains "project ai binding has PATH fallback" "$project_ai_binding" "command -v tmux-session-notify"
assert_contains_home_guard "project ai binding guards unset HOME" "$project_ai_binding"
assert_contains "project ai binding shell-quotes current pane path" "$project_ai_binding" '#{q:pane_current_path}'

project_terminal_binding="$("$real_tmux" -L "$socket_name" list-keys -T prefix T)"
assert_contains "project terminal binding uses tmux-session notify" "$project_terminal_binding" "tmux-session-notify"
assert_contains "project terminal binding passes window" "$project_terminal_binding" "--window terminal"
assert_contains "project terminal binding uses explicit home" "$project_terminal_binding" "$home_marker"
assert_contains "project terminal binding has repo fallback" "$project_terminal_binding" "$repo_marker"
assert_contains "project terminal binding has PATH fallback" "$project_terminal_binding" "command -v tmux-session-notify"
assert_contains_home_guard "project terminal binding guards unset HOME" "$project_terminal_binding"
assert_contains "project terminal binding shell-quotes current pane path" "$project_terminal_binding" '#{q:pane_current_path}'

automatic_rename_format="$("$real_tmux" -L "$socket_name" show-window-options -gv automatic-rename-format)"
assert_contains "automatic rename uses tmux-status helper" "$automatic_rename_format" "tmux-status-name.sh"
assert_contains "automatic rename uses explicit home" "$automatic_rename_format" "$home_marker"
assert_contains "automatic rename has repo fallback" "$automatic_rename_format" "$repo_marker"
assert_contains "automatic rename has PATH fallback" "$automatic_rename_format" "command -v tmux-status-name.sh"
assert_contains_home_guard_raw "automatic rename guards unset HOME" "$automatic_rename_format"
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
expected_weird_dir="${actual_weird_dir//\\\$/\$}"
printf -v popup_helper_command '%q' "$fake_home/.local/bin/tmux-popup-tool"

# shellcheck disable=SC2016
HOME="$fake_home" "$real_tmux" -L "$socket_name" run-shell -b -t "$weird_pane" "$popup_helper_command --start-dir #{q:pane_current_path} --title git lazygit gitui"
wait_for_file "$fake_home/popup.log"
assert_eq \
  "quoted run-shell start-dir preserves metacharacter path" \
  "$(printf 'argc=6\narg=--start-dir\narg=%s\narg=--title\narg=git\narg=lazygit\narg=gitui\n---' "$expected_weird_dir")" \
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
  "$(printf 'argc=6\narg=--start-dir\narg=%s\narg=--title\narg=git\narg=lazygit\narg=gitui\n---' "$expected_weird_dir")" \
  "$(cat "$fake_home/popup.log")"
assert_file_absent "repo fallback start-dir does not run command substitution" "$tmp/INJECTED"

resurrect_processes="$("$real_tmux" -L "$socket_name" show-options -gqv @resurrect-processes)"
for process in lazygit gitui tig lazydocker k9s btop yazi lf ranger nnn; do
  assert_contains "resurrect restores $process" "$resurrect_processes" "$process"
done
assert_not_contains "resurrect does not restore every process" "$resurrect_processes" ":all:"
