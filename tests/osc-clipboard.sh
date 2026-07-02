#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

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
if [[ "${OSC_PASTE_WLPASTE_STATUS:-0}" != 0 ]]; then
  printf '%s' "${OSC_PASTE_WLPASTE_PARTIAL:-}"
  exit "$OSC_PASTE_WLPASTE_STATUS"
fi
cat "${OSC_PASTE_WLPASTE_SOURCE:?}"
SH
chmod +x "$tmp/bin/wl-paste"

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

tmux_log="$tmp/tmux-buffer.txt"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_COPY_TMUX_LOG="$tmux_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$expected"
assert_files_equal "osc-copy preserves trailing newlines through tmux" "$expected" "$tmux_log"

tmux_plain_log="$tmp/tmux-buffer-plain.txt"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_COPY_TMUX_WRITE_LOG="$tmp/failed-tmux-write-buffer.txt" \
  OSC_COPY_TMUX_WRITE_STATUS=1 \
  OSC_COPY_TMUX_LOG="$tmux_plain_log" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-copy" <"$expected"
assert_files_equal "osc-copy falls back to plain tmux load-buffer" "$expected" "$tmux_plain_log"

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

paste_pbpaste_output="$tmp/paste-pbpaste-output.txt"
HOME="$tmp/home" \
  TMUX=fake \
  OSC_PASTE_TMUX_SOURCE="$tmp/missing-tmux-buffer.txt" \
  OSC_PASTE_TMUX_STATUS=1 \
  OSC_PASTE_TMUX_SHOW_STATUS=1 \
  OSC_PASTE_PBPASTE_SOURCE="$expected" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$root/common/.local/bin/osc-paste" >"$paste_pbpaste_output"
assert_files_equal "osc-paste preserves trailing newlines through pbpaste fallback" "$expected" "$paste_pbpaste_output"

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

osc52_st_mode_log="$tmp/osc52-st-mode.log"
printf '\033]52;c;%s\033%s' "$encoded" "\\" |
  OSC_PASTE_BASE64_MODE_LOG="$osc52_st_mode_log" \
    PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$root/common/.local/bin/osc-paste" --decode-osc52-response >"$tmp/osc52-st-decoded.txt"
assert_files_equal "osc-paste decodes ST-terminated OSC 52 response" "$expected" "$tmp/osc52-st-decoded.txt"

empty_expected="$tmp/empty-expected.txt"
: >"$empty_expected"
osc52_empty_mode_log="$tmp/osc52-empty-mode.log"
printf '\033]52;c;\a' |
  OSC_PASTE_BASE64_MODE_LOG="$osc52_empty_mode_log" \
    PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$root/common/.local/bin/osc-paste" --decode-osc52-response >"$tmp/osc52-empty-decoded.txt"
assert_files_equal "osc-paste handles empty OSC 52 response" "$empty_expected" "$tmp/osc52-empty-decoded.txt"
