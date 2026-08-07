# shellcheck shell=bash
# Startup hygiene: what every new shell must and must not do.
#
# Run with: tests/run-zsh-specs.sh startup
#
# The theme running through this file is that a shell starts *quietly*. A stray
# line on stderr is not cosmetic — it lands in the middle of `ssh host command`
# output, it confuses tools that parse a shell's output, and on a machine
# missing one optional tool it repeats on every single prompt.

spec_section 'a new shell says nothing'

assert_empty 'interactive startup writes nothing to stderr' \
  "$(spec_zsh_stderr -i -c true)"

assert_empty 'interactive startup writes nothing to stdout' \
  "$(spec_zsh -i -c true 2>/dev/null)"

assert_empty 'login shell startup writes nothing to stderr' \
  "$(spec_zsh_stderr -l -i -c true)"

assert_empty 'non-interactive startup writes nothing to stderr' \
  "$(spec_zsh_stderr -c true)"

assert_empty 'non-interactive startup writes nothing to stdout' \
  "$(spec_zsh -c true 2>/dev/null)"

# The one that keeps the config honest: a box with none of the optional tools
# installed. Every `eval "$(some-tool init zsh)"` has to be guarded, or the
# first shell on a fresh machine greets you with "command not found".
spec_section 'a shell on a machine with no optional tools installed'

typeset -g _bare_path
_bare_path=$(spec_bare_path)

assert_empty 'startup is silent with none of the optional tools on PATH' \
  "$(PATH=$_bare_path spec_zsh_stderr -i -c true)"

assert_empty 'non-interactive startup is silent without the optional tools' \
  "$(PATH=$_bare_path spec_zsh_stderr -c true)"

# A shell that survives startup but cannot run a command is no better.
assert_eq 'the shell still works without the optional tools' \
  'alive' \
  "$(PATH=$_bare_path spec_zsh -i -c 'print -r -- alive' 2>/dev/null)"

spec_section 'environment that scripts and editors depend on'

# EDITOR has to come from .zshenv, not .zshrc: `git commit` from a script, a
# `sudoedit`, or any non-interactive `zsh -c` reads it too, and none of those
# ever source .zshrc.
assert_eq 'EDITOR is set for non-interactive shells' 'nvim' \
  "$(spec_env_value EDITOR)"

assert_eq 'VISUAL matches EDITOR for non-interactive shells' 'nvim' \
  "$(spec_env_value VISUAL)"

assert_eq 'RIPGREP_CONFIG_PATH points at the stowed config' \
  "$HOME/.ripgreprc" \
  "$(spec_env_value RIPGREP_CONFIG_PATH)"

assert_nonempty 'BAT_THEME is set' "$(spec_env_value BAT_THEME)"

spec_section 'PATH'

local -a unique_path
unique_path=(${(u)path})
assert_eq 'PATH has no duplicate entries' "${#path}" "${#unique_path}"

assert_match 'user bins come before the system ones' \
  "*:$HOME/.local/bin:*" ":${(j.:.)path}:"

assert 'every PATH entry is an absolute path' \
  '[[ -z ${(M)path:#[^/]*} ]]'

# .zshenv is read again by every nested zsh. If PATH grew each time, a shell
# five levels deep inside tmux/ssh/make would carry five copies of every entry
# and `command -v` would slow down for good.
assert_eq 'PATH is unchanged by a nested shell' \
  "$(spec_zsh -c 'print -r -- $PATH' 2>/dev/null)" \
  "$(spec_zsh -c 'print -r -- $(zsh --no-globalrcs -c "print -r -- \$PATH")' 2>/dev/null)"

spec_section 'no malformed values'

# An empty command substitution used to leave DISPLAY=":" behind, which is not
# a display any X client can parse.
assert_no_match 'DISPLAY is never a bare colon' ':' "${DISPLAY-}"
assert 'DISPLAY is either unset or well formed' \
  '[[ -z ${DISPLAY-} || ${DISPLAY} == (:|*:)<->(|.<->) || ${DISPLAY} == *:<->(|.<->) ]]'

spec_section 'startup leaves no litter behind'

# Helpers and scratch variables that exist only to build the shell should not
# still be sitting in the namespace afterwards, where they shadow a real
# command name or get picked up by a later `unset`.
refute_function 'the plugin-sourcing helper is unset after use' _source_zsh_plugin

local leaked var
leaked=()
for var in _compdump _x_sockets _fzf_tn _bare _plugin_path; do
  (( ${(P)+var} )) && leaked+=("$var")
done
assert_empty 'no scratch variables leak into the shell' "${(j:, :)leaked}"

spec_section 'history'

assert_eq 'history file lives in HOME' "$HOME/.zsh_history" "$HISTFILE"
assert 'history is large enough to be worth searching' '(( HISTSIZE >= 50000 ))'
assert 'the saved history is at least as large as the in-memory one' \
  '(( SAVEHIST >= HISTSIZE ))'

assert_option 'duplicate commands are not stored' hist_ignore_all_dups on
assert_option 'a leading space keeps a command out of history' hist_ignore_space on
assert_option 'history is shared between running shells' share_history on
assert_option 'timestamps are recorded' extended_history on
assert_option 'blank runs of whitespace are tidied first' hist_reduce_blanks on
assert_option 'history expansion is confirmed before running' hist_verify on

spec_section 'options that make the shell pleasant'

assert_option 'a bare directory name changes to it' autocd on
assert_option 'globs ignore case' nocaseglob on
assert_option 'globs see dotfiles' globdots on
assert_option 'extended glob operators are available' extended_glob on
assert_option 'comments are allowed at an interactive prompt' interactive_comments on
assert_option 'the terminal never beeps' beep off
assert_option 'cd pushes onto the directory stack' auto_pushd on
assert_option 'the directory stack holds no duplicates' pushd_ignore_dups on
