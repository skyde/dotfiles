#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
real_tmux="$(command -v tmux)"
tmp="$(mktemp -d)"
if command -v realpath >/dev/null 2>&1; then
  tmp="$(realpath "$tmp")"
else
  tmp="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$tmp")"
fi
socket_name="dotfiles-url-test-$$"

cleanup() {
  "$real_tmux" -L "$socket_name" kill-server >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5; do
    rm -rf "$tmp" 2>/dev/null && return
    sleep 0.1
  done
  rm -rf "$tmp" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$tmp/bin" "$tmp/home" "$tmp/work/src"
printf '%s\n' 'print("hello")' >"$tmp/work/src/app.py"

cat >"$tmp/bin/tmux" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "list-commands" && -n "${TMUX_FZF_URL_NOISY_LIST_COMMANDS:-}" ]]; then
  printf 'display-popup\n'
  for i in {1..4000}; do
    printf 'fake-command-%04d\n' "$i"
  done
  exit 0
fi

if [[ -n "${TMUX_FZF_URL_STALE_CLIENT:-}" && "${1:-}" == "display-message" && "${2:-}" == "-p" && "${3:-}" == '#{pane_id}' ]]; then
  exit 1
fi

if [[ -n "${TMUX_FZF_URL_POPUP_LOG:-}" && "${1:-}" == "display-popup" ]]; then
  for arg in "$@"; do
    printf '%s\n' "$arg"
  done >"$TMUX_FZF_URL_POPUP_LOG"
  exit "${TMUX_FZF_URL_POPUP_STATUS:-0}"
fi

if [[ -n "${TMUX_FZF_URL_DISPLAY_LOG:-}" && "${1:-}" == "display-message" && "${2:-}" != "-p" ]]; then
  shift
  printf '%s\n' "$*" >>"$TMUX_FZF_URL_DISPLAY_LOG"
  exit 0
fi

if [[ -n "${TMUX_FZF_URL_CAPTURE_ENV_LOG:-}" && "${1:-}" == "capture-pane" ]]; then
  printf '%s\n' "${TMUX-<unset>}" >>"$TMUX_FZF_URL_CAPTURE_ENV_LOG"
fi

exec "$TMUX_TEST_REAL_TMUX" -L "$TMUX_TEST_SOCKET" "$@"
SH
chmod +x "$tmp/bin/tmux"

cat >"$tmp/bin/fzf" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "--help" ]]; then
  printf '%s\n' "${FZF_TEST_HELP:---tmux --bind --print-query --preview-window SIZE_THRESHOLD}"
  exit 0
fi

{
  printf 'argc=%s\n' "$#"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
  printf -- '---\n'
} >>"${TMUX_FZF_URL_FZF_LOG:-/dev/null}"

cat >/dev/null
if [[ "${FZF_TEST_KEY:-}" == "ctrl-y" ]]; then
  printf 'ctrl-y\n%s\n' "$FZF_TEST_CHOICE"
elif [[ "${FZF_TEST_KEY:-}" == "ctrl-y-query" ]]; then
  printf '%s\nctrl-y\n%s\n' "${FZF_TEST_QUERY:-typed query}" "$FZF_TEST_CHOICE"
elif [[ "${FZF_TEST_KEY:-}" == "enter" ]]; then
  printf '\n%s\n' "$FZF_TEST_CHOICE"
elif [[ "${FZF_TEST_KEY:-}" == "print-query" ]]; then
  printf '%s\n%s\n' "${FZF_TEST_QUERY:-typed query}" "$FZF_TEST_CHOICE"
elif [[ "${FZF_TEST_KEY:-}" == "query-only" ]]; then
  printf '%s\n' "${FZF_TEST_QUERY:-typed query}"
elif [[ "${FZF_TEST_KEY:-}" == "cancel" ]]; then
  printf '%s\n' "${FZF_TEST_QUERY:-typed query}"
  exit 130
else
  printf '%s\n' "$FZF_TEST_CHOICE"
fi
SH
chmod +x "$tmp/bin/fzf"

cat >"$tmp/bin/code" <<'SH'
#!/usr/bin/env bash
{
  printf 'argc=%s\n' "$#"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
  printf -- '---\n'
} >>"$TMUX_FZF_URL_CODE_LOG"
SH
chmod +x "$tmp/bin/code"

cat >"$tmp/bin/osc-copy" <<'SH'
#!/usr/bin/env bash
cat >>"$TMUX_FZF_URL_COPY_LOG"
SH
chmod +x "$tmp/bin/osc-copy"

tmux_test() {
  HOME="$tmp/home" \
    PATH="$tmp/bin:$PATH" \
    TMUX_TEST_REAL_TMUX="$real_tmux" \
    TMUX_TEST_SOCKET="$socket_name" \
    "$@"
}

run_picker() {
  local pane_id="$1"
  local choice="$2"
  local key="${3:-}"
  local query="${4:-not-a-candidate}"
  local picker="${TMUX_FZF_URL_PICKER:-$root/common/.local/bin/tmux-fzf-url.sh}"

  HOME="${TMUX_FZF_URL_HOME:-$tmp/home}" \
    PATH="${TMUX_FZF_URL_PATH:-$tmp/bin:$PATH}" \
    DISPLAY="${TMUX_FZF_URL_TEST_DISPLAY:-}" \
    WAYLAND_DISPLAY="${TMUX_FZF_URL_TEST_WAYLAND_DISPLAY:-}" \
    TMUX=fake \
    TMUX_TEST_REAL_TMUX="$real_tmux" \
    TMUX_TEST_SOCKET="$socket_name" \
    TMUX_FZF_URL_TARGET_PANE="$pane_id" \
    FZF_TEST_CHOICE="$choice" \
    FZF_TEST_KEY="$key" \
    FZF_TEST_HELP="${FZF_TEST_HELP:-}" \
    TMUX_FZF_URL_POPUP="${TMUX_FZF_URL_POPUP:-}" \
    TMUX_FZF_URL_CODE_LOG="$tmp/code.log" \
    TMUX_FZF_URL_COPY_LOG="$tmp/copy.log" \
    TMUX_FZF_URL_PBCOPY_LOG="${TMUX_FZF_URL_PBCOPY_LOG:-}" \
    TMUX_FZF_URL_WLCOPY_LOG="${TMUX_FZF_URL_WLCOPY_LOG:-}" \
    TMUX_FZF_URL_XCLIP_LOG="${TMUX_FZF_URL_XCLIP_LOG:-}" \
    TMUX_FZF_URL_XSEL_LOG="${TMUX_FZF_URL_XSEL_LOG:-}" \
    TMUX_FZF_URL_FZF_LOG="$tmp/fzf.log" \
    TMUX_FZF_URL_POPUP_LOG="${TMUX_FZF_URL_POPUP_LOG:-}" \
    TMUX_FZF_URL_POPUP_STATUS="${TMUX_FZF_URL_POPUP_STATUS:-0}" \
    TMUX_FZF_URL_DISPLAY_LOG="${TMUX_FZF_URL_DISPLAY_LOG:-}" \
    TMUX_FZF_URL_NOISY_LIST_COMMANDS="${TMUX_FZF_URL_NOISY_LIST_COMMANDS:-}" \
    TMUX_FZF_URL_STALE_CLIENT="${TMUX_FZF_URL_STALE_CLIENT:-}" \
    TMUX_FZF_URL_CAPTURE_ENV_LOG="${TMUX_FZF_URL_CAPTURE_ENV_LOG:-}" \
    FZF_TEST_QUERY="$query" \
    "$picker"
}

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

wait_for_pane_text() {
  local pane_id="$1"
  local needle="$2"
  local text

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    text="$(tmux_test tmux capture-pane -p -t "$pane_id")"
    [[ "$text" == *"$needle"* ]] && return 0
    sleep 0.1
  done

  printf 'pane did not contain expected text: %s\n' "$needle" >&2
  return 1
}

tmux_test tmux -f "$root/common/.tmux.conf" new-session -d -s picker-open -n main -c "$tmp/work" \
  "printf '%s\n' 'src/app.py:3' 'https://example.test/other'; sleep 60"
open_pane="$(tmux_test tmux list-panes -t =picker-open -F '#{pane_id}')"
wait_for_pane_text "$open_pane" "src/app.py:3"

app_path="$tmp/work/src/app.py"
: >"$tmp/code.log"
: >"$tmp/fzf.log"
run_picker "$open_pane" "src/app.py:3"
assert_eq \
  "picker opens selected file through code" \
  "$(printf 'argc=2\narg=-g\narg=%s:3\n---' "$app_path")" \
  "$(cat "$tmp/code.log")"
assert_contains "picker disables fzf multi-select" "$(cat "$tmp/fzf.log")" $'arg=+m'
assert_contains "picker enables fzf typed query output" "$(cat "$tmp/fzf.log")" "arg=--print-query"
assert_contains "picker preview exports base dir" "$(cat "$tmp/fzf.log")" "arg=--preview=TMUX_FZF_URL_BASE_DIR="
assert_not_contains "picker preview avoids env launcher" "$(cat "$tmp/fzf.log")" "arg=--preview=env "

: >"$tmp/code.log"
: >"$tmp/fzf.log"
stale_capture_env_log="$tmp/stale-capture.env"
TMUX_FZF_URL_STALE_CLIENT=1 \
  TMUX_FZF_URL_CAPTURE_ENV_LOG="$stale_capture_env_log" \
  run_picker "$open_pane" "src/app.py:3"
assert_eq \
  "stale TMUX with target pane opens selected file" \
  "$(printf 'argc=2\narg=-g\narg=%s:3\n---' "$app_path")" \
  "$(cat "$tmp/code.log")"
assert_eq "stale TMUX with target pane captures with TMUX unset" "<unset>" "$(sort -u "$stale_capture_env_log")"
assert_not_contains "stale TMUX picker avoids fzf tmux popup" "$(cat "$tmp/fzf.log")" "arg=--tmux"

no_env_url_bin="$tmp/no-env-url-bin"
no_env_stale_capture_env_log="$tmp/no-env-stale-capture.env"
mkdir -p "$no_env_url_bin"
ln -s "$(command -v bash)" "$no_env_url_bin/bash"
ln -s "$(command -v cat)" "$no_env_url_bin/cat"
ln -s "$(command -v python3)" "$no_env_url_bin/python3"
ln -s "$tmp/bin/tmux" "$no_env_url_bin/tmux"
ln -s "$tmp/bin/fzf" "$no_env_url_bin/fzf"
ln -s "$tmp/bin/code" "$no_env_url_bin/code"
ln -s "$tmp/bin/osc-copy" "$no_env_url_bin/osc-copy"
: >"$tmp/code.log"
: >"$tmp/fzf.log"
TMUX_FZF_URL_STALE_CLIENT=1 \
  TMUX_FZF_URL_CAPTURE_ENV_LOG="$no_env_stale_capture_env_log" \
  TMUX_FZF_URL_PATH="$no_env_url_bin" \
  run_picker "$open_pane" "src/app.py:3"
assert_eq \
  "stale TMUX with target pane opens selected file without env" \
  "$(printf 'argc=2\narg=-g\narg=%s:3\n---' "$app_path")" \
  "$(cat "$tmp/code.log")"
assert_eq "stale TMUX with target pane captures with TMUX unset without env" \
  "<unset>" \
  "$(sort -u "$no_env_stale_capture_env_log")"
assert_not_contains "stale TMUX picker without env avoids fzf tmux popup" "$(cat "$tmp/fzf.log")" "arg=--tmux"

stale_popup_log="$tmp/stale-popup.log"
: >"$tmp/code.log"
: >"$tmp/fzf.log"
: >"$stale_popup_log"
FZF_TEST_HELP='--bind --preview-window SIZE_THRESHOLD' \
  TMUX_FZF_URL_STALE_CLIENT=1 \
  TMUX_FZF_URL_POPUP_LOG="$stale_popup_log" \
  run_picker "$open_pane" "src/app.py:3"
assert_eq \
  "stale TMUX with old fzf runs direct picker" \
  "$(printf 'argc=2\narg=-g\narg=%s:3\n---' "$app_path")" \
  "$(cat "$tmp/code.log")"
assert_eq "stale TMUX with old fzf avoids display-popup" "" "$(cat "$stale_popup_log")"

tmux_test tmux new-session -d -s picker-single -n main -c "$tmp/work" \
  "printf '%s\n' 'src/app.py:3'; sleep 60"
single_pane="$(tmux_test tmux list-panes -t =picker-single -F '#{pane_id}')"
wait_for_pane_text "$single_pane" "src/app.py:3"

: >"$tmp/code.log"
: >"$tmp/fzf.log"
run_picker "$single_pane" "src/app.py:3"
assert_eq \
  "single candidate opens without fzf" \
  "$(printf 'argc=2\narg=-g\narg=%s:3\n---' "$app_path")" \
  "$(cat "$tmp/code.log")"
assert_eq "single candidate skips fzf" "" "$(cat "$tmp/fzf.log")"

missing_extract_helper_dir="$tmp/missing-extract-helper"
missing_extract_display_log="$tmp/missing-extract.display"
mkdir -p "$missing_extract_helper_dir"
for helper_name in tmux-fzf-url.sh tmux-open-helper.sh tmux-fzf-url-preview.sh; do
  ln -s "$root/common/.local/bin/$helper_name" "$missing_extract_helper_dir/$helper_name"
done
: >"$missing_extract_display_log"
if TMUX_FZF_URL_PICKER="$missing_extract_helper_dir/tmux-fzf-url.sh" \
  TMUX_FZF_URL_DISPLAY_LOG="$missing_extract_display_log" \
  run_picker "$open_pane" "src/app.py:3"; then
  printf 'not ok - picker exits non-zero when extractor is missing\n' >&2
  exit 1
fi
assert_contains \
  "picker reports missing extractor helper" \
  "$(cat "$missing_extract_display_log")" \
  "tmux URL extractor is unavailable"

missing_open_helper_dir="$tmp/missing-open-helper"
missing_open_display_log="$tmp/missing-open.display"
mkdir -p "$missing_open_helper_dir"
for helper_name in tmux-fzf-url.sh tmux-fzf-url-helper.py tmux-fzf-url-preview.sh; do
  ln -s "$root/common/.local/bin/$helper_name" "$missing_open_helper_dir/$helper_name"
done
: >"$missing_open_display_log"
if TMUX_FZF_URL_PICKER="$missing_open_helper_dir/tmux-fzf-url.sh" \
  TMUX_FZF_URL_DISPLAY_LOG="$missing_open_display_log" \
  run_picker "$single_pane" "src/app.py:3"; then
  printf 'not ok - picker exits non-zero when open helper is missing\n' >&2
  exit 1
fi
assert_contains \
  "picker reports missing open helper" \
  "$(cat "$missing_open_display_log")" \
  "tmux open helper is unavailable"

missing_preview_helper_dir="$tmp/missing-preview-helper"
missing_preview_display_log="$tmp/missing-preview.display"
mkdir -p "$missing_preview_helper_dir"
for helper_name in tmux-fzf-url.sh tmux-fzf-url-helper.py tmux-open-helper.sh; do
  ln -s "$root/common/.local/bin/$helper_name" "$missing_preview_helper_dir/$helper_name"
done
: >"$missing_preview_display_log"
if TMUX_FZF_URL_PICKER="$missing_preview_helper_dir/tmux-fzf-url.sh" \
  TMUX_FZF_URL_DISPLAY_LOG="$missing_preview_display_log" \
  run_picker "$open_pane" "src/app.py:3"; then
  printf 'not ok - picker exits non-zero when preview helper is missing\n' >&2
  exit 1
fi
assert_contains \
  "picker reports missing preview helper" \
  "$(cat "$missing_preview_display_log")" \
  "tmux URL preview helper is unavailable"

no_filter_bin="$tmp/no-filter-bin"
no_filter_popup_log="$tmp/no-filter-popup.log"
no_filter_display_log="$tmp/no-filter-display.log"
mkdir -p "$no_filter_bin"
for command_name in bash env python3; do
  ln -s "$(command -v "$command_name")" "$no_filter_bin/$command_name"
done
if command -v dirname >/dev/null 2>&1; then
  ln -s "$(command -v dirname)" "$no_filter_bin/dirname"
fi
if command -v realpath >/dev/null 2>&1; then
  ln -s "$(command -v realpath)" "$no_filter_bin/realpath"
fi
ln -sf "$tmp/bin/code" "$no_filter_bin/code"
ln -sf "$tmp/bin/fzf" "$no_filter_bin/fzf"
ln -sf "$tmp/bin/tmux" "$no_filter_bin/tmux"

: >"$tmp/code.log"
: >"$tmp/fzf.log"
TMUX_FZF_URL_PATH="$no_filter_bin" \
  run_picker "$single_pane" "src/app.py:3"
assert_eq \
  "single candidate opens without grep wc or tr" \
  "$(printf 'argc=2\narg=-g\narg=%s:3\n---' "$app_path")" \
  "$(cat "$tmp/code.log")"
assert_eq "single candidate without grep wc or tr skips fzf" "" "$(cat "$tmp/fzf.log")"

: >"$no_filter_popup_log"
: >"$no_filter_display_log"
FZF_TEST_HELP='--bind --preview-window SIZE_THRESHOLD' \
  TMUX_FZF_URL_PATH="$no_filter_bin" \
  TMUX_FZF_URL_POPUP_LOG="$no_filter_popup_log" \
  TMUX_FZF_URL_DISPLAY_LOG="$no_filter_display_log" \
  TMUX_FZF_URL_NOISY_LIST_COMMANDS=1 \
  run_picker "$open_pane" "src/app.py:3"
assert_contains \
  "popup detection works without grep wc or tr" \
  "$(cat "$no_filter_popup_log")" \
  "display-popup"
assert_eq "popup fallback without grep wc or tr is quiet" "" "$(cat "$no_filter_display_log")"

: >"$tmp/code.log"
run_picker "$open_pane" "src/app.py:3" enter
assert_eq \
  "picker handles fzf enter key line" \
  "$(printf 'argc=2\narg=-g\narg=%s:3\n---' "$app_path")" \
  "$(cat "$tmp/code.log")"

: >"$tmp/code.log"
run_picker "$open_pane" "src/app.py:3" print-query
assert_eq \
  "picker ignores fzf printed query" \
  "$(printf 'argc=2\narg=-g\narg=%s:3\n---' "$app_path")" \
  "$(cat "$tmp/code.log")"

: >"$tmp/code.log"
run_picker "$open_pane" "" query-only "src/app.py:3"
assert_eq \
  "picker opens typed query when no candidate is selected" \
  "$(printf 'argc=2\narg=-g\narg=%s:3\n---' "$app_path")" \
  "$(cat "$tmp/code.log")"

: >"$tmp/code.log"
run_picker "$open_pane" "" cancel "src/app.py:3"
assert_eq "picker cancel ignores typed query" "" "$(cat "$tmp/code.log")"

copy_helper_dir="$tmp/copy-helper"
mkdir -p "$copy_helper_dir"
for helper_name in tmux-fzf-url.sh tmux-fzf-url-helper.py tmux-open-helper.sh tmux-fzf-url-preview.sh; do
  ln -s "$root/common/.local/bin/$helper_name" "$copy_helper_dir/$helper_name"
done
cat >"$copy_helper_dir/osc-copy" <<'SH'
#!/usr/bin/env bash
cat >>"$TMUX_FZF_URL_COPY_LOG"
SH
chmod +x "$copy_helper_dir/osc-copy"

: >"$tmp/copy.log"
TMUX_FZF_URL_PICKER="$copy_helper_dir/tmux-fzf-url.sh" \
  run_picker "$open_pane" "" ctrl-y-query "https://example.test/typed"
assert_eq \
  "picker copies typed query on ctrl-y" \
  "https://example.test/typed" \
  "$(cat "$tmp/copy.log")"

tmux_test tmux new-session -d -s picker-copy -n main -c "$tmp/work" \
  "printf '%s\n' 'https://example.test/docs' 'src/app.py:3'; sleep 60"
copy_pane="$(tmux_test tmux list-panes -t =picker-copy -F '#{pane_id}')"
wait_for_pane_text "$copy_pane" "https://example.test/docs"
url_picker_source="$(<"$root/common/.local/bin/tmux-fzf-url.sh")"
dollar='$'
assert_not_contains "picker does not probe root-local copy helper fallback" \
  "$url_picker_source" \
  "${dollar}{HOME:-}/.local/bin/osc-copy"
assert_not_contains "picker does not probe root dotfiles copy helper fallback" \
  "$url_picker_source" \
  "${dollar}{HOME:-}/dotfiles/common/.local/bin/osc-copy"

: >"$tmp/copy.log"
TMUX_FZF_URL_PICKER="$copy_helper_dir/tmux-fzf-url.sh" \
  run_picker "$copy_pane" "https://example.test/docs" ctrl-y
assert_eq \
  "picker copies selected url on ctrl-y" \
  "https://example.test/docs" \
  "$(cat "$tmp/copy.log")"

: >"$tmp/copy.log"
TMUX_FZF_URL_PICKER="$copy_helper_dir/tmux-fzf-url.sh" \
  run_picker "$copy_pane" "https://example.test/docs" ctrl-y-query
assert_eq \
  "picker copies selected url when fzf prints query" \
  "https://example.test/docs" \
  "$(cat "$tmp/copy.log")"

isolated_helper_dir="$tmp/isolated-helper"
isolated_path_bin="$tmp/isolated-path"
isolated_home="$tmp/isolated-home"
mkdir -p "$isolated_helper_dir" "$isolated_path_bin" "$isolated_home/dotfiles/common/.local/bin"
for helper_name in tmux-fzf-url.sh tmux-fzf-url-helper.py tmux-open-helper.sh tmux-fzf-url-preview.sh; do
  ln -s "$root/common/.local/bin/$helper_name" "$isolated_helper_dir/$helper_name"
done
for command_name in tmux fzf code; do
  ln -s "$tmp/bin/$command_name" "$isolated_path_bin/$command_name"
done
cat >"$isolated_path_bin/uname" <<'SH'
#!/usr/bin/env bash
printf 'Linux\n'
SH
chmod +x "$isolated_path_bin/uname"
cat >"$isolated_helper_dir/osc-copy" <<'SH'
#!/usr/bin/env bash
cat >>"$TMUX_FZF_URL_COPY_LOG"
SH
chmod +x "$isolated_helper_dir/osc-copy"
cat >"$isolated_path_bin/osc-copy" <<'SH'
#!/usr/bin/env bash
printf 'path shadow osc-copy should not run\n' >&2
exit 99
SH
chmod +x "$isolated_path_bin/osc-copy"

: >"$tmp/copy.log"
TMUX_FZF_URL_PICKER="$isolated_helper_dir/tmux-fzf-url.sh" \
  TMUX_FZF_URL_PATH="$isolated_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  TMUX_FZF_URL_HOME="$isolated_home" \
  run_picker "$copy_pane" "https://example.test/docs" ctrl-y
assert_eq \
  "picker prefers adjacent osc-copy over PATH shadow" \
  "https://example.test/docs" \
  "$(cat "$tmp/copy.log")"

rm -f "$isolated_helper_dir/osc-copy"
cat >"$isolated_home/dotfiles/common/.local/bin/osc-copy" <<'SH'
#!/usr/bin/env bash
cat >>"$TMUX_FZF_URL_COPY_LOG"
SH
chmod +x "$isolated_home/dotfiles/common/.local/bin/osc-copy"

: >"$tmp/copy.log"
TMUX_FZF_URL_PICKER="$isolated_helper_dir/tmux-fzf-url.sh" \
  TMUX_FZF_URL_PATH="$isolated_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  TMUX_FZF_URL_HOME="$isolated_home" \
  run_picker "$copy_pane" "https://example.test/docs" ctrl-y
assert_eq \
  "picker copies via home dotfiles osc-copy fallback" \
  "https://example.test/docs" \
  "$(cat "$tmp/copy.log")"

rm -f "$isolated_home/dotfiles/common/.local/bin/osc-copy" "$isolated_path_bin/osc-copy"
cat >"$isolated_path_bin/osc-copy" <<'SH'
#!/usr/bin/env bash
cat >>"$TMUX_FZF_URL_COPY_LOG"
SH
chmod +x "$isolated_path_bin/osc-copy"
: >"$tmp/copy.log"
env -u HOME \
  PATH="$isolated_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  DISPLAY= \
  WAYLAND_DISPLAY= \
  TMUX=fake \
  TMUX_TEST_REAL_TMUX="$real_tmux" \
  TMUX_TEST_SOCKET="$socket_name" \
  TMUX_FZF_URL_TARGET_PANE="$copy_pane" \
  FZF_TEST_CHOICE="https://example.test/unset-home" \
  FZF_TEST_KEY=ctrl-y \
  FZF_TEST_HELP="${FZF_TEST_HELP:-}" \
  TMUX_FZF_URL_CODE_LOG="$tmp/code.log" \
  TMUX_FZF_URL_COPY_LOG="$tmp/copy.log" \
  TMUX_FZF_URL_FZF_LOG="$tmp/fzf.log" \
  "$isolated_helper_dir/tmux-fzf-url.sh"
assert_eq \
  "picker falls back to PATH osc-copy when HOME is unset" \
  "https://example.test/unset-home" \
  "$(cat "$tmp/copy.log")"

: >"$tmp/copy.log"
HOME="" \
  PATH="$isolated_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  DISPLAY='' \
  WAYLAND_DISPLAY='' \
  TMUX=fake \
  TMUX_TEST_REAL_TMUX="$real_tmux" \
  TMUX_TEST_SOCKET="$socket_name" \
  TMUX_FZF_URL_TARGET_PANE="$copy_pane" \
  FZF_TEST_CHOICE="https://example.test/empty-home" \
  FZF_TEST_KEY=ctrl-y \
  FZF_TEST_HELP="${FZF_TEST_HELP:-}" \
  TMUX_FZF_URL_CODE_LOG="$tmp/code.log" \
  TMUX_FZF_URL_COPY_LOG="$tmp/copy.log" \
  TMUX_FZF_URL_FZF_LOG="$tmp/fzf.log" \
  "$isolated_helper_dir/tmux-fzf-url.sh"
assert_eq \
  "picker falls back to PATH osc-copy when HOME is empty" \
  "https://example.test/empty-home" \
  "$(cat "$tmp/copy.log")"

rm -f "$isolated_path_bin/osc-copy"
cat >"$isolated_path_bin/wl-copy" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
exit 42
SH
chmod +x "$isolated_path_bin/wl-copy"
cat >"$isolated_path_bin/xclip" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
exit 42
SH
chmod +x "$isolated_path_bin/xclip"
cat >"$isolated_path_bin/xsel" <<'SH'
#!/usr/bin/env bash
if [[ "$*" != "--clipboard --input" ]]; then
  printf 'unexpected xsel args: %s\n' "$*" >&2
  exit 2
fi
cat >>"$TMUX_FZF_URL_COPY_LOG"
SH
chmod +x "$isolated_path_bin/xsel"

: >"$tmp/copy.log"
TMUX_FZF_URL_PICKER="$isolated_helper_dir/tmux-fzf-url.sh" \
  TMUX_FZF_URL_PATH="$isolated_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  TMUX_FZF_URL_HOME="$isolated_home" \
  TMUX_FZF_URL_TEST_DISPLAY=":99" \
  TMUX_FZF_URL_TEST_WAYLAND_DISPLAY="wayland-test" \
  run_picker "$copy_pane" "https://example.test/docs" ctrl-y
assert_eq \
  "picker copies via xsel after failed xclip" \
  "https://example.test/docs" \
  "$(cat "$tmp/copy.log")"

headless_copy_display_log="$tmp/headless-copy.display"
headless_wlcopy_log="$tmp/headless-copy.wl-copy"
headless_xclip_log="$tmp/headless-copy.xclip"
headless_xsel_log="$tmp/headless-copy.xsel"
cat >"$isolated_path_bin/wl-copy" <<'SH'
#!/usr/bin/env bash
cat >"${TMUX_FZF_URL_WLCOPY_LOG:?}"
exit 42
SH
chmod +x "$isolated_path_bin/wl-copy"
cat >"$isolated_path_bin/xclip" <<'SH'
#!/usr/bin/env bash
cat >"${TMUX_FZF_URL_XCLIP_LOG:?}"
exit 42
SH
chmod +x "$isolated_path_bin/xclip"
cat >"$isolated_path_bin/xsel" <<'SH'
#!/usr/bin/env bash
cat >"${TMUX_FZF_URL_XSEL_LOG:?}"
exit 42
SH
chmod +x "$isolated_path_bin/xsel"

rm -f "$headless_wlcopy_log" "$headless_xclip_log" "$headless_xsel_log"
: >"$tmp/copy.log"
: >"$headless_copy_display_log"
TMUX_FZF_URL_PICKER="$isolated_helper_dir/tmux-fzf-url.sh" \
  TMUX_FZF_URL_PATH="$isolated_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  TMUX_FZF_URL_HOME="$isolated_home" \
  TMUX_FZF_URL_DISPLAY_LOG="$headless_copy_display_log" \
  TMUX_FZF_URL_WLCOPY_LOG="$headless_wlcopy_log" \
  TMUX_FZF_URL_XCLIP_LOG="$headless_xclip_log" \
  TMUX_FZF_URL_XSEL_LOG="$headless_xsel_log" \
  run_picker "$copy_pane" "https://example.test/docs" ctrl-y
assert_eq "headless Linux picker copy leaves selection uncopied" "" "$(cat "$tmp/copy.log")"
assert_file_absent "headless Linux picker copy skips wl-copy without display" "$headless_wlcopy_log"
assert_file_absent "headless Linux picker copy skips xclip without display" "$headless_xclip_log"
assert_file_absent "headless Linux picker copy skips xsel without display" "$headless_xsel_log"
assert_contains \
  "headless Linux picker copy reports missing clipboard helper" \
  "$(cat "$headless_copy_display_log")" \
  "No clipboard helper available"

ssh_no_clipboard_helper_dir="$tmp/ssh-no-clipboard-helper"
ssh_no_clipboard_bin="$tmp/ssh-no-clipboard-bin"
ssh_no_clipboard_home="$tmp/ssh-no-clipboard-home"
ssh_no_clipboard_display_log="$tmp/ssh-no-clipboard.display"
ssh_no_clipboard_pbcopy_log="$tmp/ssh-no-clipboard.pbcopy"
ssh_no_clipboard_wlcopy_log="$tmp/ssh-no-clipboard.wl-copy"
ssh_no_clipboard_xclip_log="$tmp/ssh-no-clipboard.xclip"
ssh_no_clipboard_xsel_log="$tmp/ssh-no-clipboard.xsel"
mkdir -p "$ssh_no_clipboard_helper_dir" "$ssh_no_clipboard_bin" "$ssh_no_clipboard_home"
for helper_name in tmux-fzf-url.sh tmux-fzf-url-helper.py tmux-open-helper.sh tmux-fzf-url-preview.sh; do
  ln -s "$root/common/.local/bin/$helper_name" "$ssh_no_clipboard_helper_dir/$helper_name"
done
for command_name in bash cat python3; do
  ln -s "$(command -v "$command_name")" "$ssh_no_clipboard_bin/$command_name"
done
for command_name in tmux fzf code; do
  ln -s "$tmp/bin/$command_name" "$ssh_no_clipboard_bin/$command_name"
done
cat >"$ssh_no_clipboard_bin/uname" <<'SH'
#!/usr/bin/env bash
printf 'Darwin\n'
SH
chmod +x "$ssh_no_clipboard_bin/uname"
cat >"$ssh_no_clipboard_bin/pbcopy" <<'SH'
#!/usr/bin/env bash
cat >"${TMUX_FZF_URL_PBCOPY_LOG:?}"
SH
chmod +x "$ssh_no_clipboard_bin/pbcopy"
cat >"$ssh_no_clipboard_bin/wl-copy" <<'SH'
#!/usr/bin/env bash
cat >"${TMUX_FZF_URL_WLCOPY_LOG:?}"
SH
chmod +x "$ssh_no_clipboard_bin/wl-copy"
cat >"$ssh_no_clipboard_bin/xclip" <<'SH'
#!/usr/bin/env bash
cat >"${TMUX_FZF_URL_XCLIP_LOG:?}"
SH
chmod +x "$ssh_no_clipboard_bin/xclip"
cat >"$ssh_no_clipboard_bin/xsel" <<'SH'
#!/usr/bin/env bash
cat >"${TMUX_FZF_URL_XSEL_LOG:?}"
SH
chmod +x "$ssh_no_clipboard_bin/xsel"

rm -f "$ssh_no_clipboard_pbcopy_log" "$ssh_no_clipboard_wlcopy_log" "$ssh_no_clipboard_xclip_log" "$ssh_no_clipboard_xsel_log"
: >"$ssh_no_clipboard_display_log"
SSH_CLIENT="127.0.0.1 1000 22" \
  TMUX_FZF_URL_PICKER="$ssh_no_clipboard_helper_dir/tmux-fzf-url.sh" \
  TMUX_FZF_URL_PATH="$ssh_no_clipboard_bin" \
  TMUX_FZF_URL_HOME="$ssh_no_clipboard_home" \
  TMUX_FZF_URL_DISPLAY_LOG="$ssh_no_clipboard_display_log" \
  TMUX_FZF_URL_PBCOPY_LOG="$ssh_no_clipboard_pbcopy_log" \
  TMUX_FZF_URL_WLCOPY_LOG="$ssh_no_clipboard_wlcopy_log" \
  TMUX_FZF_URL_XCLIP_LOG="$ssh_no_clipboard_xclip_log" \
  TMUX_FZF_URL_XSEL_LOG="$ssh_no_clipboard_xsel_log" \
  TMUX_FZF_URL_TEST_DISPLAY=":99" \
  TMUX_FZF_URL_TEST_WAYLAND_DISPLAY="wayland-test" \
  run_picker "$copy_pane" "https://example.test/docs" ctrl-y
assert_file_absent "ssh picker copy skips pbcopy without osc-copy" "$ssh_no_clipboard_pbcopy_log"
assert_file_absent "ssh picker copy skips wl-copy without osc-copy" "$ssh_no_clipboard_wlcopy_log"
assert_file_absent "ssh picker copy skips xclip without osc-copy" "$ssh_no_clipboard_xclip_log"
assert_file_absent "ssh picker copy skips xsel without osc-copy" "$ssh_no_clipboard_xsel_log"
assert_contains \
  "ssh picker copy reports missing clipboard helper" \
  "$(cat "$ssh_no_clipboard_display_log")" \
  "No clipboard helper available"

: >"$tmp/code.log"
: >"$tmp/fzf.log"
FZF_TEST_HELP='--bind --preview-window SIZE_THRESHOLD' \
  TMUX_FZF_URL_POPUP=1 \
  run_picker "$open_pane" "src/app.py:3"
assert_eq \
  "old fzf in popup mode still opens selected file" \
  "$(printf 'argc=2\narg=-g\narg=%s:3\n---' "$app_path")" \
  "$(cat "$tmp/code.log")"
assert_not_contains \
  "old fzf in popup mode omits typed query output" \
  "$(cat "$tmp/fzf.log")" \
  "arg=--print-query"

popup_log="$tmp/popup.log"
display_log="$tmp/display.log"
: >"$display_log"
FZF_TEST_HELP='--bind --preview-window SIZE_THRESHOLD' \
  TMUX_FZF_URL_POPUP_LOG="$popup_log" \
  TMUX_FZF_URL_DISPLAY_LOG="$display_log" \
  TMUX_FZF_URL_NOISY_LIST_COMMANDS=1 \
  run_picker "$open_pane" "src/app.py:3"
popup_output="$(cat "$popup_log")"
assert_contains "old fzf falls back to tmux popup" "$popup_output" "display-popup"
assert_not_contains "tmux popup avoids env launcher" "$popup_output" "env TMUX_FZF_URL_POPUP=1"
assert_contains "tmux popup keeps target pane" "$popup_output" "TMUX_FZF_URL_TARGET_PANE=$open_pane"
assert_contains "tmux popup relaunches current picker" "$popup_output" "$root/common/.local/bin/tmux-fzf-url.sh"
assert_contains "popup detection tolerates noisy list-commands output" "$popup_output" "display-popup"
assert_eq "successful popup fallback does not show errors" "" "$(cat "$display_log")"

bare_helper_dir="$tmp/bare-helper"
bare_shadow_dir="$tmp/bare-shadow"
mkdir -p "$bare_helper_dir" "$bare_shadow_dir"
for helper_name in tmux-fzf-url.sh tmux-fzf-url-helper.py tmux-open-helper.sh tmux-fzf-url-preview.sh; do
  ln -s "$root/common/.local/bin/$helper_name" "$bare_helper_dir/$helper_name"
done
cat >"$bare_shadow_dir/tmux-fzf-url.sh" <<'SH'
#!/usr/bin/env bash
printf 'PATH shadow tmux-fzf-url.sh should not run\n' >&2
exit 93
SH
chmod +x "$bare_shadow_dir/tmux-fzf-url.sh"

bare_popup_log="$tmp/bare-popup.log"
: >"$bare_popup_log"
(
  cd "$bare_helper_dir"
  HOME="$tmp/home" \
    PATH="$bare_shadow_dir:$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    TMUX=fake \
    TMUX_TEST_REAL_TMUX="$real_tmux" \
    TMUX_TEST_SOCKET="$socket_name" \
    TMUX_FZF_URL_TARGET_PANE="$open_pane" \
    FZF_TEST_HELP='--bind --preview-window SIZE_THRESHOLD' \
    TMUX_FZF_URL_POPUP_LOG="$bare_popup_log" \
    bash tmux-fzf-url.sh
)
bare_popup_output="$(cat "$bare_popup_log")"
assert_contains "bare url picker popup relaunches current helper" "$bare_popup_output" "$bare_helper_dir/tmux-fzf-url.sh"
assert_not_contains "bare url picker popup avoids PATH shadow" "$bare_popup_output" "$bare_shadow_dir/tmux-fzf-url.sh"

popup_fail_log="$tmp/popup-fail.log"
popup_fail_display_log="$tmp/popup-fail.display"
if FZF_TEST_HELP='--bind --preview-window SIZE_THRESHOLD' \
  TMUX_FZF_URL_POPUP_LOG="$popup_fail_log" \
  TMUX_FZF_URL_POPUP_STATUS=88 \
  TMUX_FZF_URL_DISPLAY_LOG="$popup_fail_display_log" \
  TMUX_FZF_URL_NOISY_LIST_COMMANDS=1 \
  run_picker "$open_pane" "src/app.py:3"; then
  printf 'not ok - popup failure exits non-zero\n' >&2
  exit 1
fi
assert_contains "popup failure attempted display-popup" "$(cat "$popup_fail_log")" "display-popup"
assert_contains "popup failure is visible" \
  "$(cat "$popup_fail_display_log")" \
  "Unable to open tmux URL/path popup"
