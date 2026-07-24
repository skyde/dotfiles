#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_line() {
  local expected=$1
  local file=$2
  grep -Fx -- "$expected" "$file" >/dev/null || fail "missing '$expected' in $file"
}

mkdir -p "$test_root/bin" "$test_root/paths/left dir" "$test_root/paths/right dir"
left="$test_root/paths/left dir/alpha ü.txt"
right="$test_root/paths/right dir/beta ü.txt"
output="$test_root/paths/output dir/result ü.txt"
base="$test_root/paths/base dir/base ü.txt"
theirs="$test_root/paths/theirs dir/theirs ü.txt"
yours="$test_root/paths/yours dir/yours ü.txt"
mkdir -p "$(dirname "$output")" "$(dirname "$base")" "$(dirname "$theirs")" "$(dirname "$yours")"
touch "$left" "$right" "$output" "$base" "$theirs" "$yours"

capture_init="$test_root/capture-init.lua"
capture_log="$test_root/nvim-command.txt"
cat >"$capture_init" <<'LUA'
local log = assert(vim.env.NVIM_CAPTURE_LOG)
package.preload["config.diff_tool"] = function()
  return {
    open = function(kind, args)
      vim.fn.writefile(vim.list_extend({ kind }, args), log)
    end,
  }
end
LUA

cat >"$test_root/bin/nvim" <<'SH'
#!/usr/bin/env bash
exec "$NVIM_REAL_BIN" --headless -u "$NVIM_CAPTURE_INIT" "$@" +qa
SH
chmod +x "$test_root/bin/nvim"

read_capture() {
  captured=()
  while IFS= read -r line; do
    captured+=("$line")
  done <"$capture_log"
}

real_nvim=$(command -v nvim)
PATH="$test_root/bin:$PATH" NVIM_REAL_BIN="$real_nvim" NVIM_CAPTURE_INIT="$capture_init" NVIM_CAPTURE_LOG="$capture_log" \
  "$repo_root/common/.local/bin/nvim-diff" "$left" "$right"
read_capture
[[ ${#captured[@]} -eq 3 ]] || fail "nvim-diff captured ${#captured[@]} arguments"
[[ ${captured[0]} == files ]] || fail "nvim-diff did not select file mode"
[[ ${captured[1]} == "$left" ]] || fail "nvim-diff changed the left path"
[[ ${captured[2]} == "$right" ]] || fail "nvim-diff changed the right path"

PATH="$test_root/bin:$PATH" NVIM_REAL_BIN="$real_nvim" NVIM_CAPTURE_INIT="$capture_init" NVIM_CAPTURE_LOG="$capture_log" \
  "$repo_root/common/.local/bin/nvim-diff" "$left" "$right" "$output"
read_capture
[[ ${#captured[@]} -eq 4 ]] || fail "directory diff captured ${#captured[@]} arguments"
[[ ${captured[0]} == dirs ]] || fail "nvim-diff did not select directory mode"
[[ ${captured[3]} == "$output" ]] || fail "directory diff changed the output path"

PATH="$test_root/bin:$PATH" NVIM_REAL_BIN="$real_nvim" NVIM_CAPTURE_INIT="$capture_init" NVIM_CAPTURE_LOG="$capture_log" \
  "$repo_root/common/.local/bin/nvim-merge" "$output" "$base" "$yours" "$theirs"
read_capture
[[ ${captured[*]} == "merge $output $base $yours $theirs" ]] || fail "nvim-merge changed argument order"

PATH="$test_root/bin:$PATH" NVIM_REAL_BIN="$real_nvim" NVIM_CAPTURE_INIT="$capture_init" NVIM_CAPTURE_LOG="$capture_log" \
  "$repo_root/common/.local/bin/nvim-p4merge" "$base" "$theirs" "$yours" "$output"
read_capture
[[ ${captured[*]} == "merge $output $base $yours $theirs" ]] || fail "nvim-p4merge changed P4 argument order"

(
  cd "$test_root/paths"
  PATH="$test_root/bin:$PATH" NVIM_REAL_BIN="$real_nvim" NVIM_CAPTURE_INIT="$capture_init" \
    NVIM_CAPTURE_LOG="$capture_log" "$repo_root/common/.local/bin/nvim-diff" \
    "left dir/alpha ü.txt" "right dir/beta ü.txt"
)
read_capture
[[ ${captured[1]} == "$left" && ${captured[2]} == "$right" ]] \
  || fail "nvim-diff did not absolutize relative tool paths"

cat >"$test_root/bin/cygpath" <<'SH'
#!/usr/bin/env bash
[[ ${1:-} == -am ]] || exit 2
shift
[[ ${1:-} == -- ]] && shift
path=${1:?}
printf '%s\n' "${path//\\//}"
SH
chmod +x "$test_root/bin/cygpath"
windows_left='C:\work path\left ü.txt'
windows_right='C:\work path\right ü.txt'
PATH="$test_root/bin:$PATH" NVIM_REAL_BIN="$real_nvim" NVIM_CAPTURE_INIT="$capture_init" \
  NVIM_CAPTURE_LOG="$capture_log" "$repo_root/common/.local/bin/nvim-diff" \
  "$windows_left" "$windows_right"
read_capture
[[ ${captured[1]} == "C:/work path/left ü.txt" && ${captured[2]} == "C:/work path/right ü.txt" ]] \
  || fail "nvim-diff corrupted Git-for-Windows paths"

cat >"$test_root/bin/record-vcs" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$0" "$@" >"$VCS_CAPTURE_LOG"
SH
chmod +x "$test_root/bin/record-vcs"

vcs_log="$test_root/vcs-command.txt"
PATH="$test_root/bin:$PATH" VCS_CAPTURE_LOG="$vcs_log" NVIM_PERFORCE_CMD=record-vcs \
  "$repo_root/common/.local/bin/vcs-p4" opened "$left"
assert_line "$test_root/bin/record-vcs" "$vcs_log"
assert_line "opened" "$vcs_log"
assert_line "$left" "$vcs_log"

ln -s record-vcs "$test_root/bin/g4"
PATH="$test_root/bin:$PATH" VCS_CAPTURE_LOG="$vcs_log" "$repo_root/common/.local/bin/vcs-p4" info
assert_line "$test_root/bin/g4" "$vcs_log"

rm "$test_root/bin/g4"
ln -s record-vcs "$test_root/bin/p4"
PATH="$test_root/bin:$PATH" VCS_CAPTURE_LOG="$vcs_log" "$repo_root/common/.local/bin/vcs-p4" info
assert_line "$test_root/bin/p4" "$vcs_log"

rm "$test_root/bin/p4"
if PATH="$test_root/bin:/usr/bin:/bin" "$repo_root/common/.local/bin/vcs-p4" info 2>/dev/null; then
  fail "vcs-p4 succeeded without g4 or p4"
else
  status=$?
  [[ $status -eq 127 ]] || fail "vcs-p4 returned $status instead of 127"
fi

printf 'nvim VCS wrapper tests passed\n'
