#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runner="$root/common/.local/bin/dotfiles-run"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

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

make_fake_command() {
  local path="$1"
  local label="$2"

  mkdir -p "$(dirname -- "$path")"
  cat >"$path" <<SH
#!/usr/bin/env bash
printf '%s\\n' '$label:'"\$*" >> "\${DOTFILES_RUN_LOG:?}"
SH
  chmod +x "$path"
}

mkdir -p "$tmp/home/.local/bin" "$tmp/home/dotfiles/common/.local/bin" "$tmp/path-bin"
make_fake_command "$tmp/home/.local/bin/sample" home-local
make_fake_command "$tmp/home/dotfiles/common/.local/bin/sample" home-dotfiles
make_fake_command "$tmp/path-bin/sample" path
dollar='$'
runner_source="$(<"$runner")"

if [[ "$runner_source" == *"${dollar}{HOME:-}/.local/bin/"* ]]; then
  printf 'not ok - dotfiles-run does not probe root-local helper fallback\n' >&2
  exit 1
fi
printf 'ok - dotfiles-run does not probe root-local helper fallback\n'

if [[ "$runner_source" == *"${dollar}{HOME:-}/dotfiles/common/.local/bin/"* ]]; then
  printf 'not ok - dotfiles-run does not probe root dotfiles helper fallback\n' >&2
  exit 1
fi
printf 'ok - dotfiles-run does not probe root dotfiles helper fallback\n'

log="$tmp/run.log"
DOTFILES_RUN_LOG="$log" \
  HOME="$tmp/home" \
  PATH="$tmp/path-bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$runner" sample alpha "two words"
assert_eq "dotfiles-run prefers installed home command" "home-local:alpha two words" "$(cat "$log")"

rm -f "$tmp/home/.local/bin/sample" "$log"
DOTFILES_RUN_LOG="$log" \
  HOME="$tmp/home" \
  PATH="$tmp/path-bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$runner" sample beta
assert_eq "dotfiles-run falls back to home dotfiles command" "home-dotfiles:beta" "$(cat "$log")"

isolated_runner_dir="$tmp/isolated-runner"
mkdir -p "$isolated_runner_dir"
ln -s "$runner" "$isolated_runner_dir/dotfiles-run"
make_fake_command "$isolated_runner_dir/sample" adjacent
rm -f "$tmp/home/dotfiles/common/.local/bin/sample" "$log"
DOTFILES_RUN_LOG="$log" \
  HOME="$tmp/home" \
  PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  "$isolated_runner_dir/dotfiles-run" sample gamma
assert_eq "dotfiles-run falls back to adjacent command" "adjacent:gamma" "$(cat "$log")"

rm -f "$isolated_runner_dir/sample" "$log"
DOTFILES_RUN_LOG="$log" \
  HOME="$tmp/home" \
  PATH="$tmp/path-bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$runner" sample delta
assert_eq "dotfiles-run falls back to PATH command" "path:delta" "$(cat "$log")"

rm -f "$log"
env -u HOME \
  DOTFILES_RUN_LOG="$log" \
  PATH="$tmp/path-bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$runner" sample no-home
assert_eq "dotfiles-run falls back to PATH command when HOME is unset" "path:no-home" "$(cat "$log")"

mkdir -p "$tmp/home/custom bin"
make_fake_command "$tmp/home/custom bin/direct" direct
rm -f "$log"
home_relative_command="$(printf '~')/custom bin/direct"
DOTFILES_RUN_LOG="$log" \
  HOME="$tmp/home" \
  PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  "$runner" "$home_relative_command" epsilon
assert_eq "dotfiles-run expands explicit home path" "direct:epsilon" "$(cat "$log")"

if HOME="$tmp/home" PATH="/usr/bin:/bin:/usr/sbin:/sbin" "$runner" definitely-missing >"$tmp/missing.out" 2>"$tmp/missing.err"; then
  printf 'not ok - dotfiles-run exits non-zero for missing command\n' >&2
  exit 1
fi
assert_eq "dotfiles-run reports missing command" \
  "Error: command not found in dotfiles paths or PATH: definitely-missing" \
  "$(cat "$tmp/missing.err")"
