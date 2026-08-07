#!/usr/bin/env bash
# Check the [delta] section of common/.config/git/config against the delta
# that is actually installed, and against the things the config promises.
#
#   tests/check-delta-config.sh            # against this checkout
#   tests/check-delta-config.sh /path/dir  # against another checkout
#   tests/check-delta-config.sh --preview  # …and render the fixture in colour
#
# Three classes of failure, each of which has already happened once:
#
#   1. A key delta does not have. Delta reads its settings out of git config,
#      and git config has no schema — an option that was renamed, or never
#      existed, or arrived in a later release, sits there looking like live
#      configuration and does exactly nothing. `blame-timestamp-style` did.
#   2. The diff-body palette drifting away from lua/util/inline_diff.lua, which
#      mirrors it hex for hex so the Neovim inline diff and a terminal patch
#      are the same picture. Nothing but a comment held those together.
#   3. A change that renders as nothing at all. With file-style = omit a binary
#      file and a chmod each produced a single blank line — no name, no marker
#      — in `git diff` and in lazygit. Whatever the chrome does later, every
#      shape of change has to leave a mark.
#
# Needs delta and git; skips (exit 0) if delta is not installed, so it is safe
# to run on a machine that has not been through init.sh yet.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
root="$PWD"
preview=""
for arg in "$@"; do
  case "$arg" in
  --preview) preview=1 ;;
  *) root="$arg" ;;
  esac
done
cfg="$root/common/.config/git/config"
lua="$root/common/.config/nvim/lua/util/inline_diff.lua"

if [[ ! -f "$cfg" ]]; then
  echo "no git config at $cfg" >&2
  exit 1
fi

if ! command -v delta >/dev/null 2>&1; then
  echo "delta not found — skipping (install git-delta to run this check)"
  exit 0
fi

# The escape is spelled with printf rather than \x1b: BSD sed, which is the sed
# on macOS, does not understand \x escapes and would leave every colour code in
# place — the assertions below would then all fail for the wrong reason.
esc=$(printf '\033')
plain() { sed "s/${esc}\\[[0-9;]*m//g; s/${esc}\\[0K//g"; }

status=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() {
  printf 'FAIL  %s\n' "$1"
  if [[ $# -ge 2 ]]; then printf '      -> %s\n' "$2"; fi
  status=1
}

printf 'delta: %s\n\n' "$(delta --version)"

# ---------------------------------------------------------------- 1. keys
# --help is the only machine-readable list of options delta offers. Long-only
# forms are indented six spaces; the handful that also have a short form
# ("  -n, --line-numbers") sit at two, so the pattern has to accept both — miss
# that and -n/-s/-w read as keys delta does not have. Delta before 0.18 colours
# its own --help even into a pipe, which buries the indentation under escape
# codes, hence the strip.
opts="$(mktemp)"
keys="$(mktemp)"
trap 'rm -f "$opts" "$keys"' EXIT
delta --help 2>&1 | plain |
  sed -n 's/^ \{2,7\}\(-[a-zA-Z], \)\?--\([a-z0-9-]*\).*/\2/p' |
  sort -u >"$opts"
# Keys in the [delta] section: indented assignments between "[delta]" and the
# next section header.
sed -n '/^\[delta\]$/,/^\[/p' "$cfg" |
  sed -n 's/^[[:space:]]\{1,\}\([a-z0-9-]\{1,\}\)[[:space:]]*=.*/\1/p' |
  sort -u >"$keys"

n_opts=$(wc -l <"$opts" | tr -d ' ')
n_keys=$(wc -l <"$keys" | tr -d ' ')
if [[ "$n_opts" -lt 50 ]]; then
  fail "could not parse delta --help (only $n_opts options found)" \
    "the --help layout changed; fix the sed in this script"
else
  unknown=$(comm -23 "$keys" "$opts")
  if [[ -z "$unknown" ]]; then
    pass "all $n_keys [delta] keys exist in this delta ($n_opts options known)"
  else
    fail "[delta] sets keys this delta does not have: $(printf '%s' "$unknown" | tr '\n' ' ')" \
      "delta ignores unknown keys silently — remove them or fix the spelling"
  fi
fi

# ------------------------------------------------- 2. palette shared with nvim
# The pairs the comment in inline_diff.lua promises. Left: the delta key.
# Right: the Neovim highlight group whose bg must equal delta's background.
if [[ ! -f "$lua" ]]; then
  fail "inline_diff.lua not found at $lua"
elif ! python3 - "$cfg" "$lua" <<'PY'
import re
import sys

cfg_path, lua_path = sys.argv[1], sys.argv[2]
PAIRS = [
    ("plus-style", "InlineDiffAdd"),
    ("plus-non-emph-style", "InlineDiffAddDim"),
    ("plus-emph-style", "InlineDiffAddEmph"),
    ("minus-style", "InlineDiffDelete"),
    ("minus-non-emph-style", "InlineDiffDeleteDim"),
    ("minus-emph-style", "InlineDiffDeleteEmph"),
    ("whitespace-error-style", "InlineDiffWsError"),
]
# map-styles carries the two moved-code colours in one value.
MOVED = [("bold purple", "InlineDiffMovedDelete"), ("bold cyan", "InlineDiffMovedAdd")]

cfg = open(cfg_path).read()
section = re.search(r"^\[delta\]\n(.*?)(?=^\[)", cfg, re.M | re.S)
body = section.group(1) if section else ""


def delta_hex(key):
    m = re.search(rf"^\s+{re.escape(key)}\s*=\s*(.+?)\s*$", body, re.M)
    if not m:
        return None
    h = re.search(r"#[0-9a-fA-F]{6}", m.group(1))
    return h.group(0).lower() if h else None


def moved_hex(marker):
    m = re.search(r"^\s+map-styles\s*=\s*(.+?)\s*$", body, re.M)
    if not m:
        return None
    for part in m.group(1).strip('"').split(","):
        if part.strip().startswith(marker):
            h = re.search(r"#[0-9a-fA-F]{6}", part)
            return h.group(0).lower() if h else None
    return None


lua = open(lua_path).read()


def lua_hex(group):
    m = re.search(rf"{group}\s*=\s*\{{([^}}]*)\}}", lua)
    if not m:
        return None
    h = re.search(r'bg\s*=\s*"(#[0-9a-fA-F]{6})"', m.group(1))
    return h.group(1).lower() if h else None


bad = []
checked = 0
for key, group in PAIRS:
    a, b = delta_hex(key), lua_hex(group)
    if a is None:
        bad.append(f"{key}: no colour found in [delta]")
    elif b is None:
        bad.append(f"{group}: no bg found in inline_diff.lua")
    elif a != b:
        bad.append(f"{key} = {a} but {group} = {b}")
    else:
        checked += 1
for marker, group in MOVED:
    a, b = moved_hex(marker), lua_hex(group)
    if a is None:
        bad.append(f"map-styles '{marker}': no colour found")
    elif b is None:
        bad.append(f"{group}: no bg found in inline_diff.lua")
    elif a != b:
        bad.append(f"map-styles '{marker}' = {a} but {group} = {b}")
    else:
        checked += 1

if bad:
    print("FAIL  delta palette and inline_diff.lua disagree")
    for line in bad:
        print(f"      -> {line}")
    sys.exit(1)
print(f"PASS  all {checked} diff-body colours match inline_diff.lua")
PY
then
  status=1
fi

# ------------------------------------------------ 3. every change leaves a mark
# The fixture runs against the whole config, not just its [delta] half: the
# rendering depends on diff.context, diff.algorithm, the nofunc diff driver and
# [color "grep"] as much as on the styles. GIT_CONFIG_SYSTEM is emptied so a
# machine-wide /etc/gitconfig cannot change the answer; the sandbox repo sets
# its own identity locally, which outranks anything the config carries.
export GIT_CONFIG_GLOBAL="$cfg"
export GIT_CONFIG_SYSTEM=/dev/null

sandbox="$(mktemp -d)"
trap 'rm -f "$opts" "$keys"; rm -rf "$sandbox"' EXIT
repo="$sandbox/repo"
git init -q -b main "$repo"
(
  cd "$repo" || exit 1
  git config user.email delta@example.com
  git config user.name "Delta Check"
  printf 'one\ntwo\nthree\n' >keep.txt
  printf '#!/bin/sh\necho hi\n' >mode.sh
  printf '\x00\x01\x02old\x00\xff' >blob.bin
  printf 'moves later\n' >rename_me.txt
  printf 'goes away\n' >delete_me.txt
  printf 'alpha\n\ttab indented\nomega\n' >tabbed.txt
  git add -A
  git commit -qm initial
  printf 'one\nTWO\nthree\n' >keep.txt
  chmod +x mode.sh
  printf '\x00\x01\x02new\x00\xfe' >blob.bin
  git mv rename_me.txt renamed.txt
  git rm -q delete_me.txt
  printf 'brand new\n' >created.txt
  printf 'alpha\n\t\ttab indented deeper   \nomega\n' >tabbed.txt
  git add -A
) >/dev/null

# core.attributesFile is passed explicitly: git finds it at
# $XDG_CONFIG_HOME/git/attributes on a machine where these dotfiles are
# installed, but this check has to work against a bare checkout too, and
# without it git appends function context to every hunk header.
raw_diff() {
  git -C "$repo" --no-pager -c color.ui=always \
    -c core.attributesFile="$root/common/.config/git/attributes" \
    diff --cached -M
}
paint() { delta --config "$cfg" --paging=never --width="${COLUMNS:-100}"; }
out="$(raw_diff | paint | plain)"

expect() {
  if printf '%s\n' "$out" | grep -qE "$2"; then
    pass "$1"
  else
    fail "$1" "nothing in the rendered diff matched /$2/"
  fi
}
expect "a modified file is named"        '^M keep\.txt'
expect "a new file is named"             '^A created\.txt'
expect "a deleted file is named"         '^D delete_me\.txt'
expect "a rename shows both names"       '^R rename_me\.txt .* renamed\.txt'
# Delta only started folding these into its file header at 0.17; 0.16 passes
# git's own "Binary files … differ" and "old mode/new mode" lines through
# instead. Either is fine — the point is that something reaches the screen.
# With file-style = omit all three versions render exactly nothing here.
expect "a binary change is visible"      '^M blob\.bin \(binary file\)|Binary files .*blob\.bin'
expect "a mode change is visible"        '^M mode\.sh \(mode \+x\)|^new mode'
expect "hunk headers carry file:line"    '^• keep\.txt:[0-9]+:'
expect "tabs are not delta's default 8"  '^[0-9]+ {2,4}( {2}| {4})tab indented deeper'

# Delta locates the matched word in grep output by the SGR code git wrapped it
# in, and only recognises the default red (31). Spelling color.grep.match as a
# hex emits 38;2;… instead, and delta stops highlighting matches entirely — a
# change that looks like a pure colour tweak and silently costs a feature.
# Read the raw line rather than asking git: an unquoted # starts a comment in
# git config, so `git config --get` reports `bold reverse` for the broken
# `match = bold reverse #f7768e` and the check would pass on a value that is
# not even the colour its author meant.
grep_match=$(sed -n '/^\[color "grep"\]$/,/^\[/p' "$cfg" |
  sed -n 's/^[[:space:]]*match[[:space:]]*=[[:space:]]*//p')
if [[ -z "$grep_match" ]]; then
  pass "color.grep.match unset (delta's own grep-match-word-style is all there is)"
elif [[ "$grep_match" == *"#"* ]]; then
  fail "color.grep.match is a hex colour ($grep_match)" \
    "delta only recognises git's named red; a hex here kills its match highlighting"
else
  pass "color.grep.match is a named colour ($grep_match), so delta still finds matches"
fi

# git add -p pipes the diff through `delta --color-only` and pairs the result
# with the unfiltered diff line by line. Drop or add a line and the hunks it
# offers stop matching what it shows.
raw="$(git -C "$repo" --no-pager -c color.ui=always diff --cached -M)"
n_raw=$(printf '%s\n' "$raw" | wc -l | tr -d ' ')
n_filtered=$(printf '%s\n' "$raw" | delta --config "$cfg" --color-only | wc -l | tr -d ' ')
if [[ "$n_raw" == "$n_filtered" ]]; then
  pass "--color-only is line-for-line ($n_raw lines), so git add -p stays in sync"
else
  fail "--color-only changed the line count ($n_raw in, $n_filtered out)" \
    "git add -p pairs filtered output with the raw diff; it will show the wrong hunks"
fi

# --------------------------------------------------------------- 4. preview
# Assertions catch the things that can be named. Everything else about a diff
# — whether the hierarchy reads, whether a colour is too loud — has to be
# looked at, so the same fixture can be dumped in full colour.
if [[ -n "$preview" ]]; then
  echo
  echo "───── git diff ─────"
  raw_diff | paint
  echo "───── a merge conflict ─────"
  conflict="$sandbox/conflict"
  git init -q -b main "$conflict"
  (
    cd "$conflict" || exit 1
    git config user.email delta@example.com
    git config user.name "Delta Check"
    printf 'shared top\nthe contested line\nshared bottom\n' >c.txt
    git add -A && git commit -qm base
    git branch -q other
    printf 'shared top\nours won\nshared bottom\n' >c.txt && git commit -qam ours
    git checkout -q other
    printf 'shared top\ntheirs won\nshared bottom\n' >c.txt && git commit -qam theirs
    git checkout -q main
    git merge other
  ) >/dev/null 2>&1
  git -C "$conflict" --no-pager -c color.ui=always diff | paint
  echo "───── git blame ─────"
  git -C "$repo" --no-pager blame keep.txt | paint
  # Delta styles grep output only on the runs where its detection wins (see
  # docs/tokyonight.md), so this pane legitimately looks different run to run.
  # [color "grep"] is what keeps the two outcomes close.
  echo "───── git grep (delta's handler is racy; see docs) ─────"
  git -C "$repo" --no-pager -c color.ui=always grep -n -e one -e omega | paint
  echo
fi

echo
if [[ $status -eq 0 ]]; then
  echo "delta config OK"
  if [[ -z "$preview" ]]; then
    echo "(run with --preview to see the fixture rendered in colour)"
  fi
else
  echo "delta config has problems (see FAIL lines above)"
fi
exit $status
