#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

[[ $(uname -s) == Linux ]] || fail "JJ integration test currently requires Linux"
command -v jj >/dev/null 2>&1 || fail "jj is not installed"

export XDG_CONFIG_HOME="$test_root/config"
export TMPDIR="$test_root/tmp with spaces ü"
export PATH="$test_root/bin:$repo_root/common/.local/bin:$PATH"
mkdir -p "$XDG_CONFIG_HOME/jj/conf.d" "$TMPDIR" "$test_root/bin"
touch "$XDG_CONFIG_HOME/jj/config.toml"
cp "$repo_root/common/.config/jj/conf.d/50-neovim-diffview.toml" \
  "$XDG_CONFIG_HOME/jj/conf.d/50-neovim-diffview.toml"

fragment="$XDG_CONFIG_HOME/jj/conf.d/50-neovim-diffview.toml"
fragment_hash_before=$(sha256sum "$fragment")
jj config set --user user.name "Neovim JJ Test"
jj config set --user user.email "nvim-jj@example.invalid"
fragment_hash_after=$(sha256sum "$fragment")
[[ $fragment_hash_before == "$fragment_hash_after" ]] || fail "jj config set modified the managed fragment"
grep -F "Neovim JJ Test" "$XDG_CONFIG_HOME/jj/config.toml" >/dev/null \
  || fail "jj config set did not use the unmanaged primary config"

[[ $(jj config get ui.diff-editor) == diffview ]] || fail "JJ diff editor config did not load"
[[ $(jj config get ui.merge-editor) == diffview-merge ]] || fail "JJ merge editor config did not load"
[[ $(jj config get merge-tools.diffview.program) == nvim-diff ]] || fail "JJ diff wrapper config did not load"
[[ $(jj config get merge-tools.diffview-merge.program) == nvim-merge ]] \
  || fail "JJ merge wrapper config did not load"
grep -F 'program = "nvim-diff.cmd"' "$fragment" >/dev/null \
  || fail "JJ fragment has no native Windows diff wrapper"
grep -F 'program = "nvim-merge.cmd"' "$fragment" >/dev/null \
  || fail "JJ fragment has no native Windows merge wrapper"

cat >"$test_root/bin/nvim-diff" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: >"$JJ_CAPTURE"
for argument in "$@"; do
  [[ -d $argument ]] || {
    printf 'JJ passed a non-directory diff argument: %s\n' "$argument" >&2
    exit 41
  }
  realpath -m -- "$argument" >>"$JJ_CAPTURE"
done
SH

cat >"$test_root/bin/nvim-merge" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: >"$JJ_CAPTURE"
for argument in "$@"; do
  realpath -m -- "$argument" >>"$JJ_CAPTURE"
done
cp -- "$3" "$1"
SH
chmod +x "$test_root/bin/nvim-diff" "$test_root/bin/nvim-merge"

workspace="$test_root/workspace ü"
mkdir -p "$workspace"
jj git init "$workspace" >/dev/null
printf 'base\n' >"$workspace/conflict file.txt"
(
  cd "$workspace"
  jj describe -m base >/dev/null
  jj new >/dev/null
  printf 'left\n' >"conflict file.txt"
  jj describe -m left >/dev/null
)

diff_capture="$test_root/jj-diff-args"
JJ_CAPTURE="$diff_capture" jj -R "$workspace" diff --tool diffview >/dev/null
mapfile -t diff_args <"$diff_capture"
[[ ${#diff_args[@]} -eq 2 ]] || fail "jj diff passed ${#diff_args[@]} args instead of 2"
# JJ removes the temporary directories after the tool exits. The wrapper
# validates their type while it is running; here we verify the exact paths.
[[ ${diff_args[0]} == "$TMPDIR"/* && ${diff_args[1]} == "$TMPDIR"/* ]] \
  || fail "jj diff lost the TMPDIR containing spaces"

diffedit_capture="$test_root/jj-diffedit-args"
JJ_CAPTURE="$diffedit_capture" jj -R "$workspace" diffedit --tool diffview >/dev/null
mapfile -t diffedit_args <"$diffedit_capture"
[[ ${#diffedit_args[@]} -eq 3 ]] || fail "jj diffedit passed ${#diffedit_args[@]} args instead of 3"
for directory in "${diffedit_args[@]}"; do
  [[ $directory == "$TMPDIR"/* ]] || fail "jj diffedit lost the TMPDIR containing spaces"
done

left_change=$(jj -R "$workspace" log -r @ -T 'change_id ++ "\n"' --no-graph)
(
  cd "$workspace"
  jj new @- >/dev/null
  printf 'right\n' >"conflict file.txt"
  jj describe -m right >/dev/null
)
right_change=$(jj -R "$workspace" log -r @ -T 'change_id ++ "\n"' --no-graph)
jj -R "$workspace" new "$left_change" "$right_change" >/dev/null
jj -R "$workspace" resolve --list | grep -F "conflict file.txt" >/dev/null \
  || fail "JJ conflict fixture was not created"

merge_capture="$test_root/jj-merge-args"
(
  cd "$workspace"
  JJ_CAPTURE="$merge_capture" jj resolve --tool diffview-merge "conflict file.txt" >/dev/null
)
mapfile -t merge_args <"$merge_capture"
[[ ${#merge_args[@]} -eq 4 ]] || fail "jj resolve passed ${#merge_args[@]} args instead of 4"
for path in "${merge_args[@]}"; do
  [[ $path == "$TMPDIR"/* ]] || fail "jj resolve lost the TMPDIR containing spaces"
done
if jj -R "$workspace" resolve --list 2>/dev/null | grep -F "conflict file.txt" >/dev/null; then
  fail "JJ conflict remained after the merge wrapper completed"
fi

printf 'nvim JJ integration tests passed\n'
