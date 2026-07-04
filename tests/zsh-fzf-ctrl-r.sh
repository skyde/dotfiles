#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/zsh-fzf-ctrl-r.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

skip() {
  printf 'skip - %s\n' "$1"
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

count_exact_lines() {
  local needle="$1"
  local haystack="$2"
  local count=0 line

  while IFS= read -r line; do
    [[ "$line" == "$needle" ]] && count=$((count + 1))
  done <<<"$haystack"

  printf '%s\n' "$count"
}

if ! zsh_path="$(command -v zsh)"; then
  skip "zsh fzf Ctrl-R setup (zsh unavailable)"
  exit 0
fi

if ! python3_path="$(command -v python3)"; then
  skip "zsh fzf Ctrl-R setup (python3 unavailable)"
  exit 0
fi

"$zsh_path" -n "$root/common/.zshrc"
pass "zshrc syntax"

mkdir -p "$tmp/bin" "$tmp/home" "$tmp/cache"

# shellcheck disable=SC2016 # Expanded by the child zsh process.
minimal_output="$(
  DOTFILES_ZSHRC="$root/common/.zshrc" \
    HOME="$tmp/home" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    XDG_CACHE_HOME="$tmp/min-cache" \
    "$zsh_path" -fic 'source "$DOTFILES_ZSHRC"; print -r -- startup-ok' 2>&1
)"
assert_eq "zshrc loads without optional prompt tools" "startup-ok" "$minimal_output"

ctrl_delete_binding="$(
  DOTFILES_ZSHRC="$root/common/.zshrc" \
    HOME="$tmp/home" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    XDG_CACHE_HOME="$tmp/min-cache" \
    "$zsh_path" -fic $'source "$DOTFILES_ZSHRC"; bindkey -M emacs "\e[3;5~"' 2>&1
)"
assert_contains "zshrc maps Ctrl-Delete to kill-word" "$ctrl_delete_binding" "kill-word"

ctrl_right_binding="$(
  DOTFILES_ZSHRC="$root/common/.zshrc" \
    HOME="$tmp/home" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    XDG_CACHE_HOME="$tmp/min-cache" \
    "$zsh_path" -fic $'source "$DOTFILES_ZSHRC"; bindkey -M emacs "\e[1;5C"' 2>&1
)"
assert_contains "zshrc maps Ctrl-Right to forward-word" "$ctrl_right_binding" "forward-word"

ctrl_left_binding="$(
  DOTFILES_ZSHRC="$root/common/.zshrc" \
    HOME="$tmp/home" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    XDG_CACHE_HOME="$tmp/min-cache" \
    "$zsh_path" -fic $'source "$DOTFILES_ZSHRC"; bindkey -M emacs "\e[1;5D"' 2>&1
)"
assert_contains "zshrc maps Ctrl-Left to backward-word" "$ctrl_left_binding" "backward-word"

git_bin="$tmp/git-bin"
mkdir -p "$git_bin"
cat >"$git_bin/git" <<'SH'
#!/usr/bin/env sh
printf 'pager=%s\n' "${GIT_PAGER-<unset>}"
printf 'args=%s\n' "$*"
SH
chmod +x "$git_bin/git"

git_pager_output="$(
  DOTFILES_ZSHRC="$root/common/.zshrc" \
    GIT_PAGER=cat \
    HOME="$tmp/home" \
    PATH="$git_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    XDG_CACHE_HOME="$tmp/min-cache" \
    "$zsh_path" -fic 'source "$DOTFILES_ZSHRC"; git log' 2>&1
)"
assert_contains "zshrc clears inherited GIT_PAGER for git fallback" "$git_pager_output" "pager=<unset>"
assert_contains "zshrc git wrapper applies fallback pager config" "$git_pager_output" "core.pager=less"

code_bin="$tmp/code-bin"
mkdir -p "$code_bin"
cat >"$code_bin/code" <<'SH'
#!/usr/bin/env sh
printf '%s\n' "$*" >"${CODE_TEST_LOG:?}"
SH
chmod +x "$code_bin/code"

"$python3_path" - "$zsh_path" "$root" "$code_bin" "$tmp/home" "$tmp/min-cache" "$tmp/code.log" <<'PY'
import os
import socket
import subprocess
import sys
import tempfile

zsh_path, root, code_bin, home, cache, code_log = sys.argv[1:]
socket_dir = tempfile.mkdtemp(prefix="vscode-ipc-test.")
socket_path = os.path.join(socket_dir, "vscode-ipc.sock")
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    server.bind(socket_path)
    server.listen(1)
    env = {
        "CODE_TEST_LOG": code_log,
        "DOTFILES_ZSHRC": os.path.join(root, "common/.zshrc"),
        "HOME": home,
        "PATH": f"{code_bin}:/bin:/usr/sbin:/sbin",
        "VSCODE_IPC_HOOK_CLI": socket_path,
        "XDG_CACHE_HOME": cache,
    }
    proc = subprocess.run(
        [zsh_path, "-fic", 'source "$DOTFILES_ZSHRC"; code --reuse-window file.txt'],
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
if "nc" in proc.stderr:
    sys.stderr.write(proc.stderr)
    sys.exit(1)
PY
assert_eq "zsh code wrapper delegates without nc" "--reuse-window file.txt" "$(cat "$tmp/code.log")"

code_nc_bin="$tmp/code-nc-bin"
mkdir -p "$code_nc_bin"
cat >"$code_nc_bin/code" <<'SH'
#!/usr/bin/env sh
{
  printf 'ipc=%s\n' "${VSCODE_IPC_HOOK_CLI-<unset>}"
  printf 'args=%s\n' "$*"
} >"${CODE_TEST_LOG:?}"
SH
chmod +x "$code_nc_bin/code"

cat >"$code_nc_bin/nc" <<'SH'
#!/usr/bin/env sh
printf '%s\n' "$*" >"${NC_TEST_LOG:?}"
if [ "$*" = "-z -U ${NC_EXPECTED_SOCKET:?}" ]; then
  exit 0
fi
exit 1
SH
chmod +x "$code_nc_bin/nc"

"$python3_path" - "$zsh_path" "$root" "$code_nc_bin" "$tmp/home" "$tmp/min-cache" "$tmp/code-nc.log" "$tmp/nc.log" <<'PY'
import os
import socket
import subprocess
import sys
import tempfile

zsh_path, root, code_bin, home, cache, code_log, nc_log = sys.argv[1:]
socket_dir = tempfile.mkdtemp(prefix="vscode-ipc-test.")
socket_path = os.path.join(socket_dir, "vscode-ipc.sock")
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    server.bind(socket_path)
    server.listen(1)
    env = {
        "CODE_TEST_LOG": code_log,
        "DOTFILES_ZSHRC": os.path.join(root, "common/.zshrc"),
        "HOME": home,
        "NC_EXPECTED_SOCKET": socket_path,
        "NC_TEST_LOG": nc_log,
        "PATH": f"{code_bin}:/usr/bin:/bin:/usr/sbin:/sbin",
        "VSCODE_IPC_HOOK_CLI": socket_path,
        "XDG_CACHE_HOME": cache,
    }
    proc = subprocess.run(
        [zsh_path, "-fic", 'source "$DOTFILES_ZSHRC"; code --reuse-window file.txt'],
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
assert_eq "zsh code wrapper probes live ipc socket with nc" "-z -U $(sed -n 's/^ipc=//p' "$tmp/code-nc.log")" "$(cat "$tmp/nc.log")"
assert_eq "zsh code wrapper keeps live ipc socket" "$(printf 'ipc=%s\nargs=--reuse-window file.txt' "$(sed -n 's/^-z -U //p' "$tmp/nc.log")")" "$(cat "$tmp/code-nc.log")"

"$python3_path" - "$zsh_path" "$root" "$code_nc_bin" "$tmp/home" "$tmp/min-cache" "$tmp/code-no-find.log" "$tmp/nc-no-find.log" <<'PY'
import os
import socket
import subprocess
import sys
import tempfile

zsh_path, root, code_bin, home, cache, code_log, nc_log = sys.argv[1:]
socket_dir = tempfile.mkdtemp(prefix="vscode-ipc-test.")
socket_path = os.path.join(socket_dir, "vscode-ipc-scan.sock")
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    server.bind(socket_path)
    server.listen(1)
    env = {
        "CODE_TEST_LOG": code_log,
        "DOTFILES_VSCODE_IPC_DIR": socket_dir,
        "DOTFILES_ZSHRC": os.path.join(root, "common/.zshrc"),
        "HOME": home,
        "NC_EXPECTED_SOCKET": socket_path,
        "NC_TEST_LOG": nc_log,
        "PATH": f"{code_bin}:/bin:/usr/sbin:/sbin",
        "XDG_CACHE_HOME": cache,
    }
    proc = subprocess.run(
        [zsh_path, "-fic", 'source "$DOTFILES_ZSHRC"; code --reuse-window file.txt'],
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
assert_eq "zsh code wrapper discovers ipc socket without find" "-z -U $(sed -n 's/^ipc=//p' "$tmp/code-no-find.log")" "$(cat "$tmp/nc-no-find.log")"
assert_eq "zsh code wrapper exports socket discovered without find" "$(printf 'ipc=%s\nargs=--reuse-window file.txt' "$(sed -n 's/^-z -U //p' "$tmp/nc-no-find.log")")" "$(cat "$tmp/code-no-find.log")"

CODE_TEST_LOG="$tmp/code-stale.log" \
  DOTFILES_ZSHRC="$root/common/.zshrc" \
  HOME="$tmp/home" \
  PATH="$code_nc_bin:/bin:/usr/sbin:/sbin" \
  VSCODE_IPC_HOOK_CLI="$tmp/missing-vscode-ipc.sock" \
  XDG_CACHE_HOME="$tmp/min-cache" \
  "$zsh_path" -fic 'source "$DOTFILES_ZSHRC"; code --reuse-window file.txt' >"$tmp/zsh-code-stale.out" 2>"$tmp/zsh-code-stale.err"
assert_eq "zsh code wrapper clears stale ipc hook" "$(printf 'ipc=<unset>\nargs=--reuse-window file.txt')" "$(cat "$tmp/code-stale.log")"

cat >"$tmp/bin/starship" <<'SH'
#!/usr/bin/env sh
if [ "${1:-}" = "init" ]; then
  exit 0
fi
exit 0
SH
chmod +x "$tmp/bin/starship"

cat >"$tmp/bin/zoxide" <<'SH'
#!/usr/bin/env sh
if [ "${1:-}" = "init" ]; then
  exit 0
fi
exit 0
SH
chmod +x "$tmp/bin/zoxide"

cat >"$tmp/bin/fzf" <<'SH'
#!/usr/bin/env sh
case "${1:-}" in
  --help)
    printf '%s\n' '--tmux --bind --preview-window'
    ;;
  --zsh)
    ;;
esac
SH
chmod +x "$tmp/bin/fzf"

cat >"$tmp/bin/tmux" <<'SH'
#!/usr/bin/env sh
printf '%s\n' "$*" >>"${TMUX_CALL_LOG:?}"
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
chmod +x "$tmp/bin/tmux"

run_zsh() {
  local display_status="$1"
  local tmux_env="$2"
  local tmux_version="${3:-3.4}"
  local call_log="$tmp/tmux-calls-${display_status}-${tmux_env//[^A-Za-z0-9_]/_}-${tmux_version//[^A-Za-z0-9_]/_}.log"
  : >"$call_log"

  "$python3_path" - "$zsh_path" "$root" "$tmp/bin" "$tmp/home" "$tmp/cache" "$call_log" "$display_status" "$tmux_env" "$tmux_version" <<'PY'
import os
import pty
import select
import subprocess
import sys

zsh_path, root, bin_dir, home, cache, call_log, display_status, tmux_env, tmux_version = sys.argv[1:]
env = {
    "DOTFILES_ZSHRC": os.path.join(root, "common/.zshrc"),
    "HOME": home,
    "PATH": f"{bin_dir}:/usr/bin:/bin:/usr/sbin:/sbin",
    "TERM": "xterm-256color",
    "TMUX_CALL_LOG": call_log,
    "TMUX_DISPLAY_STATUS": display_status,
    "TMUX_VERSION": tmux_version,
    "XDG_CACHE_HOME": cache,
}
if tmux_env != "__unset__":
    env["TMUX"] = tmux_env

master, slave = pty.openpty()
try:
    proc = subprocess.Popen(
        [
            zsh_path,
            "-fic",
            'source "$DOTFILES_ZSHRC"; print -r -- "FZF_CTRL_R_OPTS=${FZF_CTRL_R_OPTS-}"',
        ],
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

rc = proc.wait()
os.close(master)
output = b"".join(chunks).decode("utf-8", "replace")
sys.stdout.write(output)
if rc != 0:
    sys.exit(rc)
PY
}

live_output="$(run_zsh 0 "/tmp/fake-tmux,1,0")"
assert_contains "live tmux Ctrl-R uses fzf native tmux popup" "$live_output" "--tmux=center,90%,70%"

stale_output="$(run_zsh 1 "/tmp/stale-tmux,1,0")"
assert_not_contains "stale TMUX Ctrl-R avoids fzf native tmux popup" "$stale_output" "--tmux=center,90%,70%"

outside_output="$(run_zsh 0 "__unset__")"
assert_not_contains "outside tmux Ctrl-R avoids fzf native tmux popup" "$outside_output" "--tmux=center,90%,70%"

old_tmux_output="$(run_zsh 0 "/tmp/old-tmux,1,0" "3.2")"
assert_not_contains "old tmux Ctrl-R avoids unsupported fzf native tmux popup" "$old_tmux_output" "--tmux=center,90%,70%"

cat >"$tmp/bin/grep" <<'SH'
#!/usr/bin/env sh
printf 'unexpected grep: %s\n' "$*" >&2
exit 99
SH
chmod +x "$tmp/bin/grep"
no_grep_output="$(run_zsh 0 "/tmp/no-grep-tmux,1,0")"
assert_contains "live tmux Ctrl-R detects fzf tmux without grep" "$no_grep_output" "--tmux=center,90%,70%"
rm -f "$tmp/bin/grep"

cat >"$tmp/bin/awk" <<'SH'
#!/usr/bin/env sh
printf 'unexpected awk: %s\n' "$*" >&2
exit 99
SH
chmod +x "$tmp/bin/awk"
history_candidates_output="$(
  DOTFILES_ZSHRC="$root/common/.zshrc" \
    HOME="$tmp/home" \
    PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    TERM=xterm-256color \
    XDG_CACHE_HOME="$tmp/cache" \
    "$zsh_path" -fic 'source "$DOTFILES_ZSHRC"; print -s "git status"; print -s "git status"; print -s "echo done"; _dotfiles_fzf_history_candidates' 2>&1
)"
assert_contains "zsh fallback history candidates work without awk" "$history_candidates_output" "git status"
assert_eq "zsh fallback history candidates dedupe commands" "1" "$(count_exact_lines "git status" "$history_candidates_output")"
rm -f "$tmp/bin/awk"
