#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/bashrc-custom.XXXXXX")"
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

assert_not_contains() {
  local description="$1"
  local haystack="$2"
  local needle="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'not ok - %s\nunexpected: %s\noutput:\n%s\n' "$description" "$needle" "$haystack" >&2
    exit 1
  fi

  pass "$description"
}

count_exact_lines() {
  local needle="$1"
  local haystack="$2"
  local count=0 line

  while IFS= read -r line; do
    [[ "$line" == "$needle" ]] && count=$((count + 1))
  done <<<"$haystack"

  printf '%s\n' "$count"
}

bash_path="/bin/bash"
if [[ ! -x "$bash_path" ]]; then
  if ! bash_path="$(command -v bash)"; then
    skip "bashrc-custom checks (bash unavailable)"
    exit 0
  fi
fi

"$bash_path" -n "$root/common/.bashrc-custom"
pass "bashrc-custom syntax"

bash_ctrl_delete_binding="$(
  DOTFILES_BASHRC="$root/common/.bashrc-custom" \
    HOME="$tmp/min-home" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    TERM=xterm-256color \
    "$bash_path" --noprofile --norc -ic 'source "$DOTFILES_BASHRC"; bind -p | grep "\\\\e\\[3;5~"' 2>/dev/null
)"
assert_contains "bashrc-custom maps Ctrl-Delete to kill-word" "$bash_ctrl_delete_binding" '"\e[3;5~": kill-word'

bash_word_motion_bindings="$(
  DOTFILES_BASHRC="$root/common/.bashrc-custom" \
    HOME="$tmp/min-home" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    TERM=xterm-256color \
    "$bash_path" --noprofile --norc -ic 'source "$DOTFILES_BASHRC"; bind -p | grep "\\\\e\\[1;5[CD]"' 2>/dev/null
)"
assert_contains "bashrc-custom maps Ctrl-Right to forward-word" "$bash_word_motion_bindings" '"\e[1;5C": forward-word'
assert_contains "bashrc-custom maps Ctrl-Left to backward-word" "$bash_word_motion_bindings" '"\e[1;5D": backward-word'

mkdir -p \
  "$tmp/home/.local/bin" \
  "$tmp/min-home/.local/bin" \
  "$tmp/code-home/.local/bin" \
  "$tmp/zsh-bin" \
  "$tmp/start" \
  "$tmp/target"

cat >"$tmp/home/.local/bin/fzf" <<'SH'
#!/bin/sh
printf 'fzf:%s\n' "$*" >>"${FZF_TEST_LOG:?}"
case "${1:-}" in
  --help)
    printf '%s\n' '--tmux --bind --preview-window'
    ;;
  --bash)
    exit 1
    ;;
esac
SH
chmod +x "$tmp/home/.local/bin/fzf"

cat >"$tmp/home/.local/bin/tmux" <<'SH'
#!/bin/sh
printf 'tmux:%s\n' "$*" >>"${TMUX_CALL_LOG:?}"
if [ "${1:-}" = "display-message" ] && [ "${2:-}" = "-p" ]; then
  if [ "${TMUX_DISPLAY_STATUS:-0}" != 0 ]; then
    exit "$TMUX_DISPLAY_STATUS"
  fi
  printf '%%1\n'
  exit 0
fi
if [ "${1:-}" = "-V" ]; then
  printf 'tmux %s\n' "${TMUX_VERSION:-3.4}"
  exit 0
fi
printf 'unexpected tmux command: %s\n' "$*" >&2
exit 1
SH
chmod +x "$tmp/home/.local/bin/tmux"

cat >"$tmp/home/.local/bin/yazi" <<'SH'
#!/bin/sh
cwd_file=""
for arg in "$@"; do
  case "$arg" in
    --cwd-file=*) cwd_file="${arg#--cwd-file=}" ;;
  esac
done

if [ -n "$cwd_file" ]; then
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
chmod +x "$tmp/home/.local/bin/yazi"

cat >"$tmp/code-home/.local/bin/code" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >"${CODE_TEST_LOG:?}"
SH
chmod +x "$tmp/code-home/.local/bin/code"

cat >"$tmp/zsh-bin/zsh" <<'SH'
#!/usr/bin/env sh
printf '%s\n' "fake-zsh:$*" >>"${BASHRC_ZSH_HANDOFF_LOG:?}"
exit 88
SH
chmod +x "$tmp/zsh-bin/zsh"

run_bash() {
  local home="$1"
  local path="$2"
  local script="$3"

  DOTFILES_BASHRC="$root/common/.bashrc-custom" \
    HOME="$home" \
    PATH="$path" \
    TERM=xterm-256color \
    START="$tmp/start" \
    TARGET="$tmp/target" \
    YAZI_TEST_MODE="${YAZI_TEST_MODE:-}" \
    YAZI_TEST_TARGET="${YAZI_TEST_TARGET:-}" \
    "$bash_path" --noprofile --norc -c 'source "$DOTFILES_BASHRC"; '"$script"
}

run_bash_interactive() {
  local display_status="$1"
  local tmux_env="$2"
  local tmux_version="${3:-3.4}"
  local call_log="$tmp/tmux-calls-${display_status}-${tmux_version//[^A-Za-z0-9_]/_}.log"
  local fzf_log="$tmp/fzf-calls-${display_status}-${tmux_version//[^A-Za-z0-9_]/_}.log"
  : >"$call_log"
  : >"$fzf_log"

  (
    export DOTFILES_BASHRC="$root/common/.bashrc-custom"
    export FZF_TEST_LOG="$fzf_log"
    export HOME="$tmp/home"
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
    export TERM=xterm-256color
    export TMUX_CALL_LOG="$call_log"
    export TMUX_DISPLAY_STATUS="$display_status"
    export TMUX_VERSION="$tmux_version"
    if [[ "$tmux_env" == "__unset__" ]]; then
      unset TMUX
    else
      export TMUX="$tmux_env"
    fi
    "$bash_path" --noprofile --norc -ic 'source "$DOTFILES_BASHRC"; printf "FZF_CTRL_R_OPTS=%s\n" "${FZF_CTRL_R_OPTS-}"'
  ) 2>&1
}

startup_output="$(
  run_bash "$tmp/min-home" "/usr/bin:/bin:/usr/sbin:/sbin" \
    'printf "startup-ok path0=%s\n" "${PATH%%:*}"'
)"
assert_eq "bashrc-custom loads non-interactively under system bash" "startup-ok path0=$tmp/min-home/.local/bin" "$startup_output"

nounset_output="$(
  DOTFILES_BASHRC="$root/common/.bashrc-custom" \
    FZF_TEST_LOG="$tmp/nounset-fzf.log" \
    HOME="$tmp/home" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    TERM=xterm-256color \
    "$bash_path" --noprofile --norc -iu -c 'unset FZF_DEFAULT_OPTS; source "$DOTFILES_BASHRC"; style_count="$(printf "%s\n" "$FZF_DEFAULT_OPTS" | grep -o -- "--style=minimal" | wc -l | tr -d " ")"; printf "nounset-ok style_count=%s\n" "$style_count"' 2>/dev/null
)"
assert_eq "bashrc-custom fzf defaults are nounset-safe" "nounset-ok style_count=1" "$nounset_output"

noninteractive_tty_output="$(
  python3 - "$bash_path" "$root/common/.bashrc-custom" "$tmp/zsh-bin" "$tmp/min-home" "$tmp/noninteractive-zsh.log" <<'PY'
import os
import pty
import select
import subprocess
import sys

bash_path, bashrc, zsh_bin, home, handoff_log = sys.argv[1:]
env = {
    "BASHRC_ZSH_HANDOFF_LOG": handoff_log,
    "DOTFILES_BASHRC": bashrc,
    "HOME": home,
    "PATH": f"{zsh_bin}:/usr/bin:/bin:/usr/sbin:/sbin",
    "TERM": "xterm-256color",
}
master, slave = pty.openpty()
try:
    proc = subprocess.Popen(
        [bash_path, "--noprofile", "--norc", "-c", 'source "$DOTFILES_BASHRC"; printf "noninteractive-tty-ok\\n"'],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
finally:
    os.close(slave)

chunks = []
while True:
    ready, _, _ = select.select([master], [], [], 0.2)
    if ready:
        try:
            chunk = os.read(master, 4096)
        except OSError:
            break
        if not chunk:
            break
        chunks.append(chunk)
    if proc.poll() is not None:
        ready, _, _ = select.select([master], [], [], 0)
        if not ready:
            break
os.close(master)
sys.stdout.write(b"".join(chunks).decode(errors="replace").replace("\r\n", "\n"))
sys.exit(proc.wait())
PY
)"
assert_eq "bashrc-custom does not hand off non-interactive tty shells to zsh" "noninteractive-tty-ok" "$noninteractive_tty_output"
if [[ -e "$tmp/noninteractive-zsh.log" ]]; then
  printf 'not ok - bashrc-custom skipped fake zsh for non-interactive tty\n' >&2
  cat "$tmp/noninteractive-zsh.log" >&2
  exit 1
fi
pass "bashrc-custom skipped fake zsh for non-interactive tty"

path_output="$(
  run_bash "$tmp/home" "/usr/bin:/bin:/usr/sbin:/sbin" \
    'printf "fzf=%s\n" "$(command -v fzf)"'
)"
assert_eq "bashrc-custom keeps HOME local bin ahead of Homebrew" "fzf=$tmp/home/.local/bin/fzf" "$path_output"

code_output="$(
  CODE_TEST_LOG="$tmp/code.log" \
    run_bash "$tmp/code-home" "/bin:/usr/sbin:/sbin" \
      'code --reuse-window file.txt'
)"
assert_eq "bash code wrapper does not require nc" "" "$code_output"
assert_eq "bash code wrapper delegates to code command" "--reuse-window file.txt" "$(cat "$tmp/code.log")"

cat >"$tmp/code-home/.local/bin/code" <<'SH'
#!/bin/sh
{
  printf 'ipc=%s\n' "${VSCODE_IPC_HOOK_CLI-<unset>}"
  printf 'args=%s\n' "$*"
} >"${CODE_TEST_LOG:?}"
SH
chmod +x "$tmp/code-home/.local/bin/code"

cat >"$tmp/code-home/.local/bin/nc" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >"${NC_TEST_LOG:?}"
if [ "$*" = "-z -U ${NC_EXPECTED_SOCKET:?}" ]; then
  exit 0
fi
exit 1
SH
chmod +x "$tmp/code-home/.local/bin/nc"

python3 - "$bash_path" "$root" "$tmp/code-home" "$tmp/code-nc.log" "$tmp/nc.log" <<'PY'
import os
import socket
import subprocess
import sys
import tempfile

bash_path, root, home, code_log, nc_log = sys.argv[1:]
socket_dir = tempfile.mkdtemp(prefix="vscode-ipc-test.")
socket_path = os.path.join(socket_dir, "vscode-ipc.sock")
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    server.bind(socket_path)
    server.listen(1)
    env = {
        "CODE_TEST_LOG": code_log,
        "DOTFILES_BASHRC": os.path.join(root, "common/.bashrc-custom"),
        "HOME": home,
        "NC_EXPECTED_SOCKET": socket_path,
        "NC_TEST_LOG": nc_log,
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "TERM": "xterm-256color",
        "VSCODE_IPC_HOOK_CLI": socket_path,
    }
    proc = subprocess.run(
        [bash_path, "--noprofile", "--norc", "-c", 'source "$DOTFILES_BASHRC"; code --reuse-window file.txt'],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
finally:
    server.close()
    try:
        os.unlink(socket_path)
        os.rmdir(socket_dir)
    except OSError:
        pass

if proc.returncode != 0:
    sys.stderr.write(proc.stdout)
    sys.stderr.write(proc.stderr)
    sys.exit(proc.returncode)
PY
assert_eq "bash code wrapper probes live ipc socket with nc" "-z -U $(sed -n 's/^ipc=//p' "$tmp/code-nc.log")" "$(cat "$tmp/nc.log")"
assert_eq "bash code wrapper keeps live ipc socket" "$(printf 'ipc=%s\nargs=--reuse-window file.txt' "$(sed -n 's/^-z -U //p' "$tmp/nc.log")")" "$(cat "$tmp/code-nc.log")"

python3 - "$bash_path" "$root" "$tmp/code-home" "$tmp/code-no-find.log" "$tmp/nc-no-find.log" <<'PY'
import os
import socket
import subprocess
import sys
import tempfile

bash_path, root, home, code_log, nc_log = sys.argv[1:]
socket_dir = tempfile.mkdtemp(prefix="vscode-ipc-test.")
socket_path = os.path.join(socket_dir, "vscode-ipc-scan.sock")
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    server.bind(socket_path)
    server.listen(1)
    env = {
        "CODE_TEST_LOG": code_log,
        "DOTFILES_BASHRC": os.path.join(root, "common/.bashrc-custom"),
        "DOTFILES_VSCODE_IPC_DIR": socket_dir,
        "HOME": home,
        "NC_EXPECTED_SOCKET": socket_path,
        "NC_TEST_LOG": nc_log,
        "PATH": "/bin:/usr/sbin:/sbin",
        "TERM": "xterm-256color",
    }
    proc = subprocess.run(
        [bash_path, "--noprofile", "--norc", "-c", 'source "$DOTFILES_BASHRC"; code --reuse-window file.txt'],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
finally:
    server.close()
    try:
        os.unlink(socket_path)
        os.rmdir(socket_dir)
    except OSError:
        pass

if proc.returncode != 0:
    sys.stderr.write(proc.stdout)
    sys.stderr.write(proc.stderr)
    sys.exit(proc.returncode)
if "find" in proc.stderr:
    sys.stderr.write(proc.stderr)
    sys.exit(1)
PY
assert_eq "bash code wrapper discovers ipc socket without find" "-z -U $(sed -n 's/^ipc=//p' "$tmp/code-no-find.log")" "$(cat "$tmp/nc-no-find.log")"
assert_eq "bash code wrapper exports socket discovered without find" "$(printf 'ipc=%s\nargs=--reuse-window file.txt' "$(sed -n 's/^-z -U //p' "$tmp/nc-no-find.log")")" "$(cat "$tmp/code-no-find.log")"

CODE_TEST_LOG="$tmp/code-stale.log" \
  DOTFILES_BASHRC="$root/common/.bashrc-custom" \
  HOME="$tmp/code-home" \
  PATH="/bin:/usr/sbin:/sbin" \
  TERM="xterm-256color" \
  VSCODE_IPC_HOOK_CLI="$tmp/missing-vscode-ipc.sock" \
  "$bash_path" --noprofile --norc -c 'source "$DOTFILES_BASHRC"; code --reuse-window file.txt' >"$tmp/bash-code-stale.out" 2>"$tmp/bash-code-stale.err"
assert_eq "bash code wrapper clears stale ipc hook" "$(printf 'ipc=<unset>\nargs=--reuse-window file.txt')" "$(cat "$tmp/code-stale.log")"

live_output="$(run_bash_interactive 0 "/tmp/fake-tmux,1,0")"
assert_contains "bash live tmux Ctrl-R uses fzf native tmux popup" "$live_output" "--tmux=center,90%,70%"

stale_output="$(run_bash_interactive 1 "/tmp/stale-tmux,1,0")"
assert_not_contains "bash stale TMUX Ctrl-R avoids fzf native tmux popup" "$stale_output" "--tmux=center,90%,70%"

outside_output="$(run_bash_interactive 0 "__unset__")"
assert_not_contains "bash outside tmux Ctrl-R avoids fzf native tmux popup" "$outside_output" "--tmux=center,90%,70%"

old_tmux_output="$(run_bash_interactive 0 "/tmp/old-tmux,1,0" "3.2")"
assert_not_contains "bash old tmux Ctrl-R avoids unsupported fzf native tmux popup" "$old_tmux_output" "--tmux=center,90%,70%"

cat >"$tmp/home/.local/bin/grep" <<'SH'
#!/bin/sh
printf 'unexpected grep: %s\n' "$*" >&2
exit 99
SH
chmod +x "$tmp/home/.local/bin/grep"
no_grep_output="$(run_bash_interactive 0 "/tmp/no-grep-tmux,1,0")"
assert_contains "bash live tmux Ctrl-R detects fzf tmux without grep" "$no_grep_output" "--tmux=center,90%,70%"
rm -f "$tmp/home/.local/bin/grep"

cat >"$tmp/home/.local/bin/sed" <<'SH'
#!/bin/sh
printf 'unexpected sed: %s\n' "$*" >&2
exit 99
SH
cat >"$tmp/home/.local/bin/awk" <<'SH'
#!/bin/sh
printf 'unexpected awk: %s\n' "$*" >&2
exit 99
SH
chmod +x "$tmp/home/.local/bin/sed" "$tmp/home/.local/bin/awk"
history_candidates_output="$(
  DOTFILES_BASHRC="$root/common/.bashrc-custom" \
    FZF_TEST_LOG="$tmp/history-fzf.log" \
    HOME="$tmp/home" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    TERM=xterm-256color \
    "$bash_path" --noprofile --norc -c 'set -o history; source "$DOTFILES_BASHRC"; history -s "  git status"; history -s "git status"; history -s "echo done"; _dotfiles_bash_fzf_history_candidates' 2>&1
)"
assert_contains "bash fallback history candidates work without sed or awk" "$history_candidates_output" "git status"
assert_eq "bash fallback history candidates dedupe trimmed commands" "1" "$(count_exact_lines "git status" "$history_candidates_output")"
rm -f "$tmp/home/.local/bin/sed" "$tmp/home/.local/bin/awk"

same_output="$(YAZI_TEST_MODE=same run_bash "$tmp/home" "/usr/bin:/bin:/usr/sbin:/sbin" 'cd "$START"; y; rc=$?; printf "rc=%s pwd=%s\n" "$rc" "$PWD"')"
assert_eq "bash y returns success when yazi stays in current dir" "rc=0 pwd=$tmp/start" "$same_output"

change_output="$(YAZI_TEST_MODE=change YAZI_TEST_TARGET="$tmp/target" run_bash "$tmp/home" "/usr/bin:/bin:/usr/sbin:/sbin" 'cd "$START"; y; rc=$?; printf "rc=%s pwd=%s\n" "$rc" "$PWD"')"
assert_eq "bash y changes to yazi cwd on success" "rc=0 pwd=$tmp/target" "$change_output"

fail_output="$(YAZI_TEST_MODE=fail YAZI_TEST_TARGET="$tmp/target" run_bash "$tmp/home" "/usr/bin:/bin:/usr/sbin:/sbin" 'cd "$START"; y; rc=$?; printf "rc=%s pwd=%s\n" "$rc" "$PWD"')"
assert_eq "bash y preserves yazi failure and cwd" "rc=42 pwd=$tmp/start" "$fail_output"

delete_output="$(YAZI_TEST_MODE=delete run_bash "$tmp/home" "/usr/bin:/bin:/usr/sbin:/sbin" 'cd "$START"; y; rc=$?; printf "rc=%s pwd=%s\n" "$rc" "$PWD"')"
assert_eq "bash y tolerates missing yazi cwd file" "rc=0 pwd=$tmp/start" "$delete_output"

if missing_output="$(run_bash "$tmp/min-home" "/usr/bin:/bin:/usr/sbin:/sbin" 'PATH="/usr/bin:/bin:/usr/sbin:/sbin"; hash -r; cd "$START"; y; rc=$?; printf "rc=%s pwd=%s\n" "$rc" "$PWD"' 2>&1)"; then
  :
fi
assert_contains "bash y reports missing yazi" "$missing_output" "y: yazi not found"
assert_contains "bash y returns 127 for missing yazi" "$missing_output" "rc=127 pwd=$tmp/start"
