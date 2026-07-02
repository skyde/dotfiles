#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$root/common/.local/bin/copy-download-command"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/copy-download-command.XXXXXX")"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

assert_eq() {
  local description="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$actual" != "$expected" ]]; then
    printf 'not ok - %s\nexpected:\n%s\nactual:\n%s\n' "$description" "$expected" "$actual" >&2
    exit 1
  fi

  pass "$description"
}

mkdir -p "$tmp/bin" "$tmp/home" "$tmp/main-helper" "$tmp/source dir" "$tmp/downloads"
main_helper="$tmp/main-helper/copy-download-command"
ln -s "$helper" "$main_helper"

cat >"$tmp/bin/date" <<'SH'
#!/usr/bin/env sh
printf '%s\n' '2026-07-01-123456'
SH
chmod +x "$tmp/bin/date"

cat >"$tmp/bin/hostname" <<'SH'
#!/usr/bin/env sh
printf '%s\n' 'default-host'
SH
chmod +x "$tmp/bin/hostname"

cat >"$tmp/bin/osc-copy" <<'SH'
#!/usr/bin/env sh
cat >"${COPY_DOWNLOAD_TEST_COPY_LOG:?}"
SH
chmod +x "$tmp/bin/osc-copy"

expected_command() {
  local host="$1"
  local src_dir="${2%/}"
  local dest_base="${3%/}"
  local dir_name dest_dir download_cmd

  dir_name="$(basename "$src_dir")"
  dest_dir="$dest_base/$dir_name-2026-07-01-123456"
  printf -v download_cmd 'rsync -avz %q:%q/ %q/' "$host" "$src_dir" "$dest_dir"
  download_cmd="${download_cmd//\\~/\~}"
  printf '%s\n' "$download_cmd"
}

copy_log="$tmp/copy.log"
expected="$(expected_command "remote.example" "$tmp/source dir" "$tmp/downloads")"
actual="$(
  COPY_DOWNLOAD_TEST_COPY_LOG="$copy_log" \
    HOME="$tmp/home" \
    PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    SSH_RSYNC_HOST="remote.example" \
    "$main_helper" "$tmp/source dir/" "$tmp/downloads/"
)"
assert_eq "download command quotes spaced source and destination" "$expected" "$actual"
assert_eq "download command is copied" "$expected" "$(cat "$copy_log")"

isolated_helper_dir="$tmp/isolated-helper"
isolated_path="$tmp/isolated-path"
isolated_home="$tmp/isolated-home"
mkdir -p "$isolated_helper_dir" "$isolated_path" "$isolated_home/.local/bin" "$isolated_home/dotfiles/common/.local/bin"
ln -s "$helper" "$isolated_helper_dir/copy-download-command"
ln -s "$tmp/bin/date" "$isolated_path/date"
ln -s "$tmp/bin/hostname" "$isolated_path/hostname"
cat >"$isolated_path/osc-copy" <<'SH'
#!/usr/bin/env sh
printf 'path shadow osc-copy should not run\n' >&2
exit 97
SH
chmod +x "$isolated_path/osc-copy"
cat >"$isolated_helper_dir/osc-copy" <<'SH'
#!/usr/bin/env sh
cat >"${COPY_DOWNLOAD_TEST_COPY_LOG:?}"
SH
chmod +x "$isolated_helper_dir/osc-copy"

fallback_copy_log="$tmp/fallback-copy.log"
literal_home_downloads="$(printf '~')/Downloads"
fallback_expected="$(expected_command "default-host" "$tmp/source dir" "$literal_home_downloads")"
adjacent_actual="$(
  COPY_DOWNLOAD_TEST_COPY_LOG="$fallback_copy_log" \
    HOME="$isolated_home" \
    PATH="$isolated_path:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$isolated_helper_dir/copy-download-command" "$tmp/source dir"
)"
assert_eq "download command uses hostname default" "$fallback_expected" "$adjacent_actual"
assert_eq "download command copies via adjacent osc-copy before PATH shadow" "$fallback_expected" "$(cat "$fallback_copy_log")"

rm -f "$isolated_helper_dir/osc-copy" "$fallback_copy_log"
cat >"$isolated_home/.local/bin/osc-copy" <<'SH'
#!/usr/bin/env sh
cat >"${COPY_DOWNLOAD_TEST_COPY_LOG:?}"
SH
chmod +x "$isolated_home/.local/bin/osc-copy"
home_local_actual="$(
  COPY_DOWNLOAD_TEST_COPY_LOG="$fallback_copy_log" \
    HOME="$isolated_home" \
    PATH="$isolated_path:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$isolated_helper_dir/copy-download-command" "$tmp/source dir"
)"
assert_eq "download command uses hostname default through home local fallback" "$fallback_expected" "$home_local_actual"
assert_eq "download command copies via home local osc-copy before PATH shadow" "$fallback_expected" "$(cat "$fallback_copy_log")"

rm -f "$isolated_home/.local/bin/osc-copy" "$fallback_copy_log"
cat >"$isolated_home/dotfiles/common/.local/bin/osc-copy" <<'SH'
#!/usr/bin/env sh
cat >"${COPY_DOWNLOAD_TEST_COPY_LOG:?}"
SH
chmod +x "$isolated_home/dotfiles/common/.local/bin/osc-copy"
fallback_actual="$(
  COPY_DOWNLOAD_TEST_COPY_LOG="$fallback_copy_log" \
    HOME="$isolated_home" \
    PATH="$isolated_path:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$isolated_helper_dir/copy-download-command" "$tmp/source dir"
)"
assert_eq "download command uses hostname default through home fallback" "$fallback_expected" "$fallback_actual"
assert_eq "download command copies via home dotfiles osc-copy fallback before PATH shadow" "$fallback_expected" "$(cat "$fallback_copy_log")"

missing_helper_dir="$tmp/missing-helper"
missing_home="$tmp/missing-home"
missing_path="$tmp/missing-path"
mkdir -p "$missing_helper_dir" "$missing_home" "$missing_path"
ln -s "$helper" "$missing_helper_dir/copy-download-command"
ln -s "$tmp/bin/date" "$missing_path/date"
ln -s "$tmp/bin/hostname" "$missing_path/hostname"
if HOME="$missing_home" \
  PATH="$missing_path:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$missing_helper_dir/copy-download-command" "$tmp/source dir" >"$tmp/missing.out" 2>"$tmp/missing.err"; then
  printf 'not ok - download command exits non-zero without copy helper\n' >&2
  exit 1
fi
assert_eq "download command reports missing copy helper" \
  "copy-download-command: osc-copy not found" \
  "$(cat "$tmp/missing.err")"
