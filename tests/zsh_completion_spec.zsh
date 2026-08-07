# shellcheck shell=bash
# Completion, tested by pressing Tab.
#
# Run with: tests/run-zsh-specs.sh completion
#
# The matching rules are the part of a zsh config most likely to be wrong while
# looking right: a match specification that does nothing produces no error, and
# `zstyle -L` will happily read it back to you. So each rule here is exercised
# through a real terminal — type a prefix, press Tab, read the command line back —
# against files that live in this repository.

if ! spec_can_pty; then
  spec_skip 'everything in this file' 'python3 is needed to run a shell under a pty'
  return 0
fi

spec_section 'the completion system is set up'

assert_function 'compdef is available' compdef
assert_zstyle 'a completion menu is offered' ':completion:*' menu '*select*'
assert_zstyle 'completions are grouped by kind' ':completion:*' group-name '*'
assert_zstyle 'group descriptions are formatted' ':completion:*:descriptions' format '*%d*'
assert_zstyle 'expensive completions are cached' ':completion:*' use-cache 'on'
assert_zstyle 'the completion cache lives with the other caches' \
  ':completion:*' cache-path "*zcompcache*"

assert_option 'a word can be completed from the middle' complete_in_word on
assert_option 'the cursor ends up after the completed word' always_to_end on

spec_section 'Tab completes'

assert_eq 'a unique match completes in full' \
  'ls tests/zsh_tools_spec.zsh ' \
  "$(spec_pty_type 'ls tests/zsh_tools_s\t')"

# Two candidates (tests/ and test-all-platforms.sh) share "test", and that is
# how much gets inserted. This is the assertion that catches an over-eager
# matcher: with substring matching switched on, every file *containing* "te" is a
# candidate, there is no common prefix, and Tab does nothing at all.
assert_eq 'an ambiguous match inserts the common prefix' \
  'ls test' \
  "$(spec_pty_type 'ls te\t')"

assert_eq 'a directory completes with its slash' \
  'cd tests/' \
  "$(spec_pty_type 'cd tes\t')"

spec_section 'Tab is not fussy about case'

assert_eq 'a wrongly-capitalised directory still completes' \
  'ls tests/zsh_tools_spec.zsh ' \
  "$(spec_pty_type 'ls TESTS/zsh_tools_s\t')"

# Two files start with README, so the common prefix is inserted — with the
# capitalisation of the files rather than the capitalisation that was typed.
assert_eq 'a lowercase prefix finds an uppercase name' \
  'ls README' \
  "$(spec_pty_type 'ls readme\t')"

spec_section 'Tab completes word by word'

# The rule that makes long names bearable: type the initials of the parts.
# `r:|[._-]=** r:|=**` — with `**`, not the `*` that most configs carry and that
# silently matches nothing.
assert_eq 'initials separated by underscores complete' \
  'ls tests/zsh_tools_spec.zsh ' \
  "$(spec_pty_type 'ls tests/z_t_s\t')"

assert_eq 'initials separated by dashes complete' \
  'ls tests/run-zsh-specs.sh ' \
  "$(spec_pty_type 'ls tests/r-z-s\t')"

spec_section 'a glob completes to what it matches'

# _match, the one extra completer that is carried, and the only one that could be
# shown to do anything.
assert_eq 'a pattern completes to the file it matches' \
  'ls tests/zsh_pty.py' \
  "$(spec_pty_type 'ls tests/zsh_p*y\t')"

spec_section 'completion does not reach for things it cannot use'

assert_zstyle 'the completion system hides its own internals' \
  ':completion:*:functions' ignored-patterns '_\*'

assert_zstyle 'kill lists this user processes' \
  ':completion:*:*:kill:*:processes' command '*ps -u*'

assert_zstyle 'cd does not offer the directory you are in' \
  ':completion:*:cd:*' ignore-parents 'parent pwd'
