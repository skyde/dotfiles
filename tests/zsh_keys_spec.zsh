# shellcheck shell=bash
# The key bindings, tested by pressing the keys.
#
# Run with: tests/run-zsh-specs.sh keys
#
# `bindkey` can only say which widget a sequence is bound to. That is not the
# question worth asking: Home is useless if the terminal sends a sequence nobody
# bound, and a history search that returns the wrong line is bound perfectly
# well. So each key here is pressed in a real terminal and the resulting command
# line is read back.

if ! spec_can_pty; then
  spec_skip 'everything in this file' 'python3 is needed to run a shell under a pty'
  return 0
fi

spec_section 'moving around a line'

# \e[H and \e[F are the "normal mode" Home and End; \eOH and \eOF are what the
# same keys send in application mode, which is what terminfo describes and what
# you get inside tmux. Both have to work.
assert_eq 'Home goes to the start of the line' \
  'start echo hello' \
  "$(spec_pty_type 'echo hello\x1b[Hstart ')"

assert_eq 'Home works in application mode too' \
  'start echo hello' \
  "$(spec_pty_type 'echo hello\x1bOHstart ')"

assert_eq 'End goes back to the end of the line' \
  'echo hello!' \
  "$(spec_pty_type 'echo hello\x1b[H\x1b[F!')"

assert_eq 'End works in application mode too' \
  'echo hello!' \
  "$(spec_pty_type 'echo hello\x1b[H\x1bOF!')"

assert_eq 'Delete removes the character under the cursor' \
  'echo ac' \
  "$(spec_pty_type 'echo abc\x1b[D\x1b[D\x1b[3~')"

assert_eq 'Ctrl-Left moves back a word' \
  'echo one threetwo' \
  "$(spec_pty_type 'echo one two\x1b[1;5Dthree')"

assert_eq 'Ctrl-Right moves forward a word' \
  'echo one two!' \
  "$(spec_pty_type 'echo one two\x1b[H\x1b[1;5C\x1b[1;5C\x1b[1;5C!')"

spec_section 'a word ends at a path separator'

# The default WORDCHARS counts / as part of a word, so this used to delete the
# whole path — a bad surprise on a long one.
assert_eq 'Ctrl-W deletes one path component' \
  'echo a/b/' \
  "$(spec_pty_type 'echo a/b/c\x17')"

assert_eq 'Ctrl-W deletes one word, not the whole assignment' \
  'FOO=bar ' \
  "$(spec_pty_type 'FOO=bar baz\x17')"

spec_section 'Up and Down search the history for what is already typed'

# A history to search. print -s appends without running anything.
typeset -g _history_setup='
print -s "git commit -m first"
print -s "echo something else"
print -s "git commit -m second"
print -s "ls -la"
'

assert_eq 'Up finds the most recent line with the typed prefix' \
  'git commit -m second' \
  "$(spec_pty_type 'git com\x1b[A' "$_history_setup")"

assert_eq 'Up again skips past the lines that do not match' \
  'git commit -m first' \
  "$(spec_pty_type 'git com\x1b[A\x1b[A' "$_history_setup")"

# Run something for real first: see spec_pty_run_then_type for why "the last
# command" is otherwise the harness's own.
assert_eq 'Up with an empty line is still the plain history walk' \
  'echo the-last-command' \
  "$(spec_pty_run_then_type 'echo the-last-command' '\x1b[A')"

assert_eq 'Ctrl-P searches the same way' \
  'git commit -m second' \
  "$(spec_pty_type 'git com\x10' "$_history_setup")"

assert_eq 'Down comes back the way it went' \
  'git commit -m second' \
  "$(spec_pty_type 'git com\x1b[A\x1b[A\x1b[B' "$_history_setup")"

spec_section 'Alt-S puts sudo in front, and takes it away again'

assert_eq 'Alt-S adds sudo' \
  'sudo apt update' \
  "$(spec_pty_type 'apt update\x1bs')"

assert_eq 'Alt-S on a line that already has it takes it off' \
  'apt update' \
  "$(spec_pty_type 'sudo apt update\x1bs')"

# The command that runs for real is an echo: a spec should not be running a
# package manager, and what is being tested is the recall, not the command.
assert_eq 'Alt-S on an empty line recalls the last command with sudo' \
  'sudo echo needed-root' \
  "$(spec_pty_run_then_type 'echo needed-root' '\x1bs')"

spec_section 'Ctrl-Z goes back to a suspended job'

# The whole round trip: start a job, suspend it with the terminal's own Ctrl-Z,
# then press Ctrl-Z at the prompt and watch zsh report it continuing. The delay
# between the keys is not decoration — the job has to be running before it can be
# suspended.
typeset -g _ctrl_z_output
_ctrl_z_output=$(
  command python3 "$SPEC_REPO/tests/zsh_pty.py" /dev/null >/dev/null 2>&1
  local script="$SPEC_TMP/ctrl-z.zsh"
  print -r -- "builtin cd -- ${(q)SPEC_REPO}" >| "$script"
  command python3 "$SPEC_REPO/tests/zsh_pty.py" "$script" \
    --delay 1.0 --send 'sleep 40\n' --send '\x1a' --send '\x1a' 2>/dev/null
)

assert_contains 'the job suspends' 'suspended' "$_ctrl_z_output"
assert_contains 'Ctrl-Z at the prompt brings it back' 'continued' "$_ctrl_z_output"

assert_eq 'Ctrl-Z leaves a line that has been typed alone' \
  'echo keep me' \
  "$(spec_pty_type 'echo keep me\x1a')"

assert_empty 'Ctrl-Z with nothing suspended does nothing' \
  "$(spec_pty_type '\x1a')"

spec_section 'the editor is reachable from the command line'

assert_bindkey 'Ctrl-G opens the line in $EDITOR' '^G' edit-command-line
assert_bindkey 'Ctrl-X Ctrl-E does too' '^X^E' edit-command-line
assert_bindkey 'Ctrl-_ undoes' '^_' undo

spec_section 'autosuggestions'

if [[ -n ${ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE-} ]]; then
  # Named rather than fg=8: the terminal's bright black is #414868 in this
  # palette, which docs/tokyonight.md calls close to unreadable for exactly this
  # kind of de-emphasised text.
  assert_contains 'suggestions use the palette comment colour' '#565f89' \
    "$ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE"
  assert_eq 'suggestions come from history first, then completion' \
    'history completion' "${ZSH_AUTOSUGGEST_STRATEGY[*]}"
  assert_eq 'the per-prompt rebind is skipped' 1 "${ZSH_AUTOSUGGEST_MANUAL_REBIND-}"
fi
