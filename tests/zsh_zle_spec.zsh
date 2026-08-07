# shellcheck shell=bash
# The parts of the shell that only exist with a terminal attached.
#
# Run with: tests/run-zsh-specs.sh zle
#
# fzf's key bindings are deliberately not loaded by a shell without a terminal
# (see the comment in .zshrc), so a `zsh -i -c` shell — which is what the other
# specs use — cannot see them. These run under a pty instead, via
# tests/zsh_pty.py.

if ! spec_can_pty; then
  spec_skip 'everything in this file' 'python3 is needed to run a shell under a pty'
  return 0
fi

spec_section 'a shell with a terminal still starts quietly'

# The same invariant as zsh_startup_spec, checked where the interesting code
# path actually runs. Anything printed here appears above the first prompt of
# every terminal window.
typeset -g _pty_noise
_pty_noise=$(spec_pty_capture 'print -r -- "---startup was quiet---"')
assert_eq 'nothing is printed before the prompt' \
  '---startup was quiet---' "$_pty_noise"

spec_section 'fzf key bindings'

if spec_have fzf; then
  typeset -g _bindings
  _bindings=$(spec_pty_capture '
    for key in "^T" "^R" "\ec" "^I"; do
      print -r -- "$key = $(bindkey -- $key)"
    done
    print -r -- "fzf-completion widget: ${+widgets[fzf-completion]}"
  ')

  # Ctrl-T (paste a path) and Alt-C (cd into a directory) were in
  # .bashrc-custom but not .zshrc, so the shell in daily use was the one
  # without them.
  assert_contains 'Ctrl-T pastes a path' 'fzf-file-widget' "$_bindings"
  assert_contains 'Alt-C changes directory' 'fzf-cd-widget' "$_bindings"

  # Ours has to win over fzf's own history widget, which its key bindings put
  # on Ctrl-R when they load.
  assert_contains 'Ctrl-R is the local history widget' \
    '^R = "^R" _fzf_history_widget' "$_bindings"
  refute_contains 'Ctrl-R is not fzf-history-widget' \
    'fzf-history-widget' "$_bindings"

  assert_contains 'Tab goes through fzf completion' 'fzf-completion' "$_bindings"
else
  spec_skip 'fzf key bindings' 'fzf is not installed'
fi

spec_section 'the fzf integration is cached, not re-derived'

if spec_have fzf; then
  assert 'the fzf integration is cached on disk' \
    '[[ -s $ZSH_CACHE_DIR/fzf-init.zsh ]]'
  assert 'the cached fzf integration is byte-compiled' \
    '[[ -s $ZSH_CACHE_DIR/fzf-init.zsh.zwc ]]'
fi

spec_section 'the terminal title'

# Every window said "zsh" before this: the line that was supposed to set a title
# sourced a file that does not exist. tmux is not the point — it names its own
# windows and has allow-rename off — the kitty tab and the OS window are.
typeset -g _title_output
_title_output=$(spec_pty_raw 'sleep 2\n' '' 1.0)

assert_contains 'at the prompt the title is the working directory' \
  $'\e]0;'"$SPEC_REPO" "$_title_output"

assert_contains 'while a command runs the title is the command' \
  $'\e]0;sleep 2' "$_title_output"

assert_contains 'and the directory it is running in' \
  "sleep 2 — $SPEC_REPO" "$_title_output"

spec_section 'a shell without a terminal skips the widget machinery'

# Not merely an optimisation: fzf's files restore the whole option array in one
# eval, and without a terminal that tries to set the read-only `zle` option and
# writes "can't change option: zle" to stderr.
assert_empty 'no option-restore warning without a terminal' \
  "$(spec_zsh_stderr -i -c true)"
