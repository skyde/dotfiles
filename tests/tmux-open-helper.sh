#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$root/common/.local/bin/tmux-open-helper.sh"
tmp="$(mktemp -d)"
socket_server_pids=""

cleanup() {
  local pid

  for pid in $socket_server_pids; do
    kill "$pid" 2>/dev/null || true
  done
  rm -rf "$tmp"
}

trap cleanup EXIT

mkdir -p "$tmp/bin" "$tmp/home" "$tmp/work/src"
mkdir -p "$tmp/work/scripts"
mkdir -p "$tmp/work/pkg"
mkdir -p "$tmp/home/src"
printf '%s\n' 'print("hello")' >"$tmp/work/src/app.py"
printf '%s\n' 'print("with spaces")' >"$tmp/work/src/my file.py"
printf '%s\n' '#!/bin/sh' 'missing command' >"$tmp/work/scripts/bootstrap.sh"
printf '%s\n' 'int main() { return 0; }' >"$tmp/work/main.cpp"
printf '%s\n' 'fn main() {' '    println!("hello");' '}' >"$tmp/work/src/main.rs"
printf '%s\n' 'package main' 'func main() {' '    run()' '}' >"$tmp/work/pkg/main.go"
printf '%s\n' 'print("home")' >"$tmp/home/src/home.py"

code_log="$tmp/code.log"
cursor_log="$tmp/cursor.log"
editor_log="$tmp/editor.log"
browser_log="$tmp/browser.log"
export TMUX_OPEN_HELPER_CODE_LOG="$code_log"
export TMUX_OPEN_HELPER_CURSOR_LOG="$cursor_log"
export TMUX_OPEN_HELPER_EDITOR_LOG="$editor_log"
export TMUX_OPEN_HELPER_BROWSER_LOG="$browser_log"

cat >"$tmp/bin/code" <<'SH'
#!/usr/bin/env bash
{
  printf 'argc=%s\n' "$#"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
  printf -- '---\n'
} >>"$TMUX_OPEN_HELPER_CODE_LOG"
SH
chmod +x "$tmp/bin/code"

cat >"$tmp/bin/cursor" <<'SH'
#!/usr/bin/env bash
{
  printf 'argc=%s\n' "$#"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
  printf -- '---\n'
} >>"$TMUX_OPEN_HELPER_CURSOR_LOG"
SH
chmod +x "$tmp/bin/cursor"

cat >"$tmp/bin/editor" <<'SH'
#!/usr/bin/env bash
{
  printf 'argc=%s\n' "$#"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
  printf -- '---\n'
} >>"$TMUX_OPEN_HELPER_EDITOR_LOG"
SH
chmod +x "$tmp/bin/editor"

cat >"$tmp/bin/browser" <<'SH'
#!/usr/bin/env bash
{
  printf 'argc=%s\n' "$#"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
  printf -- '---\n'
} >>"$TMUX_OPEN_HELPER_BROWSER_LOG"
SH
chmod +x "$tmp/bin/browser"

resolve_path() {
  local path="$1"

  if command -v realpath >/dev/null 2>&1; then
    realpath "$path"
  else
    python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$path"
  fi
}

urlencode_path() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe="/"))' "$1"
}

run_open() {
  local target="$1"

  HOME="$tmp/home" PATH="$tmp/bin:$PATH" TMUX_FZF_URL_BASE_DIR="$tmp/work" "$helper" "$target"
}

run_open_no_python() {
  local target="$1"

  HOME="$tmp/home" PATH="$no_python_bin" TMUX_FZF_URL_BASE_DIR="$tmp/work" "$helper" "$target"
}

assert_log() {
  local name="$1"
  local file="$2"
  local expected="$3"
  local actual

  actual="$(cat "$file" 2>/dev/null || true)"
  if [[ "$actual" != "$expected" ]]; then
    printf 'not ok - %s\n' "$name" >&2
    printf 'expected:\n%s\n' "$expected" >&2
    printf 'actual:\n%s\n' "$actual" >&2
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
    cat "$path" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

wait_for_log() {
  local file="$1"

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -s "$file" ]] && return 0
    sleep 0.1
  done

  return 1
}

start_unix_socket() {
  local socket_path="$1" pid

  python3 - "$socket_path" <<'PY' &
import os
import socket
import sys
import time

path = sys.argv[1]
try:
    os.unlink(path)
except FileNotFoundError:
    pass

server = socket.socket(socket.AF_UNIX)
server.bind(path)
server.listen(1)
time.sleep(60)
PY
  pid=$!
  socket_server_pids="${socket_server_pids}${socket_server_pids:+ }$pid"

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -S "$socket_path" ]] && return 0
    sleep 0.1
  done

  return 1
}

app_path="$(resolve_path "$tmp/work/src/app.py")"
cpp_path="$(resolve_path "$tmp/work/main.cpp")"
rust_path="$(resolve_path "$tmp/work/src/main.rs")"
go_path="$(resolve_path "$tmp/work/pkg/main.go")"
shell_path="$(resolve_path "$tmp/work/scripts/bootstrap.sh")"
raw_space_path="$tmp/work/src/my file.py"
space_path="$(resolve_path "$tmp/work/src/my file.py")"
home_path="$(resolve_path "$tmp/home/src/home.py")"
space_url_path="$(urlencode_path "$space_path")"

no_python_bin="$tmp/no-python-bin"
mkdir -p "$no_python_bin"
ln -s "$(command -v bash)" "$no_python_bin/bash"
ln -s "$tmp/bin/code" "$no_python_bin/code"

: >"$code_log"
run_open "src/app.py:12:3"
assert_log \
  "relative file line column opens with code -g" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:12:3\n---' "$app_path")"

no_path_split_bin="$tmp/no-path-split-bin"
no_path_split_code_log="$tmp/no-path-split-code.log"
mkdir -p "$no_path_split_bin"
for command_name in bash env python3; do
  ln -s "$(command -v "$command_name")" "$no_path_split_bin/$command_name"
done
ln -s "$tmp/bin/code" "$no_path_split_bin/code"

: >"$no_path_split_code_log"
HOME="$tmp/home" \
  PATH="$no_path_split_bin" \
  TMUX_FZF_URL_BASE_DIR="$tmp/work" \
  TMUX_OPEN_HELPER_CODE_LOG="$no_path_split_code_log" \
  "$helper" "src/app.py:13"
assert_log \
  "relative file opens without dirname basename or realpath" \
  "$no_path_split_code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s/work/src/app.py:13\n---' "$tmp")"

: >"$code_log"
run_open "src/app.py:7-9"
assert_log \
  "relative file line range opens at first line" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:7\n---' "$app_path")"

: >"$code_log"
run_open "src/my file.py:9:2"
assert_log \
  "spaced relative file line column opens with code -g" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:9:2\n---' "$space_path")"

: >"$code_log"
run_open '"src/my file.py":9:2'
assert_log \
  "quoted spaced relative file line column opens with code -g" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:9:2\n---' "$space_path")"

: >"$code_log"
run_open "src/app.py:12: message here"
assert_log \
  "compiler diagnostic line opens source location" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:12\n---' "$app_path")"

: >"$code_log"
run_open "src/my file.py:9:2: message here"
assert_log \
  "compiler diagnostic line column opens spaced source location" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:9:2\n---' "$space_path")"

: >"$code_log"
run_open "error: src/app.py:12: bad"
assert_log \
  "severity-prefixed diagnostic opens source location" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:12\n---' "$app_path")"

: >"$code_log"
run_open "   --> src/main.rs:2:5"
assert_log \
  "rust arrow diagnostic opens source location" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:2:5\n---' "$rust_path")"

: >"$code_log"
run_open "thread 'main' panicked at src/main.rs:2:5:"
assert_log \
  "rust panic diagnostic opens source location" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:2:5\n---' "$rust_path")"

: >"$code_log"
run_open "pkg/main.go:4 +0x123"
assert_log \
  "go stack frame opens source location" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:4\n---' "$go_path")"

: >"$code_log"
run_open "    at run (src/my file.py:2:1)"
assert_log \
  "javascript stack frame opens source location" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:2:1\n---' "$space_path")"

: >"$code_log"
run_open "    at load (file://$(urlencode_path "$space_path"):14:3)"
assert_log \
  "javascript file url stack frame opens source location" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:14:3\n---' "$space_path")"

: >"$code_log"
run_open "    at async main (vscode://file$(urlencode_path "$space_path")#L15C4)"
assert_log \
  "javascript editor url stack frame opens source location" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:15:4\n---' "$space_path")"

: >"$code_log"
run_open '  File "src/app.py", line 12, in main'
assert_log \
  "python traceback line opens source location" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:12\n---' "$app_path")"

: >"$code_log"
run_open "::warning file=src/my%20file.py,line=2,col=1,endLine=3,endColumn=2::bad"
assert_log \
  "github annotation opens encoded file at start line" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:2:1\n---' "$space_path")"

: >"$code_log"
run_open_no_python "::warning file=src/my%20file.py,line=2,col=1::bad"
assert_log \
  "github annotation decodes spaces without python" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:2:1\n---' "$raw_space_path")"

: >"$code_log"
run_open "src/app.py::test_runs"
assert_log \
  "pytest node id opens source file" \
  "$code_log" \
  "$(printf 'argc=1\narg=%s\n---' "$app_path")"

: >"$code_log"
run_open '~'/src/home.py:5
assert_log \
  "home-relative file opens with code -g" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:5\n---' "$home_path")"

: >"$code_log"
run_open "src/app.py(7,2)"
assert_log \
  "msvc-style location opens with code -g" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:7:2\n---' "$app_path")"

: >"$code_log"
run_open "src/app.py|6 col 2| unused value"
assert_log \
  "quickfix-style location opens with code -g" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:6:2\n---' "$app_path")"

: >"$code_log"
run_open "scripts/bootstrap.sh: line 2: missing command"
assert_log \
  "shell line diagnostic opens with code -g" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:2\n---' "$shell_path")"

: >"$code_log"
run_open "main.cpp(8,4)"
assert_log \
  "bare msvc-style location opens with code -g" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:8:4\n---' "$cpp_path")"

: >"$code_log"
run_open "main.cpp(8,4): error C2143: syntax error"
assert_log \
  "msvc-style diagnostic opens with code -g" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:8:4\n---' "$cpp_path")"

: >"$code_log"
run_open "main.cpp(9): warning C4100: unused parameter"
assert_log \
  "msvc-style line diagnostic opens with code -g" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:9\n---' "$cpp_path")"

: >"$code_log"
run_open $'C:\\Users\\sky\\repo\\src\\main.cpp(8,4): warning C4100'
assert_log \
  "windows msvc-style path opens unchanged with code -g" \
  "$code_log" \
  $'argc=2\narg=-g\narg=C:\\Users\\sky\\repo\\src\\main.cpp:8:4\n---'

: >"$code_log"
run_open $'C:\\Users\\sky\\repo\\src\\app.ts:12:3'
assert_log \
  "windows drive path line column opens unchanged with code -g" \
  "$code_log" \
  $'argc=2\narg=-g\narg=C:\\Users\\sky\\repo\\src\\app.ts:12:3\n---'

: >"$code_log"
run_open "C:/Users/sky/repo/src/app.ts:12"
assert_log \
  "windows slash drive path opens unchanged with code -g" \
  "$code_log" \
  $'argc=2\narg=-g\narg=C:/Users/sky/repo/src/app.ts:12\n---'

: >"$code_log"
run_open $'"C:\\Users\\sky\\repo\\src\\app.ts":12:3'
assert_log \
  "quoted windows drive path line column opens unchanged with code -g" \
  "$code_log" \
  $'argc=2\narg=-g\narg=C:\\Users\\sky\\repo\\src\\app.ts:12:3\n---'

: >"$code_log"
run_open $'\\\\server\\share\\repo\\src\\app.ts:12:3'
assert_log \
  "windows UNC path line column opens unchanged with code -g" \
  "$code_log" \
  $'argc=2\narg=-g\narg=\\\\server\\share\\repo\\src\\app.ts:12:3\n---'

: >"$code_log"
run_open $'"\\\\server\\share\\repo\\src\\app.ts":12:3'
assert_log \
  "quoted windows UNC path line column opens unchanged with code -g" \
  "$code_log" \
  $'argc=2\narg=-g\narg=\\\\server\\share\\repo\\src\\app.ts:12:3\n---'

: >"$code_log"
run_open $'\\\\server\\share\\repo\\src\\main.cpp(8,4): warning C4100'
assert_log \
  "windows UNC msvc-style path opens unchanged with code -g" \
  "$code_log" \
  $'argc=2\narg=-g\narg=\\\\server\\share\\repo\\src\\main.cpp:8:4\n---'

: >"$code_log"
run_open $'//server/share/repo/src/app.ts:12:3'
assert_log \
  "windows slash UNC path line column opens unchanged with code -g" \
  "$code_log" \
  $'argc=2\narg=-g\narg=//server/share/repo/src/app.ts:12:3\n---'

: >"$code_log"
run_open $'"//server/share/repo/src/app.ts":12:3'
assert_log \
  "quoted windows slash UNC path line column opens unchanged with code -g" \
  "$code_log" \
  $'argc=2\narg=-g\narg=//server/share/repo/src/app.ts:12:3\n---'

: >"$code_log"
run_open $'//server/share/repo/src/main.cpp(8,4): warning C4100'
assert_log \
  "windows slash UNC msvc-style path opens unchanged with code -g" \
  "$code_log" \
  $'argc=2\narg=-g\narg=//server/share/repo/src/main.cpp:8:4\n---'

: >"$code_log"
run_open "file://$space_url_path:8:2"
assert_log \
  "file url decodes spaces and line column" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:8:2\n---' "$space_path")"

: >"$code_log"
run_open_no_python "file://$space_url_path#L2"
assert_log \
  "file url decodes spaces without python" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:2\n---' "$space_path")"

: >"$code_log"
run_open "file://$(urlencode_path "$space_path")#L6"
assert_log \
  "file url fragment opens with code -g" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:6\n---' "$space_path")"

: >"$code_log"
run_open "file://$(urlencode_path "$space_path")#L6-L9"
assert_log \
  "file url range fragment opens at first line" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:6\n---' "$space_path")"

: >"$code_log"
run_open "vscode://file$space_url_path:4"
assert_log \
  "editor file url decodes path and line" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:4\n---' "$space_path")"

: >"$code_log"
run_open_no_python "vscode://file$space_url_path?line=3&column=2"
assert_log \
  "editor file url decodes spaces without python" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:3:2\n---' "$space_path")"

: >"$code_log"
run_open "vscode://file$(urlencode_path "$space_path")?line=4&column=2"
assert_log \
  "editor file url query opens with code -g" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:4:2\n---' "$space_path")"

: >"$code_log"
run_open "vscode://file$(urlencode_path "$space_path")#L4C2-L8C9"
assert_log \
  "editor file url range fragment opens at first line column" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:4:2\n---' "$space_path")"

: >"$code_log"
run_open "vscode://vscode-remote/ssh-remote+devbox$(urlencode_path "$space_path")?line=3&column=2"
assert_log \
  "vscode remote file url opens remote path with code -g" \
  "$code_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:3:2\n---' "$space_path")"

: >"$cursor_log"
: >"$code_log"
run_open "cursor://file$(urlencode_path "$space_path")#L4"
assert_log \
  "cursor file url opens with cursor cli" \
  "$cursor_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:4\n---' "$space_path")"
assert_log \
  "cursor file url does not fall back to code when cursor works" \
  "$code_log" \
  ""

: >"$editor_log"
: >"$code_log"
HOME="$tmp/home" PATH="$tmp/bin:$PATH" TMUX_FZF_URL_BASE_DIR="$tmp/work" TMUX_OPEN_EDITOR=editor "$helper" "src/app.py:8"
assert_log \
  "explicit editor override opens file locations first" \
  "$editor_log" \
  "$(printf 'argc=2\narg=-g\narg=%s:8\n---' "$app_path")"
assert_log \
  "explicit editor override avoids code when it works" \
  "$code_log" \
  ""

: >"$editor_log"
: >"$code_log"
HOME="$tmp/home" PATH="$tmp/bin:$PATH" TMUX_FZF_URL_BASE_DIR="$tmp/work" TMUX_OPEN_EDITOR='editor --reuse-window "Project Profile"' "$helper" "src/app.py:9"
assert_log \
  "explicit editor override supports command args" \
  "$editor_log" \
  "$(printf 'argc=4\narg=--reuse-window\narg=Project Profile\narg=-g\narg=%s:9\n---' "$app_path")"
assert_log \
  "explicit editor override with args avoids code when it works" \
  "$code_log" \
  ""

editor_with_spaces="$tmp/bin/editor with spaces"
cat >"$editor_with_spaces" <<'SH'
#!/usr/bin/env bash
{
  printf 'argc=%s\n' "$#"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
  printf -- '---\n'
} >>"$TMUX_OPEN_HELPER_EDITOR_LOG"
SH
chmod +x "$editor_with_spaces"

: >"$editor_log"
: >"$code_log"
HOME="$tmp/home" PATH="$tmp/bin:$PATH" TMUX_FZF_URL_BASE_DIR="$tmp/work" TMUX_OPEN_EDITOR="\"$editor_with_spaces\" --reuse-window" "$helper" "src/app.py:10"
assert_log \
  "explicit editor override supports quoted executable path with args" \
  "$editor_log" \
  "$(printf 'argc=3\narg=--reuse-window\narg=-g\narg=%s:10\n---' "$app_path")"
assert_log \
  "explicit editor override with quoted path avoids code when it works" \
  "$code_log" \
  ""

no_python_editor_log="$tmp/no-python-editor.log"
no_python_editor_with_spaces="$tmp/no-python editor with spaces"
cat >"$no_python_editor_with_spaces" <<'SH'
#!/usr/bin/env bash
{
  printf 'argc=%s\n' "$#"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
  printf -- '---\n'
} >>"$TMUX_OPEN_HELPER_EDITOR_LOG"
SH
chmod +x "$no_python_editor_with_spaces"

: >"$no_python_editor_log"
HOME="$tmp/home" \
  PATH="$no_python_bin" \
  TMUX_FZF_URL_BASE_DIR="$tmp/work" \
  TMUX_OPEN_HELPER_EDITOR_LOG="$no_python_editor_log" \
  TMUX_OPEN_EDITOR="\"$no_python_editor_with_spaces\" --reuse-window 'Project Profile'" \
  "$helper" "src/app.py:15"
assert_log \
  "explicit editor override supports quoted args without python" \
  "$no_python_editor_log" \
  "$(printf 'argc=4\narg=--reuse-window\narg=Project Profile\narg=-g\narg=%s/work/src/app.py:15\n---' "$tmp")"

no_nc_bin="$tmp/no-nc-bin"
no_nc_code_log="$tmp/no-nc-code.log"
no_nc_socket="$tmp/vscode-ipc-live.sock"
mkdir -p "$no_nc_bin"
ln -s "$(command -v bash)" "$no_nc_bin/bash"
ln -s "$(command -v dirname)" "$no_nc_bin/dirname"
ln -s "$(command -v env)" "$no_nc_bin/env"
ln -s "$(command -v realpath)" "$no_nc_bin/realpath"
cat >"$no_nc_bin/code" <<'SH'
#!/usr/bin/env bash
{
  printf 'ipc=%s\n' "${VSCODE_IPC_HOOK_CLI-<unset>}"
  printf 'argc=%s\n' "$#"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
  printf -- '---\n'
} >>"$TMUX_OPEN_HELPER_CODE_LOG"
SH
chmod +x "$no_nc_bin/code"
start_unix_socket "$no_nc_socket"

: >"$no_nc_code_log"
HOME="$tmp/home" \
  PATH="$no_nc_bin" \
  VSCODE_IPC_HOOK_CLI="$no_nc_socket" \
  TMUX_FZF_URL_BASE_DIR="$tmp/work" \
  TMUX_OPEN_HELPER_CODE_LOG="$no_nc_code_log" \
  "$helper" "src/app.py:11"
assert_log \
  "vscode ipc hook is preserved when nc is unavailable" \
  "$no_nc_code_log" \
  "$(printf 'ipc=%s\nargc=2\narg=-g\narg=%s:11\n---' "$no_nc_socket" "$app_path")"

nc_bin="$tmp/nc-bin"
nc_code_log="$tmp/nc-code.log"
nc_log="$tmp/nc.log"
nc_socket="$tmp/vscode-ipc-live-nc.sock"
mkdir -p "$nc_bin"
ln -s "$(command -v bash)" "$nc_bin/bash"
ln -s "$(command -v dirname)" "$nc_bin/dirname"
ln -s "$(command -v env)" "$nc_bin/env"
ln -s "$(command -v realpath)" "$nc_bin/realpath"
ln -s "$(command -v sh)" "$nc_bin/sh"
cat >"$nc_bin/code" <<'SH'
#!/usr/bin/env bash
{
  printf 'ipc=%s\n' "${VSCODE_IPC_HOOK_CLI-<unset>}"
  printf 'argc=%s\n' "$#"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
  printf -- '---\n'
} >>"$TMUX_OPEN_HELPER_CODE_LOG"
SH
chmod +x "$nc_bin/code"
cat >"$nc_bin/nc" <<'SH'
#!/usr/bin/env sh
printf '%s\n' "$*" >"${NC_TEST_LOG:?}"
if [ "$*" = "-z -U ${NC_EXPECTED_SOCKET:?}" ]; then
  exit 0
fi
exit 1
SH
chmod +x "$nc_bin/nc"
start_unix_socket "$nc_socket"

: >"$nc_code_log"
HOME="$tmp/home" \
  PATH="$nc_bin" \
  NC_EXPECTED_SOCKET="$nc_socket" \
  NC_TEST_LOG="$nc_log" \
  VSCODE_IPC_HOOK_CLI="$nc_socket" \
  TMUX_FZF_URL_BASE_DIR="$tmp/work" \
  TMUX_OPEN_HELPER_CODE_LOG="$nc_code_log" \
  "$helper" "src/app.py:12"
assert_log \
  "vscode ipc hook is probed when nc is available" \
  "$nc_log" \
  "-z -U $nc_socket"
assert_log \
  "vscode ipc hook is preserved after successful nc probe" \
  "$nc_code_log" \
  "$(printf 'ipc=%s\nargc=2\narg=-g\narg=%s:12\n---' "$nc_socket" "$app_path")"

no_find_ipc_bin="$tmp/no-find-ipc-bin"
no_find_ipc_code_log="$tmp/no-find-ipc-code.log"
no_find_ipc_nc_log="$tmp/no-find-ipc-nc.log"
no_find_ipc_socket_dir="$tmp/s"
no_find_ipc_socket="$no_find_ipc_socket_dir/vscode-ipc-a.sock"
mkdir -p "$no_find_ipc_bin" "$no_find_ipc_socket_dir"
ln -s "$(command -v bash)" "$no_find_ipc_bin/bash"
ln -s "$(command -v realpath)" "$no_find_ipc_bin/realpath"
cat >"$no_find_ipc_bin/code" <<'SH'
#!/usr/bin/env bash
{
  printf 'ipc=%s\n' "${VSCODE_IPC_HOOK_CLI-<unset>}"
  printf 'argc=%s\n' "$#"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
  printf -- '---\n'
} >>"$TMUX_OPEN_HELPER_CODE_LOG"
SH
chmod +x "$no_find_ipc_bin/code"
cat >"$no_find_ipc_bin/nc" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >"${NC_TEST_LOG:?}"
if [[ "$*" == "-z -U ${NC_EXPECTED_SOCKET:?}" ]]; then
  exit 0
fi
exit 1
SH
chmod +x "$no_find_ipc_bin/nc"
start_unix_socket "$no_find_ipc_socket"

: >"$no_find_ipc_code_log"
HOME="$tmp/home" \
  PATH="$no_find_ipc_bin" \
  NC_EXPECTED_SOCKET="$no_find_ipc_socket" \
  NC_TEST_LOG="$no_find_ipc_nc_log" \
  TMUX_OPEN_HELPER_VSCODE_SOCKET_DIR="$no_find_ipc_socket_dir" \
  TMUX_FZF_URL_BASE_DIR="$tmp/work" \
  TMUX_OPEN_HELPER_CODE_LOG="$no_find_ipc_code_log" \
  "$helper" "src/app.py:14"
assert_log \
  "vscode ipc socket discovery works without find or sort" \
  "$no_find_ipc_nc_log" \
  "-z -U $no_find_ipc_socket"
assert_log \
  "vscode ipc socket discovered without find or sort is exported" \
  "$no_find_ipc_code_log" \
  "$(printf 'ipc=%s\nargc=2\narg=-g\narg=%s:14\n---' "$no_find_ipc_socket" "$app_path")"

no_find_browser_bin="$tmp/no-find-browser-bin"
no_find_browser_home="$tmp/no-find-browser-home"
no_find_browser_log="$tmp/no-find-browser.log"
no_find_browser_helper="$no_find_browser_home/.vscode-server/cli/servers/stable/server/bin/helpers/browser.sh"
mkdir -p "$no_find_browser_bin" "$(dirname "$no_find_browser_helper")"
ln -s "$(command -v bash)" "$no_find_browser_bin/bash"
cat >"$no_find_browser_helper" <<'SH'
#!/usr/bin/env bash
{
  printf 'argc=%s\n' "$#"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
  printf -- '---\n'
} >>"$TMUX_OPEN_HELPER_BROWSER_LOG"
SH
chmod +x "$no_find_browser_helper"

: >"$no_find_browser_log"
HOME="$no_find_browser_home" \
  PATH="$no_find_browser_bin" \
  TMUX_OPEN_HELPER_BROWSER_LOG="$no_find_browser_log" \
  "$helper" "https://example.test/vscode-server-browser"
wait_for_log "$no_find_browser_log"
assert_log \
  "vscode server browser helper is discovered without find sort or tail" \
  "$no_find_browser_log" \
  "$(printf 'argc=1\narg=https://example.test/vscode-server-browser\n---')"

: >"$browser_log"
HOME="$tmp/home" PATH="$tmp/bin:$PATH" BROWSER="$tmp/bin/browser" "$helper" "https://example.test/docs"
wait_for_log "$browser_log"
assert_log \
  "http url opens with configured browser" \
  "$browser_log" \
  "$(printf 'argc=1\narg=https://example.test/docs\n---')"

: >"$browser_log"
HOME="$tmp/home" PATH="$tmp/bin:$PATH" BROWSER='browser --profile "Work Profile"' "$helper" "https://example.test/with-browser-args"
wait_for_log "$browser_log"
assert_log \
  "http url opens with configured browser command args" \
  "$browser_log" \
  "$(printf 'argc=3\narg=--profile\narg=Work Profile\narg=https://example.test/with-browser-args\n---')"

: >"$browser_log"
HOME="$tmp/home" PATH="$tmp/bin:$PATH" BROWSER='browser --target=%s --profile "Work Profile"' "$helper" "https://example.test/placeholder?x=1&y=2"
wait_for_log "$browser_log"
assert_log \
  "http url substitutes configured browser placeholder" \
  "$browser_log" \
  "$(printf 'argc=3\narg=--target=https://example.test/placeholder?x=1&y=2\narg=--profile\narg=Work Profile\n---')"

: >"$browser_log"
HOME="$tmp/home" PATH="$tmp/bin:$PATH" BROWSER='browser --first=%s --second=%s' "$helper" "https://example.test/two-placeholders"
wait_for_log "$browser_log"
assert_log \
  "http url substitutes repeated browser placeholders without appending" \
  "$browser_log" \
  "$(printf 'argc=2\narg=--first=https://example.test/two-placeholders\narg=--second=https://example.test/two-placeholders\n---')"

: >"$browser_log"
HOME="$tmp/home" PATH="$tmp/bin:$PATH" BROWSER='missing-browser:browser --profile "Fallback Profile"' "$helper" "https://example.test/browser-fallback-list"
wait_for_log "$browser_log"
assert_log \
  "http url falls through configured browser list" \
  "$browser_log" \
  "$(printf 'argc=3\narg=--profile\narg=Fallback Profile\narg=https://example.test/browser-fallback-list\n---')"

browser_with_spaces="$tmp/bin/browser with spaces"
cat >"$browser_with_spaces" <<'SH'
#!/usr/bin/env bash
{
  printf 'argc=%s\n' "$#"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
  printf -- '---\n'
} >>"$TMUX_OPEN_HELPER_BROWSER_LOG"
SH
chmod +x "$browser_with_spaces"

: >"$browser_log"
HOME="$tmp/home" PATH="$tmp/bin:$PATH" BROWSER="$browser_with_spaces" "$helper" "https://example.test/browser-path-with-spaces"
wait_for_log "$browser_log"
assert_log \
  "http url preserves configured browser executable path with spaces" \
  "$browser_log" \
  "$(printf 'argc=1\narg=https://example.test/browser-path-with-spaces\n---')"

no_python_browser_log="$tmp/no-python-browser.log"
no_python_browser_with_spaces="$tmp/no-python browser with spaces"
cat >"$no_python_browser_with_spaces" <<'SH'
#!/usr/bin/env bash
{
  printf 'argc=%s\n' "$#"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
  printf -- '---\n'
} >>"$TMUX_OPEN_HELPER_BROWSER_LOG"
SH
chmod +x "$no_python_browser_with_spaces"

: >"$no_python_browser_log"
HOME="$tmp/home" \
  PATH="$no_python_bin" \
  BROWSER="\"$no_python_browser_with_spaces\" --profile 'Work Profile' --target=%s" \
  TMUX_OPEN_HELPER_BROWSER_LOG="$no_python_browser_log" \
  "$helper" "https://example.test/no-python-browser?x=1"
wait_for_log "$no_python_browser_log"
assert_log \
  "http url supports quoted browser command without python" \
  "$no_python_browser_log" \
  "$(printf 'argc=3\narg=--profile\narg=Work Profile\narg=--target=https://example.test/no-python-browser?x=1\n---')"

: >"$browser_log"
HOME="$tmp/home" PATH="$tmp/bin:$PATH" BROWSER="$tmp/bin/browser" "$helper" "ssh://dev.example.com/repo.git"
wait_for_log "$browser_log"
assert_log \
  "generic uri opens with configured browser" \
  "$browser_log" \
  "$(printf 'argc=1\narg=ssh://dev.example.com/repo.git\n---')"

: >"$browser_log"
HOME="$tmp/home" PATH="$tmp/bin:$PATH" BROWSER="$tmp/bin/browser" "$helper" "mailto:ops@example.com"
wait_for_log "$browser_log"
assert_log \
  "mailto uri opens with configured browser" \
  "$browser_log" \
  "$(printf 'argc=1\narg=mailto:ops@example.com\n---')"

isolated_helper_dir="$tmp/isolated-helper"
isolated_path_bin="$tmp/isolated-path"
isolated_home="$tmp/isolated-home"
isolated_copy_log="$tmp/isolated-copy.log"
mkdir -p "$isolated_helper_dir" "$isolated_path_bin" "$isolated_home/.local/bin" "$isolated_home/dotfiles/common/.local/bin"
ln -s "$helper" "$isolated_helper_dir/tmux-open-helper.sh"
cat >"$isolated_path_bin/uname" <<'SH'
#!/usr/bin/env bash
printf 'Linux\n'
SH
chmod +x "$isolated_path_bin/uname"
cat >"$isolated_path_bin/osc-copy" <<'SH'
#!/usr/bin/env bash
printf 'path shadow osc-copy should not run\n' >&2
exit 99
SH
chmod +x "$isolated_path_bin/osc-copy"
cat >"$isolated_helper_dir/osc-copy" <<'SH'
#!/usr/bin/env bash
cat >>"$TMUX_OPEN_HELPER_COPY_LOG"
SH
chmod +x "$isolated_helper_dir/osc-copy"

TMUX_OPEN_HELPER_COPY_LOG="$isolated_copy_log" \
  HOME="$isolated_home" \
  PATH="$isolated_path_bin:/bin:/usr/bin:/usr/sbin:/sbin" \
  "$isolated_helper_dir/tmux-open-helper.sh" "https://example.test/adjacent-fallback" \
  >"$tmp/isolated-adjacent-copy.out" 2>"$tmp/isolated-adjacent-copy.err"
assert_log \
  "external uri copies via adjacent osc-copy before PATH shadow" \
  "$isolated_copy_log" \
  "https://example.test/adjacent-fallback"

cat >"$isolated_helper_dir/osc-copy" <<'SH'
#!/usr/bin/env bash
printf 'failing osc-copy invoked\n' >>"$TMUX_OPEN_HELPER_COPY_LOG"
exit 42
SH
chmod +x "$isolated_helper_dir/osc-copy"
: >"$isolated_copy_log"
set +e
TMUX_OPEN_HELPER_COPY_LOG="$isolated_copy_log" \
  HOME="$isolated_home" \
  PATH="$isolated_path_bin:/bin:/usr/bin:/usr/sbin:/sbin" \
  "$isolated_helper_dir/tmux-open-helper.sh" "https://example.test/failing-copy" \
  >"$tmp/isolated-failing-copy.out" 2>"$tmp/isolated-failing-copy.err"
isolated_failing_copy_status=$?
set -e
assert_log "external uri exits non-zero when osc-copy fails" <(printf '%s\n' "$isolated_failing_copy_status") "1"
assert_log \
  "external uri invokes failing osc-copy" \
  "$isolated_copy_log" \
  "failing osc-copy invoked"
assert_log \
  "external uri reports failing copy helper" \
  "$tmp/isolated-failing-copy.err" \
  "$(printf 'Error: failed to copy link to clipboard\nUnable to copy link to clipboard')"

: >"$isolated_copy_log"
rm -f "$isolated_helper_dir/osc-copy"
cat >"$isolated_home/.local/bin/osc-copy" <<'SH'
#!/usr/bin/env bash
cat >>"$TMUX_OPEN_HELPER_COPY_LOG"
SH
chmod +x "$isolated_home/.local/bin/osc-copy"

TMUX_OPEN_HELPER_COPY_LOG="$isolated_copy_log" \
  HOME="$isolated_home" \
  PATH="$isolated_path_bin:/bin:/usr/bin:/usr/sbin:/sbin" \
  "$isolated_helper_dir/tmux-open-helper.sh" "https://example.test/home-local-fallback" \
  >"$tmp/isolated-home-local-copy.out" 2>"$tmp/isolated-home-local-copy.err"
assert_log \
  "external uri copies via home local osc-copy before PATH shadow" \
  "$isolated_copy_log" \
  "https://example.test/home-local-fallback"

: >"$isolated_copy_log"
rm -f "$isolated_home/.local/bin/osc-copy"
cat >"$isolated_home/dotfiles/common/.local/bin/osc-copy" <<'SH'
#!/usr/bin/env bash
cat >>"$TMUX_OPEN_HELPER_COPY_LOG"
SH
chmod +x "$isolated_home/dotfiles/common/.local/bin/osc-copy"

TMUX_OPEN_HELPER_COPY_LOG="$isolated_copy_log" \
  HOME="$isolated_home" \
  PATH="$isolated_path_bin:/bin:/usr/bin:/usr/sbin:/sbin" \
  "$isolated_helper_dir/tmux-open-helper.sh" "https://example.test/fallback" \
  >"$tmp/isolated-copy.out" 2>"$tmp/isolated-copy.err"
assert_log \
  "external uri copies via home dotfiles osc-copy fallback" \
  "$isolated_copy_log" \
  "https://example.test/fallback"

stale_helper_dir="$tmp/stale-helper"
stale_path_bin="$tmp/stale-path"
stale_home="$tmp/stale-home"
stale_copy_log="$tmp/stale-copy.log"
stale_tmux_log="$tmp/stale-tmux.log"
mkdir -p "$stale_helper_dir" "$stale_path_bin" "$stale_home/dotfiles/common/.local/bin"
ln -s "$helper" "$stale_helper_dir/tmux-open-helper.sh"
ln -s "$(command -v bash)" "$stale_path_bin/bash"
ln -s "$(command -v cat)" "$stale_path_bin/cat"
ln -s "$(command -v dirname)" "$stale_path_bin/dirname"
cat >"$stale_path_bin/uname" <<'SH'
#!/usr/bin/env bash
printf 'Linux\n'
SH
chmod +x "$stale_path_bin/uname"
cat >"$stale_path_bin/tmux" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "display-message" && "${2:-}" != "-p" ]]; then
  printf '%s\n' "${TMUX-<unset>}" >>"${TMUX_OPEN_HELPER_TMUX_LOG:?}"
fi
exit 1
SH
chmod +x "$stale_path_bin/tmux"
cat >"$stale_path_bin/osc-copy" <<'SH'
#!/usr/bin/env bash
printf 'path shadow osc-copy should not run\n' >&2
exit 99
SH
chmod +x "$stale_path_bin/osc-copy"
cat >"$stale_home/dotfiles/common/.local/bin/osc-copy" <<'SH'
#!/usr/bin/env bash
cat >>"$TMUX_OPEN_HELPER_COPY_LOG"
SH
chmod +x "$stale_home/dotfiles/common/.local/bin/osc-copy"

TMUX="$tmp/stale-client" \
  TMUX_OPEN_HELPER_COPY_LOG="$stale_copy_log" \
  TMUX_OPEN_HELPER_TMUX_LOG="$stale_tmux_log" \
  HOME="$stale_home" \
  PATH="$stale_path_bin" \
  "$stale_helper_dir/tmux-open-helper.sh" "https://example.test/stale-fallback" \
  >"$tmp/stale-copy.out" 2>"$tmp/stale-copy.err"
assert_log \
  "stale TMUX external uri copies via home dotfiles osc-copy fallback without env" \
  "$stale_copy_log" \
  "https://example.test/stale-fallback"
assert_log \
  "stale TMUX open helper clears TMUX for display message without env" \
  "$stale_tmux_log" \
  "<unset>"

ssh_no_clipboard_bin="$tmp/ssh-no-clipboard-bin"
ssh_no_clipboard_helper_dir="$tmp/ssh-no-clipboard-helper"
ssh_no_clipboard_home="$tmp/ssh-no-clipboard-home"
ssh_no_clipboard_open_log="$tmp/ssh-no-clipboard.open"
ssh_no_clipboard_pbcopy_log="$tmp/ssh-no-clipboard.pbcopy"
ssh_no_clipboard_wlcopy_log="$tmp/ssh-no-clipboard.wl-copy"
ssh_no_clipboard_xclip_log="$tmp/ssh-no-clipboard.xclip"
mkdir -p "$ssh_no_clipboard_bin" "$ssh_no_clipboard_helper_dir" "$ssh_no_clipboard_home"
ln -s "$helper" "$ssh_no_clipboard_helper_dir/tmux-open-helper.sh"
ln -s "$(command -v bash)" "$ssh_no_clipboard_bin/bash"
cat >"$ssh_no_clipboard_bin/uname" <<'SH'
#!/usr/bin/env bash
printf 'Darwin\n'
SH
chmod +x "$ssh_no_clipboard_bin/uname"
cat >"$ssh_no_clipboard_bin/open" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$TMUX_OPEN_HELPER_OPEN_LOG"
SH
chmod +x "$ssh_no_clipboard_bin/open"
cat >"$ssh_no_clipboard_bin/pbcopy" <<'SH'
#!/usr/bin/env bash
printf 'pbcopy invoked\n' >"$TMUX_OPEN_HELPER_PBCOPY_LOG"
while IFS= read -r _; do :; done
SH
chmod +x "$ssh_no_clipboard_bin/pbcopy"
cat >"$ssh_no_clipboard_bin/wl-copy" <<'SH'
#!/usr/bin/env bash
printf 'wl-copy invoked\n' >"$TMUX_OPEN_HELPER_WLCOPY_LOG"
while IFS= read -r _; do :; done
SH
chmod +x "$ssh_no_clipboard_bin/wl-copy"
cat >"$ssh_no_clipboard_bin/xclip" <<'SH'
#!/usr/bin/env bash
printf 'xclip invoked\n' >"$TMUX_OPEN_HELPER_XCLIP_LOG"
while IFS= read -r _; do :; done
SH
chmod +x "$ssh_no_clipboard_bin/xclip"

rm -f "$ssh_no_clipboard_open_log" "$ssh_no_clipboard_pbcopy_log" "$ssh_no_clipboard_wlcopy_log" "$ssh_no_clipboard_xclip_log"
set +e
SSH_CLIENT="127.0.0.1 1000 22" \
  HOME="$ssh_no_clipboard_home" \
  PATH="$ssh_no_clipboard_bin" \
  TMUX_OPEN_HELPER_OPEN_LOG="$ssh_no_clipboard_open_log" \
  TMUX_OPEN_HELPER_PBCOPY_LOG="$ssh_no_clipboard_pbcopy_log" \
  TMUX_OPEN_HELPER_WLCOPY_LOG="$ssh_no_clipboard_wlcopy_log" \
  TMUX_OPEN_HELPER_XCLIP_LOG="$ssh_no_clipboard_xclip_log" \
  "$ssh_no_clipboard_helper_dir/tmux-open-helper.sh" "https://example.test/ssh-no-local-open" \
  >"$tmp/ssh-no-clipboard-link.out" 2>"$tmp/ssh-no-clipboard-link.err"
ssh_no_clipboard_status=$?
set -e
assert_log "ssh external uri without clipboard helper exits non-zero" <(printf '%s\n' "$ssh_no_clipboard_status") "1"
assert_file_absent "ssh external uri skips host open without helper" "$ssh_no_clipboard_open_log"
assert_file_absent "ssh external uri skips host pbcopy without helper" "$ssh_no_clipboard_pbcopy_log"
assert_file_absent "ssh external uri skips host wl-copy without helper" "$ssh_no_clipboard_wlcopy_log"
assert_file_absent "ssh external uri skips host xclip without helper" "$ssh_no_clipboard_xclip_log"
assert_log \
  "ssh external uri reports missing clipboard helper" \
  "$tmp/ssh-no-clipboard-link.err" \
  "Error: cannot open link and no clipboard helper is available"

rm -f "$ssh_no_clipboard_open_log" "$ssh_no_clipboard_pbcopy_log" "$ssh_no_clipboard_wlcopy_log" "$ssh_no_clipboard_xclip_log"
set +e
SSH_CLIENT="127.0.0.1 1000 22" \
  HOME="$ssh_no_clipboard_home" \
  PATH="$ssh_no_clipboard_bin" \
  TMUX_OPEN_HELPER_OPEN_LOG="$ssh_no_clipboard_open_log" \
  TMUX_OPEN_HELPER_PBCOPY_LOG="$ssh_no_clipboard_pbcopy_log" \
  TMUX_OPEN_HELPER_WLCOPY_LOG="$ssh_no_clipboard_wlcopy_log" \
  TMUX_OPEN_HELPER_XCLIP_LOG="$ssh_no_clipboard_xclip_log" \
  "$ssh_no_clipboard_helper_dir/tmux-open-helper.sh" "$tmp/work/src/app.py" \
  >"$tmp/ssh-no-clipboard-path.out" 2>"$tmp/ssh-no-clipboard-path.err"
ssh_no_clipboard_path_status=$?
set -e
assert_log "ssh path without clipboard helper exits non-zero" <(printf '%s\n' "$ssh_no_clipboard_path_status") "1"
assert_file_absent "ssh path skips host open without helper" "$ssh_no_clipboard_open_log"
assert_file_absent "ssh path skips host pbcopy without helper" "$ssh_no_clipboard_pbcopy_log"
assert_file_absent "ssh path skips host wl-copy without helper" "$ssh_no_clipboard_wlcopy_log"
assert_file_absent "ssh path skips host xclip without helper" "$ssh_no_clipboard_xclip_log"
assert_log \
  "ssh path reports missing clipboard helper" \
  "$tmp/ssh-no-clipboard-path.err" \
  "Error: cannot open path and no clipboard helper is available"
