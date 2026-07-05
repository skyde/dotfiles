#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/zshenv.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

skip() {
  printf 'skip - %s\n' "$1"
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

if ! zsh_path="$(command -v zsh)"; then
  skip "zshenv checks (zsh unavailable)"
  exit 0
fi

"$zsh_path" -n "$root/common/.zshenv"
pass "zshenv syntax"

mkdir -p "$tmp/home/.local/bin" "$tmp/x11" "$tmp/no-x11-parent"
touch "$tmp/x11/X3"
cat >"$tmp/home/.local/bin/fzf" <<'SH'
#!/usr/bin/env sh
exit 0
SH
chmod +x "$tmp/home/.local/bin/fzf"

run_zshenv() {
  local display="$1"
  local x11_dir="$2"
  local script="$3"

  ZDOTDIR="$root/common" \
    HOME="$tmp/home" \
    PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$tmp/home/.local/bin" \
    DISPLAY="$display" \
    DOTFILES_X11_UNIX_DIR="$x11_dir" \
    "$zsh_path" -c "$script"
}

path_output="$(
  run_zshenv "" "$tmp/no-x11-parent/missing" \
    'print -r -- "path=${(j:|:)path[1,8]}"; print -r -- "display=${DISPLAY-}"' 2>&1
)"
assert_eq \
  "zshenv orders user bins before Homebrew and system bins" \
  "$(printf 'path=%s\n%s\n' "$tmp/home/.local/bin|$tmp/home/local/bin|$tmp/home/bin|$tmp/home/go/bin|$tmp/home/.cargo/bin|$tmp/home/depot_tools|/opt/homebrew/bin|/usr/local/bin" "display=")" \
  "$path_output"

x_display_output="$(run_zshenv "" "$tmp/x11" 'print -r -- "display=${DISPLAY-}"' 2>&1)"
assert_eq "zshenv detects X display when socket directory exists" "display=:3" "$x_display_output"

preserved_display_output="$(run_zshenv ":99" "$tmp/x11" 'print -r -- "display=${DISPLAY-}"' 2>&1)"
assert_eq "zshenv preserves existing DISPLAY" "display=:99" "$preserved_display_output"

nounset_output="$(
  DOTFILES_ZSHENV="$root/common/.zshenv" \
    HOME="$tmp/home" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    DOTFILES_X11_UNIX_DIR="$tmp/no-x11-parent/missing" \
    "$zsh_path" -f -c 'unset FZF_DEFAULT_OPTS; setopt nounset; source "$DOTFILES_ZSHENV"; style_count="$(printf "%s\n" "$FZF_DEFAULT_OPTS" | grep -o -- "--style=minimal" | wc -l | tr -d " ")"; print -r -- "nounset-ok style_count=$style_count"' 2>&1
)"
assert_eq "zshenv fzf defaults are nounset-safe" "nounset-ok style_count=1" "$nounset_output"
