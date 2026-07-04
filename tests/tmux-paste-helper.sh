#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
live_socket=""
real_clipboard_backup=""

cleanup() {
  if [[ -n "$live_socket" ]] && command -v tmux >/dev/null 2>&1; then
    tmux -L "$live_socket" kill-server >/dev/null 2>&1 || true
  fi
  if [[ -n "$real_clipboard_backup" && -f "$real_clipboard_backup" ]] &&
    command -v pbcopy >/dev/null 2>&1; then
    pbcopy <"$real_clipboard_backup" || true
  fi
  if [[ -n "${no_search_tmp:-}" && -d "$no_search_tmp" ]]; then
    chmod 700 "$no_search_tmp" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/bin" "$tmp/helper"
ln -s "$root/common/.local/bin/tmux-paste-helper" "$tmp/helper/tmux-paste-helper"
helper="$tmp/helper/tmux-paste-helper"

cat >"$tmp/bin/tmux" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

command="${1:-}"
shift || true

case "$command" in
  load-buffer)
    buffer=""
    path=""
    while (($#)); do
      case "$1" in
        -b)
          buffer="$2"
          shift 2
          ;;
        *)
          path="$1"
          shift
        ;;
      esac
    done
    if [[ "${TMUX_TEST_LOAD_STATUS:-0}" != "0" ]]; then
      exit "$TMUX_TEST_LOAD_STATUS"
    fi
    printf 'load-buffer buffer=%s tmux=%s\n' "$buffer" "${TMUX-<unset>}" >>"${TMUX_TEST_LOG:?}"
    cat "$path" >"${TMUX_TEST_LOADED:?}"
    ;;
  paste-buffer)
    printf 'paste-buffer %s tmux=%s\n' "$*" "${TMUX-<unset>}" >>"${TMUX_TEST_LOG:?}"
    if [[ "${TMUX_TEST_PASTE_STATUS:-0}" != "0" ]]; then
      exit "$TMUX_TEST_PASTE_STATUS"
    fi
    ;;
  delete-buffer)
    printf 'delete-buffer %s tmux=%s\n' "$*" "${TMUX-<unset>}" >>"${TMUX_TEST_LOG:?}"
    ;;
  display-message)
    if [[ "${1:-}" == "-p" ]]; then
      if [[ -n "${TMUX_TEST_STALE_CLIENT:-}" && "${2:-}" == '#{pane_id}' ]]; then
        exit 1
      fi
      printf '%%1\n'
    else
      printf '%s\n' "$*" >>"${TMUX_TEST_DISPLAY_LOG:?}"
    fi
    ;;
  *)
    printf 'unexpected tmux command: %s %s\n' "$command" "$*" >&2
    exit 2
    ;;
esac
SH
chmod +x "$tmp/bin/tmux"

cat >"$tmp/helper/osc-paste" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${OSC_PASTE_STATUS:-0}" != "0" ]]; then
  exit "$OSC_PASTE_STATUS"
fi

cat "${OSC_PASTE_SOURCE:?}"
SH
chmod +x "$tmp/helper/osc-paste"

cat >"$tmp/bin/osc-paste" <<'SH'
#!/usr/bin/env bash
printf 'path shadow osc-paste should not run\n' >&2
exit 99
SH
chmod +x "$tmp/bin/osc-paste"

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

assert_files_equal() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if ! cmp -s "$expected" "$actual"; then
    printf 'not ok - %s\n' "$name" >&2
    printf 'expected bytes:\n' >&2
    od -An -tx1 "$expected" >&2
    printf 'actual bytes:\n' >&2
    od -An -tx1 "$actual" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

assert_file_absent() {
  local name="$1"
  local path="$2"

  if [[ -e "$path" ]]; then
    printf 'not ok - %s\nunexpected file: %s\n' "$name" "$path" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

assert_no_temp_files() {
  local name="$1"
  local dir="$2"
  local pattern="$3"
  local matches

  matches="$(find "$dir" -maxdepth 1 -name "$pattern" -print 2>/dev/null || true)"
  if [[ -n "$matches" ]]; then
    printf 'not ok - %s\n' "$name" >&2
    printf 'unexpected temp files:\n%s\n' "$matches" >&2
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

clipboard="$tmp/clipboard.txt"
printf 'line one\nline two\n\n' >"$clipboard"
paste_helper_source="$(<"$root/common/.local/bin/tmux-paste-helper")"
dollar='$'
assert_not_contains "paste helper does not probe root-local home fallback" \
  "$paste_helper_source" \
  "${dollar}{HOME:-}/.local/bin/osc-paste"
assert_not_contains "paste helper does not probe root dotfiles fallback" \
  "$paste_helper_source" \
  "${dollar}{HOME:-}/dotfiles/common/.local/bin/osc-paste"

tmux_log="$tmp/tmux.log"
display_log="$tmp/display.log"
loaded="$tmp/loaded.txt"

OSC_PASTE_SOURCE="$clipboard" \
  TMUX_TEST_LOG="$tmux_log" \
  TMUX_TEST_DISPLAY_LOG="$display_log" \
  TMUX_TEST_LOADED="$loaded" \
  TMUX_PASTE_BUFFER_NAME="test-clipboard" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$helper" "%7"

assert_files_equal "paste helper preserves clipboard bytes" "$clipboard" "$loaded"
tmux_output="$(cat "$tmux_log")"
assert_contains "paste helper loads named buffer" "$tmux_output" "load-buffer buffer=test-clipboard"
assert_contains "paste helper uses bracketed paste" "$tmux_output" "paste-buffer -p -b test-clipboard -t %7"
assert_contains "paste helper cleans up buffer" "$tmux_output" "delete-buffer -b test-clipboard"

binary_clipboard="$tmp/binary-clipboard.bin"
binary_loaded="$tmp/binary-loaded.bin"
binary_log="$tmp/binary-tmux.log"
printf 'paste-helper binary before\0middle\n\nlast line\n' >"$binary_clipboard"
OSC_PASTE_SOURCE="$binary_clipboard" \
  TMUX_TEST_LOG="$binary_log" \
  TMUX_TEST_DISPLAY_LOG="$tmp/binary-display.log" \
  TMUX_TEST_LOADED="$binary_loaded" \
  TMUX_PASTE_BUFFER_NAME="binary-clipboard" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$helper" "%15"

assert_files_equal "paste helper preserves binary clipboard bytes" "$binary_clipboard" "$binary_loaded"
assert_contains "paste helper targets pane for binary clipboard" "$(cat "$binary_log")" "-t %15"

crlf_clipboard="$tmp/crlf-clipboard.bin"
crlf_loaded="$tmp/crlf-loaded.bin"
crlf_log="$tmp/crlf-tmux.log"
printf 'paste-helper crlf\r\nsecond\rthird\n' >"$crlf_clipboard"
OSC_PASTE_SOURCE="$crlf_clipboard" \
  TMUX_TEST_LOG="$crlf_log" \
  TMUX_TEST_DISPLAY_LOG="$tmp/crlf-display.log" \
  TMUX_TEST_LOADED="$crlf_loaded" \
  TMUX_PASTE_BUFFER_NAME="crlf-clipboard" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$helper" "%22"

assert_files_equal "paste helper preserves CRLF clipboard bytes" "$crlf_clipboard" "$crlf_loaded"
assert_contains "paste helper targets pane for CRLF clipboard" "$(cat "$crlf_log")" "-t %22"

unicode_clipboard="$tmp/unicode-clipboard.txt"
unicode_loaded="$tmp/unicode-loaded.txt"
unicode_log="$tmp/unicode-tmux.log"
printf 'paste-helper caf\xc3\xa9\nlambda \xce\xbb\neuro \xe2\x82\xac\n' >"$unicode_clipboard"
OSC_PASTE_SOURCE="$unicode_clipboard" \
  TMUX_TEST_LOG="$unicode_log" \
  TMUX_TEST_DISPLAY_LOG="$tmp/unicode-display.log" \
  TMUX_TEST_LOADED="$unicode_loaded" \
  TMUX_PASTE_BUFFER_NAME="unicode-clipboard" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$helper" "%23"

assert_files_equal "paste helper preserves UTF-8 clipboard bytes" "$unicode_clipboard" "$unicode_loaded"
assert_contains "paste helper targets pane for UTF-8 clipboard" "$(cat "$unicode_log")" "-t %23"

large_clipboard="$tmp/large-clipboard.txt"
large_loaded="$tmp/large-loaded.txt"
large_log="$tmp/large-tmux.log"
{
  for ((i = 1; i <= 4096; i++)); do
    printf 'paste-helper-large-%04d\ttrailing spaces   \n' "$i"
  done
  printf 'paste-helper-large-final\ttrail   '
} >"$large_clipboard"
OSC_PASTE_SOURCE="$large_clipboard" \
  TMUX_TEST_LOG="$large_log" \
  TMUX_TEST_DISPLAY_LOG="$tmp/large-display.log" \
  TMUX_TEST_LOADED="$large_loaded" \
  TMUX_PASTE_BUFFER_NAME="large-clipboard" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$helper" "%24"

assert_files_equal "paste helper preserves large whitespace clipboard bytes" "$large_clipboard" "$large_loaded"
assert_contains "paste helper targets pane for large whitespace clipboard" "$(cat "$large_log")" "-t %24"

empty_clipboard="$tmp/empty-clipboard.txt"
empty_loaded="$tmp/empty-loaded.txt"
empty_log="$tmp/empty-tmux.log"
: >"$empty_clipboard"
OSC_PASTE_SOURCE="$empty_clipboard" \
  TMUX_TEST_LOG="$empty_log" \
  TMUX_TEST_DISPLAY_LOG="$tmp/empty-display.log" \
  TMUX_TEST_LOADED="$empty_loaded" \
  TMUX_PASTE_BUFFER_NAME="empty-clipboard" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$helper" "%16"

assert_files_equal "paste helper preserves an empty clipboard" "$empty_clipboard" "$empty_loaded"
assert_contains "paste helper targets pane for empty clipboard" "$(cat "$empty_log")" "-t %16"

spaced_tmp="$tmp/spaced tmux paste tmpdir"
spaced_tmp_log="$tmp/spaced-tmp-tmux.log"
spaced_tmp_loaded="$tmp/spaced-tmp-loaded.txt"
mkdir -p "$spaced_tmp"
OSC_PASTE_SOURCE="$clipboard" \
  TMUX_TEST_LOG="$spaced_tmp_log" \
  TMUX_TEST_DISPLAY_LOG="$tmp/spaced-tmp-display.log" \
  TMUX_TEST_LOADED="$spaced_tmp_loaded" \
  TMPDIR="$spaced_tmp" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$helper" "%17"

assert_files_equal "paste helper preserves clipboard bytes when TMPDIR has spaces" "$clipboard" "$spaced_tmp_loaded"
assert_contains "paste helper targets pane when TMPDIR has spaces" "$(cat "$spaced_tmp_log")" "-t %17"
assert_no_temp_files "paste helper cleans temp file when TMPDIR has spaces" "$spaced_tmp" "tmux-paste.*"

invalid_tmp_log="$tmp/invalid-tmp-tmux.log"
invalid_tmp_loaded="$tmp/invalid-tmp-loaded.txt"
OSC_PASTE_SOURCE="$clipboard" \
  TMUX_TEST_LOG="$invalid_tmp_log" \
  TMUX_TEST_DISPLAY_LOG="$tmp/invalid-tmp-display.log" \
  TMUX_TEST_LOADED="$invalid_tmp_loaded" \
  TMPDIR="$tmp/missing-tmux-paste-tmpdir" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$helper" "%8"

assert_files_equal "paste helper preserves clipboard bytes when TMPDIR is invalid" "$clipboard" "$invalid_tmp_loaded"
assert_contains "paste helper targets pane when TMPDIR is invalid" "$(cat "$invalid_tmp_log")" "-t %8"

no_search_tmp="$tmp/no-search-tmux-paste-tmpdir"
no_search_log="$tmp/no-search-tmux.log"
no_search_loaded="$tmp/no-search-loaded.txt"
mkdir -p "$no_search_tmp"
chmod 200 "$no_search_tmp"
OSC_PASTE_SOURCE="$clipboard" \
  TMUX_TEST_LOG="$no_search_log" \
  TMUX_TEST_DISPLAY_LOG="$tmp/no-search-display.log" \
  TMUX_TEST_LOADED="$no_search_loaded" \
  TMPDIR="$no_search_tmp" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$helper" "%11"

assert_files_equal "paste helper preserves clipboard bytes when TMPDIR is not searchable" "$clipboard" "$no_search_loaded"
assert_contains "paste helper targets pane when TMPDIR is not searchable" "$(cat "$no_search_log")" "-t %11"

broken_mktemp_bin="$tmp/broken-mktemp-bin"
broken_mktemp_tmp="$tmp/broken-mktemp-tmp"
broken_mktemp_log="$tmp/broken-mktemp-tmux.log"
broken_mktemp_loaded="$tmp/broken-mktemp-loaded.txt"
mkdir -p "$broken_mktemp_bin" "$broken_mktemp_tmp"
cat >"$broken_mktemp_bin/mktemp" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$broken_mktemp_bin/mktemp"
OSC_PASTE_SOURCE="$clipboard" \
  TMUX_TEST_LOG="$broken_mktemp_log" \
  TMUX_TEST_DISPLAY_LOG="$tmp/broken-mktemp-display.log" \
  TMUX_TEST_LOADED="$broken_mktemp_loaded" \
  TMPDIR="$broken_mktemp_tmp" \
  PATH="$broken_mktemp_bin:$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$helper" "%10"

assert_files_equal "paste helper preserves clipboard bytes when mktemp fails" "$clipboard" "$broken_mktemp_loaded"
assert_contains "paste helper targets pane when mktemp fails" "$(cat "$broken_mktemp_log")" "-t %10"
assert_no_temp_files "paste helper cleans fallback temp file when mktemp fails" "$broken_mktemp_tmp" "tmux-paste.*"

no_mktemp_bin="$tmp/no-mktemp-bin"
no_mktemp_tmp="$tmp/no-mktemp-tmp"
no_mktemp_log="$tmp/no-mktemp-tmux.log"
no_mktemp_loaded="$tmp/no-mktemp-loaded.txt"
mkdir -p "$no_mktemp_bin" "$no_mktemp_tmp"
ln -s "$(command -v bash)" "$no_mktemp_bin/bash"
ln -s "$(command -v cat)" "$no_mktemp_bin/cat"
ln -s "$(command -v rm)" "$no_mktemp_bin/rm"
ln -s "$tmp/bin/tmux" "$no_mktemp_bin/tmux"
ln -s "$tmp/helper/osc-paste" "$no_mktemp_bin/osc-paste"
ln -s "$root/common/.local/bin/tmux-paste-helper" "$no_mktemp_bin/tmux-paste-helper"
OSC_PASTE_SOURCE="$clipboard" \
  TMUX_TEST_LOG="$no_mktemp_log" \
  TMUX_TEST_DISPLAY_LOG="$tmp/no-mktemp-display.log" \
  TMUX_TEST_LOADED="$no_mktemp_loaded" \
  TMPDIR="$no_mktemp_tmp" \
  PATH="$no_mktemp_bin" \
  "$no_mktemp_bin/tmux-paste-helper" "%9"

assert_files_equal "paste helper preserves clipboard bytes without mktemp" "$clipboard" "$no_mktemp_loaded"
no_mktemp_output="$(cat "$no_mktemp_log")"
assert_contains "paste helper loads buffer without mktemp" "$no_mktemp_output" "load-buffer buffer=dotfiles-clipboard-"
assert_contains "paste helper targets pane without mktemp" "$no_mktemp_output" "-t %9"
assert_contains "paste helper cleans up buffer without mktemp" "$no_mktemp_output" "delete-buffer -b dotfiles-clipboard-"

isolated_helper_dir="$tmp/isolated-helper"
isolated_path_bin="$tmp/isolated-path"
isolated_home="$tmp/isolated-home"
isolated_log="$tmp/isolated-tmux.log"
isolated_loaded="$tmp/isolated-loaded.txt"
mkdir -p "$isolated_helper_dir" "$isolated_path_bin" "$isolated_home/.local/bin" "$isolated_home/dotfiles/common/.local/bin"
ln -s "$root/common/.local/bin/tmux-paste-helper" "$isolated_helper_dir/tmux-paste-helper"
ln -s "$tmp/bin/tmux" "$isolated_path_bin/tmux"
cat >"$isolated_path_bin/osc-paste" <<'SH'
#!/usr/bin/env bash
printf 'path shadow osc-paste should not run\n' >&2
exit 99
SH
chmod +x "$isolated_path_bin/osc-paste"

cat >"$isolated_home/.local/bin/osc-paste" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

cat "${OSC_PASTE_SOURCE:?}"
SH
chmod +x "$isolated_home/.local/bin/osc-paste"

OSC_PASTE_SOURCE="$clipboard" \
  TMUX_TEST_LOG="$isolated_log" \
  TMUX_TEST_DISPLAY_LOG="$tmp/isolated-display.log" \
  TMUX_TEST_LOADED="$isolated_loaded" \
  HOME="$isolated_home" \
  PATH="$isolated_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$isolated_helper_dir/tmux-paste-helper" "%12"

assert_files_equal "paste helper reads via home local osc-paste before PATH shadow" "$clipboard" "$isolated_loaded"
assert_contains "paste helper home local fallback targets pane" \
  "$(cat "$isolated_log")" \
  "-t %12"

: >"$isolated_log"
rm -f "$isolated_loaded" "$isolated_home/.local/bin/osc-paste"
cat >"$isolated_home/dotfiles/common/.local/bin/osc-paste" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

cat "${OSC_PASTE_SOURCE:?}"
SH
chmod +x "$isolated_home/dotfiles/common/.local/bin/osc-paste"

OSC_PASTE_SOURCE="$clipboard" \
  TMUX_TEST_LOG="$isolated_log" \
  TMUX_TEST_DISPLAY_LOG="$tmp/isolated-display.log" \
  TMUX_TEST_LOADED="$isolated_loaded" \
  HOME="$isolated_home" \
  PATH="$isolated_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$isolated_helper_dir/tmux-paste-helper" "%12"

assert_files_equal "paste helper reads via home dotfiles osc-paste fallback before PATH shadow" "$clipboard" "$isolated_loaded"
assert_contains "paste helper fallback targets pane" \
  "$(cat "$isolated_log")" \
  "-t %12"

rm -f "$isolated_home/dotfiles/common/.local/bin/osc-paste"
cat >"$isolated_path_bin/osc-paste" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

cat "${OSC_PASTE_SOURCE:?}"
SH
chmod +x "$isolated_path_bin/osc-paste"
: >"$isolated_log"
rm -f "$isolated_loaded"
env -u HOME \
  OSC_PASTE_SOURCE="$clipboard" \
  TMUX_TEST_LOG="$isolated_log" \
  TMUX_TEST_DISPLAY_LOG="$tmp/isolated-display.log" \
  TMUX_TEST_LOADED="$isolated_loaded" \
  PATH="$isolated_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$isolated_helper_dir/tmux-paste-helper" "%12"

assert_files_equal "paste helper falls back to PATH osc-paste when HOME is unset" "$clipboard" "$isolated_loaded"
assert_contains "paste helper unset HOME fallback targets pane" \
  "$(cat "$isolated_log")" \
  "-t %12"

spaced_helper_dir="$tmp/spaced paste helper"
spaced_path_bin="$tmp/spaced paste path"
spaced_home="$tmp/spaced paste home"
spaced_log="$tmp/spaced-resolver-tmux.log"
spaced_display_log="$tmp/spaced-resolver-display.log"
spaced_loaded="$tmp/spaced-resolver-loaded.txt"
mkdir -p "$spaced_helper_dir" "$spaced_path_bin" "$spaced_home/.local/bin" "$spaced_home/dotfiles/common/.local/bin"
ln -s "$root/common/.local/bin/tmux-paste-helper" "$spaced_helper_dir/tmux-paste-helper"
ln -s "$tmp/bin/tmux" "$spaced_path_bin/tmux"
cat >"$spaced_path_bin/osc-paste" <<'SH'
#!/usr/bin/env bash
printf 'spaced path shadow osc-paste should not run\n' >&2
exit 99
SH
chmod +x "$spaced_path_bin/osc-paste"

cat >"$spaced_helper_dir/osc-paste" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

cat "${OSC_PASTE_SOURCE:?}"
SH
chmod +x "$spaced_helper_dir/osc-paste"

OSC_PASTE_SOURCE="$clipboard" \
  TMUX_TEST_LOG="$spaced_log" \
  TMUX_TEST_DISPLAY_LOG="$spaced_display_log" \
  TMUX_TEST_LOADED="$spaced_loaded" \
  HOME="$spaced_home" \
  PATH="$spaced_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$spaced_helper_dir/tmux-paste-helper" "%18"

assert_files_equal "paste helper handles adjacent helper path with spaces" "$clipboard" "$spaced_loaded"
assert_contains "paste helper spaced adjacent target pane" \
  "$(cat "$spaced_log")" \
  "-t %18"

: >"$spaced_log"
rm -f "$spaced_loaded" "$spaced_helper_dir/osc-paste"
cat >"$spaced_home/.local/bin/osc-paste" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

cat "${OSC_PASTE_SOURCE:?}"
SH
chmod +x "$spaced_home/.local/bin/osc-paste"

OSC_PASTE_SOURCE="$clipboard" \
  TMUX_TEST_LOG="$spaced_log" \
  TMUX_TEST_DISPLAY_LOG="$spaced_display_log" \
  TMUX_TEST_LOADED="$spaced_loaded" \
  HOME="$spaced_home" \
  PATH="$spaced_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$spaced_helper_dir/tmux-paste-helper" "%19"

assert_files_equal "paste helper handles HOME local path with spaces" "$clipboard" "$spaced_loaded"
assert_contains "paste helper spaced HOME local target pane" \
  "$(cat "$spaced_log")" \
  "-t %19"

: >"$spaced_log"
rm -f "$spaced_loaded" "$spaced_home/.local/bin/osc-paste"
cat >"$spaced_home/dotfiles/common/.local/bin/osc-paste" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

cat "${OSC_PASTE_SOURCE:?}"
SH
chmod +x "$spaced_home/dotfiles/common/.local/bin/osc-paste"

OSC_PASTE_SOURCE="$clipboard" \
  TMUX_TEST_LOG="$spaced_log" \
  TMUX_TEST_DISPLAY_LOG="$spaced_display_log" \
  TMUX_TEST_LOADED="$spaced_loaded" \
  HOME="$spaced_home" \
  PATH="$spaced_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$spaced_helper_dir/tmux-paste-helper" "%20"

assert_files_equal "paste helper handles HOME dotfiles path with spaces" "$clipboard" "$spaced_loaded"
assert_contains "paste helper spaced HOME dotfiles target pane" \
  "$(cat "$spaced_log")" \
  "-t %20"

: >"$spaced_log"
rm -f "$spaced_loaded" "$spaced_home/dotfiles/common/.local/bin/osc-paste" "$spaced_path_bin/osc-paste"
cat >"$spaced_path_bin/osc-paste" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

cat "${OSC_PASTE_SOURCE:?}"
SH
chmod +x "$spaced_path_bin/osc-paste"

env -u HOME \
  OSC_PASTE_SOURCE="$clipboard" \
  TMUX_TEST_LOG="$spaced_log" \
  TMUX_TEST_DISPLAY_LOG="$spaced_display_log" \
  TMUX_TEST_LOADED="$spaced_loaded" \
  PATH="$spaced_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$spaced_helper_dir/tmux-paste-helper" "%21"

assert_files_equal "paste helper handles PATH entry with spaces" "$clipboard" "$spaced_loaded"
assert_contains "paste helper spaced PATH target pane" \
  "$(cat "$spaced_log")" \
  "-t %21"

missing_helper_dir="$tmp/missing-helper"
missing_path_bin="$tmp/missing-path"
missing_home="$tmp/missing-home"
missing_display_log="$tmp/missing-display.log"
mkdir -p "$missing_helper_dir" "$missing_path_bin" "$missing_home"
ln -s "$root/common/.local/bin/tmux-paste-helper" "$missing_helper_dir/tmux-paste-helper"
ln -s "$tmp/bin/tmux" "$missing_path_bin/tmux"
if TMUX_TEST_LOG="$tmp/missing-tmux.log" \
  TMUX_TEST_DISPLAY_LOG="$missing_display_log" \
  TMUX_TEST_LOADED="$tmp/missing-loaded.txt" \
  HOME="$missing_home" \
  PATH="$missing_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$missing_helper_dir/tmux-paste-helper" "%12" 2>"$tmp/missing-stderr.txt"; then
  printf 'not ok - paste helper exits non-zero when osc-paste is missing\n' >&2
  exit 1
fi
printf 'ok - paste helper exits non-zero when osc-paste is missing\n'
assert_contains "paste helper reports missing osc-paste to stderr" \
  "$(cat "$tmp/missing-stderr.txt")" \
  "osc-paste is unavailable"
assert_contains "paste helper reports missing osc-paste to tmux" \
  "$(cat "$missing_display_log")" \
  "osc-paste is unavailable"

stale_log="$tmp/stale-tmux.log"
stale_display_log="$tmp/stale-display.log"
stale_loaded="$tmp/stale-loaded.txt"
OSC_PASTE_SOURCE="$clipboard" \
  TMUX=fake \
  TMUX_TEST_STALE_CLIENT=1 \
  TMUX_TEST_LOG="$stale_log" \
  TMUX_TEST_DISPLAY_LOG="$stale_display_log" \
  TMUX_TEST_LOADED="$stale_loaded" \
  TMUX_PASTE_BUFFER_NAME="stale-clipboard" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$helper" "%13"

assert_files_equal "stale TMUX paste helper preserves clipboard bytes" "$clipboard" "$stale_loaded"
stale_output="$(cat "$stale_log")"
assert_contains "stale TMUX paste helper clears TMUX for load-buffer" "$stale_output" "load-buffer buffer=stale-clipboard tmux=<unset>"
assert_contains "stale TMUX paste helper clears TMUX for paste-buffer" "$stale_output" "paste-buffer -p -b stale-clipboard -t %13 tmux=<unset>"
assert_contains "stale TMUX paste helper clears TMUX for delete-buffer" "$stale_output" "delete-buffer -b stale-clipboard tmux=<unset>"

no_env_stale_bin="$tmp/no-env-stale-bin"
no_env_stale_tmp="$tmp/no-env-stale-tmp"
no_env_stale_log="$tmp/no-env-stale-tmux.log"
no_env_stale_display_log="$tmp/no-env-stale-display.log"
no_env_stale_loaded="$tmp/no-env-stale-loaded.txt"
mkdir -p "$no_env_stale_bin" "$no_env_stale_tmp"
ln -s "$(command -v bash)" "$no_env_stale_bin/bash"
ln -s "$(command -v cat)" "$no_env_stale_bin/cat"
ln -s "$(command -v rm)" "$no_env_stale_bin/rm"
ln -s "$tmp/bin/tmux" "$no_env_stale_bin/tmux"
ln -s "$tmp/helper/osc-paste" "$no_env_stale_bin/osc-paste"
ln -s "$root/common/.local/bin/tmux-paste-helper" "$no_env_stale_bin/tmux-paste-helper"
OSC_PASTE_SOURCE="$clipboard" \
  TMUX=fake \
  TMUX_TEST_STALE_CLIENT=1 \
  TMUX_TEST_LOG="$no_env_stale_log" \
  TMUX_TEST_DISPLAY_LOG="$no_env_stale_display_log" \
  TMUX_TEST_LOADED="$no_env_stale_loaded" \
  TMUX_PASTE_BUFFER_NAME="no-env-stale-clipboard" \
  TMPDIR="$no_env_stale_tmp" \
  PATH="$no_env_stale_bin" \
  "$no_env_stale_bin/tmux-paste-helper" "%14"

assert_files_equal "stale TMUX paste helper preserves bytes without env" "$clipboard" "$no_env_stale_loaded"
no_env_stale_output="$(cat "$no_env_stale_log")"
assert_contains "stale TMUX paste helper clears TMUX without env for load-buffer" \
  "$no_env_stale_output" \
  "load-buffer buffer=no-env-stale-clipboard tmux=<unset>"
assert_contains "stale TMUX paste helper clears TMUX without env for paste-buffer" \
  "$no_env_stale_output" \
  "paste-buffer -p -b no-env-stale-clipboard -t %14 tmux=<unset>"
assert_contains "stale TMUX paste helper clears TMUX without env for delete-buffer" \
  "$no_env_stale_output" \
  "delete-buffer -b no-env-stale-clipboard tmux=<unset>"

failure_log="$tmp/failure-tmux.log"
failure_display_log="$tmp/failure-display.log"
if OSC_PASTE_SOURCE="$clipboard" \
  OSC_PASTE_STATUS=7 \
  TMUX_TEST_LOG="$failure_log" \
  TMUX_TEST_DISPLAY_LOG="$failure_display_log" \
  TMUX_TEST_LOADED="$tmp/failure-loaded.txt" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$helper" "%8" 2>"$tmp/failure-stderr.txt"; then
  printf 'not ok - paste helper exits non-zero on clipboard failure\n' >&2
  exit 1
fi

printf 'ok - paste helper exits non-zero on clipboard failure\n'
assert_contains "paste helper reports clipboard failure to stderr" \
  "$(cat "$tmp/failure-stderr.txt")" \
  "Unable to read clipboard"
assert_contains "paste helper reports clipboard failure to tmux" \
  "$(cat "$failure_display_log")" \
  "Unable to read clipboard"

default_log="$tmp/default-tmux.log"
default_display_log="$tmp/default-display.log"
default_loaded="$tmp/default-loaded.txt"
OSC_PASTE_SOURCE="$clipboard" \
  TMUX_TEST_LOG="$default_log" \
  TMUX_TEST_DISPLAY_LOG="$default_display_log" \
  TMUX_TEST_LOADED="$default_loaded" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$helper" "%9"

default_output="$(cat "$default_log")"
assert_contains "paste helper default buffer name is unique" "$default_output" "dotfiles-clipboard-"
assert_contains "paste helper deletes default unique buffer" "$default_output" "delete-buffer -b dotfiles-clipboard-"

load_failure_log="$tmp/load-failure-tmux.log"
load_failure_display_log="$tmp/load-failure-display.log"
if OSC_PASTE_SOURCE="$clipboard" \
  TMUX_TEST_LOAD_STATUS=9 \
  TMUX_TEST_LOG="$load_failure_log" \
  TMUX_TEST_DISPLAY_LOG="$load_failure_display_log" \
  TMUX_TEST_LOADED="$tmp/load-failure-loaded.txt" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$helper" "%10" 2>"$tmp/load-failure-stderr.txt"; then
  printf 'not ok - paste helper exits non-zero on load-buffer failure\n' >&2
  exit 1
fi

printf 'ok - paste helper exits non-zero on load-buffer failure\n'
assert_contains "paste helper reports load-buffer failure to stderr" \
  "$(cat "$tmp/load-failure-stderr.txt")" \
  "Unable to load paste buffer"
assert_contains "paste helper reports load-buffer failure to tmux" \
  "$(cat "$load_failure_display_log")" \
  "Unable to load paste buffer"

paste_failure_log="$tmp/paste-failure-tmux.log"
paste_failure_display_log="$tmp/paste-failure-display.log"
OSC_PASTE_SOURCE="$clipboard" \
  TMUX_TEST_PASTE_STATUS=11 \
  TMUX_TEST_LOG="$paste_failure_log" \
  TMUX_TEST_DISPLAY_LOG="$paste_failure_display_log" \
  TMUX_TEST_LOADED="$tmp/paste-failure-loaded.txt" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$helper" "%11" 2>"$tmp/paste-failure-stderr.txt" && {
    printf 'not ok - paste helper exits non-zero on paste-buffer failure\n' >&2
    exit 1
  }

printf 'ok - paste helper exits non-zero on paste-buffer failure\n'
assert_contains "paste helper reports paste-buffer failure to stderr" \
  "$(cat "$tmp/paste-failure-stderr.txt")" \
  "Unable to paste buffer"
assert_contains "paste helper reports paste-buffer failure to tmux" \
  "$(cat "$paste_failure_display_log")" \
  "Unable to paste buffer"
assert_contains "paste helper cleans buffer after paste failure" \
  "$(cat "$paste_failure_log")" \
  "delete-buffer -b dotfiles-clipboard-"

if real_tmux="$(command -v tmux 2>/dev/null)"; then
  live_socket="dotfiles-paste-helper-$$"
  live_home="$tmp/live-home"
  live_clipboard="$tmp/live-clipboard.txt"
  live_binding_clipboard="$tmp/live-binding-clipboard.txt"
  live_binding_output="$tmp/live-binding-pane-output.txt"
  live_output="$tmp/live-pane-output.txt"
  live_tmux_env="$tmp/live-tmux-env.txt"
  live_session="paste-helper-live"
  real_tmux_dir="${real_tmux%/*}"
  mkdir -p "$live_home/.local/bin"

  cat >"$live_home/.local/bin/osc-paste" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

cat "${OSC_PASTE_SOURCE:?}"
SH
  chmod +x "$live_home/.local/bin/osc-paste"
  ln -s "$root/common/.local/bin/tmux-paste-helper" "$live_home/.local/bin/tmux-paste-helper"
  ln -s "$root/common/.local/bin/tmux-pane-should-passthrough" "$live_home/.local/bin/tmux-pane-should-passthrough"
  printf 'live paste alpha\nlive paste beta\n' >"$live_clipboard"

  printf -v live_cat_command 'cat > %q' "$live_output"
  # shellcheck disable=SC2016
  printf -v live_env_command 'printf %%s "$TMUX" > %q; sleep 60' "$live_tmux_env"

  "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
  HOME="$live_home" "$real_tmux" -L "$live_socket" new-session -d -s "$live_session" "$live_cat_command"
  live_pane="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p '#{pane_id}')"
  HOME="$live_home" "$real_tmux" -L "$live_socket" split-window -d "$live_env_command"
  wait_for_file "$live_tmux_env"

  OSC_PASTE_SOURCE="$live_clipboard" \
    TMUX="$(cat "$live_tmux_env")" \
    HOME="$live_home" \
    "$live_home/.local/bin/tmux-paste-helper" "$live_pane"
  HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -t "$live_pane" C-d
  wait_for_file "$live_output"
  assert_files_equal "live tmux paste helper pastes clipboard bytes into pane" "$live_clipboard" "$live_output"

  printf 'binding paste alpha\nbinding paste beta\n' >"$live_binding_clipboard"
  printf -v live_binding_cat_command 'cat > %q' "$live_binding_output"
  live_binding_window="$(
    HOME="$live_home" "$real_tmux" -L "$live_socket" new-window -d -n paste-binding -P -F '#{window_id}' "$live_binding_cat_command"
  )"
  live_binding_pane="$(
    HOME="$live_home" "$real_tmux" -L "$live_socket" list-panes -t "$live_binding_window" -F '#{pane_id}' |
      awk 'NR == 1 { print; exit }'
  )"
  HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -g OSC_PASTE_SOURCE "$live_binding_clipboard"
  HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -g PATH "$live_home/.local/bin:$real_tmux_dir:/usr/bin:/bin:/usr/sbin:/sbin"
  # shellcheck disable=SC2016
  paste_binding_run_shell='if [ -n "${HOME:-}" ]; then for helper in "$HOME/.local/bin/tmux-paste-helper" "$HOME/dotfiles/common/.local/bin/tmux-paste-helper"; do [ -x "$helper" ] && exec "$helper" "#{pane_id}"; done; fi; helper="$(command -v tmux-paste-helper 2>/dev/null)" && exec "$helper" "#{pane_id}"; command -v tmux >/dev/null 2>&1 && tmux display-message "tmux-paste-helper unavailable" 2>/dev/null; echo "tmux-paste-helper unavailable" >&2; exit 127'
  HOME="$live_home" "$real_tmux" -L "$live_socket" run-shell -b -t "$live_binding_pane" "$paste_binding_run_shell"
  wait_for_file "$live_binding_output"
  HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -t "$live_binding_pane" C-d
  assert_files_equal "live tmux paste binding pastes clipboard bytes through helper" \
    "$live_binding_clipboard" \
    "$live_binding_output"

  if python3_path="$(command -v python3 2>/dev/null)"; then
    shift_insert_binding_clipboard="$tmp/live-shift-insert-binding-clipboard.txt"
    shift_insert_binding_output="$tmp/live-shift-insert-binding-pane-output.txt"
    printf 'shift insert binding alpha\nshift insert binding beta\n' >"$shift_insert_binding_clipboard"
    printf -v shift_insert_binding_cat_command 'cat > %q' "$shift_insert_binding_output"
    shift_insert_binding_window="$(
      HOME="$live_home" "$real_tmux" -L "$live_socket" new-window -d -n shift-insert-binding -P -F '#{window_id}' "$shift_insert_binding_cat_command"
    )"
    shift_insert_binding_pane="$(
      HOME="$live_home" "$real_tmux" -L "$live_socket" list-panes -t "$shift_insert_binding_window" -F '#{pane_id}' |
        awk 'NR == 1 { print; exit }'
    )"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -g OSC_PASTE_SOURCE "$shift_insert_binding_clipboard"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -g PATH "$live_home/.local/bin:$real_tmux_dir:/usr/bin:/bin:/usr/sbin:/sbin"
    HOME="$live_home" "$real_tmux" -L "$live_socket" source-file "$root/common/.tmux.conf"
    HOME="$live_home" "$real_tmux" -L "$live_socket" select-window -t "$shift_insert_binding_window"
    if ! TERM=xterm-256color TERM_PROGRAM=vscode HOME="$live_home" "$python3_path" - \
      "$real_tmux" \
      "$live_socket" \
      "$live_session" \
      "$shift_insert_binding_output" <<'PY'
import os
import pty
import select
import subprocess
import sys
import time

tmux_path, socket_name, session_name, output_path = sys.argv[1:]
env = os.environ.copy()
env.update({
    "TERM": "xterm-256color",
    "TERM_PROGRAM": "vscode",
})

master, slave = pty.openpty()
try:
    proc = subprocess.Popen(
        [tmux_path, "-L", socket_name, "attach-session", "-t", session_name],
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
            os.write(master, b"\x1b[2;2~")
            sent = True

        if os.path.exists(output_path) and os.path.getsize(output_path) > 0:
            sys.exit(0)

    print("timeout waiting for Shift-Insert paste binding output")
    sys.exit(1)
finally:
    proc.terminate()
    try:
        proc.wait(timeout=1)
    except subprocess.TimeoutExpired:
        proc.kill()
    os.close(master)
PY
    then
      printf 'not ok - live tmux Shift-Insert paste binding writes clipboard bytes through helper\n' >&2
      exit 1
    fi
    wait_for_file "$shift_insert_binding_output"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -t "$shift_insert_binding_pane" C-d
    assert_files_equal "live tmux Shift-Insert paste binding writes clipboard bytes through helper" \
      "$shift_insert_binding_clipboard" \
      "$shift_insert_binding_output"

    guarded_copy_cut_output="$tmp/live-guarded-copy-cut-pane-output.txt"
    printf -v guarded_copy_cut_cat_command 'cat > %q' "$guarded_copy_cut_output"
    guarded_copy_cut_window="$(
      HOME="$live_home" "$real_tmux" -L "$live_socket" new-window -d -n guarded-copy-cut -P -F '#{window_id}' "$guarded_copy_cut_cat_command"
    )"
    HOME="$live_home" "$real_tmux" -L "$live_socket" source-file "$root/common/.tmux.conf"
    HOME="$live_home" "$real_tmux" -L "$live_socket" select-window -t "$guarded_copy_cut_window"
    if ! TERM=xterm-256color TERM_PROGRAM=vscode HOME="$live_home" "$python3_path" - \
      "$real_tmux" \
      "$live_socket" \
      "$live_session" \
      "$guarded_copy_cut_output" <<'PY'
import os
import pty
import select
import subprocess
import sys
import time

tmux_path, socket_name, session_name, output_path = sys.argv[1:]
env = os.environ.copy()
env.update({
    "TERM": "xterm-256color",
    "TERM_PROGRAM": "vscode",
})

master, slave = pty.openpty()
try:
    proc = subprocess.Popen(
        [tmux_path, "-L", socket_name, "attach-session", "-t", session_name],
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
            os.write(master, b"\x1b[2;5~\x1b[3;2~guarded copy cut ok\n\x04")
            sent = True

        if os.path.exists(output_path) and os.path.getsize(output_path) > 0:
            sys.exit(0)

    print("timeout waiting for guarded copy/cut pane output")
    sys.exit(1)
finally:
    proc.terminate()
    try:
        proc.wait(timeout=1)
    except subprocess.TimeoutExpired:
        proc.kill()
    os.close(master)
PY
    then
      printf 'not ok - live tmux guarded copy/cut bindings avoid raw plain-pane bytes\n' >&2
      exit 1
    fi
    wait_for_file "$guarded_copy_cut_output"
    assert_files_equal "live tmux guarded copy/cut bindings avoid raw plain-pane bytes" \
      <(printf 'guarded copy cut ok\n') \
      "$guarded_copy_cut_output"
  else
    printf 'skip - live tmux Shift-Insert paste binding (python3 unavailable)\n'
  fi

  path_binding_bin="$tmp/live-path-binding-bin"
  path_binding_clipboard="$tmp/live-path-binding-clipboard.txt"
  path_binding_output="$tmp/live-path-binding-output.txt"
  mkdir -p "$path_binding_bin"
  ln -s "$root/common/.local/bin/tmux-paste-helper" "$path_binding_bin/tmux-paste-helper"
  cat >"$path_binding_bin/osc-paste" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

cat "${OSC_PASTE_SOURCE:?}"
SH
  chmod +x "$path_binding_bin/osc-paste"
  printf 'path binding alpha\npath binding beta\n' >"$path_binding_clipboard"
  printf -v path_binding_cat_command 'cat > %q' "$path_binding_output"
  path_binding_window="$(
    HOME="$live_home" "$real_tmux" -L "$live_socket" new-window -d -n paste-binding-path -P -F '#{window_id}' "$path_binding_cat_command"
  )"
  path_binding_pane="$(
    HOME="$live_home" "$real_tmux" -L "$live_socket" list-panes -t "$path_binding_window" -F '#{pane_id}' |
      awk 'NR == 1 { print; exit }'
  )"
  HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -g OSC_PASTE_SOURCE "$path_binding_clipboard"
  HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -g PATH "$path_binding_bin:$real_tmux_dir:/usr/bin:/bin:/usr/sbin:/sbin"
  HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -gu HOME
  HOME="$live_home" "$real_tmux" -L "$live_socket" run-shell -b -t "$path_binding_pane" "$paste_binding_run_shell"
  wait_for_file "$path_binding_output"
  HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -t "$path_binding_pane" C-d
  assert_files_equal "live tmux paste binding falls back to PATH when HOME is unset" \
    "$path_binding_clipboard" \
    "$path_binding_output"

  path_binding_empty_clipboard="$tmp/live-path-binding-empty-home-clipboard.txt"
  path_binding_empty_output="$tmp/live-path-binding-empty-home-output.txt"
  printf 'path binding empty home alpha\npath binding empty home beta\n' >"$path_binding_empty_clipboard"
  printf -v path_binding_empty_cat_command 'cat > %q' "$path_binding_empty_output"
  path_binding_empty_window="$(
    HOME="$live_home" "$real_tmux" -L "$live_socket" new-window -d -n paste-binding-empty-home -P -F '#{window_id}' "$path_binding_empty_cat_command"
  )"
  path_binding_empty_pane="$(
    HOME="$live_home" "$real_tmux" -L "$live_socket" list-panes -t "$path_binding_empty_window" -F '#{pane_id}' |
      awk 'NR == 1 { print; exit }'
  )"
  HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -g OSC_PASTE_SOURCE "$path_binding_empty_clipboard"
  HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -g PATH "$path_binding_bin:$real_tmux_dir:/usr/bin:/bin:/usr/sbin:/sbin"
  HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -g HOME ""
  HOME="$live_home" "$real_tmux" -L "$live_socket" run-shell -b -t "$path_binding_empty_pane" "$paste_binding_run_shell"
  wait_for_file "$path_binding_empty_output"
  HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -t "$path_binding_empty_pane" C-d
  assert_files_equal "live tmux paste binding falls back to PATH when HOME is empty" \
    "$path_binding_empty_clipboard" \
    "$path_binding_empty_output"
  HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -g HOME "$live_home"
  HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -g PATH "$live_home/.local/bin:$real_tmux_dir:/usr/bin:/bin:/usr/sbin:/sbin"

  if python3_path="$(command -v python3 2>/dev/null)"; then
    live_bracketed_capture_script="$tmp/live-bracketed-capture.py"
    live_bracketed_clipboard="$tmp/live-bracketed-clipboard.txt"
    live_bracketed_expected="$tmp/live-bracketed-expected.bin"
    live_bracketed_output="$tmp/live-bracketed-output.bin"
    live_bracketed_ready="$tmp/live-bracketed-ready.txt"

    cat >"$live_bracketed_capture_script" <<'PY'
import os
import select
import sys
import termios
import time

output_path = os.environ["TMUX_TEST_BRACKETED_OUTPUT"]
ready_path = os.environ["TMUX_TEST_BRACKETED_READY"]
fd = sys.stdin.fileno()
old = termios.tcgetattr(fd)

try:
    new = termios.tcgetattr(fd)
    new[3] &= ~(termios.ECHO | termios.ICANON | termios.ISIG)
    new[6][termios.VMIN] = 0
    new[6][termios.VTIME] = 1
    termios.tcsetattr(fd, termios.TCSANOW, new)

    sys.stdout.write("\x1b[?2004h")
    sys.stdout.flush()
    with open(ready_path, "w", encoding="utf-8") as ready_file:
        ready_file.write("ready\n")

    data = bytearray()
    deadline = time.time() + 5
    while time.time() < deadline:
        readable, _, _ = select.select([fd], [], [], 0.2)
        if not readable:
            continue
        chunk = os.read(fd, 4096)
        if not chunk:
            continue
        data.extend(chunk)
        if b"\x1b[201~" in data:
            break

    sys.stdout.write("\x1b[?2004l")
    sys.stdout.flush()
    with open(output_path, "wb") as output_file:
        output_file.write(data)
finally:
    termios.tcsetattr(fd, termios.TCSANOW, old)
PY

    printf 'bracket paste alpha\nbracket paste beta\n' >"$live_bracketed_clipboard"
    printf '\033[200~bracket paste alpha\nbracket paste beta\n\033[201~' >"$live_bracketed_expected"
    printf -v live_bracketed_capture_command \
      'TMUX_TEST_BRACKETED_OUTPUT=%q TMUX_TEST_BRACKETED_READY=%q %q %q' \
      "$live_bracketed_output" \
      "$live_bracketed_ready" \
      "$python3_path" \
      "$live_bracketed_capture_script"

    live_bracketed_window="$(
      HOME="$live_home" "$real_tmux" -L "$live_socket" new-window -d -n bracketed-paste -P -F '#{window_id}' "$live_bracketed_capture_command"
    )"
    live_bracketed_pane="$(
      HOME="$live_home" "$real_tmux" -L "$live_socket" list-panes -t "$live_bracketed_window" -F '#{pane_id}' |
        awk 'NR == 1 { print; exit }'
    )"
    wait_for_file "$live_bracketed_ready"

    OSC_PASTE_SOURCE="$live_bracketed_clipboard" \
      TMUX="$(cat "$live_tmux_env")" \
      HOME="$live_home" \
      PATH="$live_home/.local/bin:$real_tmux_dir:/usr/bin:/bin:/usr/sbin:/sbin" \
      "$live_home/.local/bin/tmux-paste-helper" "$live_bracketed_pane"
    wait_for_file "$live_bracketed_output"
    assert_files_equal "live tmux paste helper sends bracketed paste markers when requested" \
      "$live_bracketed_expected" \
      "$live_bracketed_output"
  else
    printf 'skip - live tmux bracketed paste helper (python3 unavailable)\n'
  fi

  "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
  live_socket=""

  mock_ssh_home="$tmp/live-mock-ssh-home"
  mock_ssh_expected="$tmp/live-mock-ssh-expected.txt"
  mock_ssh_output="$tmp/live-mock-ssh-pane-output.txt"
  mock_ssh_pbpaste_log="$tmp/live-mock-ssh-pbpaste.log"
  mock_ssh_session="paste-helper-mock-ssh"

  rm -rf "$mock_ssh_home"
  mkdir -p "$mock_ssh_home/.local/bin"
  ln -s "$root/common/.local/bin/tmux-paste-helper" "$mock_ssh_home/.local/bin/tmux-paste-helper"
  ln -s "$root/common/.local/bin/osc-paste" "$mock_ssh_home/.local/bin/osc-paste"
  cat >"$mock_ssh_home/.local/bin/pbpaste" <<SH
#!/usr/bin/env bash
cat >"$mock_ssh_pbpaste_log"
SH
  chmod +x "$mock_ssh_home/.local/bin/pbpaste"
  printf 'mock ssh paste alpha\nmock ssh paste beta\n' >"$mock_ssh_expected"

  live_socket="dotfiles-paste-helper-mock-ssh-$$"
  printf -v mock_ssh_cat_command 'cat > %q' "$mock_ssh_output"

  "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
  HOME="$mock_ssh_home" "$real_tmux" -L "$live_socket" -f "$root/common/.tmux.conf" \
    new-session -d -s "$mock_ssh_session" "$mock_ssh_cat_command"
  mock_ssh_pane="$(HOME="$mock_ssh_home" "$real_tmux" -L "$live_socket" display-message -p '#{pane_id}')"
  HOME="$mock_ssh_home" "$real_tmux" -L "$live_socket" set-environment -g HOME "$mock_ssh_home"
  HOME="$mock_ssh_home" "$real_tmux" -L "$live_socket" set-environment -g PATH \
    "$mock_ssh_home/.local/bin:$real_tmux_dir:/usr/bin:/bin:/usr/sbin:/sbin"
  HOME="$mock_ssh_home" "$real_tmux" -L "$live_socket" set-environment -g SSH_CLIENT "127.0.0.1 1000 22"
  HOME="$mock_ssh_home" "$real_tmux" -L "$live_socket" set-environment -gu SSH_TTY >/dev/null 2>&1 || true
  HOME="$mock_ssh_home" "$real_tmux" -L "$live_socket" set-environment -gu SSH_CONNECTION >/dev/null 2>&1 || true
  HOME="$mock_ssh_home" "$real_tmux" -L "$live_socket" set-environment -gu OSC_PASTE_SOURCE >/dev/null 2>&1 || true
  HOME="$mock_ssh_home" "$real_tmux" -L "$live_socket" load-buffer - <"$mock_ssh_expected"
  rm -f "$mock_ssh_pbpaste_log"
  HOME="$mock_ssh_home" "$real_tmux" -L "$live_socket" run-shell -b -t "$mock_ssh_pane" "$paste_binding_run_shell"
  wait_for_file "$mock_ssh_output"

  python3_path=""
  if python3_path="$(command -v python3 2>/dev/null)"; then
    mock_ssh_shift_insert_output="$tmp/live-mock-ssh-shift-insert-pane-output.txt"
    printf -v mock_ssh_shift_insert_cat_command 'cat > %q' "$mock_ssh_shift_insert_output"
    mock_ssh_shift_insert_window="$(
      HOME="$mock_ssh_home" "$real_tmux" -L "$live_socket" new-window -d -n mock-ssh-shift-insert -P -F '#{window_id}' "$mock_ssh_shift_insert_cat_command"
    )"
    mock_ssh_shift_insert_pane="$(
      HOME="$mock_ssh_home" "$real_tmux" -L "$live_socket" list-panes -t "$mock_ssh_shift_insert_window" -F '#{pane_id}' |
        awk 'NR == 1 { print; exit }'
    )"
  fi

  HOME="$mock_ssh_home" "$real_tmux" -L "$live_socket" send-keys -t "$mock_ssh_pane" C-d
  assert_files_equal "live mock ssh tmux paste binding reads tmux buffer" \
    "$mock_ssh_expected" \
    "$mock_ssh_output"
  assert_file_absent "live mock ssh tmux paste binding skips host pbpaste" "$mock_ssh_pbpaste_log"

  if [[ -n "$python3_path" ]]; then
    HOME="$mock_ssh_home" "$real_tmux" -L "$live_socket" select-window -t "$mock_ssh_shift_insert_window"
    HOME="$mock_ssh_home" "$real_tmux" -L "$live_socket" load-buffer - <"$mock_ssh_expected"
    rm -f "$mock_ssh_pbpaste_log"
    if ! TERM=xterm-256color TERM_PROGRAM=vscode HOME="$mock_ssh_home" "$python3_path" - \
      "$real_tmux" \
      "$live_socket" \
      "$mock_ssh_session" \
      "$mock_ssh_shift_insert_output" <<'PY'
import os
import pty
import select
import subprocess
import sys
import time

tmux_path, socket_name, session_name, output_path = sys.argv[1:]
env = os.environ.copy()
env.update({
    "TERM": "xterm-256color",
    "TERM_PROGRAM": "vscode",
})

master, slave = pty.openpty()
try:
    proc = subprocess.Popen(
        [tmux_path, "-L", socket_name, "attach-session", "-t", session_name],
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
            os.write(master, b"\x1b[2;2~")
            sent = True

        if os.path.exists(output_path) and os.path.getsize(output_path) > 0:
            sys.exit(0)

    print("timeout waiting for mock ssh Shift-Insert paste binding output")
    sys.exit(1)
finally:
    proc.terminate()
    try:
        proc.wait(timeout=1)
    except subprocess.TimeoutExpired:
        proc.kill()
    os.close(master)
PY
    then
      printf 'not ok - live mock ssh tmux Shift-Insert binding reads tmux buffer\n' >&2
      exit 1
    fi
    wait_for_file "$mock_ssh_shift_insert_output"
    HOME="$mock_ssh_home" "$real_tmux" -L "$live_socket" send-keys -t "$mock_ssh_shift_insert_pane" C-d
    assert_files_equal "live mock ssh tmux Shift-Insert binding reads tmux buffer" \
      "$mock_ssh_expected" \
      "$mock_ssh_shift_insert_output"
    assert_file_absent "live mock ssh tmux Shift-Insert binding skips host pbpaste" "$mock_ssh_pbpaste_log"
  else
    printf 'skip - live mock ssh tmux Shift-Insert binding (python3 unavailable)\n'
  fi

  "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
  live_socket=""

  if command -v pbcopy >/dev/null 2>&1 && command -v pbpaste >/dev/null 2>&1; then
    real_clipboard_backup="$tmp/real-clipboard-backup.txt"
    if pbpaste >"$real_clipboard_backup"; then
      real_home="$tmp/live-real-home"
      real_clipboard="$tmp/live-real-clipboard.txt"
      real_output="$tmp/live-real-pane-output.txt"
      real_tmux_env="$tmp/live-real-tmux-env.txt"
      real_session="paste-helper-real-host"

      rm -rf "$real_home"
      mkdir -p "$real_home/.local/bin"
      ln -s "$root/common/.local/bin/tmux-paste-helper" "$real_home/.local/bin/tmux-paste-helper"
      ln -s "$root/common/.local/bin/osc-paste" "$real_home/.local/bin/osc-paste"
      printf 'real host paste alpha\nreal host paste beta\n' >"$real_clipboard"
      pbcopy <"$real_clipboard"

      live_socket="dotfiles-paste-helper-real-host-$$"
      printf -v real_cat_command 'cat > %q' "$real_output"
      # shellcheck disable=SC2016
      printf -v real_env_command 'printf %%s "$TMUX" > %q; sleep 60' "$real_tmux_env"

      "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
      HOME="$real_home" "$real_tmux" -L "$live_socket" new-session -d -s "$real_session" "$real_cat_command"
      real_pane="$(HOME="$real_home" "$real_tmux" -L "$live_socket" display-message -p '#{pane_id}')"
      HOME="$real_home" "$real_tmux" -L "$live_socket" split-window -d "$real_env_command"
      wait_for_file "$real_tmux_env"
      printf 'stale tmux buffer\n' | HOME="$real_home" "$real_tmux" -L "$live_socket" load-buffer -

      TMUX="$(cat "$real_tmux_env")" \
        HOME="$real_home" \
        PATH="$real_home/.local/bin:$real_tmux_dir:/usr/bin:/bin:/usr/sbin:/sbin" \
        "$real_home/.local/bin/tmux-paste-helper" "$real_pane"
      HOME="$real_home" "$real_tmux" -L "$live_socket" send-keys -t "$real_pane" C-d
      wait_for_file "$real_output"
      assert_files_equal "live tmux paste helper reads host clipboard through real osc-paste" \
        "$real_clipboard" \
        "$real_output"

      "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
      live_socket=""
    else
      real_clipboard_backup=""
      printf 'skip - live tmux paste helper real host clipboard (pbpaste failed)\n'
    fi
  else
    printf 'skip - live tmux paste helper real host clipboard (pbcopy/pbpaste unavailable)\n'
  fi
else
  printf 'skip - live tmux paste helper (tmux unavailable)\n'
fi
