# shellcheck shell=bash
# Assertions for the zsh specs. Sourced by tests/run-zsh-specs.sh *after* the
# real ~/.zshenv and ~/.zshrc have been read, so a spec inspects the shell the
# config actually built rather than a re-implementation of it.
#
# Everything here reports through _spec_pass/_spec_fail so one spec file can
# fail several assertions and still list them all, instead of dying on the
# first. spec_finish() prints the tally and sets the exit status.

typeset -g _spec_passed=0 _spec_failed=0 _spec_skipped=0
typeset -ga _spec_failures=()

# Where the spec may create scratch files. Removed by the driver.
: "${SPEC_TMP:=${TMPDIR:-/tmp}}"

_spec_pass() { (( ++_spec_passed )); }

_spec_fail() {
  (( ++_spec_failed ))
  _spec_failures+=("$1")
  print -r -- "  FAIL $1"
  [[ -n ${2-} ]] && print -r -- "       ${2//$'\n'/$'\n'       }"
  return 0
}

# A heading in the output. Purely cosmetic; groups related assertions.
spec_section() { print -r -- "  · $1"; }

# spec_skip <name> <reason>
#   For assertions that need an optional tool this machine does not have. Skips
#   are printed and counted but never fail: the config is built to work with any
#   subset of its tools installed, and so are its specs.
spec_skip() {
  (( ++_spec_skipped ))
  print -r -- "  SKIP $1 — $2"
  return 0
}

# spec_have <command> — true when the command exists.
spec_have() { (( $+commands[$1] )); }

# assert <name> <zsh code>
#   Passes when the code returns 0. The code is eval'd in the calling shell on
#   purpose: an assertion about `setopt` or a widget has to see this shell's
#   state, not a subshell's copy of it.
assert() {
  local name=$1 code=$2
  if eval "$code"; then
    _spec_pass
  else
    _spec_fail "$name" "expected success from: $code"
  fi
}

# refute <name> <zsh code> — passes when the code returns non-zero.
refute() {
  local name=$1 code=$2
  if eval "$code"; then
    _spec_fail "$name" "expected failure from: $code"
  else
    _spec_pass
  fi
}

assert_eq() {
  local name=$1 expected=$2 actual=$3
  if [[ $expected == "$actual" ]]; then
    _spec_pass
  else
    _spec_fail "$name" "expected: ${(qqq)expected}"$'\n'"  actual: ${(qqq)actual}"
  fi
}

assert_ne() {
  local name=$1 unexpected=$2 actual=$3
  if [[ $unexpected != "$actual" ]]; then
    _spec_pass
  else
    _spec_fail "$name" "expected anything but: ${(qqq)unexpected}"
  fi
}

# assert_contains <name> <needle> <haystack> — plain substring, no globbing.
#   Preferred over assert_match for literal text: prompt strings and zstyle
#   values are full of characters (%, ~, (, |, #) that a zsh glob would read as
#   operators, and quoting them one at a time is how a spec ends up asserting
#   something other than what it says.
assert_contains() {
  local name=$1 needle=$2 haystack=$3
  if [[ $haystack == *"$needle"* ]]; then
    _spec_pass
  else
    _spec_fail "$name" "expected to contain: ${(qqq)needle}"$'\n'"  in: ${(qqq)haystack}"
  fi
}

refute_contains() {
  local name=$1 needle=$2 haystack=$3
  if [[ $haystack == *"$needle"* ]]; then
    _spec_fail "$name" "expected not to contain ${(qqq)needle}, but: ${(qqq)haystack}"
  else
    _spec_pass
  fi
}

# assert_match <name> <pattern> <value> — pattern is a zsh glob (extended).
assert_match() {
  local name=$1 pattern=$2 value=$3
  if [[ $value == ${~pattern} ]]; then
    _spec_pass
  else
    _spec_fail "$name" "pattern: ${(qqq)pattern}"$'\n'"  value: ${(qqq)value}"
  fi
}

assert_no_match() {
  local name=$1 pattern=$2 value=$3
  if [[ $value != ${~pattern} ]]; then
    _spec_pass
  else
    _spec_fail "$name" "value unexpectedly matched ${(qqq)pattern}: ${(qqq)value}"
  fi
}

assert_empty() {
  local name=$1 value=$2
  if [[ -z $value ]]; then
    _spec_pass
  else
    _spec_fail "$name" "expected nothing, got: ${(qqq)value}"
  fi
}

assert_nonempty() {
  local name=$1 value=$2
  if [[ -n $value ]]; then
    _spec_pass
  else
    _spec_fail "$name" "expected a value, got nothing"
  fi
}

# assert_option <name> <option> <on|off>
assert_option() {
  local name=$1 opt=$2 want=$3
  local have=${options[$opt]:-<unknown option>}
  if [[ $have == "$want" ]]; then
    _spec_pass
  else
    _spec_fail "$name" "setopt $opt is '$have', expected '$want'"
  fi
}

# assert_bindkey <name> <keyseq> <widget>
#   `bindkey -- <seq>` prints e.g.  "^R" _fzf_history_widget
#   and  "^R" undefined-key  when nothing is bound.
assert_bindkey() {
  local name=$1 seq=$2 want=$3
  local line have
  line=$(bindkey -- "$seq" 2>/dev/null)
  have=${line##* }
  if [[ $have == "$want" ]]; then
    _spec_pass
  else
    _spec_fail "$name" "bindkey $seq -> ${have:-<nothing>}, expected $want"
  fi
}

# assert_widget <name> <widget> — the widget exists (so a binding can reach it).
assert_widget() {
  local name=$1 widget=$2
  if (( $+widgets[$widget] )); then
    _spec_pass
  else
    _spec_fail "$name" "no zle widget named $widget"
  fi
}

assert_function() {
  local name=$1 fn=$2
  if (( $+functions[$fn] )); then
    _spec_pass
  else
    _spec_fail "$name" "no function named $fn"
  fi
}

refute_function() {
  local name=$1 fn=$2
  if (( $+functions[$fn] )); then
    _spec_fail "$name" "function $fn should not survive startup"
  else
    _spec_pass
  fi
}

# assert_alias <name> <alias> <expected expansion>
assert_alias() {
  local name=$1 key=$2 want=$3
  local have=${aliases[$key]-}
  if [[ $have == "$want" ]]; then
    _spec_pass
  else
    _spec_fail "$name" "alias $key -> ${have:-<unset>}, expected $want"
  fi
}

refute_alias() {
  local name=$1 key=$2
  if (( $+aliases[$key] )); then
    _spec_fail "$name" "alias $key should not exist here (-> ${aliases[$key]})"
  else
    _spec_pass
  fi
}

# assert_zstyle <name> <context> <style> <pattern>
#   Checks a completion zstyle resolves to something matching <pattern>.
assert_zstyle() {
  local name=$1 context=$2 style=$3 pattern=$4
  local -a reply
  zstyle -a "$context" "$style" reply
  local joined="${(j: :)reply}"
  if [[ $joined == ${~pattern} ]]; then
    _spec_pass
  else
    _spec_fail "$name" "zstyle $context $style -> ${(qqq)joined}, wanted ${(qqq)pattern}"
  fi
}

# spec_zsh [args...]
#   A fresh zsh in the same sandbox HOME, so a spec can assert on what a real
#   new shell prints. --no-globalrcs keeps /etc/zsh* out: the specs test this
#   repo's config, not whatever the CI image ships.
spec_zsh() { command zsh --no-globalrcs "$@"; }

# spec_zsh_stderr <args...> — stderr only, stdout discarded.
spec_zsh_stderr() { spec_zsh "$@" 2>&1 >/dev/null; }

# spec_env_value <var>
#   What a fresh *non-interactive* shell computes for <var>, with the variable
#   scrubbed from the environment first. Without the scrub the child would
#   inherit the value this spec's own interactive shell already exported and the
#   assertion would pass no matter which file set it — which is exactly the
#   thing being tested for variables that belong in .zshenv rather than .zshrc.
spec_env_value() {
  local var=$1
  command env -u "$var" zsh --no-globalrcs -c "print -r -- \${$var-}" 2>/dev/null
}

# spec_pty_capture <zsh code>
#   Runs the code in an interactive shell that has a real terminal, and returns
#   what it printed. For the parts of the config that only exist with a terminal
#   attached — fzf's key bindings, anything looked up through zsh/terminfo, the
#   line editor itself.
#
#   The code's output is redirected to a file inside the pty rather than read
#   back off the terminal, so none of it has to be recovered from the echo of the
#   input or from the prompt drawn around it.
spec_pty_capture() {
  local code=$1
  local script="$SPEC_TMP/pty-script.zsh" out="$SPEC_TMP/pty-output"
  {
    print -r -- "{"
    print -r -- "$code"
    print -r -- "} >| ${(q)out} 2>&1"
  } >| "$script"
  : >| "$out"
  command python3 "$SPEC_REPO/tests/zsh_pty.py" "$script" >/dev/null 2>&1
  print -r -- "$(<$out)"
}

# spec_can_pty — true when a pty-backed shell can be run at all.
spec_can_pty() { (( $+commands[python3] )); }

# spec_pty_type <keys> [setup code]
#   Types <keys> at a real prompt and returns the command line that resulted.
#   This is how a binding gets tested by pressing the key rather than by asking
#   `bindkey` what it thinks is bound: Tab really completes, an arrow really
#   searches the history.
#
#   The line is read back through a widget of our own on Ctrl-X Ctrl-X, which
#   writes $BUFFER to a file. Reading it off the terminal instead would mean
#   separating it from the echo, the prompt, the autosuggestion and the syntax
#   highlighting's redraws.
spec_pty_type() {
  local keys=$1 setup=${2-}
  _spec_pty_write_script "$setup"
  command python3 "$SPEC_REPO/tests/zsh_pty.py" "$SPEC_TMP/pty-type.zsh" \
    --send "$keys" --send '\x18\x18' >/dev/null 2>&1
  print -r -- "$(<$SPEC_TMP/pty-buffer)"
}

# spec_pty_run_then_type <command> <keys> [setup code]
#   Runs a command at the prompt for real, then types <keys>, and returns the
#   command line that resulted.
#
#   For anything that depends on what the *last* command was. The harness types
#   its own scaffolding with a leading space so hist_ignore_space keeps it out of
#   the history — but that only half works by design: zsh keeps such a line in the
#   internal history until the next command is entered, "allowing you to briefly
#   reuse or edit the line", so until something else runs it is what Up recalls.
#   Running one real command clears it and makes the answer the spec's own.
spec_pty_run_then_type() {
  local command=$1 keys=$2 setup=${3-}
  _spec_pty_write_script "$setup"
  # A delay between the two, so the command has run and the editor is back
  # before the keys arrive.
  command python3 "$SPEC_REPO/tests/zsh_pty.py" "$SPEC_TMP/pty-type.zsh" \
    --delay 0.6 --send "$command\\n" --send "$keys" --send '\x18\x18' \
    >/dev/null 2>&1
  print -r -- "$(<$SPEC_TMP/pty-buffer)"
}

# spec_pty_raw <keys> [setup code] [delay]
#   Everything the terminal emitted, escape sequences and all. For the things a
#   shell says to the terminal rather than to the user — the title, in
#   particular, which has no other way of being observed.
spec_pty_raw() {
  local keys=$1 setup=${2-} delay=${3-0}
  _spec_pty_write_script "$setup"
  command python3 "$SPEC_REPO/tests/zsh_pty.py" "$SPEC_TMP/pty-type.zsh" \
    --delay "$delay" --send "$keys" 2>/dev/null
}

_spec_pty_write_script() {
  local setup=$1
  local script="$SPEC_TMP/pty-type.zsh" out="$SPEC_TMP/pty-buffer"
  : >| "$out"
  {
    print -r -- "_spec_report_buffer() { print -r -- \"\$BUFFER\" >| ${(q)out} }"
    print -r -- 'zle -N _spec_report_buffer'
    print -r -- "bindkey '^X^X' _spec_report_buffer"
    print -r -- "builtin cd -- ${(q)SPEC_REPO}"
    [[ -n $setup ]] && print -r -- "$setup"
  } >| "$script"
}

# spec_stub <name> <shell body>
#   Puts an executable of that name first on PATH and prints its path. Lets a
#   spec exercise a wrapper function — `gg`, `e`, `code`, the git wrapper —
#   against a stand-in that records how it was called, on a machine where the
#   real tool may not be installed at all.
#
#   The stub is /bin/sh, not zsh: it stands in for an arbitrary binary, and a
#   spec should not accidentally depend on zsh syntax being available to it.
spec_stub() {
  local name=$1 body=$2
  local dir="$SPEC_TMP/stub-bin"
  [[ -d $dir ]] || mkdir -p -- "$dir"
  {
    print -r -- '#!/bin/sh'
    print -r -- "$body"
  } >| "$dir/$name"
  chmod +x -- "$dir/$name"
  # Prepended, and any earlier copy of the directory dropped, so repeated calls
  # cannot grow PATH. Assigning to path clears zsh's command hash table, so the
  # new stub is found even where a real binary of the same name was cached.
  path=("$dir" ${path:#$dir})
  print -r -- "$dir/$name"
}

# spec_unstub — drop the stub directory from PATH again.
spec_unstub() {
  local dir="$SPEC_TMP/stub-bin"
  path=(${path:#$dir})
}

# spec_bare_path
#   A PATH holding only the handful of binaries any machine has, so a spec can
#   check the config degrades cleanly on a box where none of the optional tools
#   (starship, fzf, bat, eza, zoxide, delta...) are installed. Built once and
#   cached in $SPEC_TMP.
spec_bare_path() {
  local dir="$SPEC_TMP/bare-bin"
  if [[ ! -d $dir ]]; then
    mkdir -p -- "$dir"
    local tool src
    # zsh itself has to be reachable: a spec that asserts on a nested shell's
    # output still needs to be able to start one.
    #
    # `mv` is not optional either, and its absence is not obvious: zsh's own
    # compdump shells out to it when writing the completion dump, so a cold cache
    # under a PATH without it prints "compdump:138: command not found: mv" and
    # every "startup is silent" assertion fails for a reason that has nothing to
    # do with the config. A machine with no fzf still has coreutils.
    # python3 is in the list for the harness's sake — tests/zsh_pty.py needs it
    # to open a terminal — not because the shell ever looks for it.
    for tool in zsh sh cat cp mv rm ls mkdir mktemp stty tput uname sed awk grep git tr touch python3; do
      # `whence -p`, not `command -v`: this shell has `cat` aliased to bat and
      # `git` wrapped in a function, and command -v answers with the alias text
      # ("alias cat=batcat") or the bare function name. Those became symlinks to
      # nothing — `git -> git`, pointing at itself — so anything in the config
      # that shells out to git in the bare environment silently did nothing, and
      # a spec that checked for its effect failed for a reason that was entirely
      # the harness's.
      src=$(whence -p -- "$tool" 2>/dev/null) || continue
      ln -sf -- "$src" "$dir/$tool"
    done
  fi
  print -r -- "$dir"
}

spec_finish() {
  local skipped=""
  (( _spec_skipped )) && skipped=", ${_spec_skipped} skipped"
  print -r -- ""
  if (( _spec_failed )); then
    print -r -- "  ${_spec_passed} passed, ${_spec_failed} failed${skipped}:"
    local failure
    for failure in "${_spec_failures[@]}"; do
      print -r -- "    - $failure"
    done
    return 1
  fi
  print -r -- "  ${_spec_passed} passed${skipped}"
  return 0
}
