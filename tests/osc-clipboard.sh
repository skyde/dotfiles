#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
real_clipboard_backup=""

cleanup() {
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

mkdir -p "$tmp/bin" "$tmp/home"

cat >"$tmp/bin/tmux" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "load-buffer" ]]; then
  case "$*" in
    "load-buffer -w -")
      cat >"${OSC_COPY_TMUX_WRITE_LOG:-${OSC_COPY_TMUX_LOG:?}}"
      exit "${OSC_COPY_TMUX_WRITE_STATUS:-${OSC_COPY_TMUX_STATUS:-0}}"
      ;;
    "load-buffer -")
      cat >"${OSC_COPY_TMUX_LOG:?}"
      exit "${OSC_COPY_TMUX_STATUS:-0}"
      ;;
  esac
fi

if [[ "${1:-}" == "save-buffer" ]]; then
  if [[ "${OSC_PASTE_TMUX_STATUS:-0}" != 0 ]]; then
    exit "$OSC_PASTE_TMUX_STATUS"
  fi
  cat "${OSC_PASTE_TMUX_SOURCE:?}"
  exit 0
fi

if [[ "${1:-}" == "show-buffer" ]]; then
  if [[ "${OSC_PASTE_TMUX_SHOW_STATUS:-0}" != 0 ]]; then
    exit "$OSC_PASTE_TMUX_SHOW_STATUS"
  fi
  cat "${OSC_PASTE_TMUX_SHOW_SOURCE:?}"
  exit 0
fi

if [[ "${1:-}" == "display-message" && "${2:-}" == "-p" ]]; then
  display_status="${OSC_TMUX_DISPLAY_STATUS:-${OSC_COPY_TMUX_DISPLAY_STATUS:-0}}"
  if [[ "$display_status" != 0 ]]; then
    exit "$display_status"
  fi
  printf '%%1\n'
  exit 0
fi

printf 'unexpected tmux command: %s\n' "$*" >&2
exit 2
SH
chmod +x "$tmp/bin/tmux"

cat >"$tmp/bin/pbcopy" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${OSC_COPY_PBCOPY_STATUS:-0}" != 0 ]]; then
  cat >/dev/null
  exit "$OSC_COPY_PBCOPY_STATUS"
fi
cat >"${OSC_COPY_PBCOPY_LOG:?}"
SH
chmod +x "$tmp/bin/pbcopy"

cat >"$tmp/bin/wl-copy" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${OSC_COPY_WLCOPY_CALL_LOG:-}" ]]; then
  printf 'wl-copy\n' >>"$OSC_COPY_WLCOPY_CALL_LOG"
fi
if [[ "${OSC_COPY_WLCOPY_STATUS:-0}" != 0 ]]; then
  cat >/dev/null
  exit "$OSC_COPY_WLCOPY_STATUS"
fi
cat >"${OSC_COPY_WLCOPY_LOG:?}"
SH
chmod +x "$tmp/bin/wl-copy"

cat >"$tmp/bin/pbpaste" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${OSC_PASTE_PBPASTE_CALL_LOG:-}" ]]; then
  printf 'pbpaste\n' >>"$OSC_PASTE_PBPASTE_CALL_LOG"
fi
if [[ "${OSC_PASTE_PBPASTE_STATUS:-0}" != 0 ]]; then
  printf '%s' "${OSC_PASTE_PBPASTE_PARTIAL:-}"
  exit "$OSC_PASTE_PBPASTE_STATUS"
fi
cat "${OSC_PASTE_PBPASTE_SOURCE:?}"
SH
chmod +x "$tmp/bin/pbpaste"

cat >"$tmp/bin/wl-paste" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${OSC_PASTE_WLPASTE_CALL_LOG:-}" ]]; then
  printf 'wl-paste\n' >>"$OSC_PASTE_WLPASTE_CALL_LOG"
fi
if [[ "${OSC_PASTE_WLPASTE_STATUS:-0}" != 0 ]]; then
  printf '%s' "${OSC_PASTE_WLPASTE_PARTIAL:-}"
  exit "$OSC_PASTE_WLPASTE_STATUS"
fi
cat "${OSC_PASTE_WLPASTE_SOURCE:?}"
SH
chmod +x "$tmp/bin/wl-paste"

cat >"$tmp/bin/xclip" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == "-selection clipboard -o" ]]; then
  if [[ -n "${OSC_PASTE_XCLIP_CALL_LOG:-}" ]]; then
    printf 'xclip paste\n' >>"$OSC_PASTE_XCLIP_CALL_LOG"
  fi
  if [[ "${OSC_PASTE_XCLIP_STATUS:-0}" != 0 ]]; then
    printf '%s' "${OSC_PASTE_XCLIP_PARTIAL:-}"
    exit "$OSC_PASTE_XCLIP_STATUS"
  fi
  cat "${OSC_PASTE_XCLIP_SOURCE:?}"
  exit 0
fi

if [[ "$*" == "-selection clipboard" ]]; then
  if [[ -n "${OSC_COPY_XCLIP_CALL_LOG:-}" ]]; then
    printf 'xclip copy\n' >>"$OSC_COPY_XCLIP_CALL_LOG"
  fi
  if [[ "${OSC_COPY_XCLIP_STATUS:-0}" != 0 ]]; then
    cat >/dev/null
    exit "$OSC_COPY_XCLIP_STATUS"
  fi
  cat >"${OSC_COPY_XCLIP_LOG:?}"
  exit 0
fi

printf 'unexpected xclip command: %s\n' "$*" >&2
exit 2
SH
chmod +x "$tmp/bin/xclip"

cat >"$tmp/bin/xsel" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == "--clipboard --output" ]]; then
  if [[ -n "${OSC_PASTE_XSEL_CALL_LOG:-}" ]]; then
    printf 'xsel paste\n' >>"$OSC_PASTE_XSEL_CALL_LOG"
  fi
  if [[ "${OSC_PASTE_XSEL_STATUS:-0}" != 0 ]]; then
    printf '%s' "${OSC_PASTE_XSEL_PARTIAL:-}"
    exit "$OSC_PASTE_XSEL_STATUS"
  fi
  cat "${OSC_PASTE_XSEL_SOURCE:?}"
  exit 0
fi

if [[ "$*" == "--clipboard --input" ]]; then
  if [[ -n "${OSC_COPY_XSEL_CALL_LOG:-}" ]]; then
    printf 'xsel copy\n' >>"$OSC_COPY_XSEL_CALL_LOG"
  fi
  if [[ "${OSC_COPY_XSEL_STATUS:-0}" != 0 ]]; then
    cat >/dev/null
    exit "$OSC_COPY_XSEL_STATUS"
  fi
  cat >"${OSC_COPY_XSEL_LOG:?}"
  exit 0
fi

printf 'unexpected xsel command: %s\n' "$*" >&2
exit 2
SH
chmod +x "$tmp/bin/xsel"

cat >"$tmp/bin/base64" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  --decode)
    exit 1
    ;;
  -d)
    printf '%s\n' "-d" >"${OSC_PASTE_BASE64_MODE_LOG:?}"
    exec python3 -c 'import base64, sys; sys.stdout.buffer.write(base64.b64decode(sys.stdin.buffer.read()))'
    ;;
  -D)
    printf '%s\n' "-D" >"${OSC_PASTE_BASE64_MODE_LOG:?}"
    exec python3 -c 'import base64, sys; sys.stdout.buffer.write(base64.b64decode(sys.stdin.buffer.read()))'
    ;;
  *)
    exec /usr/bin/base64 "$@"
    ;;
esac
SH
chmod +x "$tmp/bin/base64"

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
    printf 'not ok - %s\nunexpected file exists: %s\n' "$name" "$path" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

assert_file_not_contains() {
  local name="$1"
  local path="$2"
  local unexpected="$3"
  local actual

  actual="$(cat "$path" 2>/dev/null || true)"
  if [[ "$actual" == *"$unexpected"* ]]; then
    printf 'not ok - %s\nunexpected content: %s\n' "$name" "$unexpected" >&2
    printf 'actual:\n%s\n' "$actual" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

assert_no_temp_files() {
  local name="$1"
  local dir="$2"
  local pattern="$3"
  local found

  found="$(find "$dir" -maxdepth 1 -type f -name "$pattern" -print -quit)"
  if [[ -n "$found" ]]; then
    printf 'not ok - %s\nunexpected temp file exists: %s\n' "$name" "$found" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

expected="$tmp/expected.txt"
printf 'line one\nline two\n\n' >"$expected"
encoded="$(/usr/bin/base64 <"$expected" | tr -d '\n')"
binary_expected="$tmp/expected-binary.bin"
printf '\000binary\ntrail\000' >"$binary_expected"
crlf_expected="$tmp/expected-crlf.bin"
printf 'carriage\r\nreturn\rbare\n' >"$crlf_expected"
crlf_encoded="$(/usr/bin/base64 <"$crlf_expected" | tr -d '\n')"
unicode_expected="$tmp/expected-unicode.txt"
printf 'unicode caf\xc3\xa9\nlambda \xce\xbb\neuro \xe2\x82\xac\n' >"$unicode_expected"
unicode_encoded="$(/usr/bin/base64 <"$unicode_expected" | tr -d '\n')"
large_expected="$tmp/expected-large-whitespace.txt"
{
  for ((i = 1; i <= 4096; i++)); do
    printf 'large-%04d\talpha beta trailing   \n' "$i"
  done
  printf 'large-final-no-newline\ttrail   '
} >"$large_expected"
invalid_utf8_expected="$tmp/expected-invalid-utf8.bin"
printf '\000binary\377\ntrail\000' >"$invalid_utf8_expected"
invalid_utf8_encoded="$(/usr/bin/base64 <"$invalid_utf8_expected" | tr -d '\n')"
empty_copy_expected="$tmp/expected-empty-copy.bin"
: >"$empty_copy_expected"

spaced_tmp="$tmp/spaced clipboard tmpdir"
mkdir -p "$spaced_tmp"
spaced_tmp_copy_log="$tmp/spaced-tmp-pbcopy-buffer.txt"
HOME="$tmp/home" \
  TMUX="" \
  TMPDIR="$spaced_tmp" \
  OSC_COPY_PBCOPY_LOG="$spaced_tmp_copy_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$expected"
assert_files_equal "osc-copy handles TMPDIR with spaces" "$expected" "$spaced_tmp_copy_log"
assert_no_temp_files "osc-copy cleans temp file when TMPDIR has spaces" "$spaced_tmp" "osc-copy.*"

invalid_tmp_copy_log="$tmp/invalid-tmp-pbcopy-buffer.txt"
HOME="$tmp/home" \
  TMUX="" \
  TMPDIR="$tmp/missing-copy-tmpdir" \
  OSC_COPY_PBCOPY_LOG="$invalid_tmp_copy_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$expected"
assert_files_equal "osc-copy falls back to /tmp when TMPDIR is invalid" "$expected" "$invalid_tmp_copy_log"

no_search_tmp="$tmp/no-search-tmpdir"
mkdir -p "$no_search_tmp"
chmod 200 "$no_search_tmp"
no_search_copy_log="$tmp/no-search-pbcopy-buffer.txt"
HOME="$tmp/home" \
  TMUX="" \
  TMPDIR="$no_search_tmp" \
  OSC_COPY_PBCOPY_LOG="$no_search_copy_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$expected"
assert_files_equal "osc-copy falls back when TMPDIR is not searchable" "$expected" "$no_search_copy_log"

broken_mktemp_bin="$tmp/broken-mktemp-bin"
broken_mktemp_tmp="$tmp/broken-mktemp-tmp"
broken_mktemp_copy_log="$tmp/broken-mktemp-pbcopy-buffer.txt"
mkdir -p "$broken_mktemp_bin" "$broken_mktemp_tmp"
cat >"$broken_mktemp_bin/mktemp" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$broken_mktemp_bin/mktemp"
HOME="$tmp/home" \
  TMUX="" \
  TMPDIR="$broken_mktemp_tmp" \
  OSC_COPY_PBCOPY_LOG="$broken_mktemp_copy_log" \
  PATH="$broken_mktemp_bin:$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$expected"
assert_files_equal "osc-copy falls back when mktemp fails" "$expected" "$broken_mktemp_copy_log"
assert_no_temp_files "osc-copy cleans fallback temp file when mktemp fails" "$broken_mktemp_tmp" "osc-copy.*"

tmux_log="$tmp/tmux-buffer.txt"
tmux_host_log="$tmp/tmux-host-pbcopy-buffer.txt"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_COPY_TMUX_LOG="$tmux_log" \
  OSC_COPY_PBCOPY_LOG="$tmux_host_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$expected"
assert_files_equal "osc-copy preserves trailing newlines through tmux" "$expected" "$tmux_log"
assert_files_equal "osc-copy live local tmux also updates host clipboard" "$expected" "$tmux_host_log"

crlf_tmux_log="$tmp/crlf-tmux-buffer.bin"
crlf_tmux_host_log="$tmp/crlf-tmux-host-pbcopy-buffer.bin"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_COPY_TMUX_LOG="$crlf_tmux_log" \
  OSC_COPY_PBCOPY_LOG="$crlf_tmux_host_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$crlf_expected"
assert_files_equal "osc-copy preserves CRLF bytes through tmux" "$crlf_expected" "$crlf_tmux_log"
assert_files_equal "osc-copy live local tmux also updates host clipboard with CRLF bytes" \
  "$crlf_expected" \
  "$crlf_tmux_host_log"

unicode_tmux_log="$tmp/unicode-tmux-buffer.txt"
unicode_tmux_host_log="$tmp/unicode-tmux-host-pbcopy-buffer.txt"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_COPY_TMUX_LOG="$unicode_tmux_log" \
  OSC_COPY_PBCOPY_LOG="$unicode_tmux_host_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$unicode_expected"
assert_files_equal "osc-copy preserves UTF-8 bytes through tmux" "$unicode_expected" "$unicode_tmux_log"
assert_files_equal "osc-copy live local tmux also updates host clipboard with UTF-8 bytes" \
  "$unicode_expected" \
  "$unicode_tmux_host_log"

large_tmux_log="$tmp/large-tmux-buffer.txt"
large_tmux_host_log="$tmp/large-tmux-host-pbcopy-buffer.txt"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_COPY_TMUX_LOG="$large_tmux_log" \
  OSC_COPY_PBCOPY_LOG="$large_tmux_host_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$large_expected"
assert_files_equal "osc-copy preserves large whitespace payload through tmux" "$large_expected" "$large_tmux_log"
assert_files_equal "osc-copy live local tmux also updates host clipboard with large whitespace payload" \
  "$large_expected" \
  "$large_tmux_host_log"

empty_tmux_log="$tmp/empty-tmux-buffer.txt"
empty_tmux_host_log="$tmp/empty-tmux-host-pbcopy-buffer.txt"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_COPY_TMUX_LOG="$empty_tmux_log" \
  OSC_COPY_PBCOPY_LOG="$empty_tmux_host_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$empty_copy_expected"
assert_files_equal "osc-copy preserves empty content through tmux" "$empty_copy_expected" "$empty_tmux_log"
assert_files_equal "osc-copy live local tmux also clears host clipboard for empty content" \
  "$empty_copy_expected" \
  "$empty_tmux_host_log"

tmux_plain_log="$tmp/tmux-buffer-plain.txt"
tmux_plain_host_log="$tmp/tmux-buffer-plain-pbcopy.txt"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_COPY_TMUX_WRITE_LOG="$tmp/failed-tmux-write-buffer.txt" \
  OSC_COPY_TMUX_WRITE_STATUS=1 \
  OSC_COPY_TMUX_LOG="$tmux_plain_log" \
  OSC_COPY_PBCOPY_LOG="$tmux_plain_host_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$expected"
assert_files_equal "osc-copy falls back to plain tmux load-buffer" "$expected" "$tmux_plain_log"
assert_files_equal "osc-copy plain tmux fallback also updates host clipboard" "$expected" "$tmux_plain_host_log"

tmux_plain_ssh_log="$tmp/tmux-buffer-plain-ssh.txt"
tmux_plain_ssh_osc52_expected="$tmp/tmux-buffer-plain-ssh-osc52.expected"
tmux_plain_ssh_osc52_actual="$tmp/tmux-buffer-plain-ssh-osc52.actual"
tmux_plain_ssh_pbcopy_log="$tmp/tmux-buffer-plain-ssh-pbcopy-should-not-run.txt"
printf '\033Ptmux;\033\033]52;c;%s\a\033%s' "$encoded" "\\" >"$tmux_plain_ssh_osc52_expected"
HOME="$tmp/home" \
  TMUX=fake \
  SSH_CLIENT="127.0.0.1 1000 22" \
  OSC_COPY_TMUX_WRITE_LOG="$tmp/failed-tmux-write-buffer-plain-ssh.txt" \
  OSC_COPY_TMUX_WRITE_STATUS=1 \
  OSC_COPY_TMUX_LOG="$tmux_plain_ssh_log" \
  OSC_COPY_PBCOPY_LOG="$tmux_plain_ssh_pbcopy_log" \
  OSC_TTY="$tmux_plain_ssh_osc52_actual" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$expected"
assert_files_equal "osc-copy SSH plain tmux fallback still writes tmux buffer" \
  "$expected" \
  "$tmux_plain_ssh_log"
assert_files_equal "osc-copy SSH plain tmux fallback also emits wrapped OSC52" \
  "$tmux_plain_ssh_osc52_expected" \
  "$tmux_plain_ssh_osc52_actual"
assert_file_absent "osc-copy SSH plain tmux fallback skips host pbcopy" "$tmux_plain_ssh_pbcopy_log"

tmux_plain_ssh_no_tty_log="$tmp/tmux-buffer-plain-ssh-no-tty.txt"
tmux_plain_ssh_no_tty_pbcopy_log="$tmp/tmux-buffer-plain-ssh-no-tty-pbcopy-should-not-run.txt"
tmux_plain_ssh_no_tty_err="$tmp/tmux-buffer-plain-ssh-no-tty.err"
HOME="$tmp/home" \
  TMUX=fake \
  SSH_CLIENT="127.0.0.1 1000 22" \
  OSC_COPY_TMUX_WRITE_LOG="$tmp/failed-tmux-write-buffer-plain-ssh-no-tty.txt" \
  OSC_COPY_TMUX_WRITE_STATUS=1 \
  OSC_COPY_TMUX_LOG="$tmux_plain_ssh_no_tty_log" \
  OSC_COPY_PBCOPY_LOG="$tmux_plain_ssh_no_tty_pbcopy_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$expected" 2>"$tmux_plain_ssh_no_tty_err"
assert_files_equal "osc-copy SSH plain tmux fallback without tty still writes tmux buffer" \
  "$expected" \
  "$tmux_plain_ssh_no_tty_log"
assert_files_equal "osc-copy SSH plain tmux fallback without tty stays quiet" \
  /dev/null \
  "$tmux_plain_ssh_no_tty_err"
assert_file_absent "osc-copy SSH plain tmux fallback without tty skips host pbcopy" \
  "$tmux_plain_ssh_no_tty_pbcopy_log"

ssh_tmux_log="$tmp/ssh-tmux-buffer.txt"
ssh_tmux_pbcopy_log="$tmp/ssh-tmux-pbcopy-should-not-run.txt"
HOME="$tmp/home" \
  TMUX=fake \
  SSH_CLIENT="127.0.0.1 1000 22" \
  OSC_COPY_TMUX_LOG="$ssh_tmux_log" \
  OSC_COPY_PBCOPY_LOG="$ssh_tmux_pbcopy_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$expected"
assert_files_equal "osc-copy live SSH tmux still writes tmux buffer" "$expected" "$ssh_tmux_log"
assert_file_absent "osc-copy live SSH tmux skips host pbcopy" "$ssh_tmux_pbcopy_log"

stale_tmux_log="$tmp/stale-tmux-buffer.txt"
stale_pbcopy_log="$tmp/stale-pbcopy-buffer.txt"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_COPY_TMUX_DISPLAY_STATUS=1 \
  OSC_COPY_TMUX_LOG="$stale_tmux_log" \
  OSC_COPY_PBCOPY_LOG="$stale_pbcopy_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$expected"
assert_files_equal "osc-copy stale TMUX falls back to pbcopy" "$expected" "$stale_pbcopy_log"
assert_file_absent "osc-copy stale TMUX skips tmux load-buffer" "$stale_tmux_log"

pbcopy_log="$tmp/pbcopy-buffer.txt"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_COPY_TMUX_WRITE_LOG="$tmp/failed-tmux-write-buffer-pbcopy.txt" \
  OSC_COPY_TMUX_WRITE_STATUS=1 \
  OSC_COPY_TMUX_LOG="$tmp/failed-tmux-buffer.txt" \
  OSC_COPY_TMUX_STATUS=1 \
  OSC_COPY_PBCOPY_LOG="$pbcopy_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$expected"
assert_files_equal "osc-copy preserves trailing newlines through pbcopy fallback" "$expected" "$pbcopy_log"

binary_pbcopy_log="$tmp/binary-pbcopy-buffer.bin"
HOME="$tmp/home" \
  TMUX="" \
  OSC_COPY_PBCOPY_LOG="$binary_pbcopy_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$binary_expected"
assert_files_equal "osc-copy preserves binary bytes through pbcopy" "$binary_expected" "$binary_pbcopy_log"

crlf_pbcopy_log="$tmp/crlf-pbcopy-buffer.bin"
HOME="$tmp/home" \
  TMUX="" \
  OSC_COPY_PBCOPY_LOG="$crlf_pbcopy_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$crlf_expected"
assert_files_equal "osc-copy preserves CRLF bytes through pbcopy" "$crlf_expected" "$crlf_pbcopy_log"

unicode_pbcopy_log="$tmp/unicode-pbcopy-buffer.txt"
HOME="$tmp/home" \
  TMUX="" \
  OSC_COPY_PBCOPY_LOG="$unicode_pbcopy_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$unicode_expected"
assert_files_equal "osc-copy preserves UTF-8 bytes through pbcopy" "$unicode_expected" "$unicode_pbcopy_log"

large_pbcopy_log="$tmp/large-pbcopy-buffer.txt"
HOME="$tmp/home" \
  TMUX="" \
  OSC_COPY_PBCOPY_LOG="$large_pbcopy_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$large_expected"
assert_files_equal "osc-copy preserves large whitespace payload through pbcopy" "$large_expected" "$large_pbcopy_log"

empty_pbcopy_log="$tmp/empty-pbcopy-buffer.bin"
HOME="$tmp/home" \
  TMUX="" \
  OSC_COPY_PBCOPY_LOG="$empty_pbcopy_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$empty_copy_expected"
assert_files_equal "osc-copy preserves empty content through pbcopy" "$empty_copy_expected" "$empty_pbcopy_log"

invalid_utf8_osc52_expected="$tmp/invalid-utf8-osc52.expected"
invalid_utf8_osc52_actual="$tmp/invalid-utf8-osc52.actual"
invalid_utf8_pbcopy_log="$tmp/invalid-utf8-pbcopy-should-not-run.bin"
printf '\033]52;c;%s\a' "$invalid_utf8_encoded" >"$invalid_utf8_osc52_expected"
HOME="$tmp/home" \
  TMUX="" \
  OSC_COPY_PBCOPY_LOG="$invalid_utf8_pbcopy_log" \
  OSC_TTY="$invalid_utf8_osc52_actual" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$invalid_utf8_expected"
assert_files_equal "osc-copy uses OSC52 instead of pbcopy for invalid UTF-8" \
  "$invalid_utf8_osc52_expected" \
  "$invalid_utf8_osc52_actual"
assert_file_absent "osc-copy skips pbcopy for invalid UTF-8" "$invalid_utf8_pbcopy_log"

invalid_utf8_tmux_log="$tmp/invalid-utf8-tmux-buffer.bin"
invalid_utf8_tmux_pbcopy_log="$tmp/invalid-utf8-tmux-pbcopy-should-not-run.bin"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_COPY_TMUX_LOG="$invalid_utf8_tmux_log" \
  OSC_COPY_PBCOPY_LOG="$invalid_utf8_tmux_pbcopy_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$invalid_utf8_expected"
assert_files_equal "osc-copy preserves invalid UTF-8 through tmux buffer" \
  "$invalid_utf8_expected" \
  "$invalid_utf8_tmux_log"
assert_file_absent "osc-copy live local tmux skips host pbcopy for invalid UTF-8" \
  "$invalid_utf8_tmux_pbcopy_log"

if python3_path="$(command -v python3 2>/dev/null)"; then
  no_iconv_bin="$tmp/no-iconv-bin"
  mkdir -p "$no_iconv_bin"
  ln -s "$(command -v bash)" "$no_iconv_bin/bash"
  ln -s "$(command -v cat)" "$no_iconv_bin/cat"
  ln -s "$(command -v rm)" "$no_iconv_bin/rm"
  ln -s "$python3_path" "$no_iconv_bin/python3"
  ln -s "$tmp/bin/base64" "$no_iconv_bin/base64"
  ln -s "$tmp/bin/pbcopy" "$no_iconv_bin/pbcopy"

  no_iconv_valid_pbcopy_log="$tmp/no-iconv-valid-pbcopy-buffer.txt"
  HOME="$tmp/home" \
    TMUX="" \
    OSC_COPY_PBCOPY_LOG="$no_iconv_valid_pbcopy_log" \
    PATH="$no_iconv_bin" \
    "$root/common/.local/bin/osc-copy" <"$expected"
  assert_files_equal "osc-copy uses pbcopy for valid UTF-8 without iconv" \
    "$expected" \
    "$no_iconv_valid_pbcopy_log"

  no_iconv_invalid_osc52_expected="$tmp/no-iconv-invalid-osc52.expected"
  no_iconv_invalid_osc52_actual="$tmp/no-iconv-invalid-osc52.actual"
  no_iconv_invalid_pbcopy_log="$tmp/no-iconv-invalid-pbcopy-should-not-run.bin"
  printf '\033]52;c;%s\a' "$invalid_utf8_encoded" >"$no_iconv_invalid_osc52_expected"
  HOME="$tmp/home" \
    TMUX="" \
    OSC_COPY_PBCOPY_LOG="$no_iconv_invalid_pbcopy_log" \
    OSC_TTY="$no_iconv_invalid_osc52_actual" \
    PATH="$no_iconv_bin" \
    "$root/common/.local/bin/osc-copy" <"$invalid_utf8_expected"
  assert_files_equal "osc-copy uses OSC52 for invalid UTF-8 without iconv" \
    "$no_iconv_invalid_osc52_expected" \
    "$no_iconv_invalid_osc52_actual"
  assert_file_absent "osc-copy skips pbcopy for invalid UTF-8 without iconv" \
    "$no_iconv_invalid_pbcopy_log"
else
  printf 'skip - osc-copy UTF-8 validation without iconv (python3 unavailable)\n'
fi

if command -v pbcopy >/dev/null 2>&1 && command -v pbpaste >/dev/null 2>&1; then
  real_clipboard_backup="$tmp/real-clipboard-backup.txt"
  if pbpaste >"$real_clipboard_backup"; then
    real_pbpaste_output="$tmp/real-pbpaste-output.txt"
    printf 'old real clipboard value\n' | pbcopy
    HOME="$tmp/home" \
      TMUX="" \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      "$root/common/.local/bin/osc-copy" <"$expected"
    pbpaste >"$real_pbpaste_output"
    assert_files_equal "osc-copy writes real macOS pasteboard with trailing newlines" \
      "$expected" \
      "$real_pbpaste_output"

    HOME="$tmp/home" \
      TMUX="" \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      "$root/common/.local/bin/osc-paste" >"$real_pbpaste_output"
    assert_files_equal "osc-paste reads real macOS pasteboard with trailing newlines" \
      "$expected" \
      "$real_pbpaste_output"

    real_empty_pbpaste_output="$tmp/real-empty-pbpaste-output.bin"
    printf 'old real clipboard value\n' | pbcopy
    HOME="$tmp/home" \
      TMUX="" \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      "$root/common/.local/bin/osc-copy" <"$empty_copy_expected"
    pbpaste >"$real_empty_pbpaste_output"
    assert_files_equal "osc-copy clears the real macOS pasteboard for empty content" \
      "$empty_copy_expected" \
      "$real_empty_pbpaste_output"

    HOME="$tmp/home" \
      TMUX="" \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      "$root/common/.local/bin/osc-paste" >"$real_empty_pbpaste_output"
    assert_files_equal "osc-paste reads an empty real macOS pasteboard" \
      "$empty_copy_expected" \
      "$real_empty_pbpaste_output"

    real_invalid_osc52_expected="$tmp/real-invalid-utf8-osc52.expected"
    real_invalid_osc52_actual="$tmp/real-invalid-utf8-osc52.actual"
    real_invalid_pbpaste_expected="$tmp/real-invalid-pbpaste-expected.txt"
    real_invalid_pbpaste_output="$tmp/real-invalid-pbpaste-output.txt"
    printf 'old real clipboard value\n' >"$real_invalid_pbpaste_expected"
    pbcopy <"$real_invalid_pbpaste_expected"
    printf '\033]52;c;%s\a' "$invalid_utf8_encoded" >"$real_invalid_osc52_expected"
    HOME="$tmp/home" \
      TMUX="" \
      OSC_TTY="$real_invalid_osc52_actual" \
      PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
      "$root/common/.local/bin/osc-copy" <"$invalid_utf8_expected"
    pbpaste >"$real_invalid_pbpaste_output"
    assert_files_equal "osc-copy emits OSC52 for invalid UTF-8 instead of real macOS pasteboard" \
      "$real_invalid_osc52_expected" \
      "$real_invalid_osc52_actual"
    assert_files_equal "osc-copy leaves real macOS pasteboard unchanged for invalid UTF-8" \
      "$real_invalid_pbpaste_expected" \
      "$real_invalid_pbpaste_output"
  else
    real_clipboard_backup=""
    printf 'skip - osc-copy real macOS empty pasteboard (pbpaste failed)\n'
  fi
else
  printf 'skip - osc-copy real macOS empty pasteboard (pbcopy/pbpaste unavailable)\n'
fi

wlcopy_log="$tmp/wlcopy-buffer.txt"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_COPY_TMUX_WRITE_LOG="$tmp/failed-tmux-write-buffer-wlcopy.txt" \
  OSC_COPY_TMUX_WRITE_STATUS=1 \
  OSC_COPY_TMUX_LOG="$tmp/failed-tmux-buffer-wlcopy.txt" \
  OSC_COPY_TMUX_STATUS=1 \
  OSC_COPY_PBCOPY_STATUS=1 \
  OSC_COPY_WLCOPY_LOG="$wlcopy_log" \
  WAYLAND_DISPLAY=wayland-0 \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$expected"
assert_files_equal "osc-copy falls back after failed pbcopy" "$expected" "$wlcopy_log"

xclip_log="$tmp/xclip-buffer.txt"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_COPY_TMUX_WRITE_LOG="$tmp/failed-tmux-write-buffer-xclip.txt" \
  OSC_COPY_TMUX_WRITE_STATUS=1 \
  OSC_COPY_TMUX_LOG="$tmp/failed-tmux-buffer-xclip.txt" \
  OSC_COPY_TMUX_STATUS=1 \
  OSC_COPY_PBCOPY_STATUS=1 \
  OSC_COPY_WLCOPY_STATUS=1 \
  OSC_COPY_XCLIP_LOG="$xclip_log" \
  WAYLAND_DISPLAY=wayland-0 \
  DISPLAY=:99 \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$expected"
assert_files_equal "osc-copy falls back to xclip after failed Wayland copy" "$expected" "$xclip_log"

xsel_log="$tmp/xsel-buffer.txt"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_COPY_TMUX_WRITE_LOG="$tmp/failed-tmux-write-buffer-xsel.txt" \
  OSC_COPY_TMUX_WRITE_STATUS=1 \
  OSC_COPY_TMUX_LOG="$tmp/failed-tmux-buffer-xsel.txt" \
  OSC_COPY_TMUX_STATUS=1 \
  OSC_COPY_PBCOPY_STATUS=1 \
  OSC_COPY_WLCOPY_STATUS=1 \
  OSC_COPY_XCLIP_STATUS=1 \
  OSC_COPY_XSEL_LOG="$xsel_log" \
  WAYLAND_DISPLAY=wayland-0 \
  DISPLAY=:99 \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$expected"
assert_files_equal "osc-copy falls back to xsel after failed xclip" "$expected" "$xsel_log"

headless_bin="$tmp/headless-bin"
mkdir -p "$headless_bin"
ln -s "$tmp/bin/wl-copy" "$headless_bin/wl-copy"
ln -s "$tmp/bin/xclip" "$headless_bin/xclip"
ln -s "$tmp/bin/xsel" "$headless_bin/xsel"
ln -s "$tmp/bin/base64" "$headless_bin/base64"

headless_osc52_expected="$tmp/headless-osc52.expected"
headless_osc52_actual="$tmp/headless-osc52.actual"
headless_wlcopy_call_log="$tmp/headless-wlcopy-should-not-run.log"
headless_xclip_call_log="$tmp/headless-xclip-should-not-run.log"
headless_xsel_call_log="$tmp/headless-xsel-should-not-run.log"
printf '\033]52;c;%s\a' "$encoded" >"$headless_osc52_expected"
env -u DISPLAY -u WAYLAND_DISPLAY \
  HOME="$tmp/home" \
  TMUX="" \
  OSC_COPY_WLCOPY_CALL_LOG="$headless_wlcopy_call_log" \
  OSC_COPY_XCLIP_CALL_LOG="$headless_xclip_call_log" \
  OSC_COPY_XSEL_CALL_LOG="$headless_xsel_call_log" \
  OSC_TTY="$headless_osc52_actual" \
  PATH="$headless_bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$expected"
assert_files_equal "osc-copy headless Linux falls back to OSC52" \
  "$headless_osc52_expected" \
  "$headless_osc52_actual"
assert_file_absent "osc-copy headless Linux skips wl-copy without display" "$headless_wlcopy_call_log"
assert_file_absent "osc-copy headless Linux skips xclip without display" "$headless_xclip_call_log"
assert_file_absent "osc-copy headless Linux skips xsel without display" "$headless_xsel_call_log"

osc52_tmux_expected="$tmp/osc52-tmux.expected"
osc52_tmux_actual="$tmp/osc52-tmux.actual"
printf '\033Ptmux;\033\033]52;c;%s\a\033%s' "$encoded" "\\" >"$osc52_tmux_expected"
HOME="$tmp/home" \
  TMUX=fake \
  SSH_CLIENT="127.0.0.1 1000 22" \
  OSC_COPY_TMUX_WRITE_LOG="$tmp/osc52-tmux-failed-write.txt" \
  OSC_COPY_TMUX_WRITE_STATUS=1 \
  OSC_COPY_TMUX_LOG="$tmp/osc52-tmux-failed-plain.txt" \
  OSC_COPY_TMUX_STATUS=1 \
  OSC_TTY="$osc52_tmux_actual" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$expected"
assert_files_equal "osc-copy wraps OSC52 when tmux client is live" "$osc52_tmux_expected" "$osc52_tmux_actual"

osc52_plain_expected="$tmp/osc52-plain.expected"
osc52_plain_actual="$tmp/osc52-plain.actual"
printf '\033]52;c;%s\a' "$encoded" >"$osc52_plain_expected"
HOME="$tmp/home" \
  TMUX=fake \
  SSH_CLIENT="127.0.0.1 1000 22" \
  OSC_COPY_TMUX_WRITE_LOG="$tmp/osc52-plain-failed-write.txt" \
  OSC_COPY_TMUX_WRITE_STATUS=1 \
  OSC_COPY_TMUX_LOG="$tmp/osc52-plain-failed-plain.txt" \
  OSC_COPY_TMUX_STATUS=1 \
  OSC_COPY_TMUX_DISPLAY_STATUS=1 \
  OSC_TTY="$osc52_plain_actual" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$expected"
assert_files_equal "osc-copy uses plain OSC52 when TMUX is stale" "$osc52_plain_expected" "$osc52_plain_actual"

binary_osc52_expected="$tmp/binary-osc52.expected"
binary_osc52_actual="$tmp/binary-osc52.actual"
printf '\033]52;c;%s\a' "$invalid_utf8_encoded" >"$binary_osc52_expected"
HOME="$tmp/home" \
  TMUX="" \
  SSH_CLIENT="127.0.0.1 1000 22" \
  OSC_TTY="$binary_osc52_actual" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$invalid_utf8_expected"
assert_files_equal "osc-copy OSC52 encodes invalid UTF-8 bytes" "$binary_osc52_expected" "$binary_osc52_actual"

empty_osc52_expected="$tmp/empty-osc52.expected"
empty_osc52_actual="$tmp/empty-osc52.actual"
printf '\033]52;c;\a' >"$empty_osc52_expected"
HOME="$tmp/home" \
  TMUX="" \
  SSH_CLIENT="127.0.0.1 1000 22" \
  OSC_TTY="$empty_osc52_actual" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$empty_copy_expected"
assert_files_equal "osc-copy OSC52 encodes empty content" "$empty_osc52_expected" "$empty_osc52_actual"

ssh_copy_osc52_expected="$tmp/ssh-copy-osc52.expected"
ssh_copy_osc52_actual="$tmp/ssh-copy-osc52.actual"
ssh_copy_pbcopy_log="$tmp/ssh-copy-pbcopy-should-not-run.txt"
printf '\033]52;c;%s\a' "$encoded" >"$ssh_copy_osc52_expected"
HOME="$tmp/home" \
  TMUX="" \
  SSH_CLIENT="127.0.0.1 1000 22" \
  OSC_COPY_PBCOPY_LOG="$ssh_copy_pbcopy_log" \
  OSC_TTY="$ssh_copy_osc52_actual" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$expected"
assert_files_equal "osc-copy SSH session emits OSC52 instead of host pbcopy" \
  "$ssh_copy_osc52_expected" \
  "$ssh_copy_osc52_actual"
assert_file_absent "osc-copy SSH session skips host pbcopy" "$ssh_copy_pbcopy_log"

no_mktemp_tr_bin="$tmp/no-mktemp-tr-bin"
no_mktemp_tr_tmp="$tmp/no-mktemp-tr-tmp"
osc52_no_mktemp_tr_expected="$tmp/osc52-no-mktemp-tr.expected"
osc52_no_mktemp_tr_actual="$tmp/osc52-no-mktemp-tr.actual"
mkdir -p "$no_mktemp_tr_bin" "$no_mktemp_tr_tmp"
ln -s "$(command -v bash)" "$no_mktemp_tr_bin/bash"
ln -s "$(command -v cat)" "$no_mktemp_tr_bin/cat"
ln -s "$(command -v rm)" "$no_mktemp_tr_bin/rm"
ln -s "$tmp/bin/tmux" "$no_mktemp_tr_bin/tmux"
cat >"$no_mktemp_tr_bin/base64" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

encoded="$(/usr/bin/base64 "$@")"
printf '%s\n%s\n' "${encoded:0:5}" "${encoded:5}"
SH
chmod +x "$no_mktemp_tr_bin/base64"

printf '\033Ptmux;\033\033]52;c;%s\a\033%s' "$encoded" "\\" >"$osc52_no_mktemp_tr_expected"
HOME="$tmp/home" \
  TMUX=fake \
  SSH_CLIENT="127.0.0.1 1000 22" \
  TMPDIR="$no_mktemp_tr_tmp" \
  OSC_COPY_TMUX_WRITE_LOG="$tmp/osc52-no-mktemp-tr-failed-write.txt" \
  OSC_COPY_TMUX_WRITE_STATUS=1 \
  OSC_COPY_TMUX_LOG="$tmp/osc52-no-mktemp-tr-failed-plain.txt" \
  OSC_COPY_TMUX_STATUS=1 \
  OSC_TTY="$osc52_no_mktemp_tr_actual" \
  PATH="$no_mktemp_tr_bin" \
  "$root/common/.local/bin/osc-copy" <"$expected"
assert_files_equal "osc-copy emits OSC52 without mktemp or tr" \
  "$osc52_no_mktemp_tr_expected" \
  "$osc52_no_mktemp_tr_actual"

paste_tmux_output="$tmp/paste-tmux-output.txt"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_PASTE_TMUX_SOURCE="$expected" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$paste_tmux_output"
assert_files_equal "osc-paste preserves trailing newlines through tmux" "$expected" "$paste_tmux_output"

paste_tmux_show_output="$tmp/paste-tmux-show-output.txt"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_PASTE_TMUX_SOURCE="$tmp/missing-save-buffer.txt" \
  OSC_PASTE_TMUX_STATUS=1 \
  OSC_PASTE_TMUX_SHOW_SOURCE="$expected" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$paste_tmux_show_output"
assert_files_equal "osc-paste falls back to tmux show-buffer" "$expected" "$paste_tmux_show_output"

paste_host_expected="$tmp/paste-host-expected.txt"
paste_stale_tmux_buffer="$tmp/paste-stale-tmux-buffer.txt"
paste_local_tmux_host_output="$tmp/paste-local-tmux-host-output.txt"
printf 'host clipboard line\n' >"$paste_host_expected"
printf 'stale tmux buffer\n' >"$paste_stale_tmux_buffer"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_PASTE_TMUX_SOURCE="$paste_stale_tmux_buffer" \
  OSC_PASTE_PBPASTE_SOURCE="$paste_host_expected" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$paste_local_tmux_host_output"
assert_files_equal "osc-paste live local tmux prefers host clipboard" \
  "$paste_host_expected" \
  "$paste_local_tmux_host_output"

paste_local_tmux_fallback_output="$tmp/paste-local-tmux-fallback-output.txt"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_PASTE_TMUX_SOURCE="$expected" \
  OSC_PASTE_PBPASTE_STATUS=1 \
  OSC_PASTE_PBPASTE_PARTIAL="partial pbpaste output" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$paste_local_tmux_fallback_output"
assert_files_equal "osc-paste live local tmux falls back to tmux buffer after host failure" \
  "$expected" \
  "$paste_local_tmux_fallback_output"

paste_ssh_tmux_output="$tmp/paste-ssh-tmux-output.txt"
paste_ssh_tmux_pbpaste_log="$tmp/paste-ssh-tmux-pbpaste-should-not-run.log"
HOME="$tmp/home" \
  TMUX=fake \
  SSH_CLIENT="127.0.0.1 1000 22" \
  OSC_PASTE_TMUX_SOURCE="$expected" \
  OSC_PASTE_PBPASTE_SOURCE="$paste_host_expected" \
  OSC_PASTE_PBPASTE_CALL_LOG="$paste_ssh_tmux_pbpaste_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$paste_ssh_tmux_output"
assert_files_equal "osc-paste live SSH tmux still uses tmux buffer" "$expected" "$paste_ssh_tmux_output"
assert_file_absent "osc-paste live SSH tmux skips host pbpaste" "$paste_ssh_tmux_pbpaste_log"

paste_pbpaste_output="$tmp/paste-pbpaste-output.txt"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_PASTE_TMUX_SOURCE="$tmp/missing-tmux-buffer.txt" \
  OSC_PASTE_TMUX_STATUS=1 \
  OSC_PASTE_TMUX_SHOW_STATUS=1 \
  OSC_PASTE_PBPASTE_SOURCE="$expected" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$paste_pbpaste_output"
assert_files_equal "osc-paste preserves trailing newlines through pbpaste" "$expected" "$paste_pbpaste_output"

paste_binary_pbpaste_output="$tmp/paste-binary-pbpaste-output.bin"
HOME="$tmp/home" \
  TMUX="" \
  OSC_PASTE_PBPASTE_SOURCE="$binary_expected" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$paste_binary_pbpaste_output"
assert_files_equal "osc-paste preserves binary bytes through pbpaste" \
  "$binary_expected" \
  "$paste_binary_pbpaste_output"

paste_crlf_pbpaste_output="$tmp/paste-crlf-pbpaste-output.bin"
HOME="$tmp/home" \
  TMUX="" \
  OSC_PASTE_PBPASTE_SOURCE="$crlf_expected" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$paste_crlf_pbpaste_output"
assert_files_equal "osc-paste preserves CRLF bytes through pbpaste" \
  "$crlf_expected" \
  "$paste_crlf_pbpaste_output"

paste_unicode_pbpaste_output="$tmp/paste-unicode-pbpaste-output.txt"
HOME="$tmp/home" \
  TMUX="" \
  OSC_PASTE_PBPASTE_SOURCE="$unicode_expected" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$paste_unicode_pbpaste_output"
assert_files_equal "osc-paste preserves UTF-8 bytes through pbpaste" \
  "$unicode_expected" \
  "$paste_unicode_pbpaste_output"

paste_large_pbpaste_output="$tmp/paste-large-pbpaste-output.txt"
HOME="$tmp/home" \
  TMUX="" \
  OSC_PASTE_PBPASTE_SOURCE="$large_expected" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$paste_large_pbpaste_output"
assert_files_equal "osc-paste preserves large whitespace payload through pbpaste" \
  "$large_expected" \
  "$paste_large_pbpaste_output"

spaced_tmp_pbpaste_output="$tmp/spaced-tmp-pbpaste-output.txt"
HOME="$tmp/home" \
  TMUX="" \
  TMPDIR="$spaced_tmp" \
  OSC_PASTE_PBPASTE_SOURCE="$expected" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$spaced_tmp_pbpaste_output"
assert_files_equal "osc-paste handles TMPDIR with spaces" \
  "$expected" \
  "$spaced_tmp_pbpaste_output"
assert_no_temp_files "osc-paste cleans temp file when TMPDIR has spaces" "$spaced_tmp" "osc-paste.*"

invalid_tmp_pbpaste_output="$tmp/invalid-tmp-pbpaste-output.txt"
HOME="$tmp/home" \
  TMUX="" \
  TMPDIR="$tmp/missing-paste-tmpdir" \
  OSC_PASTE_PBPASTE_SOURCE="$expected" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$invalid_tmp_pbpaste_output"
assert_files_equal "osc-paste falls back to /tmp when TMPDIR is invalid" \
  "$expected" \
  "$invalid_tmp_pbpaste_output"

no_search_pbpaste_output="$tmp/no-search-pbpaste-output.txt"
HOME="$tmp/home" \
  TMUX="" \
  TMPDIR="$no_search_tmp" \
  OSC_PASTE_PBPASTE_SOURCE="$expected" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$no_search_pbpaste_output"
assert_files_equal "osc-paste falls back when TMPDIR is not searchable" \
  "$expected" \
  "$no_search_pbpaste_output"

broken_mktemp_pbpaste_output="$tmp/broken-mktemp-pbpaste-output.txt"
HOME="$tmp/home" \
  TMUX="" \
  TMPDIR="$broken_mktemp_tmp" \
  OSC_PASTE_PBPASTE_SOURCE="$expected" \
  PATH="$broken_mktemp_bin:$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$broken_mktemp_pbpaste_output"
assert_files_equal "osc-paste falls back when mktemp fails" \
  "$expected" \
  "$broken_mktemp_pbpaste_output"
assert_no_temp_files "osc-paste cleans fallback temp file when mktemp fails" "$broken_mktemp_tmp" "osc-paste.*"

paste_wlpaste_output="$tmp/paste-wlpaste-output.txt"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_PASTE_TMUX_SOURCE="$tmp/missing-tmux-buffer-wlpaste.txt" \
  OSC_PASTE_TMUX_STATUS=1 \
  OSC_PASTE_TMUX_SHOW_STATUS=1 \
  OSC_PASTE_PBPASTE_STATUS=1 \
  OSC_PASTE_PBPASTE_PARTIAL="partial pbpaste output" \
  OSC_PASTE_WLPASTE_SOURCE="$expected" \
  WAYLAND_DISPLAY=wayland-0 \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$paste_wlpaste_output"
assert_files_equal "osc-paste falls back after failed pbpaste without partial output" \
  "$expected" \
  "$paste_wlpaste_output"

paste_xclip_output="$tmp/paste-xclip-output.txt"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_PASTE_TMUX_SOURCE="$tmp/missing-tmux-buffer-xclip.txt" \
  OSC_PASTE_TMUX_STATUS=1 \
  OSC_PASTE_TMUX_SHOW_STATUS=1 \
  OSC_PASTE_PBPASTE_STATUS=1 \
  OSC_PASTE_PBPASTE_PARTIAL="partial pbpaste output" \
  OSC_PASTE_WLPASTE_STATUS=1 \
  OSC_PASTE_WLPASTE_PARTIAL="partial wl-paste output" \
  OSC_PASTE_XCLIP_SOURCE="$expected" \
  WAYLAND_DISPLAY=wayland-0 \
  DISPLAY=:99 \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$paste_xclip_output"
assert_files_equal "osc-paste falls back to xclip after failed Wayland paste" \
  "$expected" \
  "$paste_xclip_output"

paste_xsel_output="$tmp/paste-xsel-output.txt"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_PASTE_TMUX_SOURCE="$tmp/missing-tmux-buffer-xsel.txt" \
  OSC_PASTE_TMUX_STATUS=1 \
  OSC_PASTE_TMUX_SHOW_STATUS=1 \
  OSC_PASTE_PBPASTE_STATUS=1 \
  OSC_PASTE_PBPASTE_PARTIAL="partial pbpaste output" \
  OSC_PASTE_WLPASTE_STATUS=1 \
  OSC_PASTE_WLPASTE_PARTIAL="partial wl-paste output" \
  OSC_PASTE_XCLIP_STATUS=1 \
  OSC_PASTE_XCLIP_PARTIAL="partial xclip output" \
  OSC_PASTE_XSEL_SOURCE="$expected" \
  WAYLAND_DISPLAY=wayland-0 \
  DISPLAY=:99 \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$paste_xsel_output"
assert_files_equal "osc-paste falls back to xsel after failed xclip" \
  "$expected" \
  "$paste_xsel_output"

headless_paste_query_expected="$tmp/headless-paste-query.expected"
headless_paste_query_actual="$tmp/headless-paste-query.actual"
headless_wlpaste_call_log="$tmp/headless-wlpaste-should-not-run.log"
headless_paste_xclip_call_log="$tmp/headless-paste-xclip-should-not-run.log"
headless_paste_xsel_call_log="$tmp/headless-paste-xsel-should-not-run.log"
ln -s "$tmp/bin/wl-paste" "$headless_bin/wl-paste"
printf '\033]52;c;?\a' >"$headless_paste_query_expected"
if env -u DISPLAY -u WAYLAND_DISPLAY \
  HOME="$tmp/home" \
  TMUX="" \
  OSC_PASTE_WLPASTE_CALL_LOG="$headless_wlpaste_call_log" \
  OSC_PASTE_XCLIP_CALL_LOG="$headless_paste_xclip_call_log" \
  OSC_PASTE_XSEL_CALL_LOG="$headless_paste_xsel_call_log" \
  OSC_TTY="$headless_paste_query_actual" \
  OSC_PASTE_TIMEOUT=0.01 \
  PATH="$headless_bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$tmp/headless-paste.stdout" 2>"$tmp/headless-paste.stderr"; then
  printf 'not ok - osc-paste headless Linux query exits non-zero without response\n' >&2
  exit 1
fi
assert_files_equal "osc-paste headless Linux queries OSC52" \
  "$headless_paste_query_expected" \
  "$headless_paste_query_actual"
assert_file_absent "osc-paste headless Linux skips wl-paste without display" "$headless_wlpaste_call_log"
assert_file_absent "osc-paste headless Linux skips xclip without display" "$headless_paste_xclip_call_log"
assert_file_absent "osc-paste headless Linux skips xsel without display" "$headless_paste_xsel_call_log"

paste_osc52_tmux_expected="$tmp/paste-osc52-tmux.expected"
paste_osc52_tmux_actual="$tmp/paste-osc52-tmux.actual"
printf '\033Ptmux;\033\033]52;c;?\a\033%s' "\\" >"$paste_osc52_tmux_expected"
if HOME="$tmp/home" \
  TMUX=fake \
  SSH_CLIENT="127.0.0.1 1000 22" \
  OSC_PASTE_TMUX_SOURCE="$tmp/paste-osc52-missing-save.txt" \
  OSC_PASTE_TMUX_STATUS=1 \
  OSC_PASTE_TMUX_SHOW_SOURCE="$tmp/paste-osc52-missing-show.txt" \
  OSC_PASTE_TMUX_SHOW_STATUS=1 \
  OSC_TTY="$paste_osc52_tmux_actual" \
  OSC_PASTE_TIMEOUT=0.01 \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$tmp/paste-osc52-tmux.stdout" 2>"$tmp/paste-osc52-tmux.stderr"; then
  printf 'not ok - osc-paste OSC52 tmux query exits non-zero without response\n' >&2
  exit 1
fi
assert_files_equal "osc-paste wraps OSC52 query when tmux client is live" "$paste_osc52_tmux_expected" "$paste_osc52_tmux_actual"
assert_file_not_contains "osc-paste fractional timeout is quiet for tmux OSC52 query" \
  "$tmp/paste-osc52-tmux.stderr" \
  "invalid timeout specification"

paste_osc52_plain_expected="$tmp/paste-osc52-plain.expected"
paste_osc52_plain_actual="$tmp/paste-osc52-plain.actual"
printf '\033]52;c;?\a' >"$paste_osc52_plain_expected"
if HOME="$tmp/home" \
  TMUX=fake \
  SSH_CLIENT="127.0.0.1 1000 22" \
  OSC_TMUX_DISPLAY_STATUS=1 \
  OSC_TTY="$paste_osc52_plain_actual" \
  OSC_PASTE_TIMEOUT=0.01 \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$tmp/paste-osc52-plain.stdout" 2>"$tmp/paste-osc52-plain.stderr"; then
  printf 'not ok - osc-paste OSC52 plain query exits non-zero without response\n' >&2
  exit 1
fi
assert_files_equal "osc-paste uses plain OSC52 query when TMUX is stale" "$paste_osc52_plain_expected" "$paste_osc52_plain_actual"
assert_file_not_contains "osc-paste fractional timeout is quiet for stale TMUX OSC52 query" \
  "$tmp/paste-osc52-plain.stderr" \
  "invalid timeout specification"

ssh_paste_query_expected="$tmp/ssh-paste-query.expected"
ssh_paste_query_actual="$tmp/ssh-paste-query.actual"
ssh_paste_pbpaste_log="$tmp/ssh-paste-pbpaste-should-not-run.log"
printf '\033]52;c;?\a' >"$ssh_paste_query_expected"
if HOME="$tmp/home" \
  TMUX="" \
  SSH_CLIENT="127.0.0.1 1000 22" \
  OSC_PASTE_PBPASTE_SOURCE="$expected" \
  OSC_PASTE_PBPASTE_CALL_LOG="$ssh_paste_pbpaste_log" \
  OSC_TTY="$ssh_paste_query_actual" \
  OSC_PASTE_TIMEOUT=0.01 \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$tmp/ssh-paste-query.stdout" 2>"$tmp/ssh-paste-query.stderr"; then
  printf 'not ok - osc-paste SSH query exits non-zero without response\n' >&2
  exit 1
fi
assert_files_equal "osc-paste SSH session queries OSC52 instead of host pbpaste" \
  "$ssh_paste_query_expected" \
  "$ssh_paste_query_actual"
assert_file_absent "osc-paste SSH session skips host pbpaste" "$ssh_paste_pbpaste_log"

stty_cleanup_bin="$tmp/stty-cleanup-bin"
stty_cleanup_tmp="$tmp/stty-cleanup-tmp"
stty_cleanup_tty="$tmp/stty-cleanup.tty"
mkdir -p "$stty_cleanup_bin" "$stty_cleanup_tmp"
: >"$stty_cleanup_tty"
cat >"$stty_cleanup_bin/stty" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-g" ]]; then
  printf 'fake-tty-state\n'
fi
SH
chmod +x "$stty_cleanup_bin/stty"
if HOME="$tmp/home" \
  TMPDIR="$stty_cleanup_tmp" \
  OSC_TTY="$stty_cleanup_tty" \
  OSC_PASTE_TIMEOUT=0.01 \
  PATH="$stty_cleanup_bin:$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$tmp/paste-cleanup.stdout" 2>"$tmp/paste-cleanup.stderr"; then
  printf 'not ok - osc-paste OSC52 cleanup path exits non-zero without response\n' >&2
  exit 1
fi
assert_no_temp_files "osc-paste cleans temp file after OSC52 tty fallback" "$stty_cleanup_tmp" "osc-paste.*"

base64_mode_log="$tmp/base64-mode.log"
printf '%s' "$encoded" |
  OSC_PASTE_BASE64_MODE_LOG="$base64_mode_log" \
    PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$root/common/.local/bin/osc-paste" --decode-base64 >"$tmp/base64-decoded.txt"
assert_files_equal "osc-paste base64 decoder supports -d fallback" "$expected" "$tmp/base64-decoded.txt"
if [[ "$(cat "$base64_mode_log")" != "-d" ]]; then
  printf 'not ok - osc-paste base64 decoder used -d fallback\n' >&2
  printf 'actual mode: %s\n' "$(cat "$base64_mode_log")" >&2
  exit 1
fi
printf 'ok - osc-paste base64 decoder used -d fallback\n'

osc52_bel_mode_log="$tmp/osc52-bel-mode.log"
printf '\033]52;c;%s\a' "$encoded" |
  OSC_PASTE_BASE64_MODE_LOG="$osc52_bel_mode_log" \
    PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$root/common/.local/bin/osc-paste" --decode-osc52-response >"$tmp/osc52-bel-decoded.txt"
assert_files_equal "osc-paste decodes BEL-terminated OSC 52 response" "$expected" "$tmp/osc52-bel-decoded.txt"

osc52_binary_mode_log="$tmp/osc52-binary-mode.log"
printf '\033]52;c;%s\a' "$invalid_utf8_encoded" |
  OSC_PASTE_BASE64_MODE_LOG="$osc52_binary_mode_log" \
    PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$root/common/.local/bin/osc-paste" --decode-osc52-response >"$tmp/osc52-binary-decoded.bin"
assert_files_equal "osc-paste decodes invalid UTF-8 OSC 52 response" \
  "$invalid_utf8_expected" \
  "$tmp/osc52-binary-decoded.bin"

osc52_crlf_mode_log="$tmp/osc52-crlf-mode.log"
printf '\033]52;c;%s\a' "$crlf_encoded" |
  OSC_PASTE_BASE64_MODE_LOG="$osc52_crlf_mode_log" \
    PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$root/common/.local/bin/osc-paste" --decode-osc52-response >"$tmp/osc52-crlf-decoded.bin"
assert_files_equal "osc-paste decodes CRLF OSC 52 response" "$crlf_expected" "$tmp/osc52-crlf-decoded.bin"

osc52_unicode_mode_log="$tmp/osc52-unicode-mode.log"
printf '\033]52;c;%s\a' "$unicode_encoded" |
  OSC_PASTE_BASE64_MODE_LOG="$osc52_unicode_mode_log" \
    PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$root/common/.local/bin/osc-paste" --decode-osc52-response >"$tmp/osc52-unicode-decoded.txt"
assert_files_equal "osc-paste decodes UTF-8 OSC 52 response" "$unicode_expected" "$tmp/osc52-unicode-decoded.txt"

osc52_st_mode_log="$tmp/osc52-st-mode.log"
printf '\033]52;c;%s\033%s' "$encoded" "\\" |
  OSC_PASTE_BASE64_MODE_LOG="$osc52_st_mode_log" \
    PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$root/common/.local/bin/osc-paste" --decode-osc52-response >"$tmp/osc52-st-decoded.txt"
assert_files_equal "osc-paste decodes ST-terminated OSC 52 response" "$expected" "$tmp/osc52-st-decoded.txt"

osc52_tmux_dcs_mode_log="$tmp/osc52-tmux-dcs-mode.log"
printf '\033Ptmux;\033\033]52;c;%s\a\033%s' "$encoded" "\\" |
  OSC_PASTE_BASE64_MODE_LOG="$osc52_tmux_dcs_mode_log" \
    PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$root/common/.local/bin/osc-paste" --decode-osc52-response >"$tmp/osc52-tmux-dcs-decoded.txt"
assert_files_equal "osc-paste decodes tmux DCS-wrapped OSC 52 response" \
  "$expected" \
  "$tmp/osc52-tmux-dcs-decoded.txt"

empty_expected="$tmp/empty-expected.txt"
: >"$empty_expected"
osc52_empty_mode_log="$tmp/osc52-empty-mode.log"
printf '\033]52;c;\a' |
  OSC_PASTE_BASE64_MODE_LOG="$osc52_empty_mode_log" \
    PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$root/common/.local/bin/osc-paste" --decode-osc52-response >"$tmp/osc52-empty-decoded.txt"
assert_files_equal "osc-paste handles empty OSC 52 response" "$empty_expected" "$tmp/osc52-empty-decoded.txt"

osc52_invalid_output="$tmp/osc52-invalid-decoded.txt"
osc52_invalid_mode_log="$tmp/osc52-invalid-mode.log"
if printf '\033]52;c;not-base64\a' |
  OSC_PASTE_BASE64_MODE_LOG="$osc52_invalid_mode_log" \
    PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$root/common/.local/bin/osc-paste" --decode-osc52-response >"$osc52_invalid_output" 2>"$tmp/osc52-invalid.err"; then
  printf 'not ok - osc-paste rejects invalid OSC 52 response\n' >&2
  exit 1
fi
assert_files_equal "osc-paste rejects invalid OSC 52 response without output" "$empty_expected" "$osc52_invalid_output"
