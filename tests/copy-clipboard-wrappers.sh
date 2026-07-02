#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/copy-clipboard-wrappers.XXXXXX")"
tmp="$(cd "$tmp" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

copy_diff="$root/common/.local/bin/copy-diff"
git_copy="$root/common/.local/bin/git-copy"

assert_eq() {
  local description="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$actual" != "$expected" ]]; then
    printf 'not ok - %s\nexpected:\n%s\nactual:\n%s\n' "$description" "$expected" "$actual" >&2
    exit 1
  fi

  printf 'ok - %s\n' "$description"
}

write_copy_helper() {
  local path="$1"

  mkdir -p "$(dirname "$path")"
  cat >"$path" <<'SH'
#!/usr/bin/env bash
cat >"${COPY_WRAPPER_LOG:?}"
SH
  chmod +x "$path"
}

write_path_shadow_copy_helper() {
  local path="$1"

  mkdir -p "$(dirname "$path")"
  cat >"$path" <<'SH'
#!/usr/bin/env bash
printf 'path shadow osc-copy should not run\n' >&2
exit 97
SH
  chmod +x "$path"
}

path_bin="$tmp/path-bin"
home="$tmp/home"
mkdir -p "$path_bin" "$home"

cat >"$path_bin/git" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  merge-base)
    printf 'base-ref\n'
    ;;
  diff)
    shift
    printf 'copy-diff:%s\n' "$*"
    ;;
  *)
    printf 'unexpected git command: %s\n' "$*" >&2
    exit 2
    ;;
esac
SH
chmod +x "$path_bin/git"

cat >"$path_bin/diff-branch" <<'SH'
#!/usr/bin/env bash
printf 'git-copy:%s\n' "$*"
SH
chmod +x "$path_bin/diff-branch"
write_path_shadow_copy_helper "$path_bin/osc-copy"

adjacent_dir="$tmp/adjacent"
mkdir -p "$adjacent_dir"
ln -s "$copy_diff" "$adjacent_dir/copy-diff"
ln -s "$git_copy" "$adjacent_dir/git-copy"

copy_diff_log="$tmp/copy-diff-adjacent.log"
write_copy_helper "$adjacent_dir/osc-copy"
COPY_WRAPPER_LOG="$copy_diff_log" \
  HOME="$home" \
  PATH="$path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$adjacent_dir/copy-diff" 7
assert_eq "copy-diff uses adjacent osc-copy before PATH shadow" "copy-diff:-U7 base-ref" "$(cat "$copy_diff_log")"

git_copy_log="$tmp/git-copy-adjacent.log"
COPY_WRAPPER_LOG="$git_copy_log" \
  HOME="$home" \
  PATH="$path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$adjacent_dir/git-copy" alpha "two words"
assert_eq "git-copy uses adjacent osc-copy before PATH shadow" "git-copy:alpha two words" "$(cat "$git_copy_log")"

rm -f "$adjacent_dir/osc-copy"
mkdir -p "$home/.local/bin" "$home/dotfiles/common/.local/bin"
write_copy_helper "$home/.local/bin/osc-copy"

home_local_copy_diff_log="$tmp/copy-diff-home-local.log"
COPY_WRAPPER_LOG="$home_local_copy_diff_log" \
  HOME="$home" \
  PATH="$path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$adjacent_dir/copy-diff" 5
assert_eq "copy-diff uses home local osc-copy before PATH shadow" "copy-diff:-U5 base-ref" "$(cat "$home_local_copy_diff_log")"

home_local_git_copy_log="$tmp/git-copy-home-local.log"
COPY_WRAPPER_LOG="$home_local_git_copy_log" \
  HOME="$home" \
  PATH="$path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$adjacent_dir/git-copy" gamma
assert_eq "git-copy uses home local osc-copy before PATH shadow" "git-copy:gamma" "$(cat "$home_local_git_copy_log")"

rm -f "$home/.local/bin/osc-copy"
write_copy_helper "$home/dotfiles/common/.local/bin/osc-copy"

home_copy_diff_log="$tmp/copy-diff-home.log"
COPY_WRAPPER_LOG="$home_copy_diff_log" \
  HOME="$home" \
  PATH="$path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$adjacent_dir/copy-diff" 3
assert_eq "copy-diff uses home dotfiles osc-copy before PATH shadow" "copy-diff:-U3 base-ref" "$(cat "$home_copy_diff_log")"

home_git_copy_log="$tmp/git-copy-home.log"
COPY_WRAPPER_LOG="$home_git_copy_log" \
  HOME="$home" \
  PATH="$path_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$adjacent_dir/git-copy" beta
assert_eq "git-copy uses home dotfiles osc-copy before PATH shadow" "git-copy:beta" "$(cat "$home_git_copy_log")"

missing_home="$tmp/missing-home"
missing_path="$tmp/missing-path"
mkdir -p "$missing_home" "$missing_path"

if HOME="$missing_home" PATH="$missing_path:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$adjacent_dir/copy-diff" >"$tmp/copy-diff-missing.out" 2>"$tmp/copy-diff-missing.err"; then
  printf 'not ok - copy-diff exits non-zero without osc-copy\n' >&2
  exit 1
fi
assert_eq "copy-diff reports missing osc-copy" "copy-diff: osc-copy not found" "$(cat "$tmp/copy-diff-missing.err")"

if HOME="$missing_home" PATH="$missing_path:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$adjacent_dir/git-copy" >"$tmp/git-copy-missing.out" 2>"$tmp/git-copy-missing.err"; then
  printf 'not ok - git-copy exits non-zero without osc-copy\n' >&2
  exit 1
fi
assert_eq "git-copy reports missing osc-copy" "git-copy: osc-copy not found" "$(cat "$tmp/git-copy-missing.err")"
