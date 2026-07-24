#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d)
p4d_pid=

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  set +e
  if [[ -n $p4d_pid ]] && kill -0 "$p4d_pid" 2>/dev/null; then
    kill "$p4d_pid" 2>/dev/null
    for _ in $(seq 1 100); do
      kill -0 "$p4d_pid" 2>/dev/null || break
      sleep 0.02
    done
    if kill -0 "$p4d_pid" 2>/dev/null; then
      kill -KILL "$p4d_pid" 2>/dev/null
    fi
  fi
  if ((status != 0)) && [[ -s $test_root/p4d.log ]]; then
    printf '%s\n' '--- p4d.log ---' >&2
    tail -200 "$test_root/p4d.log" >&2
  fi
  rm -rf "$test_root"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

encode_p4_filespec() {
  local path=$1
  path=${path//%/%25}
  path=${path//@/%40}
  path=${path//\#/%23}
  path=${path//\*/%2A}
  printf '%s\n' "$path"
}

[[ $(uname -s) == Linux ]] || fail "P4 integration test currently requires Linux"
command -v p4 >/dev/null 2>&1 || fail "p4 is not installed"
command -v p4d >/dev/null 2>&1 || fail "p4d is not installed"
command -v python3 >/dev/null 2>&1 || fail "python3 is not installed"

server_root="$test_root/server"
workspace="$test_root/workspace ü"
unrelated="$test_root/unrelated cwd"
mkdir -p "$server_root" "$workspace/src one" "$workspace/src two" "$test_root/bin" "$unrelated"

port=$(
  python3 -c \
    'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
)
export P4PORT="127.0.0.1:$port"
export P4USER=nvim-test
export P4CLIENT=nvim-test-client

p4d -q --daemonsafe \
  --pid-file="$test_root/p4d.pid" \
  -r "$server_root" \
  -J off \
  -L "$test_root/p4d.log" \
  -p "$P4PORT"
p4d_pid=$(<"$test_root/p4d.pid")

ready=0
for _ in $(seq 1 100); do
  if p4 info >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.02
done
((ready == 1)) || fail "persistent p4d did not become ready"
p4 client -i >/dev/null <<EOF
Client: $P4CLIENT
Owner: $P4USER
Root: $workspace
Options: noallwrite noclobber nocompress unlocked nomodtime rmdir
SubmitOptions: submitunchanged
LineEnd: local
View:
	//depot/... //$P4CLIENT/...
EOF

p4 client -i >/dev/null <<EOF
Client: nvim-test-decoy
Owner: $P4USER
Root: $unrelated
Options: noallwrite noclobber nocompress unlocked nomodtime rmdir
SubmitOptions: submitunchanged
LineEnd: local
View:
	//depot/... //nvim-test-decoy/...
EOF

plain="$workspace/000-plain.txt"
current="$workspace/src one/current file ü [*] #%.txt"
current_filespec=$(encode_p4_filespec "$current")
depot_current="//depot/src one/current file ü [%2A] %23%25.txt"
other="$workspace/src two/other file ü.txt"
outside="$test_root/outside file ü.txt"
printf 'plain\n' >"$plain"
printf 'base\n' >"$current"
printf 'base\n' >"$other"
printf 'outside\n' >"$outside"
p4 add "$plain" "$other" >/dev/null
p4 add -f "$current" >/dev/null
p4 submit -d "initial files" >/dev/null
p4 edit "$current_filespec" "$other" >/dev/null
printf 'base\ncurrent change\n' >"$current"
printf 'base\nother change\n' >"$other"

# Exercise the common P4CONFIG workflow: the client is available only when a
# command runs from the workspace tree, while Neovim itself starts elsewhere.
# Keep the real client config below the client root. Diffview still uses the
# root for path math, but every P4 process must retain this discovery cwd.
printf 'P4CLIENT=%s\n' "$P4CLIENT" >"$workspace/src one/.p4config"
printf 'P4CLIENT=%s\n' "$P4CLIENT" >"$workspace/src two/.p4config"
printf 'P4CLIENT=%s\n' "nvim-test-decoy" >"$unrelated/.p4config"
export P4CONFIG=.p4config
unset P4CLIENT

real_p4=$(command -v p4)
command_log="$test_root/p4-commands"
command_cwd_log="$test_root/p4-command-cwds"
info_cwd_log="$test_root/p4-info-cwds"
cat >"$test_root/bin/log-p4" <<SH
#!/usr/bin/env bash
printf '%s\n' "\${1:-}" >>"\$P4_COMMAND_LOG"
printf '%s\t%s\n' "\${1:-}" "\$PWD" >>"\$P4_COMMAND_CWD_LOG"
if [[ \${1:-} == info ]]; then
  printf '%s\n' "\$PWD" >>"\$P4_INFO_CWD_LOG"
fi
exec "$real_p4" "\$@"
SH
chmod +x "$test_root/bin/log-p4"

cat >"$test_root/bin/hanging-p4" <<SH
#!/usr/bin/env bash
printf 'info\n' >>"$test_root/p4-hang-calls"
exec sleep 30
SH
chmod +x "$test_root/bin/hanging-p4"

export P4_TEST_WORKSPACE="$workspace"
export P4_TEST_SUBTREE="$workspace/src one"
export P4_TEST_DIRECT_CPATH="$workspace/src two"
export P4_TEST_CURRENT_FILE="$current"
export P4_TEST_CURRENT_FILESPEC="$current_filespec"
export P4_TEST_DEPOT_CURRENT="$depot_current"
export P4_TEST_OTHER_FILE="$other"
export P4_TEST_OUTSIDE_FILE="$outside"
export P4_TEST_UNRELATED_CWD="$unrelated"
export P4_TEST_HANGING_P4="$test_root/bin/hanging-p4"
export P4_HANG_LOG="$test_root/p4-hang-calls"
export P4_COMMAND_LOG="$command_log"
export P4_COMMAND_CWD_LOG="$command_cwd_log"
export P4_INFO_CWD_LOG="$info_cwd_log"
export NVIM_PERFORCE_CMD="$test_root/bin/log-p4"
export NVIM_P4_TIMEOUT_SECONDS=10

(
  cd "$unrelated"
  nvim --headless -u NONE -i NONE -l "$repo_root/tests/nvim_p4_spec.lua"
  nvim --headless -i NONE "$current" \
    -c "lua local ok, err = pcall(dofile, [[$repo_root/tests/nvim_p4_diffview_spec.lua]]); if not ok then vim.api.nvim_err_writeln(err); vim.cmd('cquit 1') end" \
    +qa
)

if [[ -f $info_cwd_log ]] && grep -Fx -- "$unrelated" "$info_cwd_log" >/dev/null; then
  fail "a P4 info probe used Neovim's unrelated process cwd"
fi
while IFS=$'\t' read -r p4_subcommand p4_cwd; do
  if
    [[ $p4_subcommand != info ]] \
      && [[ $p4_cwd != "$workspace/src one" ]] \
      && [[ $p4_cwd != "$workspace/src two" ]]
  then
    fail "P4 operation '$p4_subcommand' lost nested P4CONFIG cwd (used '$p4_cwd')"
  fi
done <"$command_cwd_log"

# Confirm P4 itself invokes the configured two-way diff program with a depot
# temporary file followed by the exact workspace path. The wrapper's Neovim
# side is exercised by nvim_diff_tool_spec.lua.
cat >"$test_root/bin/capture-diff" <<'SH'
#!/usr/bin/env bash
: >"$P4_DIFF_CAPTURE"
for argument in "$@"; do
  printf '%s\n' "$argument" >>"$P4_DIFF_CAPTURE"
done
cp -- "$1" "$P4_DIFF_BASE_CAPTURE"
SH
chmod +x "$test_root/bin/capture-diff"
diff_capture="$test_root/p4-diff-args"
base_capture="$test_root/p4-diff-base"
P4DIFF="$test_root/bin/capture-diff" \
  P4_DIFF_CAPTURE="$diff_capture" \
  P4_DIFF_BASE_CAPTURE="$base_capture" \
  p4 -c nvim-test-client -d "$workspace" diff "$current_filespec" >/dev/null
mapfile -t diff_args <"$diff_capture"
[[ ${#diff_args[@]} -eq 2 ]] || fail "P4DIFF received ${#diff_args[@]} arguments instead of 2"
[[ $(<"$base_capture") == base ]] || fail "P4DIFF's depot-side temporary file has unexpected contents"
[[ ${diff_args[1]} == "$current" ]] || fail "P4DIFF changed the workspace file path"

# The shell shim is a second safety net outside Neovim.
set +e
NVIM_PERFORCE_CMD="$test_root/bin/hanging-p4" \
  NVIM_P4_TIMEOUT_SECONDS=0.2 \
  "$repo_root/common/.local/bin/vcs-p4" info >/dev/null 2>&1
hang_status=$?
set -e
[[ $hang_status -eq 124 ]] || fail "vcs-p4 did not time out a hanging info probe (exit $hang_status)"

printf 'nvim P4 integration tests passed\n'
