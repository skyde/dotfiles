#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$root/common/.local/bin/kill-tmux"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"

cat >"$tmp/bin/tmux" <<'SH'
#!/usr/bin/env bash
printf 'tmux %s\n' "$*" >>"$KILL_TMUX_LOG"
exit "${KILL_TMUX_TMUX_RC:-0}"
SH
chmod +x "$tmp/bin/tmux"

cat >"$tmp/bin/pgrep" <<'SH'
#!/usr/bin/env bash
printf 'pgrep %s\n' "$*" >>"$KILL_TMUX_LOG"
count_file="$KILL_TMUX_PGREP_COUNT"
count=0
if [[ -f "$count_file" ]]; then
  count="$(cat "$count_file")"
fi
count=$((count + 1))
printf '%s' "$count" >"$count_file"

IFS=, read -r -a responses <<<"${KILL_TMUX_PGREP_RESPONSES:-1}"
response="${responses[$((count - 1))]:-${responses[-1]}}"
exit "$response"
SH
chmod +x "$tmp/bin/pgrep"

cat >"$tmp/bin/pkill" <<'SH'
#!/usr/bin/env bash
printf 'pkill %s\n' "$*" >>"$KILL_TMUX_LOG"
exit 0
SH
chmod +x "$tmp/bin/pkill"

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

log="$tmp/kill.log"
count="$tmp/pgrep.count"

: >"$log"
rm -f "$count"
output="$(
  PATH="$tmp/bin:/usr/bin:/bin" \
    USER=tester \
    KILL_TMUX_LOG="$log" \
    KILL_TMUX_PGREP_COUNT="$count" \
    KILL_TMUX_PGREP_RESPONSES=1 \
    "$helper"
)"
assert_eq "no tmux processes exits cleanly" "No tmux processes running" "$output"
assert_eq \
  "no tmux processes still attempts exact tmux lookup" \
  "$(printf 'tmux kill-server\npgrep -x -u tester tmux')" \
  "$(cat "$log")"

: >"$log"
rm -f "$count"
output="$(
  PATH="$tmp/bin:/usr/bin:/bin" \
    USER=tester \
    KILL_TMUX_LOG="$log" \
    KILL_TMUX_PGREP_COUNT="$count" \
    KILL_TMUX_PGREP_RESPONSES=0,1 \
    "$helper"
)"
assert_eq \
  "stuck tmux receives term before success" \
  "Some tmux processes are still running. Sending TERM..." \
  "$output"
assert_eq \
  "stuck tmux term path avoids kill" \
  "$(printf 'tmux kill-server\npgrep -x -u tester tmux\npkill -TERM -x -u tester tmux\npgrep -x -u tester tmux')" \
  "$(cat "$log")"

: >"$log"
rm -f "$count"
output="$(
  PATH="$tmp/bin:/usr/bin:/bin" \
    USER=tester \
    KILL_TMUX_LOG="$log" \
    KILL_TMUX_PGREP_COUNT="$count" \
    KILL_TMUX_PGREP_RESPONSES=0,0,1 \
    "$helper"
)"
assert_eq \
  "stuck tmux escalates to kill" \
  "$(printf 'Some tmux processes are still running. Sending TERM...\nTmux processes are still running. Force killing...')" \
  "$output"
assert_eq \
  "stuck tmux escalates after term" \
  "$(printf 'tmux kill-server\npgrep -x -u tester tmux\npkill -TERM -x -u tester tmux\npgrep -x -u tester tmux\npkill -KILL -x -u tester tmux\npgrep -x -u tester tmux')" \
  "$(cat "$log")"

: >"$log"
rm -f "$count"
set +e
output="$(
  PATH="$tmp/bin:/usr/bin:/bin" \
    USER=tester \
    KILL_TMUX_LOG="$log" \
    KILL_TMUX_PGREP_COUNT="$count" \
    KILL_TMUX_PGREP_RESPONSES=0,0,0 \
    "$helper"
)"
rc=$?
set -e
assert_eq "persistent tmux process exits non-zero" "1" "$rc"
assert_eq \
  "persistent tmux process reports failure" \
  "$(printf 'Some tmux processes are still running. Sending TERM...\nTmux processes are still running. Force killing...\nUnable to stop tmux processes')" \
  "$output"
