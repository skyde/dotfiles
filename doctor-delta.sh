#!/bin/bash
# Diagnose the git → delta pager chain on this machine.
#
# Run it wherever diffs look wrong (plain, unthemed, or paged through less)
# and read the FAILs top to bottom — the first one is almost always the cause.
# Written against macOS's bash 3.2, so keep new bashisms out of here.

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n      -> %s\n' "$1" "$2"; }

echo "git:   $(git --version 2>/dev/null || echo 'not found')"
echo "delta: $(delta --version 2>/dev/null || echo 'not found')"
echo

# 1. Is the delta binary there at all? On macOS the brew formula is
#    git-delta; a plain `brew install delta` fails (no such formula).
if command -v delta >/dev/null 2>&1; then
  pass "delta is on PATH ($(command -v delta))"
else
  case "$(uname)" in
  Darwin) fix="brew install git-delta" ;;
  Linux) fix="sudo apt install git-delta" ;;
  *) fix="install git-delta with your package manager" ;;
  esac
  fail "delta is not on PATH" "$fix, then open a new terminal"
fi

# 2. Is the dotfiles git config the one git actually loads?
xdg_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/git/config"
if [ -e "$xdg_cfg" ]; then
  pass "$xdg_cfg exists"
else
  fail "$xdg_cfg is missing" "the dotfiles are not applied here — run ./apply.sh"
fi

# 3. What pager does git resolve, and from which file? ~/.gitconfig is read
#    AFTER ~/.config/git/config, so a stale core.pager there wins over ours.
pager_origin=$(git config --show-origin --get core.pager 2>/dev/null)
case "$pager_origin" in
*delta*)
  case "$pager_origin" in
  *"$xdg_cfg"*) pass "core.pager = delta, from the dotfiles config" ;;
  *) pass "core.pager = delta, but from ${pager_origin%%$'\t'*} (not the dotfiles file — fine, just unexpected)" ;;
  esac
  ;;
"") fail "core.pager is not set anywhere" "git is falling back to less; check that $xdg_cfg is the dotfiles file" ;;
*) fail "core.pager is overridden: $pager_origin" "remove core.pager from that file so the dotfiles value wins" ;;
esac

# 4. Same shadowing check for the delta section itself.
hh_origin=$(git config --show-origin --get delta.hunk-header-style 2>/dev/null)
case "$hh_origin" in
*"$xdg_cfg"*) pass "[delta] section comes from the dotfiles config" ;;
"") fail "[delta] section not found" "the dotfiles git config is not being read" ;;
*) fail "[delta] is shadowed: $hh_origin" "a later config file overrides the dotfiles [delta] section" ;;
esac

# 5. Environment overrides beat every config file.
if [ -n "$GIT_PAGER" ]; then
  case "$GIT_PAGER" in
  *delta*) pass "GIT_PAGER=$GIT_PAGER" ;;
  *) fail "GIT_PAGER=$GIT_PAGER overrides core.pager" "unset GIT_PAGER (check shell rc files)" ;;
  esac
else
  pass "GIT_PAGER is not set (config decides)"
fi

# 6. The shell fallback in .zshrc/.bashrc-custom wraps git in a function when
#    delta was missing at shell startup. This script runs in its own shell and
#    cannot see your interactive one, so check that yourself:
echo
echo "Last check, in your own shell (not this script):  type git"
echo "If it prints a function and delta is freshly installed, open a new"
echo "terminal — the wrapper decided pager-vs-less before delta existed."
