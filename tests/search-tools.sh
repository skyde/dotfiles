#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/search-tools.XXXXXX")"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

assert_contains() {
  local description="$1"
  local haystack="$2"
  local needle="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'not ok - %s\nmissing:\n%s\nactual:\n%s\n' "$description" "$needle" "$haystack" >&2
    exit 1
  fi

  pass "$description"
}

assert_not_contains() {
  local description="$1"
  local haystack="$2"
  local needle="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'not ok - %s\nunexpected:\n%s\nactual:\n%s\n' "$description" "$needle" "$haystack" >&2
    exit 1
  fi

  pass "$description"
}

assert_file_exists() {
  local description="$1"
  local path="$2"

  if [[ ! -e "$path" ]]; then
    printf 'not ok - %s\nmissing path: %s\n' "$description" "$path" >&2
    exit 1
  fi

  pass "$description"
}

shell_quote() {
  printf '%q' "$1"
}

mkdir -p "$tmp/bin"
for command_name in rg bat zoekt; do
  cat >"$tmp/bin/$command_name" <<'SH'
#!/usr/bin/env sh
exit 0
SH
  chmod +x "$tmp/bin/$command_name"
done

for command_name in st-rg st-zoekt; do
  cat >"$tmp/bin/$command_name" <<'SH'
#!/usr/bin/env sh
exit 77
SH
  chmod +x "$tmp/bin/$command_name"
done

cat >"$tmp/bin/zoekt-index" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

index_dir=""
{
  printf 'cwd=%s\n' "$PWD"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
} >"${SEARCH_TOOLS_INDEX_LOG:?}"

while (($#)); do
  case "$1" in
    -index)
      shift
      index_dir="${1:?}"
      ;;
  esac
  shift || true
done

[[ -n "$index_dir" ]] || exit 3
printf 'indexed\n' >"$index_dir/indexed"
SH
chmod +x "$tmp/bin/zoekt-index"

cat >"$tmp/bin/fzf" <<'SH'
#!/usr/bin/env bash
{
  printf 'argc=%s\n' "$#"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
} >"${SEARCH_TOOLS_FZF_LOG:?}"
SH
chmod +x "$tmp/bin/fzf"

st_source="$(<"$root/common/.local/bin/st")"
dollar='$'
assert_not_contains \
  "st does not probe root-local helper fallback" \
  "$st_source" \
  "${dollar}{HOME:-}/.local/bin/"
assert_not_contains \
  "st does not probe root dotfiles helper fallback" \
  "$st_source" \
  "${dollar}{HOME:-}/dotfiles/common/.local/bin/"

isolated_st_dir="$tmp/isolated st"
isolated_st_path="$tmp/isolated st path"
isolated_st_root="$tmp/isolated st root"
mkdir -p "$isolated_st_dir" "$isolated_st_path" "$isolated_st_root"
ln -s "$root/common/.local/bin/st" "$isolated_st_dir/st"
cat >"$isolated_st_path/st-rg" <<'SH'
#!/usr/bin/env bash
{
  printf 'helper=st-rg\n'
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
} >"${SEARCH_TOOLS_ST_HELPER_LOG:?}"
SH
chmod +x "$isolated_st_path/st-rg"

env -u HOME \
  SEARCH_TOOLS_ST_HELPER_LOG="$tmp/st-path-unset-home.log" \
  PATH="$isolated_st_path:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$isolated_st_dir/st" "$isolated_st_root"
assert_contains \
  "st falls back to PATH helper when HOME is unset" \
  "$(cat "$tmp/st-path-unset-home.log")" \
  "arg=$isolated_st_root"

HOME="" \
  SEARCH_TOOLS_ST_HELPER_LOG="$tmp/st-path-empty-home.log" \
  PATH="$isolated_st_path:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$isolated_st_dir/st" "$isolated_st_root"
assert_contains \
  "st falls back to PATH helper when HOME is empty" \
  "$(cat "$tmp/st-path-empty-home.log")" \
  "arg=$isolated_st_root"

rg_root="$tmp/search root's dir"
mkdir -p "$rg_root/src"
rg_log="$tmp/st-rg.log"
SEARCH_TOOLS_FZF_LOG="$rg_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/st-rg" "$rg_root"
rg_output="$(cat "$rg_log")"
quoted_rg_root="$(shell_quote "$rg_root")"
assert_contains "st-rg enter binding shell-quotes root" "$rg_output" "arg=enter:become(cd $quoted_rg_root && nvim +{2} {1})"
assert_contains "st-rg reload shell-quotes root" "$rg_output" "arg=start:reload:cd $quoted_rg_root && rg"
assert_contains "st-rg preview shell-quotes root" "$rg_output" "arg=cd $quoted_rg_root && bat"
assert_contains "st-rg preview highlights selected line" "$rg_output" "--highlight-line {2} {1}"
assert_not_contains "st-rg preview does not pass line as a file" "$rg_output" "--paging=never {2} {1}"

if SEARCH_TOOLS_FZF_LOG="$tmp/st-rg-missing.log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/st-rg" "$tmp/missing-rg-root" >"$tmp/st-rg-missing.out" 2>"$tmp/st-rg-missing.err"; then
  printf 'not ok - st-rg exits non-zero for missing root\n' >&2
  exit 1
fi
pass "st-rg exits non-zero for missing root"
assert_contains \
  "st-rg reports missing root" \
  "$(cat "$tmp/st-rg-missing.err")" \
  "error: search root not found: $tmp/missing-rg-root"

rg_code_log="$tmp/st-rg-code.log"
SEARCH_TOOLS_FZF_LOG="$rg_code_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/st-rg" --code "$rg_root"
rg_code_output="$(cat "$rg_code_log")"
assert_contains \
  "st-rg code binding shell-quotes root" \
  "$rg_code_output" \
  "arg=enter:execute-silent(cd $quoted_rg_root && code -r -g {1}:{2})"

zoekt_root="$tmp/zoekt root's dir"
mkdir -p "$zoekt_root/.zoekt"
zoekt_log="$tmp/st-zoekt.log"
SEARCH_TOOLS_FZF_LOG="$zoekt_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/st-zoekt" "$zoekt_root"
zoekt_output="$(cat "$zoekt_log")"
quoted_zoekt_root="$(shell_quote "$zoekt_root")"
quoted_zoekt_index="$(shell_quote "$zoekt_root/.zoekt")"
assert_contains "st-zoekt enter binding shell-quotes root" "$zoekt_output" "arg=enter:become(cd $quoted_zoekt_root && nvim +{2} {1})"
assert_contains "st-zoekt reload shell-quotes index" "$zoekt_output" "zoekt -index_dir $quoted_zoekt_index --"
assert_contains "st-zoekt preview shell-quotes root" "$zoekt_output" "arg=cd $quoted_zoekt_root && bat"
assert_contains "st-zoekt preview highlights selected line" "$zoekt_output" "--highlight-line {2} {1}"
assert_not_contains "st-zoekt preview does not pass line as a file" "$zoekt_output" "--paging=never {2} {1}"

if SEARCH_TOOLS_FZF_LOG="$tmp/st-zoekt-missing.log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/st-zoekt" "$tmp/missing-zoekt-root" >"$tmp/st-zoekt-missing.out" 2>"$tmp/st-zoekt-missing.err"; then
  printf 'not ok - st-zoekt exits non-zero for missing root\n' >&2
  exit 1
fi
pass "st-zoekt exits non-zero for missing root"
assert_contains \
  "st-zoekt reports missing root" \
  "$(cat "$tmp/st-zoekt-missing.err")" \
  "error: search root not found: $tmp/missing-zoekt-root"

no_index_root="$tmp/zoekt without index"
mkdir -p "$no_index_root"
if SEARCH_TOOLS_FZF_LOG="$tmp/st-zoekt-no-index.log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/st-zoekt" "$no_index_root" >"$tmp/st-zoekt-no-index.out" 2>"$tmp/st-zoekt-no-index.err"; then
  printf 'not ok - st-zoekt exits non-zero without index\n' >&2
  exit 1
fi
pass "st-zoekt exits non-zero without index"
assert_contains \
  "st-zoekt reports missing index" \
  "$(cat "$tmp/st-zoekt-no-index.err")" \
  "error: no Zoekt index found at: $no_index_root/.zoekt"

dispatch_rg_root="$tmp/dispatch rg root"
mkdir -p "$dispatch_rg_root"
dispatch_rg_log="$tmp/st-dispatch-rg.log"
SEARCH_TOOLS_FZF_LOG="$dispatch_rg_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/st" "$dispatch_rg_root"
quoted_dispatch_rg_root="$(shell_quote "$dispatch_rg_root")"
assert_contains \
  "st dispatches unindexed target to adjacent st-rg before PATH shadow" \
  "$(cat "$dispatch_rg_log")" \
  "arg=start:reload:cd $quoted_dispatch_rg_root && rg"

dispatch_zoekt_root="$tmp/dispatch zoekt root"
mkdir -p "$dispatch_zoekt_root/.zoekt"
dispatch_zoekt_log="$tmp/st-dispatch-zoekt.log"
SEARCH_TOOLS_FZF_LOG="$dispatch_zoekt_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/st" "$dispatch_zoekt_root"
quoted_dispatch_zoekt_index="$(shell_quote "$dispatch_zoekt_root/.zoekt")"
assert_contains \
  "st dispatches indexed target to adjacent st-zoekt before PATH shadow" \
  "$(cat "$dispatch_zoekt_log")" \
  "zoekt -index_dir $quoted_dispatch_zoekt_index --"

printf 'int main(void) { return 0; }\n' >"$dispatch_zoekt_root/main.c"
dispatch_file_log="$tmp/st-dispatch-file.log"
SEARCH_TOOLS_FZF_LOG="$dispatch_file_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/st" --code "$dispatch_zoekt_root/main.c"
quoted_dispatch_zoekt_root="$(shell_quote "$dispatch_zoekt_root")"
assert_contains \
  "st dispatches indexed file target parent to st-zoekt" \
  "$(cat "$dispatch_file_log")" \
  "zoekt -index_dir $quoted_dispatch_zoekt_index --"
assert_contains \
  "st preserves --code through indexed dispatch" \
  "$(cat "$dispatch_file_log")" \
  "arg=enter:execute-silent(cd $quoted_dispatch_zoekt_root && code -r -g {1}:{2})"

index_root="$tmp/index root's dir"
mkdir -p "$index_root/src"
index_log="$tmp/si-index.log"
index_stdout="$(
  SEARCH_TOOLS_INDEX_LOG="$index_log" \
    PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$root/common/.local/bin/si" "$index_root/src/.."
)"
assert_contains "si announces requested index root" "$index_stdout" "Indexing $index_root with "
assert_contains "si runs zoekt-index from requested root" "$(cat "$index_log")" "cwd=$index_root"
assert_contains "si passes temporary index directory" "$(cat "$index_log")" "arg=$index_root/.zoekt.tmp."
assert_file_exists "si swaps completed index into requested root" "$index_root/.zoekt/indexed"
if compgen -G "$index_root/.zoekt.tmp.*" >/dev/null; then
  printf 'not ok - si removes temporary index directory\n' >&2
  exit 1
fi
pass "si removes temporary index directory"

file_root="$tmp/file target root"
mkdir -p "$file_root/app"
printf 'int main(void) { return 0; }\n' >"$file_root/app/main.c"
file_index_log="$tmp/si-file-index.log"
SEARCH_TOOLS_INDEX_LOG="$file_index_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/si" "$file_root/app/main.c" >/dev/null
assert_contains "si indexes file target parent directory" "$(cat "$file_index_log")" "cwd=$file_root/app"
assert_file_exists "si writes file target parent index" "$file_root/app/.zoekt/indexed"

missing_index_root="$tmp/missing index root"
if SEARCH_TOOLS_INDEX_LOG="$tmp/si-missing-root.log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/si" "$missing_index_root" >"$tmp/si-missing-root.out" 2>"$tmp/si-missing-root.err"; then
  printf 'not ok - si exits non-zero for missing root\n' >&2
  exit 1
fi
pass "si exits non-zero for missing root"
assert_contains \
  "si reports missing root" \
  "$(cat "$tmp/si-missing-root.err")" \
  "error: index root not found: $missing_index_root"

missing_tool_root="$tmp/missing zoekt-index root"
mkdir -p "$missing_tool_root"
if PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/si" "$missing_tool_root" >"$tmp/si-missing-tool.out" 2>"$tmp/si-missing-tool.err"; then
  printf 'not ok - si exits non-zero when zoekt-index is missing\n' >&2
  exit 1
fi
pass "si exits non-zero when zoekt-index is missing"
assert_contains \
  "si reports missing zoekt-index" \
  "$(cat "$tmp/si-missing-tool.err")" \
  "error: zoekt-index not found in PATH"

if "$root/common/.local/bin/si" "$index_root" extra >"$tmp/si-too-many.out" 2>"$tmp/si-too-many.err"; then
  printf 'not ok - si exits non-zero for too many arguments\n' >&2
  exit 1
fi
pass "si exits non-zero for too many arguments"
assert_contains "si prints usage for too many arguments" "$(cat "$tmp/si-too-many.err")" "Usage: si [PATH]"
