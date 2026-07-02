#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

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

clipboard="$tmp/clipboard.txt"
printf 'line one\nline two\n\n' >"$clipboard"

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
