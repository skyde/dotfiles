#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
real_tmux="$(command -v tmux)"
python3_path="$(command -v python3 || true)"
tmp="$(mktemp -d)"
kitty_program_socket="dotfiles-env-kitty-program-$$"
kitty_missing_terminfo_socket="dotfiles-env-kitty-missing-terminfo-$$"
kitty_term_socket="dotfiles-env-kitty-term-$$"
kitty_id_socket="dotfiles-env-kitty-id-$$"
vscode_socket="dotfiles-env-vscode-$$"
vscode_prefix_socket="dotfiles-env-vscode-prefix-$$"
apple_socket="dotfiles-env-apple-$$"
generic_socket="dotfiles-env-generic-$$"
ssh_socket="dotfiles-env-ssh-$$"

cleanup() {
  rm -rf "$tmp"
  "$real_tmux" -L "$kitty_program_socket" kill-server >/dev/null 2>&1 || true
  "$real_tmux" -L "$kitty_missing_terminfo_socket" kill-server >/dev/null 2>&1 || true
  "$real_tmux" -L "$kitty_term_socket" kill-server >/dev/null 2>&1 || true
  "$real_tmux" -L "$kitty_id_socket" kill-server >/dev/null 2>&1 || true
  "$real_tmux" -L "$vscode_socket" kill-server >/dev/null 2>&1 || true
  "$real_tmux" -L "$vscode_prefix_socket" kill-server >/dev/null 2>&1 || true
  "$real_tmux" -L "$apple_socket" kill-server >/dev/null 2>&1 || true
  "$real_tmux" -L "$generic_socket" kill-server >/dev/null 2>&1 || true
  "$real_tmux" -L "$ssh_socket" kill-server >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$tmp/bin"

cat >"$tmp/bin/infocmp" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "xterm-kitty" && "${TMUX_TEST_HAS_KITTY_TERMINFO:-}" == "1" ]]; then
  exit 0
fi
exit 1
SH
chmod +x "$tmp/bin/infocmp"

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

skip() {
  printf 'skip - %s\n' "$1"
}

assert_file_absent() {
  local name="$1"
  local path="$2"

  if [[ -e "$path" ]]; then
    printf 'not ok - %s\n' "$name" >&2
    printf 'unexpected file exists: %s\n' "$path" >&2
    cat "$path" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

tmux_conf="$(cat "$root/common/.tmux.conf")"
assert_contains "secondary prefix keeps default C-b fallback" "$tmux_conf" "set -g prefix2 C-b"
assert_contains "Shift-F10 enters tmux prefix table" "$tmux_conf" "bind-key -n S-F10 switch-client -T prefix"
assert_contains "focus events option is quiet for old tmux" "$tmux_conf" "set-option -gq focus-events on"
assert_contains "xterm keys option is quiet for old tmux" "$tmux_conf" "set-option -gq xterm-keys on"
assert_contains "extended keys option is quiet for old tmux" "$tmux_conf" "set-option -gq extended-keys on"
assert_contains "kitty extkeys feature is quiet for old tmux" "$tmux_conf" "set-option -gq terminal-features 'xterm-kitty:extkeys'"
assert_contains "clipboard option is quiet for old tmux" "$tmux_conf" "set-option -gq set-clipboard on"
assert_contains "clipboard terminal feature append is quiet for old tmux" "$tmux_conf" "set-option -asq terminal-features ',xterm*:clipboard'"
assert_contains "copy-command option is quiet for old tmux" "$tmux_conf" "set-option -gq copy-command"
assert_contains "RGB terminal override append is quiet for old tmux" "$tmux_conf" "set-option -agq terminal-overrides"
assert_contains "RGB terminal feature append is quiet for old tmux" "$tmux_conf" "set-option -asq terminal-features ',xterm-kitty:RGB"
assert_contains "allow passthrough option is quiet for old tmux" "$tmux_conf" "set-option -gq allow-passthrough on"
assert_contains "detach-on-destroy option is quiet for old tmux" "$tmux_conf" "set-option -gq detach-on-destroy off"
assert_contains "display panes timing option is quiet for old tmux" "$tmux_conf" "set-option -gq display-panes-time 2000"

TMUX_TEST_HAS_KITTY_TERMINFO=1 PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" TERM_PROGRAM=kitty "$real_tmux" -L "$kitty_program_socket" -f "$root/common/.tmux.conf" new-session -d -s kitty-program-env 'sleep 60'
kitty_program_terminal="$("$real_tmux" -L "$kitty_program_socket" show-options -gqv default-terminal)"
assert_eq "kitty TERM_PROGRAM tmux uses kitty terminfo" "xterm-kitty" "$kitty_program_terminal"
kitty_features="$("$real_tmux" -L "$kitty_program_socket" show-options -gqv terminal-features)"
assert_contains "kitty tmux advertises kitty extkeys" "$kitty_features" "xterm-kitty:extkeys"
assert_contains "kitty tmux advertises RGB" "$kitty_features" "xterm-kitty:RGB"

TMUX_TEST_HAS_KITTY_TERMINFO=0 PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" TERM_PROGRAM=kitty "$real_tmux" -L "$kitty_missing_terminfo_socket" -f "$root/common/.tmux.conf" new-session -d -s kitty-missing-terminfo-env 'sleep 60'
kitty_missing_terminfo_terminal="$("$real_tmux" -L "$kitty_missing_terminfo_socket" show-options -gqv default-terminal)"
assert_eq "kitty without terminfo tmux uses xterm-256color" "xterm-256color" "$kitty_missing_terminfo_terminal"

set +e
TMUX_TEST_HAS_KITTY_TERMINFO=1 PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" TERM=xterm-kitty env -u TERM_PROGRAM -u KITTY_WINDOW_ID "$real_tmux" -L "$kitty_term_socket" -f "$root/common/.tmux.conf" new-session -d -s kitty-term-env 'sleep 60' 2>"$tmp/kitty-term.err"
kitty_term_status=$?
set -e
if [[ "$kitty_term_status" -eq 0 ]]; then
  kitty_term_terminal="$("$real_tmux" -L "$kitty_term_socket" show-options -gqv default-terminal)"
  assert_eq "xterm-kitty TERM tmux uses kitty terminfo" "xterm-kitty" "$kitty_term_terminal"
else
  skip "xterm-kitty TERM tmux start ($(tr '\n' ' ' <"$tmp/kitty-term.err"))"
fi

TMUX_TEST_HAS_KITTY_TERMINFO=1 PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" KITTY_WINDOW_ID=1 TERM=xterm-256color env -u TERM_PROGRAM "$real_tmux" -L "$kitty_id_socket" -f "$root/common/.tmux.conf" new-session -d -s kitty-id-env 'sleep 60'
kitty_id_terminal="$("$real_tmux" -L "$kitty_id_socket" show-options -gqv default-terminal)"
assert_eq "kitty window id tmux uses kitty terminfo" "xterm-kitty" "$kitty_id_terminal"

TERM_PROGRAM=vscode "$real_tmux" -L "$vscode_socket" -f "$root/common/.tmux.conf" new-session -d -s vscode-env 'sleep 60'
vscode_terminal="$("$real_tmux" -L "$vscode_socket" show-options -gqv default-terminal)"
assert_eq "VS Code tmux uses xterm-256color" "xterm-256color" "$vscode_terminal"
vscode_features="$("$real_tmux" -L "$vscode_socket" show-options -gqv terminal-features)"
assert_contains "VS Code tmux advertises xterm RGB" "$vscode_features" "xterm-256color:RGB"

if [[ -n "$python3_path" ]]; then
  TERM_PROGRAM=vscode TERM=xterm-256color "$real_tmux" -L "$vscode_prefix_socket" -f "$root/common/.tmux.conf" \
    new-session -d -s vscode-prefix-env 'sleep 60'
  if prefix_output="$("$python3_path" - "$real_tmux" "$vscode_prefix_socket" <<'PY'
import os
import pty
import select
import subprocess
import sys
import time

tmux_path, socket_name = sys.argv[1:]
env = os.environ.copy()
env.update({
    "TERM": "xterm-256color",
    "TERM_PROGRAM": "vscode",
})

master, slave = pty.openpty()
try:
    proc = subprocess.Popen(
        [tmux_path, "-L", socket_name, "attach-session", "-t", "vscode-prefix-env"],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
finally:
    os.close(slave)

try:
    deadline = time.time() + 5
    sent = False
    while time.time() < deadline:
        ready, _, _ = select.select([master], [], [], 0.05)
        if ready:
            try:
                os.read(master, 4096)
            except OSError:
                break

        if not sent and time.time() > deadline - 4.5:
            os.write(master, b"\x1b[21;2~c")
            sent = True

        output = subprocess.check_output(
            [tmux_path, "-L", socket_name, "list-windows", "-F", "#{window_index}:#{window_name}"],
            env=env,
            text=True,
        )
        windows = [line for line in output.splitlines() if line]
        if len(windows) >= 2:
            print("window_count=%d" % len(windows))
            print(output, end="")
            sys.exit(0)

    print("timeout waiting for Shift-F10 prefix window")
    print(
        subprocess.check_output(
            [tmux_path, "-L", socket_name, "list-windows", "-F", "#{window_index}:#{window_name}"],
            env=env,
            text=True,
        ),
        end="",
    )
    sys.exit(1)
finally:
    proc.terminate()
    try:
        proc.wait(timeout=1)
    except subprocess.TimeoutExpired:
        proc.kill()
    os.close(master)
PY
  )"; then
    assert_contains "VS Code Shift-F10 raw bytes enter tmux prefix table" "$prefix_output" "window_count=2"
  else
    printf 'not ok - VS Code Shift-F10 raw bytes enter tmux prefix table\n%s\n' "$prefix_output" >&2
    exit 1
  fi
else
  skip "VS Code Shift-F10 attached-client path (python3 unavailable)"
fi

TERM_PROGRAM=Apple_Terminal TERM=xterm-256color "$real_tmux" -L "$apple_socket" -f "$root/common/.tmux.conf" new-session -d -s apple-env 'sleep 60'
apple_terminal="$("$real_tmux" -L "$apple_socket" show-options -gqv default-terminal)"
assert_eq "Apple Terminal tmux uses xterm-256color" "xterm-256color" "$apple_terminal"

TERM=xterm-256color env -u TERM_PROGRAM -u KITTY_WINDOW_ID "$real_tmux" -L "$generic_socket" -f "$root/common/.tmux.conf" new-session -d -s generic-env 'sleep 60'
generic_terminal="$("$real_tmux" -L "$generic_socket" show-options -gqv default-terminal)"
assert_eq "generic xterm tmux uses xterm-256color" "xterm-256color" "$generic_terminal"

SSH_CLIENT="127.0.0.1 1000 22" TERM=xterm-256color env -u TERM_PROGRAM -u KITTY_WINDOW_ID "$real_tmux" -L "$ssh_socket" -f "$root/common/.tmux.conf" new-session -d -s ssh-env 'sleep 60'
ssh_terminal="$("$real_tmux" -L "$ssh_socket" show-options -gqv default-terminal)"
assert_eq "mock ssh tmux uses xterm-256color" "xterm-256color" "$ssh_terminal"

cat >"$tmp/bin/tmux" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  load-buffer)
    case "$*" in
      "load-buffer -w -")
        cat >"${TMUX_TEST_LOAD_BUFFER_WRITE_LOG:-${TMUX_TEST_LOAD_BUFFER_LOG:?}}"
        exit "${TMUX_TEST_LOAD_BUFFER_WRITE_STATUS:-0}"
        ;;
      "load-buffer -")
        cat >"${TMUX_TEST_LOAD_BUFFER_LOG:?}"
        exit "${TMUX_TEST_LOAD_BUFFER_STATUS:-0}"
        ;;
    esac
    ;;
  save-buffer)
    if [[ "${TMUX_TEST_SAVE_BUFFER_STATUS:-0}" != 0 ]]; then
      exit "$TMUX_TEST_SAVE_BUFFER_STATUS"
    fi
    cat "${TMUX_TEST_SAVE_BUFFER_SOURCE:?}"
    ;;
  show-buffer)
    if [[ "${TMUX_TEST_SHOW_BUFFER_STATUS:-0}" != 0 ]]; then
      exit "$TMUX_TEST_SHOW_BUFFER_STATUS"
    fi
    cat "${TMUX_TEST_SHOW_BUFFER_SOURCE:?}"
    ;;
  display-message)
    if [[ "${2:-}" == "-p" ]]; then
      if [[ "${TMUX_TEST_DISPLAY_MESSAGE_STATUS:-0}" != 0 ]]; then
        exit "$TMUX_TEST_DISPLAY_MESSAGE_STATUS"
      fi
      printf '%%1\n'
      exit 0
    fi
    ;;
  *)
    printf 'unexpected tmux command: %s\n' "$*" >&2
    exit 2
    ;;
esac
SH
chmod +x "$tmp/bin/tmux"

cat >"$tmp/bin/pbcopy" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cat >"${TMUX_TEST_PBCOPY_LOG:?}"
SH
chmod +x "$tmp/bin/pbcopy"

cat >"$tmp/bin/pbpaste" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${TMUX_TEST_PBPASTE_LOG:-}" ]]; then
  printf 'pbpaste invoked\n' >"$TMUX_TEST_PBPASTE_LOG"
fi
cat "${TMUX_TEST_PBPASTE_SOURCE:?}"
SH
chmod +x "$tmp/bin/pbpaste"

clipboard="$tmp/clipboard.txt"
printf 'ssh line one\nssh line two\n' >"$clipboard"

ssh_tmux_copy_log="$tmp/ssh-tmux-copy.log"
SSH_CLIENT="127.0.0.1 1000 22" \
  TMUX=fake \
  TMUX_TEST_LOAD_BUFFER_LOG="$ssh_tmux_copy_log" \
  TMUX_TEST_PBCOPY_LOG="$tmp/ssh-tmux-pbcopy.log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$clipboard"
assert_eq "mock ssh tmux copy uses tmux buffer" "$(cat "$clipboard")" "$(cat "$ssh_tmux_copy_log")"
assert_file_absent "mock ssh tmux copy skips host pbcopy" "$tmp/ssh-tmux-pbcopy.log"

ssh_old_tmux_copy_log="$tmp/ssh-old-tmux-copy.log"
SSH_CLIENT="127.0.0.1 1000 22" \
  TMUX=fake \
  TMUX_TEST_LOAD_BUFFER_WRITE_LOG="$tmp/ssh-old-tmux-write-copy.log" \
  TMUX_TEST_LOAD_BUFFER_WRITE_STATUS=1 \
  TMUX_TEST_LOAD_BUFFER_LOG="$ssh_old_tmux_copy_log" \
  TMUX_TEST_PBCOPY_LOG="$tmp/ssh-old-tmux-pbcopy.log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$clipboard"
assert_eq "mock ssh older tmux copy uses plain tmux buffer fallback" "$(cat "$clipboard")" "$(cat "$ssh_old_tmux_copy_log")"
assert_file_absent "mock ssh older tmux copy skips host pbcopy" "$tmp/ssh-old-tmux-pbcopy.log"

ssh_tmux_paste_output="$tmp/ssh-tmux-paste.out"
SSH_CLIENT="127.0.0.1 1000 22" \
  TMUX=fake \
  TMUX_TEST_SAVE_BUFFER_SOURCE="$clipboard" \
  TMUX_TEST_PBPASTE_SOURCE="$tmp/missing-pbpaste-source" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$ssh_tmux_paste_output"
assert_eq "mock ssh tmux paste uses tmux buffer" "$(cat "$clipboard")" "$(cat "$ssh_tmux_paste_output")"

ssh_old_tmux_paste_output="$tmp/ssh-old-tmux-paste.out"
SSH_CLIENT="127.0.0.1 1000 22" \
  TMUX=fake \
  TMUX_TEST_SAVE_BUFFER_STATUS=1 \
  TMUX_TEST_SAVE_BUFFER_SOURCE="$tmp/missing-save-buffer-source" \
  TMUX_TEST_SHOW_BUFFER_SOURCE="$clipboard" \
  TMUX_TEST_PBPASTE_LOG="$tmp/ssh-old-tmux-pbpaste.log" \
  TMUX_TEST_PBPASTE_SOURCE="$tmp/missing-pbpaste-source" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$ssh_old_tmux_paste_output"
assert_eq "mock ssh older tmux paste uses show-buffer fallback" "$(cat "$clipboard")" "$(cat "$ssh_old_tmux_paste_output")"
assert_file_absent "mock ssh older tmux paste skips host pbpaste" "$tmp/ssh-old-tmux-pbpaste.log"

set +e
env -u TMUX \
  SSH_CLIENT="127.0.0.1 1000 22" \
  TMUX_TEST_PBCOPY_LOG="$tmp/ssh-no-tmux-pbcopy.log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$clipboard" 2>"$tmp/ssh-no-tmux-copy.err"
ssh_no_tmux_copy_status=$?
set -e
assert_file_absent "mock ssh copy without tmux skips pbcopy" "$tmp/ssh-no-tmux-pbcopy.log"
if [[ "$ssh_no_tmux_copy_status" -eq 0 ]]; then
  printf 'ok - mock ssh copy without tmux can use terminal fallback\n'
else
  assert_contains "mock ssh copy without tmux reports no method" "$(cat "$tmp/ssh-no-tmux-copy.err")" "No copy method available"
fi

set +e
env -u TMUX \
  SSH_CLIENT="127.0.0.1 1000 22" \
  TMUX_TEST_PBPASTE_LOG="$tmp/ssh-no-tmux-pbpaste.log" \
  TMUX_TEST_PBPASTE_SOURCE="$clipboard" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$tmp/ssh-no-tmux-paste.out" 2>"$tmp/ssh-no-tmux-paste.err"
ssh_no_tmux_paste_status=$?
set -e
assert_file_absent "mock ssh paste without tmux skips pbpaste" "$tmp/ssh-no-tmux-pbpaste.log"
if [[ "$ssh_no_tmux_paste_status" -eq 0 ]]; then
  printf 'ok - mock ssh paste without tmux can use terminal fallback\n'
else
  assert_contains "mock ssh paste without tmux reports no method" "$(cat "$tmp/ssh-no-tmux-paste.err")" "No paste method available"
fi
