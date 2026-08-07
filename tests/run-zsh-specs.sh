#!/usr/bin/env bash
# Run the zsh specs against the real config in this checkout.
#
#   tests/run-zsh-specs.sh              # all specs
#   tests/run-zsh-specs.sh editor       # only specs whose name matches "editor"
#
# Each spec runs in a throwaway HOME whose dotfiles are symlinks into this
# repository — the same shape `stow` produces — so the specs exercise the files
# you are about to commit and never read or write the real ~/.
#
# The shell under test is started interactively (`zsh -i -c`), because almost
# everything worth asserting about .zshrc — options, keybindings, widgets,
# completion styles — only exists in an interactive shell. --no-globalrcs keeps
# /etc/zshrc out of the picture so results do not depend on the CI image.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
repo="$PWD"

if ! command -v zsh >/dev/null 2>&1; then
  echo "zsh not found" >&2
  exit 1
fi

filter="${1:-}"

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

# Shared between specs: building the completion dump costs a few hundred
# milliseconds and nothing in it is spec-specific. HOME is *not* shared, so a
# spec that appends to its history cannot influence the next one.
export XDG_CACHE_HOME="$sandbox/cache"
mkdir -p "$XDG_CACHE_HOME"

# The fake HOME mirrors common/ with symlinks, so ~/.local in it points *into the
# checkout*. Any tool that stores state under ~/.local/share or ~/.local/state
# would therefore write into the working tree — zoxide did exactly that, and its
# database, full of the specs' temporary directories, ended up staged for commit.
# Pointing the XDG data and state directories at the sandbox keeps the checkout
# read-only for the duration of a run.
export XDG_DATA_HOME="$sandbox/data"
export XDG_STATE_HOME="$sandbox/state"
export XDG_RUNTIME_DIR="$sandbox/runtime"
mkdir -p "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"

# Mirror common/ into a fake HOME the way stow would: a symlink per entry, with
# .config expanded one level so a spec can add files under it. Anything new in
# common/ is picked up automatically.
mirror_common() {
  local dest="$1" entry name
  mkdir -p "$dest/.config"
  for entry in "$repo"/common/* "$repo"/common/.*; do
    name="$(basename "$entry")"
    case "$name" in
      . | .. | .config | '*') continue ;;
    esac
    ln -sfn "$entry" "$dest/$name"
  done
  for entry in "$repo"/common/.config/*; do
    [[ -e "$entry" ]] || continue
    ln -sfn "$entry" "$dest/.config/$(basename "$entry")"
  done
}

status=0
ran=0

# The state of the working tree before anything runs. Compared again at the end:
# a spec that writes into the checkout — through one of those ~/.local symlinks,
# or by using the repo as a scratch directory — is a bug in the spec, and one
# that otherwise shows up much later as a stray file swept into a commit.
tree_before=""
if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  tree_before="$(git status --porcelain)"
fi

for spec in tests/zsh_*_spec.zsh; do
  [[ -e "$spec" ]] || continue
  name="$(basename "$spec" .zsh)"
  if [[ -n "$filter" && "$name" != *"$filter"* ]]; then
    continue
  fi

  spec_home="$sandbox/home-$name"
  spec_tmp="$sandbox/tmp-$name"
  mkdir -p "$spec_home" "$spec_tmp"
  mirror_common "$spec_home"

  printf '\n=== %s ===\n' "$name"
  ran=$((ran + 1))

  # SPEC_REPO lets a spec reach back into the checkout (to grep a config file,
  # or run a script) without guessing where it lives.
  if HOME="$spec_home" \
    ZDOTDIR="$spec_home" \
    SPEC_TMP="$spec_tmp" \
    SPEC_REPO="$repo" \
    zsh --no-globalrcs -i -c "
      source ${repo@Q}/tests/zsh_spec_helper.zsh || exit 1
      source ${repo@Q}/${spec@Q} || exit 1
      spec_finish
    "; then
    printf '%s: OK\n' "$name"
  else
    printf '%s: FAILED\n' "$name" >&2
    status=1
  fi
done

if ((ran == 0)); then
  echo "no specs matched ${filter:-*}" >&2
  exit 1
fi

if [[ -n "$tree_before" || -n "$(git status --porcelain 2>/dev/null)" ]]; then
  tree_after="$(git status --porcelain 2>/dev/null)"
  if [[ "$tree_before" != "$tree_after" ]]; then
    printf '\nFAILED: the specs changed the working tree\n' >&2
    diff <(printf '%s\n' "$tree_before") <(printf '%s\n' "$tree_after") >&2 || true
    status=1
  fi
fi

exit "$status"
