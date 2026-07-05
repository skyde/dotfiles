#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
preview="$root/common/.local/bin/tmux-fzf-url-preview.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/work/src" "$tmp/work/scripts" "$tmp/home/src"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  printf 'line %s\n' "$i"
done >"$tmp/work/src/app.py"
for ((i = 1; i <= 130; i++)); do
  printf 'limit %03d\n' "$i" >"$tmp/work/src/zz-limit-$(printf '%03d' "$i").txt"
done
printf '%s\n' 'space one' 'space two' 'space three' >"$tmp/work/src/my file.py"
printf '%s\n' 'fn main() {' '    println!("hello");' '}' >"$tmp/work/src/main.rs"
mkdir -p "$tmp/work/pkg"
printf '%s\n' 'package main' 'func main() {' '    run()' '}' >"$tmp/work/pkg/main.go"
printf '%s\n' '#!/bin/sh' 'missing command' 'echo done' >"$tmp/work/scripts/bootstrap.sh"
for i in 1 2 3 4 5; do
  printf 'cpp line %s\n' "$i"
done >"$tmp/work/main.cpp"
mkdir -p "$tmp/work/C:/Users/sky/project"
printf '%s\n' 'drive trap one' 'drive trap two' >"$tmp/work/C:/Users/sky/project/main.cpp"
printf '%s\n' 'unc trap one' 'unc trap two' >"$tmp/work/\\\\server\\share\\repo\\main.cpp"
printf '%s\n' 'home one' 'home two' 'home three' >"$tmp/home/src/home.py"

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

run_preview() {
  local target="$1"

  HOME="$tmp/home" PATH="/usr/bin:/bin:/usr/sbin:/sbin" TMUX_FZF_URL_BASE_DIR="$tmp/work" "$preview" "$target"
}

run_preview_no_sed() {
  local target="$1"

  HOME="$tmp/home" PATH="$no_sed_bin" TMUX_FZF_URL_BASE_DIR="$tmp/work" "$preview" "$target"
}

run_preview_no_python() {
  local target="$1"

  HOME="$tmp/home" PATH="$no_python_bin" TMUX_FZF_URL_BASE_DIR="$tmp/work" "$preview" "$target"
}

run_preview_no_find_sort() {
  local target="$1"

  HOME="$tmp/home" PATH="$no_find_sort_bin" TMUX_FZF_URL_BASE_DIR="$tmp/work" "$preview" "$target"
}

run_preview_no_awk() {
  local target="$1"

  HOME="$tmp/home" PATH="$no_awk_bin" TMUX_FZF_URL_BASE_DIR="$tmp/work" "$preview" "$target"
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

no_sed_bin="$tmp/no-sed-bin"
mkdir -p "$no_sed_bin"
for tool in bash find awk sort python3; do
  ln -s "$(command -v "$tool")" "$no_sed_bin/$tool"
done

no_python_bin="$tmp/no-python-bin"
mkdir -p "$no_python_bin"
for tool in bash awk; do
  ln -s "$(command -v "$tool")" "$no_python_bin/$tool"
done

no_find_sort_bin="$tmp/no-find-sort-bin"
mkdir -p "$no_find_sort_bin"
ln -s "$(command -v bash)" "$no_find_sort_bin/bash"

no_awk_bin="$tmp/no-awk-bin"
mkdir -p "$no_awk_bin"
ln -s "$(command -v bash)" "$no_awk_bin/bash"

app_path="$(resolve_path "$tmp/work/src/app.py")"
cpp_path="$(resolve_path "$tmp/work/main.cpp")"
rust_path="$(resolve_path "$tmp/work/src/main.rs")"
go_path="$(resolve_path "$tmp/work/pkg/main.go")"
shell_path="$(resolve_path "$tmp/work/scripts/bootstrap.sh")"
src_path="$(resolve_path "$tmp/work/src")"
no_sed_src_path="$tmp/work/src"
home_path="$(resolve_path "$tmp/home/src/home.py")"
raw_space_path="$tmp/work/src/my file.py"
space_path="$(resolve_path "$tmp/work/src/my file.py")"
space_url_path="$(urlencode_path "$space_path")"

file_preview="$(run_preview "src/app.py:3")"
assert_contains "file preview shows path" "$file_preview" "$app_path"
assert_contains "file preview highlights selected line" "$file_preview" ">     3  line 3"
assert_contains "file preview shows nearby lines" "$file_preview" "      1  line 1"

file_preview_no_awk="$(run_preview_no_awk "$tmp/work/src/app.py:3")"
assert_contains "file preview works without awk bat realpath or python" "$file_preview_no_awk" "$tmp/work/src/app.py"
assert_contains "file preview without awk highlights selected line" "$file_preview_no_awk" ">     3  line 3"
assert_contains "file preview without awk shows nearby lines" "$file_preview_no_awk" "      1  line 1"

file_range_preview="$(run_preview "src/app.py:4-7")"
assert_contains "file range preview shows path" "$file_range_preview" "$app_path"
assert_contains "file range preview highlights first line" "$file_range_preview" ">     4  line 4"

spaced_file_preview="$(run_preview "src/my file.py:2:1")"
assert_contains "spaced file preview shows path" "$spaced_file_preview" "$space_path"
assert_contains "spaced file preview highlights selected line" "$spaced_file_preview" ">     2  space two"

compiler_preview="$(run_preview "src/app.py:4: message here")"
assert_contains "compiler diagnostic preview shows path" "$compiler_preview" "$app_path"
assert_contains "compiler diagnostic preview highlights selected line" "$compiler_preview" ">     4  line 4"

compiler_column_preview="$(run_preview "src/my file.py:2:1: message here")"
assert_contains "compiler diagnostic column preview shows path" "$compiler_column_preview" "$space_path"
assert_contains "compiler diagnostic column preview highlights selected line" "$compiler_column_preview" ">     2  space two"

severity_preview="$(run_preview "error: src/app.py:4: bad")"
assert_contains "severity-prefixed diagnostic preview shows path" "$severity_preview" "$app_path"
assert_contains "severity-prefixed diagnostic preview highlights selected line" "$severity_preview" ">     4  line 4"

rust_arrow_preview="$(run_preview "   --> src/main.rs:2:5")"
assert_contains "rust arrow diagnostic preview shows path" "$rust_arrow_preview" "$rust_path"
assert_contains "rust arrow diagnostic preview highlights selected line" "$rust_arrow_preview" ">     2      println!"

rust_panic_preview="$(run_preview "thread 'main' panicked at src/main.rs:2:5:")"
assert_contains "rust panic diagnostic preview shows path" "$rust_panic_preview" "$rust_path"
assert_contains "rust panic diagnostic preview highlights selected line" "$rust_panic_preview" ">     2      println!"

go_stack_preview="$(run_preview "pkg/main.go:4 +0x123")"
assert_contains "go stack frame preview shows path" "$go_stack_preview" "$go_path"
assert_contains "go stack frame preview highlights selected line" "$go_stack_preview" ">     4  }"

stack_frame_preview="$(run_preview "    at run (src/my file.py:2:1)")"
assert_contains "javascript stack frame preview shows path" "$stack_frame_preview" "$space_path"
assert_contains "javascript stack frame preview highlights selected line" "$stack_frame_preview" ">     2  space two"

file_url_stack_preview="$(run_preview "    at load (file://$(urlencode_path "$space_path"):2:1)")"
assert_contains "javascript file url stack preview shows path" "$file_url_stack_preview" "$space_path"
assert_contains "javascript file url stack preview highlights selected line" "$file_url_stack_preview" ">     2  space two"

editor_url_stack_preview="$(run_preview "    at async main (vscode://file$(urlencode_path "$space_path")#L3C1)")"
assert_contains "javascript editor url stack preview shows path" "$editor_url_stack_preview" "$space_path"
assert_contains "javascript editor url stack preview highlights selected line" "$editor_url_stack_preview" ">     3  space three"

traceback_line_preview="$(run_preview '  File "src/app.py", line 4, in main')"
assert_contains "python traceback line preview shows path" "$traceback_line_preview" "$app_path"
assert_contains "python traceback line preview highlights selected line" "$traceback_line_preview" ">     4  line 4"

github_annotation_preview="$(run_preview "::warning file=src/my%20file.py,line=2,col=1,endLine=3,endColumn=2::bad")"
assert_contains "github annotation preview shows path" "$github_annotation_preview" "$space_path"
assert_contains "github annotation preview highlights start line" "$github_annotation_preview" ">     2  space two"

github_annotation_no_python_preview="$(run_preview_no_python "::warning file=src/my%20file.py,line=2,col=1::bad")"
assert_contains "github annotation preview decodes spaces without python" "$github_annotation_no_python_preview" "$raw_space_path"
assert_contains "github annotation preview without python highlights line" "$github_annotation_no_python_preview" ">     2  space two"

bare_msvc_preview="$(run_preview "main.cpp(4,2)")"
assert_contains "bare msvc preview shows path" "$bare_msvc_preview" "$cpp_path"
assert_contains "bare msvc preview highlights selected line" "$bare_msvc_preview" ">     4  cpp line 4"

msvc_diagnostic_preview="$(run_preview "main.cpp(4,2): error C2143: syntax error")"
assert_contains "msvc-style diagnostic preview shows path" "$msvc_diagnostic_preview" "$cpp_path"
assert_contains "msvc-style diagnostic preview highlights selected line" "$msvc_diagnostic_preview" ">     4  cpp line 4"

msvc_line_diagnostic_preview="$(run_preview "main.cpp(5): warning C4100: unused parameter")"
assert_contains "msvc-style line diagnostic preview shows path" "$msvc_line_diagnostic_preview" "$cpp_path"
assert_contains "msvc-style line diagnostic preview highlights selected line" "$msvc_line_diagnostic_preview" ">     5  cpp line 5"

windows_drive_preview="$(run_preview "C:/Users/sky/project/main.cpp:2")"
assert_contains "windows drive preview is not base-relative" "$windows_drive_preview" "No preview available:"
assert_contains "windows drive preview preserves selection" "$windows_drive_preview" "C:/Users/sky/project/main.cpp:2"
assert_not_contains "windows drive preview avoids local trap file" "$windows_drive_preview" "drive trap two"

windows_unc_preview="$(run_preview "\\\\server\\share\\repo\\main.cpp:2")"
assert_contains "windows UNC preview is not base-relative" "$windows_unc_preview" "No preview available:"
assert_contains "windows UNC preview preserves selection" "$windows_unc_preview" "\\\\server\\share\\repo\\main.cpp:2"
assert_not_contains "windows UNC preview avoids local trap file" "$windows_unc_preview" "unc trap two"

windows_slash_unc_preview="$(run_preview "//server/share/repo/main.cpp:2")"
assert_contains "windows slash UNC preview is not base-relative" "$windows_slash_unc_preview" "No preview available:"
assert_contains "windows slash UNC preview preserves selection" "$windows_slash_unc_preview" "//server/share/repo/main.cpp:2"
assert_not_contains "windows slash UNC preview avoids local trap file" "$windows_slash_unc_preview" "unc trap two"

quickfix_preview="$(run_preview "src/app.py|5 col 2| unused value")"
assert_contains "quickfix preview shows path" "$quickfix_preview" "$app_path"
assert_contains "quickfix preview highlights selected line" "$quickfix_preview" ">     5  line 5"

shell_line_preview="$(run_preview "scripts/bootstrap.sh: line 2: missing command")"
assert_contains "shell line preview shows path" "$shell_line_preview" "$shell_path"
assert_contains "shell line preview highlights selected line" "$shell_line_preview" ">     2  missing command"

file_url_preview="$(run_preview "file://$(urlencode_path "$app_path")#L4")"
assert_contains "file url preview shows path" "$file_url_preview" "$app_path"
assert_contains "file url preview highlights fragment line" "$file_url_preview" ">     4  line 4"

file_url_no_python_preview="$(run_preview_no_python "file://$space_url_path#L2")"
assert_contains "file url preview decodes spaces without python" "$file_url_no_python_preview" "$space_path"
assert_contains "file url preview without python highlights fragment line" "$file_url_no_python_preview" ">     2  space two"

file_url_range_preview="$(run_preview "file://$(urlencode_path "$app_path")#L4-L7")"
assert_contains "file url range preview shows path" "$file_url_range_preview" "$app_path"
assert_contains "file url range preview highlights first line" "$file_url_range_preview" ">     4  line 4"

editor_url_preview="$(run_preview "vscode://file$(urlencode_path "$app_path")?line=5&column=1")"
assert_contains "editor url preview shows path" "$editor_url_preview" "$app_path"
assert_contains "editor url preview highlights query line" "$editor_url_preview" ">     5  line 5"

editor_url_no_python_preview="$(run_preview_no_python "vscode://file$space_url_path?line=3&column=1")"
assert_contains "editor url preview decodes spaces without python" "$editor_url_no_python_preview" "$space_path"
assert_contains "editor url preview without python highlights query line" "$editor_url_no_python_preview" ">     3  space three"

editor_url_range_preview="$(run_preview "vscode://file$(urlencode_path "$app_path")#L6C2-L9C1")"
assert_contains "editor url range preview shows path" "$editor_url_range_preview" "$app_path"
assert_contains "editor url range preview highlights first line" "$editor_url_range_preview" ">     6  line 6"

remote_editor_url_preview="$(run_preview "vscode://vscode-remote/ssh-remote+devbox$(urlencode_path "$space_path")?line=2&column=1")"
assert_contains "vscode remote url preview shows path" "$remote_editor_url_preview" "$space_path"
assert_contains "vscode remote url preview highlights query line" "$remote_editor_url_preview" ">     2  space two"

home_preview="$(run_preview '~'/src/home.py:2)"
assert_contains "home-relative preview shows path" "$home_preview" "$home_path"
assert_contains "home-relative preview highlights selected line" "$home_preview" ">     2  home two"

dir_preview="$(run_preview "src")"
assert_contains "directory preview shows path" "$dir_preview" "$src_path/"
assert_contains "directory preview lists file" "$dir_preview" "app.py"
assert_contains "directory preview lists spaced file" "$dir_preview" "my file.py"
assert_not_contains "directory preview caps entries" "$dir_preview" "zz-limit-130.txt"

dir_preview_no_sed="$(run_preview_no_sed "src")"
assert_contains "directory preview works without sed" "$dir_preview_no_sed" "$no_sed_src_path/"
assert_contains "directory preview without sed lists file" "$dir_preview_no_sed" "app.py"
assert_not_contains "directory preview without sed caps entries" "$dir_preview_no_sed" "zz-limit-130.txt"

dir_preview_no_find_sort="$(run_preview_no_find_sort "src")"
assert_contains "directory preview works without find awk sort sed tail or python" "$dir_preview_no_find_sort" "$no_sed_src_path/"
assert_contains "directory preview without find awk sort sed tail or python lists file" "$dir_preview_no_find_sort" "app.py"
assert_contains "directory preview without find awk sort sed tail or python lists spaced file" "$dir_preview_no_find_sort" "my file.py"
assert_not_contains "directory preview without find awk sort sed tail or python caps entries" "$dir_preview_no_find_sort" "zz-limit-130.txt"

url_preview="$(run_preview "https://example.test/docs")"
assert_contains "url preview prints url" "$url_preview" "https://example.test/docs"

generic_uri_preview="$(run_preview "ssh://dev.example.com/repo.git")"
assert_contains "generic uri preview prints uri" "$generic_uri_preview" "ssh://dev.example.com/repo.git"

mailto_preview="$(run_preview "mailto:ops@example.com")"
assert_contains "mailto preview prints uri" "$mailto_preview" "mailto:ops@example.com"

missing_preview="$(run_preview "missing/file.py:10")"
assert_contains "missing preview reports target" "$missing_preview" "No preview available:"
assert_contains "missing preview preserves selection" "$missing_preview" "missing/file.py:10"
