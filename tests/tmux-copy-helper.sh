#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$root/common/.local/bin/tmux-copy-helper"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/tmux-copy-helper.XXXXXX")"
tmp="$(cd "$tmp" && pwd -P)"
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
  rm -rf "$tmp"
}
trap cleanup EXIT

assert_eq() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$actual" != "$expected" ]]; then
    printf 'not ok - %s\nexpected:\n%s\nactual:\n%s\n' "$name" "$expected" "$actual" >&2
    exit 1
  fi

  printf 'ok - %s\n' "$name"
}

assert_contains() {
  local name="$1"
  local haystack="$2"
  local needle="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'not ok - %s\nmissing: %s\nactual:\n%s\n' "$name" "$needle" "$haystack" >&2
    exit 1
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
    exit 1
  fi

  printf 'ok - %s\n' "$name"
}

assert_file_absent() {
  local name="$1"
  local path="$2"

  if [[ -e "$path" ]]; then
    printf 'not ok - %s\nunexpected file: %s\n' "$name" "$path" >&2
    exit 1
  fi

  printf 'ok - %s\n' "$name"
}

write_osc_copy() {
  local path="$1"
  local label="$2"

  mkdir -p "$(dirname "$path")"
  cat >"$path" <<SH
#!/usr/bin/env bash
printf '%s:' '$label' >"\${TMUX_COPY_HELPER_LOG:?}"
cat >>"\${TMUX_COPY_HELPER_LOG:?}"
SH
  chmod +x "$path"
}

write_shadow_osc_copy() {
  local path="$1"

  mkdir -p "$(dirname "$path")"
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf 'shadow osc-copy should not run\n' >&2
exit 97
SH
  chmod +x "$path"
}

write_failing_osc_copy() {
  local path="$1"
  local status="$2"

  mkdir -p "$(dirname "$path")"
  cat >"$path" <<SH
#!/usr/bin/env bash
cat >/dev/null
printf 'osc-copy failed internally\n' >&2
exit $status
SH
  chmod +x "$path"
}

home="$tmp/home"
path_bin="$tmp/path-bin"
adjacent_dir="$tmp/adjacent"
mkdir -p "$home" "$path_bin" "$adjacent_dir"
ln -s "$helper" "$adjacent_dir/tmux-copy-helper"
write_shadow_osc_copy "$path_bin/osc-copy"

adjacent_log="$tmp/adjacent.log"
write_osc_copy "$adjacent_dir/osc-copy" adjacent
printf 'alpha\nbeta' | TMUX_COPY_HELPER_LOG="$adjacent_log" HOME="$home" PATH="$path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$adjacent_dir/tmux-copy-helper"
assert_eq "tmux copy helper uses adjacent osc-copy before PATH" $'adjacent:alpha\nbeta' "$(cat "$adjacent_log")"

rm -f "$adjacent_dir/osc-copy"
mkdir -p "$home/.local/bin" "$home/dotfiles/common/.local/bin"
home_local_log="$tmp/home-local.log"
write_osc_copy "$home/.local/bin/osc-copy" home-local
printf 'from-home-local' | TMUX_COPY_HELPER_LOG="$home_local_log" HOME="$home" PATH="$path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$adjacent_dir/tmux-copy-helper"
assert_eq "tmux copy helper uses home local osc-copy" "home-local:from-home-local" "$(cat "$home_local_log")"

rm -f "$home/.local/bin/osc-copy"
home_dotfiles_log="$tmp/home-dotfiles.log"
write_osc_copy "$home/dotfiles/common/.local/bin/osc-copy" home-dotfiles
printf 'from-home-dotfiles' | TMUX_COPY_HELPER_LOG="$home_dotfiles_log" HOME="$home" PATH="$path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$adjacent_dir/tmux-copy-helper"
assert_eq "tmux copy helper uses home dotfiles osc-copy" "home-dotfiles:from-home-dotfiles" "$(cat "$home_dotfiles_log")"

rm -f "$home/dotfiles/common/.local/bin/osc-copy" "$path_bin/osc-copy"
path_log="$tmp/path.log"
write_osc_copy "$path_bin/osc-copy" path
printf 'from-path' | TMUX_COPY_HELPER_LOG="$path_log" HOME="$home" PATH="$path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$adjacent_dir/tmux-copy-helper"
assert_eq "tmux copy helper falls back to PATH osc-copy" "path:from-path" "$(cat "$path_log")"

spaced_helper_dir="$tmp/spaced helper dir"
spaced_home="$tmp/spaced home"
spaced_path_bin="$tmp/spaced path bin"
mkdir -p "$spaced_helper_dir" "$spaced_home/.local/bin" "$spaced_home/dotfiles/common/.local/bin" "$spaced_path_bin"
ln -s "$helper" "$spaced_helper_dir/tmux-copy-helper"
write_shadow_osc_copy "$spaced_path_bin/osc-copy"

spaced_adjacent_log="$tmp/spaced-adjacent.log"
write_osc_copy "$spaced_helper_dir/osc-copy" spaced-adjacent
printf 'from-spaced-adjacent' | TMUX_COPY_HELPER_LOG="$spaced_adjacent_log" HOME="$spaced_home" \
  PATH="$spaced_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$spaced_helper_dir/tmux-copy-helper"
assert_eq "tmux copy helper handles adjacent helper path with spaces" \
  "spaced-adjacent:from-spaced-adjacent" \
  "$(cat "$spaced_adjacent_log")"

rm -f "$spaced_helper_dir/osc-copy"
spaced_home_local_log="$tmp/spaced-home-local.log"
write_osc_copy "$spaced_home/.local/bin/osc-copy" spaced-home-local
printf 'from-spaced-home-local' | TMUX_COPY_HELPER_LOG="$spaced_home_local_log" HOME="$spaced_home" \
  PATH="$spaced_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$spaced_helper_dir/tmux-copy-helper"
assert_eq "tmux copy helper handles HOME local path with spaces" \
  "spaced-home-local:from-spaced-home-local" \
  "$(cat "$spaced_home_local_log")"

rm -f "$spaced_home/.local/bin/osc-copy"
spaced_home_dotfiles_log="$tmp/spaced-home-dotfiles.log"
write_osc_copy "$spaced_home/dotfiles/common/.local/bin/osc-copy" spaced-home-dotfiles
printf 'from-spaced-home-dotfiles' | TMUX_COPY_HELPER_LOG="$spaced_home_dotfiles_log" HOME="$spaced_home" \
  PATH="$spaced_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$spaced_helper_dir/tmux-copy-helper"
assert_eq "tmux copy helper handles HOME dotfiles path with spaces" \
  "spaced-home-dotfiles:from-spaced-home-dotfiles" \
  "$(cat "$spaced_home_dotfiles_log")"

rm -f "$spaced_home/dotfiles/common/.local/bin/osc-copy" "$spaced_path_bin/osc-copy"
spaced_path_log="$tmp/spaced-path.log"
write_osc_copy "$spaced_path_bin/osc-copy" spaced-path
env -u HOME \
  TMUX_COPY_HELPER_LOG="$spaced_path_log" \
  PATH="$spaced_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$spaced_helper_dir/tmux-copy-helper" <<<"from-spaced-path"
assert_eq "tmux copy helper handles PATH entry with spaces" \
  "spaced-path:from-spaced-path" \
  "$(cat "$spaced_path_log")"

exact_helper_dir="$tmp/exact-helper"
exact_home="$tmp/exact-home"
exact_path_bin="$tmp/exact-path-bin"
exact_expected="$tmp/exact-copy-input.bin"
exact_actual="$tmp/exact-copy-output.bin"
exact_crlf_expected="$tmp/exact-copy-crlf-input.bin"
exact_crlf_actual="$tmp/exact-copy-crlf-output.bin"
exact_unicode_expected="$tmp/exact-copy-unicode-input.txt"
exact_unicode_actual="$tmp/exact-copy-unicode-output.txt"
exact_large_expected="$tmp/exact-copy-large-input.txt"
exact_large_actual="$tmp/exact-copy-large-output.txt"
exact_empty_expected="$tmp/exact-copy-empty-input.bin"
exact_empty_actual="$tmp/exact-copy-empty-output.bin"
mkdir -p "$exact_helper_dir" "$exact_home" "$exact_path_bin"
ln -s "$helper" "$exact_helper_dir/tmux-copy-helper"
{
  printf '#!/usr/bin/env bash\n'
  printf 'cat >%q\n' "$exact_actual"
} >"$exact_helper_dir/osc-copy"
chmod +x "$exact_helper_dir/osc-copy"
printf 'copy-helper binary before\0middle\n\nlast line\n' >"$exact_expected"
HOME="$exact_home" PATH="$exact_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$exact_helper_dir/tmux-copy-helper" <"$exact_expected"
assert_files_equal "tmux copy helper preserves exact stdin bytes" "$exact_expected" "$exact_actual"

{
  printf '#!/usr/bin/env bash\n'
  printf 'cat >%q\n' "$exact_crlf_actual"
} >"$exact_helper_dir/osc-copy"
chmod +x "$exact_helper_dir/osc-copy"
printf 'copy-helper crlf\r\nsecond\rthird\n' >"$exact_crlf_expected"
HOME="$exact_home" PATH="$exact_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$exact_helper_dir/tmux-copy-helper" <"$exact_crlf_expected"
assert_files_equal "tmux copy helper preserves CRLF stdin bytes" "$exact_crlf_expected" "$exact_crlf_actual"

{
  printf '#!/usr/bin/env bash\n'
  printf 'cat >%q\n' "$exact_unicode_actual"
} >"$exact_helper_dir/osc-copy"
chmod +x "$exact_helper_dir/osc-copy"
printf 'copy-helper caf\xc3\xa9\nlambda \xce\xbb\neuro \xe2\x82\xac\n' >"$exact_unicode_expected"
HOME="$exact_home" PATH="$exact_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$exact_helper_dir/tmux-copy-helper" <"$exact_unicode_expected"
assert_files_equal "tmux copy helper preserves UTF-8 stdin bytes" "$exact_unicode_expected" "$exact_unicode_actual"

{
  printf '#!/usr/bin/env bash\n'
  printf 'cat >%q\n' "$exact_large_actual"
} >"$exact_helper_dir/osc-copy"
chmod +x "$exact_helper_dir/osc-copy"
{
  for ((i = 1; i <= 4096; i++)); do
    printf 'copy-helper-large-%04d\ttrailing spaces   \n' "$i"
  done
  printf 'copy-helper-large-final\ttrail   '
} >"$exact_large_expected"
HOME="$exact_home" PATH="$exact_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$exact_helper_dir/tmux-copy-helper" <"$exact_large_expected"
assert_files_equal "tmux copy helper preserves large whitespace stdin bytes" \
  "$exact_large_expected" \
  "$exact_large_actual"

{
  printf '#!/usr/bin/env bash\n'
  printf 'cat >%q\n' "$exact_empty_actual"
} >"$exact_helper_dir/osc-copy"
chmod +x "$exact_helper_dir/osc-copy"
: >"$exact_empty_expected"
HOME="$exact_home" PATH="$exact_path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$exact_helper_dir/tmux-copy-helper" <"$exact_empty_expected"
assert_files_equal "tmux copy helper preserves empty stdin" "$exact_empty_expected" "$exact_empty_actual"

write_failing_osc_copy "$path_bin/osc-copy" 42
if printf 'failing' | HOME="$home" PATH="$path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$adjacent_dir/tmux-copy-helper" >"$tmp/failing.out" 2>"$tmp/failing.err"; then
  printf 'not ok - tmux copy helper exits non-zero when osc-copy fails\n' >&2
  exit 1
else
  failing_status=$?
fi
assert_eq "tmux copy helper preserves failed osc-copy status" "42" "$failing_status"
assert_contains "tmux copy helper keeps osc-copy stderr" "$(cat "$tmp/failing.err")" "osc-copy failed internally"
assert_contains "tmux copy helper reports failed osc-copy" "$(cat "$tmp/failing.err")" "tmux-copy-helper: osc-copy failed"

rm -f "$path_bin/osc-copy"
if printf 'missing' | HOME="$home" PATH="$path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$adjacent_dir/tmux-copy-helper" >"$tmp/missing.out" 2>"$tmp/missing.err"; then
  printf 'not ok - tmux copy helper exits non-zero without osc-copy\n' >&2
  exit 1
fi
assert_eq "tmux copy helper reports missing osc-copy" "tmux-copy-helper: osc-copy not found" "$(cat "$tmp/missing.err")"

cat >"$path_bin/tmux" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "display-message" && "${2:-}" == "-p" ]]; then
  printf '%%1\n'
  exit 0
fi

if [[ "${1:-}" == "display-message" ]]; then
  shift
  printf '%s\n' "$*" >>"${TMUX_COPY_HELPER_DISPLAY_LOG:?}"
  exit 0
fi

printf 'unexpected tmux command: %s\n' "$*" >&2
exit 2
SH
chmod +x "$path_bin/tmux"
missing_display_log="$tmp/missing-display.log"
if printf 'missing' | TMUX=fake TMUX_COPY_HELPER_DISPLAY_LOG="$missing_display_log" HOME="$home" \
  PATH="$path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$adjacent_dir/tmux-copy-helper" >"$tmp/missing-display.out" 2>"$tmp/missing-display.err"; then
  printf 'not ok - tmux copy helper exits non-zero without osc-copy inside tmux\n' >&2
  exit 1
fi
assert_eq "tmux copy helper reports missing osc-copy to stderr inside tmux" \
  "tmux-copy-helper: osc-copy not found" \
  "$(cat "$tmp/missing-display.err")"
assert_eq "tmux copy helper reports missing osc-copy to tmux" \
  "osc-copy not found" \
  "$(cat "$missing_display_log")"
write_failing_osc_copy "$path_bin/osc-copy" 43
failing_display_log="$tmp/failing-display.log"
if printf 'failing' | TMUX=fake TMUX_COPY_HELPER_DISPLAY_LOG="$failing_display_log" HOME="$home" \
  PATH="$path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$adjacent_dir/tmux-copy-helper" >"$tmp/failing-display.out" 2>"$tmp/failing-display.err"; then
  printf 'not ok - tmux copy helper exits non-zero when osc-copy fails inside tmux\n' >&2
  exit 1
else
  failing_display_status=$?
fi
assert_eq "tmux copy helper preserves failed osc-copy status inside tmux" "43" "$failing_display_status"
assert_contains "tmux copy helper keeps failed osc-copy stderr inside tmux" \
  "$(cat "$tmp/failing-display.err")" \
  "osc-copy failed internally"
assert_contains "tmux copy helper reports failed osc-copy to stderr inside tmux" \
  "$(cat "$tmp/failing-display.err")" \
  "tmux-copy-helper: osc-copy failed"
assert_eq "tmux copy helper reports failed osc-copy to tmux" \
  "osc-copy failed" \
  "$(cat "$failing_display_log")"
rm -f "$path_bin/tmux"

tmux_conf="$(<"$root/common/.tmux.conf")"
copy_binding_home_guard="if [ -n \"\${HOME:-}\" ]; then for helper in \"\$HOME/.local/bin/tmux-copy-helper\""
assert_contains "tmux copy bindings call tmux-copy-helper" "$tmux_conf" "tmux-copy-helper"
assert_contains "tmux copy-command uses tmux-copy-helper" "$tmux_conf" "set-option -gq copy-command"
assert_contains "tmux copy bindings guard unset HOME" \
  "$tmux_conf" \
  "$copy_binding_home_guard"
if [[ "$tmux_conf" == *"osc-copy unavailable"* ]]; then
  printf 'not ok - tmux copy bindings avoid inline osc-copy fallback\n' >&2
  exit 1
fi
printf 'ok - tmux copy bindings avoid inline osc-copy fallback\n'

wait_for_nonempty_file() {
  local path="$1"

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -s "$path" ]] && return 0
    sleep 0.1
  done

  printf 'timed out waiting for %s\n' "$path" >&2
  return 1
}

wait_for_pbpaste_value() {
  local expected="$1"
  local actual=""

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    actual="$(pbpaste 2>/dev/null || true)"
    if [[ "$actual" == "$expected" ]]; then
      return 0
    fi
    sleep 0.1
  done

  printf 'timed out waiting for pbpaste value\nexpected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
  return 1
}

wait_for_pbpaste_file() {
  local expected_file="$1"
  local actual_file="$2"

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pbpaste >"$actual_file" 2>/dev/null || true
    if cmp -s "$expected_file" "$actual_file"; then
      return 0
    fi
    sleep 0.1
  done

  printf 'timed out waiting for pbpaste file value\n' >&2
  printf 'expected bytes:\n' >&2
  od -An -tx1 "$expected_file" >&2
  printf 'actual bytes:\n' >&2
  od -An -tx1 "$actual_file" >&2
  return 1
}

if real_tmux="$(command -v tmux 2>/dev/null)"; then
  run_live_copy_binding() {
    local mode_keys="$1"
    local key="$2"
    local expected="$3"
    local label="$4"
    local selection_setup="${5:-line}"
    local live_home="$tmp/live-home-$label"
    local live_copy_log="$tmp/live-copy-$label.log"
    local live_window
    local session_name="copy-helper-$label"

    live_socket="dotfiles-copy-helper-$label-$$"
    rm -rf "$live_home"
    mkdir -p "$live_home/.local/bin"
    cat >"$live_home/.local/bin/tmux-copy-helper" <<SH
#!/usr/bin/env bash
cat >"$live_copy_log"
SH
    chmod +x "$live_home/.local/bin/tmux-copy-helper"

    "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
    HOME="$live_home" "$real_tmux" -L "$live_socket" -f "$root/common/.tmux.conf" \
      new-session -d -s "$session_name" "printf 'copy-mode alpha\\ncopy-mode beta\\ncopy-mode gamma\\n'; sleep 60"
    live_pane="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p '#{pane_id}')"
    live_window="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p -t "$live_pane" '#{window_id}')"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-window-option -t "$live_window" mode-keys "$mode_keys" >/dev/null
    sleep 0.2

    HOME="$live_home" "$real_tmux" -L "$live_socket" copy-mode -t "$live_pane"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" search-backward "$expected"
    if [[ "$selection_setup" == "line" ]]; then
      HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" select-line
    fi
    rm -f "$live_copy_log"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -t "$live_pane" "$key"
    wait_for_nonempty_file "$live_copy_log"
    assert_eq "tmux $mode_keys copy-mode $key binding pipes selection through copy helper" "$expected" "$(cat "$live_copy_log")"
    "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
    live_socket=""
  }

  run_live_copy_binding_e2e() {
    local live_home="$tmp/live-home-e2e"
    local live_copy_log="$tmp/live-copy-e2e.log"
    local live_pane
    local live_window

    live_socket="dotfiles-copy-helper-e2e-$$"
    rm -rf "$live_home"
    mkdir -p "$live_home/.local/bin"
    ln -s "$helper" "$live_home/.local/bin/tmux-copy-helper"
    {
      printf '#!/usr/bin/env bash\n'
      printf 'cat >%q\n' "$live_copy_log"
    } >"$live_home/.local/bin/osc-copy"
    chmod +x "$live_home/.local/bin/osc-copy"

    "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
    HOME="$live_home" "$real_tmux" -L "$live_socket" -f "$root/common/.tmux.conf" \
      new-session -d -s "copy-helper-e2e" "printf 'copy chain alpha\\ncopy chain beta\\ncopy chain gamma\\n'; sleep 60"
    live_pane="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p '#{pane_id}')"
    live_window="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p -t "$live_pane" '#{window_id}')"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-window-option -t "$live_window" mode-keys vi >/dev/null
    sleep 0.2

    HOME="$live_home" "$real_tmux" -L "$live_socket" copy-mode -t "$live_pane"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" search-backward "copy chain beta"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" select-line
    rm -f "$live_copy_log"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -t "$live_pane" y
    wait_for_nonempty_file "$live_copy_log"
    assert_eq "live tmux copy binding pipes selection through real copy helper" "copy chain beta" "$(cat "$live_copy_log")"
    "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
    live_socket=""
  }

  run_live_copy_binding_path_fallback_case() {
    local home_mode="$1"
    local label="$2"
    local home_description="$3"
    local live_home="$tmp/live-home-path-$label"
    local path_bin="$tmp/live-copy-path-bin-$label"
    local live_copy_log="$tmp/live-copy-path-$label.log"
    local live_pane
    local live_window
    local real_tmux_dir="${real_tmux%/*}"
    local expected="path copy $label beta"

    live_socket="dotfiles-copy-helper-path-$label-$$"
    rm -rf "$live_home" "$path_bin"
    mkdir -p "$live_home" "$path_bin"
    ln -s "$helper" "$path_bin/tmux-copy-helper"
    {
      printf '#!/usr/bin/env bash\n'
      printf 'cat >%q\n' "$live_copy_log"
    } >"$path_bin/osc-copy"
    chmod +x "$path_bin/osc-copy"

    "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
    HOME="$live_home" "$real_tmux" -L "$live_socket" -f "$root/common/.tmux.conf" \
      new-session -d -s "copy-helper-path-$label" "printf 'path copy $label alpha\\npath copy $label beta\\npath copy $label gamma\\n'; sleep 60"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -g PATH \
      "$path_bin:$real_tmux_dir:/usr/bin:/bin:/usr/sbin:/sbin"
    if [[ "$home_mode" == "unset" ]]; then
      HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -gu HOME
    else
      HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -g HOME ""
    fi
    live_pane="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p '#{pane_id}')"
    live_window="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p -t "$live_pane" '#{window_id}')"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-window-option -t "$live_window" mode-keys vi >/dev/null
    sleep 0.2

    HOME="$live_home" "$real_tmux" -L "$live_socket" copy-mode -t "$live_pane"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" search-backward "$expected"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" select-line
    rm -f "$live_copy_log"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -t "$live_pane" y
    wait_for_nonempty_file "$live_copy_log"
    assert_eq "live tmux copy binding falls back to PATH when HOME is $home_description" \
      "$expected" \
      "$(cat "$live_copy_log")"
    "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
    live_socket=""
  }

  run_live_copy_binding_path_fallback() {
    run_live_copy_binding_path_fallback_case unset unset unset
    run_live_copy_binding_path_fallback_case empty empty empty
  }

  run_live_copy_command_default() {
    local live_home="$tmp/live-home-copy-command"
    local live_copy_log="$tmp/live-copy-command.log"
    local live_pane
    local live_window

    live_socket="dotfiles-copy-command-$$"
    rm -rf "$live_home"
    mkdir -p "$live_home/.local/bin"
    cat >"$live_home/.local/bin/tmux-copy-helper" <<SH
#!/usr/bin/env bash
cat >"$live_copy_log"
SH
    chmod +x "$live_home/.local/bin/tmux-copy-helper"

    "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
    HOME="$live_home" "$real_tmux" -L "$live_socket" -f "$root/common/.tmux.conf" \
      new-session -d -s "copy-command-default" "printf 'copy command alpha\\ncopy command beta\\ncopy command gamma\\n'; sleep 60"
    live_pane="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p '#{pane_id}')"
    live_window="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p -t "$live_pane" '#{window_id}')"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-window-option -t "$live_window" mode-keys vi >/dev/null
    sleep 0.2

    HOME="$live_home" "$real_tmux" -L "$live_socket" copy-mode -t "$live_pane"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" search-backward "copy command beta"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" select-line
    rm -f "$live_copy_log"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" copy-pipe-and-cancel
    wait_for_nonempty_file "$live_copy_log"
    assert_eq "tmux copy-command pipes no-arg copy-pipe through copy helper" \
      "copy command beta" \
      "$(cat "$live_copy_log")"
    "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
    live_socket=""
  }

  run_live_copy_command_path_fallback_case() {
    local home_mode="$1"
    local label="$2"
    local home_description="$3"
    local live_home="$tmp/live-home-copy-command-path-$label"
    local path_bin="$tmp/live-copy-command-path-bin-$label"
    local live_copy_log="$tmp/live-copy-command-path-$label.log"
    local live_pane
    local live_window
    local real_tmux_dir="${real_tmux%/*}"
    local expected="copy command path $label beta"

    live_socket="dotfiles-copy-command-path-$label-$$"
    rm -rf "$live_home" "$path_bin"
    mkdir -p "$live_home" "$path_bin"
    ln -s "$helper" "$path_bin/tmux-copy-helper"
    {
      printf '#!/usr/bin/env bash\n'
      printf 'cat >%q\n' "$live_copy_log"
    } >"$path_bin/osc-copy"
    chmod +x "$path_bin/osc-copy"

    "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
    HOME="$live_home" "$real_tmux" -L "$live_socket" -f "$root/common/.tmux.conf" \
      new-session -d -s "copy-command-path-$label" "printf 'copy command path $label alpha\\ncopy command path $label beta\\ncopy command path $label gamma\\n'; sleep 60"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -g PATH \
      "$path_bin:$real_tmux_dir:/usr/bin:/bin:/usr/sbin:/sbin"
    if [[ "$home_mode" == "unset" ]]; then
      HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -gu HOME
    else
      HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -g HOME ""
    fi
    live_pane="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p '#{pane_id}')"
    live_window="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p -t "$live_pane" '#{window_id}')"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-window-option -t "$live_window" mode-keys vi >/dev/null
    sleep 0.2

    HOME="$live_home" "$real_tmux" -L "$live_socket" copy-mode -t "$live_pane"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" search-backward "$expected"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" select-line
    rm -f "$live_copy_log"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" copy-pipe-and-cancel
    wait_for_nonempty_file "$live_copy_log"
    assert_eq "tmux copy-command falls back to PATH when HOME is $home_description" \
      "$expected" \
      "$(cat "$live_copy_log")"
    "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
    live_socket=""
  }

  run_live_copy_command_path_fallback() {
    run_live_copy_command_path_fallback_case unset unset unset
    run_live_copy_command_path_fallback_case empty empty empty
  }

  run_live_copy_command_mock_ssh_buffer() {
    local live_home="$tmp/live-home-copy-command-mock-ssh"
    local live_pane
    local live_window
    local real_tmux_dir="${real_tmux%/*}"
    local expected="mock ssh copy command beta"
    local actual=""
    local pbcopy_log="$tmp/mock-ssh-copy-command-pbcopy.log"

    live_socket="dotfiles-copy-command-mock-ssh-$$"
    rm -rf "$live_home"
    mkdir -p "$live_home/.local/bin"
    ln -s "$helper" "$live_home/.local/bin/tmux-copy-helper"
    ln -s "$root/common/.local/bin/osc-copy" "$live_home/.local/bin/osc-copy"
    cat >"$live_home/.local/bin/pbcopy" <<SH
#!/usr/bin/env bash
cat >"$pbcopy_log"
SH
    chmod +x "$live_home/.local/bin/pbcopy"

    "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
    HOME="$live_home" "$real_tmux" -L "$live_socket" -f "$root/common/.tmux.conf" \
      new-session -d -s "copy-command-mock-ssh" "printf 'mock ssh copy command alpha\\nmock ssh copy command beta\\nmock ssh copy command gamma\\n'; sleep 60"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -g PATH \
      "$live_home/.local/bin:$real_tmux_dir:/usr/bin:/bin:/usr/sbin:/sbin"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -g SSH_CLIENT "127.0.0.1 1000 22"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -gu SSH_TTY >/dev/null 2>&1 || true
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -gu SSH_CONNECTION >/dev/null 2>&1 || true
    live_pane="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p '#{pane_id}')"
    live_window="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p -t "$live_pane" '#{window_id}')"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-window-option -t "$live_window" mode-keys vi >/dev/null
    sleep 0.2

    HOME="$live_home" "$real_tmux" -L "$live_socket" copy-mode -t "$live_pane"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" search-backward "$expected"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" select-line
    rm -f "$pbcopy_log"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" copy-pipe-and-cancel
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      actual="$(HOME="$live_home" "$real_tmux" -L "$live_socket" save-buffer - 2>/dev/null || true)"
      [[ "$actual" == "$expected" ]] && break
      sleep 0.1
    done
    assert_eq "live mock ssh tmux copy-command writes tmux buffer" "$expected" "$actual"
    assert_file_absent "live mock ssh tmux copy-command skips host pbcopy" "$pbcopy_log"
    "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
    live_socket=""
  }

  run_live_copy_rectangle_binding() {
    local live_home="$tmp/live-home-rectangle"
    local live_copy_log="$tmp/live-copy-rectangle.log"
    local live_pane
    local live_window

    live_socket="dotfiles-copy-helper-rectangle-$$"
    rm -rf "$live_home"
    mkdir -p "$live_home/.local/bin"
    cat >"$live_home/.local/bin/tmux-copy-helper" <<SH
#!/usr/bin/env bash
cat >"$live_copy_log"
SH
    chmod +x "$live_home/.local/bin/tmux-copy-helper"

    "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
    HOME="$live_home" "$real_tmux" -L "$live_socket" -f "$root/common/.tmux.conf" \
      new-session -d -s "copy-helper-rectangle" "printf 'R1-abcd\\nR2-EFGH\\nR3-uvwx\\n'; sleep 60"
    live_pane="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p '#{pane_id}')"
    live_window="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p -t "$live_pane" '#{window_id}')"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-window-option -t "$live_window" mode-keys vi >/dev/null
    sleep 0.2

    HOME="$live_home" "$real_tmux" -L "$live_socket" copy-mode -t "$live_pane"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" search-backward "R2-"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -t "$live_pane" C-v
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -N 1 -X -t "$live_pane" cursor-down
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -N 2 -X -t "$live_pane" cursor-right
    rm -f "$live_copy_log"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -t "$live_pane" y
    wait_for_nonempty_file "$live_copy_log"
    assert_eq "tmux vi copy-mode C-v binding pipes rectangle through copy helper" $'R2-\nR3-' "$(cat "$live_copy_log")"
    "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
    live_socket=""
  }

  run_live_copy_binding_real_host() {
    local live_home="$tmp/live-home-real-host"
    local live_pane
    local live_window
    local real_tmux_dir="${real_tmux%/*}"
    local expected="real host copy beta"

    if ! command -v pbcopy >/dev/null 2>&1 || ! command -v pbpaste >/dev/null 2>&1; then
      printf 'skip - live tmux copy binding real host clipboard (pbcopy/pbpaste unavailable)\n'
      return 0
    fi

    real_clipboard_backup="$tmp/real-clipboard-backup.txt"
    if ! pbpaste >"$real_clipboard_backup"; then
      real_clipboard_backup=""
      printf 'skip - live tmux copy binding real host clipboard (pbpaste failed)\n'
      return 0
    fi

    live_socket="dotfiles-copy-helper-real-host-$$"
    rm -rf "$live_home"
    mkdir -p "$live_home/.local/bin"
    ln -s "$helper" "$live_home/.local/bin/tmux-copy-helper"
    ln -s "$root/common/.local/bin/osc-copy" "$live_home/.local/bin/osc-copy"

    "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
    HOME="$live_home" "$real_tmux" -L "$live_socket" -f "$root/common/.tmux.conf" \
      new-session -d -s "copy-helper-real-host" "printf 'real host copy alpha\\nreal host copy beta\\nreal host copy gamma\\n'; sleep 60"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -g PATH \
      "$live_home/.local/bin:$real_tmux_dir:/usr/bin:/bin:/usr/sbin:/sbin"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -gu SSH_CLIENT >/dev/null 2>&1 || true
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -gu SSH_TTY >/dev/null 2>&1 || true
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -gu SSH_CONNECTION >/dev/null 2>&1 || true
    live_pane="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p '#{pane_id}')"
    live_window="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p -t "$live_pane" '#{window_id}')"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-window-option -t "$live_window" mode-keys vi >/dev/null
    printf 'old pasteboard value\n' | pbcopy
    sleep 0.2

    HOME="$live_home" "$real_tmux" -L "$live_socket" copy-mode -t "$live_pane"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" search-backward "$expected"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" select-line
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -t "$live_pane" y
    wait_for_pbpaste_value "$expected"
    assert_eq "live tmux copy binding writes real host clipboard" "$expected" "$(pbpaste)"
    "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
    live_socket=""
  }

  run_live_copy_binding_mock_ssh_buffer() {
    local live_home="$tmp/live-home-mock-ssh"
    local live_pane
    local live_window
    local real_tmux_dir="${real_tmux%/*}"
    local expected="mock ssh copy beta"
    local actual=""
    local pbcopy_log="$tmp/mock-ssh-pbcopy.log"

    live_socket="dotfiles-copy-helper-mock-ssh-$$"
    rm -rf "$live_home"
    mkdir -p "$live_home/.local/bin"
    ln -s "$helper" "$live_home/.local/bin/tmux-copy-helper"
    ln -s "$root/common/.local/bin/osc-copy" "$live_home/.local/bin/osc-copy"
    cat >"$live_home/.local/bin/pbcopy" <<SH
#!/usr/bin/env bash
cat >"$pbcopy_log"
SH
    chmod +x "$live_home/.local/bin/pbcopy"

    "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
    HOME="$live_home" "$real_tmux" -L "$live_socket" -f "$root/common/.tmux.conf" \
      new-session -d -s "copy-helper-mock-ssh" "printf 'mock ssh copy alpha\\nmock ssh copy beta\\nmock ssh copy gamma\\n'; sleep 60"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -g PATH \
      "$live_home/.local/bin:$real_tmux_dir:/usr/bin:/bin:/usr/sbin:/sbin"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -g SSH_CLIENT "127.0.0.1 1000 22"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -gu SSH_TTY >/dev/null 2>&1 || true
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -gu SSH_CONNECTION >/dev/null 2>&1 || true
    live_pane="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p '#{pane_id}')"
    live_window="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p -t "$live_pane" '#{window_id}')"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-window-option -t "$live_window" mode-keys vi >/dev/null
    sleep 0.2

    HOME="$live_home" "$real_tmux" -L "$live_socket" copy-mode -t "$live_pane"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" search-backward "$expected"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" select-line
    rm -f "$pbcopy_log"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -t "$live_pane" y
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      actual="$(HOME="$live_home" "$real_tmux" -L "$live_socket" save-buffer - 2>/dev/null || true)"
      [[ "$actual" == "$expected" ]] && break
      sleep 0.1
    done
    assert_eq "live mock ssh tmux copy binding writes tmux buffer" "$expected" "$actual"
    assert_file_absent "live mock ssh tmux copy binding skips host pbcopy" "$pbcopy_log"
    "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
    live_socket=""
  }

  run_live_copy_paste_roundtrip() {
    local live_home="$tmp/live-home-roundtrip"
    local live_tmux_env="$tmp/live-roundtrip-tmux-env.txt"
    local live_output="$tmp/live-roundtrip-output.txt"
    local live_expected="$tmp/live-roundtrip-expected.txt"
    local live_pane
    local live_window
    local target_window
    local target_pane
    local real_tmux_dir="${real_tmux%/*}"
    local expected="roundtrip copy beta"

    if ! command -v pbcopy >/dev/null 2>&1 || ! command -v pbpaste >/dev/null 2>&1; then
      printf 'skip - live tmux copy paste roundtrip (pbcopy/pbpaste unavailable)\n'
      return 0
    fi

    real_clipboard_backup="$tmp/real-clipboard-backup.txt"
    if ! pbpaste >"$real_clipboard_backup"; then
      real_clipboard_backup=""
      printf 'skip - live tmux copy paste roundtrip (pbpaste failed)\n'
      return 0
    fi

    live_socket="dotfiles-copy-paste-roundtrip-$$"
    rm -rf "$live_home"
    mkdir -p "$live_home/.local/bin"
    ln -s "$helper" "$live_home/.local/bin/tmux-copy-helper"
    ln -s "$root/common/.local/bin/tmux-paste-helper" "$live_home/.local/bin/tmux-paste-helper"
    ln -s "$root/common/.local/bin/osc-copy" "$live_home/.local/bin/osc-copy"
    ln -s "$root/common/.local/bin/osc-paste" "$live_home/.local/bin/osc-paste"
    printf '%s\n' "$expected" >"$live_expected"

    "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
    HOME="$live_home" "$real_tmux" -L "$live_socket" -f "$root/common/.tmux.conf" \
      new-session -d -s "copy-paste-roundtrip" "printf 'roundtrip copy alpha\\nroundtrip copy beta\\nroundtrip copy gamma\\n'; sleep 60"
    live_pane="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p '#{pane_id}')"
    live_window="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p -t "$live_pane" '#{window_id}')"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-window-option -t "$live_window" mode-keys vi >/dev/null
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -g PATH \
      "$live_home/.local/bin:$real_tmux_dir:/usr/bin:/bin:/usr/sbin:/sbin"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -gu SSH_CLIENT >/dev/null 2>&1 || true
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -gu SSH_TTY >/dev/null 2>&1 || true
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -gu SSH_CONNECTION >/dev/null 2>&1 || true

    # shellcheck disable=SC2016
    printf -v live_env_command 'printf %%s "$TMUX" > %q; sleep 60' "$live_tmux_env"
    HOME="$live_home" "$real_tmux" -L "$live_socket" split-window -d "$live_env_command"
    wait_for_nonempty_file "$live_tmux_env"

    HOME="$live_home" "$real_tmux" -L "$live_socket" copy-mode -t "$live_pane"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" search-backward "$expected"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" select-line
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -t "$live_pane" y
    wait_for_pbpaste_value "$expected"

    printf -v live_cat_command 'cat > %q' "$live_output"
    target_window="$(
      HOME="$live_home" "$real_tmux" -L "$live_socket" new-window -d -n roundtrip-target -P -F '#{window_id}' "$live_cat_command"
    )"
    target_pane="$(
      HOME="$live_home" "$real_tmux" -L "$live_socket" list-panes -t "$target_window" -F '#{pane_id}' |
        awk 'NR == 1 { print; exit }'
    )"

    TMUX="$(cat "$live_tmux_env")" \
      HOME="$live_home" \
      PATH="$live_home/.local/bin:$real_tmux_dir:/usr/bin:/bin:/usr/sbin:/sbin" \
      "$live_home/.local/bin/tmux-paste-helper" "$target_pane"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -t "$target_pane" C-d
    wait_for_nonempty_file "$live_output"
    assert_files_equal "live tmux copy paste roundtrip through host clipboard" "$live_expected" "$live_output"

    "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
    live_socket=""
  }

  run_live_copy_paste_multiline_roundtrip() {
    local live_home="$tmp/live-home-multiline-roundtrip"
    local live_tmux_env="$tmp/live-multiline-roundtrip-tmux-env.txt"
    local live_expected="$tmp/live-multiline-roundtrip-expected.txt"
    local live_pbpaste_actual="$tmp/live-multiline-roundtrip-pbpaste.txt"
    local live_output="$tmp/live-multiline-roundtrip-output.txt"
    local live_pane
    local live_window
    local target_window
    local target_pane
    local real_tmux_dir="${real_tmux%/*}"
    local live_session="copy-paste-multiline-roundtrip"
    local source_command

    if ! command -v pbcopy >/dev/null 2>&1 || ! command -v pbpaste >/dev/null 2>&1; then
      printf 'skip - live tmux multiline copy paste roundtrip (pbcopy/pbpaste unavailable)\n'
      return 0
    fi

    real_clipboard_backup="$tmp/real-clipboard-backup.txt"
    if ! pbpaste >"$real_clipboard_backup"; then
      real_clipboard_backup=""
      printf 'skip - live tmux multiline copy paste roundtrip (pbpaste failed)\n'
      return 0
    fi

    live_socket="dotfiles-copy-paste-multiline-roundtrip-$$"
    rm -rf "$live_home"
    mkdir -p "$live_home/.local/bin"
    ln -s "$helper" "$live_home/.local/bin/tmux-copy-helper"
    ln -s "$root/common/.local/bin/tmux-paste-helper" "$live_home/.local/bin/tmux-paste-helper"
    ln -s "$root/common/.local/bin/osc-copy" "$live_home/.local/bin/osc-copy"
    ln -s "$root/common/.local/bin/osc-paste" "$live_home/.local/bin/osc-paste"
    # shellcheck disable=SC2016
    printf 'roundtrip multiline one $HOME\nroundtrip multiline two ; $(no)\nroundtrip multiline three * [brackets]\n' \
      >"$live_expected"
    printf -v source_command 'cat %q; sleep 60' "$live_expected"

    "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
    HOME="$live_home" "$real_tmux" -L "$live_socket" -f "$root/common/.tmux.conf" \
      new-session -d -s "$live_session" "$source_command"
    live_pane="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p '#{pane_id}')"
    live_window="$(HOME="$live_home" "$real_tmux" -L "$live_socket" display-message -p -t "$live_pane" '#{window_id}')"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-window-option -t "$live_window" mode-keys vi >/dev/null
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -g PATH \
      "$live_home/.local/bin:$real_tmux_dir:/usr/bin:/bin:/usr/sbin:/sbin"
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -gu SSH_CLIENT >/dev/null 2>&1 || true
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -gu SSH_TTY >/dev/null 2>&1 || true
    HOME="$live_home" "$real_tmux" -L "$live_socket" set-environment -gu SSH_CONNECTION >/dev/null 2>&1 || true

    # shellcheck disable=SC2016
    printf -v live_env_command 'printf %%s "$TMUX" > %q; sleep 60' "$live_tmux_env"
    HOME="$live_home" "$real_tmux" -L "$live_socket" split-window -d "$live_env_command"
    wait_for_nonempty_file "$live_tmux_env"

    HOME="$live_home" "$real_tmux" -L "$live_socket" copy-mode -t "$live_pane"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" search-backward "roundtrip multiline one"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" begin-selection
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -N 2 -X -t "$live_pane" cursor-down
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -X -t "$live_pane" end-of-line
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -t "$live_pane" y
    wait_for_pbpaste_file "$live_expected" "$live_pbpaste_actual"
    assert_files_equal "live tmux multiline copy writes exact host clipboard bytes" \
      "$live_expected" \
      "$live_pbpaste_actual"

    printf -v live_cat_command 'cat > %q' "$live_output"
    target_window="$(
      HOME="$live_home" "$real_tmux" -L "$live_socket" new-window -d -n multiline-roundtrip-target -P -F '#{window_id}' "$live_cat_command"
    )"
    target_pane="$(
      HOME="$live_home" "$real_tmux" -L "$live_socket" list-panes -t "$target_window" -F '#{pane_id}' |
        awk 'NR == 1 { print; exit }'
    )"

    TMUX="$(cat "$live_tmux_env")" \
      HOME="$live_home" \
      PATH="$live_home/.local/bin:$real_tmux_dir:/usr/bin:/bin:/usr/sbin:/sbin" \
      "$live_home/.local/bin/tmux-paste-helper" "$target_pane"
    HOME="$live_home" "$real_tmux" -L "$live_socket" send-keys -t "$target_pane" C-d
    wait_for_nonempty_file "$live_output"
    assert_files_equal "live tmux multiline copy paste roundtrip preserves exact bytes" \
      "$live_expected" \
      "$live_output"

    "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
    live_socket=""
  }

  run_live_copy_binding vi Enter "copy-mode beta" "vi-enter"
  run_live_copy_binding vi y "copy-mode gamma" "vi-y"
  run_live_copy_binding vi MouseDragEnd1Pane "copy-mode beta" "vi-mouse-drag"
  run_live_copy_binding vi DoubleClick1Pane "beta" "vi-double-click" cursor
  run_live_copy_binding vi TripleClick1Pane "copy-mode gamma" "vi-triple-click" cursor
  run_live_copy_binding emacs Enter "copy-mode beta" "emacs-enter"
  run_live_copy_binding emacs y "copy-mode gamma" "emacs-y"
  run_live_copy_binding emacs MouseDragEnd1Pane "copy-mode beta" "emacs-mouse-drag"
  run_live_copy_binding emacs DoubleClick1Pane "beta" "emacs-double-click" cursor
  run_live_copy_binding emacs TripleClick1Pane "copy-mode gamma" "emacs-triple-click" cursor
  run_live_copy_rectangle_binding
  run_live_copy_binding_e2e
  run_live_copy_binding_path_fallback
  run_live_copy_command_default
  run_live_copy_command_path_fallback
  run_live_copy_command_mock_ssh_buffer
  run_live_copy_binding_real_host
  run_live_copy_binding_mock_ssh_buffer
  run_live_copy_paste_roundtrip
  run_live_copy_paste_multiline_roundtrip
else
  printf 'skip - tmux copy-mode live binding (tmux unavailable)\n'
fi
