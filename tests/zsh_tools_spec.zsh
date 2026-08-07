# shellcheck shell=bash
# The wrapper functions and aliases: yazi, lf, lazygit, code, git, and the
# aliases that stand in for a tool the machine may not have.
#
# Run with: tests/run-zsh-specs.sh tools
#
# Almost everything here runs against a stub binary rather than the real tool.
# That is not only so the specs pass on a bare machine: a stub can record how it
# was called, which is the part of a wrapper that actually breaks.

# Recorded before any stub goes on PATH: some assertions are about what the
# config decided *at startup*, and a stub added later would answer for the
# machine the spec has built rather than the one the shell started on.
typeset -g _had_delta=$+commands[delta]
typeset -g _had_code=$+commands[code]

spec_section 'gg (lazygit)'

assert_function 'gg is defined' gg

typeset -g _record="$SPEC_TMP/record"
spec_stub lazygit "printf '%s\n' \"\$@\" > ${(qqq)_record}" >/dev/null

: >| "$_record"
gg log --filter=foo
assert_eq 'gg forwards its arguments to lazygit' \
  $'log\n--filter=foo' "$(<$_record)"

spec_section 'e (yazi)'

assert_function 'e is defined' e

# yazi reports where it ended up by writing that path to --cwd-file. The stub
# writes whatever SPEC_STUB_CWD says, so both outcomes can be exercised.
spec_stub yazi '
for arg in "$@"; do
  case "$arg" in
    --cwd-file=*) out="${arg#--cwd-file=}" ;;
  esac
done
printf "%s\n" "$SPEC_STUB_CWD" > "$out"
' >/dev/null

typeset -g _target="$SPEC_TMP/jump-target"
[[ -d $_target ]] || mkdir -p -- "$_target"

typeset -g _origin=$PWD
SPEC_STUB_CWD=$_target e
assert_eq 'e follows yazi to the directory it exited in' "$_target" "$PWD"
builtin cd -- "$_origin"

# The bug this pins down: `... && builtin cd -- "$cwd" || return` returned 1
# whenever the test was false, so quitting yazi in the directory you started in
# left $? at 1 and the prompt drew an error marker for a successful visit.
SPEC_STUB_CWD=$PWD e
assert_eq 'e succeeds when yazi exits where it started' 0 "$?"
assert_eq 'e stays put when yazi exits where it started' "$_origin" "$PWD"

# An empty cwd-file (yazi killed before it wrote anything) must not move us to
# the filesystem root or to $HOME.
SPEC_STUB_CWD='' e
assert_eq 'e succeeds when yazi wrote no directory' 0 "$?"
assert_eq 'e stays put when yazi wrote no directory' "$_origin" "$PWD"

spec_section 'lfcd (lf)'

assert_function 'lfcd is defined' lfcd
assert_alias 'lf runs lfcd' lf lfcd

spec_stub lf '
prev=""
for arg in "$@"; do
  case "$prev" in
    -last-dir-path) out="$arg" ;;
  esac
  prev="$arg"
done
printf "%s\n" "$SPEC_STUB_CWD" > "$out"
' >/dev/null

SPEC_STUB_CWD=$_target lfcd
assert_eq 'lfcd follows lf to the directory it exited in' "$_target" "$PWD"
builtin cd -- "$_origin"

SPEC_STUB_CWD=$PWD lfcd
assert_eq 'lfcd succeeds when lf exits where it started' 0 "$?"
assert_eq 'lfcd stays put when lf exits where it started' "$_origin" "$PWD"

spec_section 'a missing file manager reports itself'

# With no yazi anywhere, `e` used to run "" and report `command not found:` with
# nothing after the colon.
# HOME is redirected too, not just PATH: this repo installs its own yazi
# wrapper at ~/.local/bin/yazi, which `e` prefers, so a bare PATH alone still
# finds a yazi. ZDOTDIR keeps pointing at the config under test.
typeset -g _empty_home="$SPEC_TMP/home-without-tools"
[[ -d $_empty_home ]] || mkdir -p -- "$_empty_home"
typeset -g _missing_out
_missing_out=$(HOME=$_empty_home PATH=$(spec_bare_path) spec_zsh -i -c 'e' 2>&1)
assert_contains 'e names the tool that is missing' 'yazi' "$_missing_out"
assert_no_match 'e does not report an empty command' '*not found: (|)$' "$_missing_out"

spec_section 'code (VS Code remote IPC socket)'

assert_function 'code is defined' code

# Two sockets: one nothing is listening on, one with a live listener. code()
# has to skip the dead one and export the live one, because VS Code leaves the
# sockets of previous sessions lying around and writing to a stale one hangs.
typeset -g _sockdir="$SPEC_TMP/sockets"
[[ -d $_sockdir ]] || mkdir -p -- "$_sockdir"
typeset -g _dead="$_sockdir/vscode-ipc-dead.sock" _live="$_sockdir/vscode-ipc-live.sock"

if (( $+commands[python3] )); then
  command rm -f -- "$_dead" "$_live"
  # A listener that stays up for the length of this spec and is never connected
  # to by anything else.
  python3 -c '
import socket, sys, time
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sys.argv[1])
s.listen(1)
sys.stdout.write("ready\n")
sys.stdout.flush()
time.sleep(60)
' "$_live" >"$SPEC_TMP/listener-ready" &
  typeset -g _listener=$!
  # The dead socket is a plain socket file with nobody accepting on it.
  python3 -c '
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sys.argv[1])
' "$_dead"

  # Wait for the listener rather than sleeping a guessed interval.
  typeset -g _waited=0
  while [[ ! -s $SPEC_TMP/listener-ready ]] && (( _waited < 200 )); do
    command sleep 0.01
    (( ++_waited ))
  done

  spec_stub code 'exit 0' >/dev/null

  # A plain assignment, not a `VAR= code ...` prefix: zsh restores a prefix
  # assignment when the function returns, so the export inside code() would be
  # undone before it could be checked.
  VSCODE_IPC_HOOK_CLI=''
  VSCODE_IPC_SOCKET_DIRS=$_sockdir code
  assert_eq 'code picks the socket something is listening on' "$_live" "${VSCODE_IPC_HOOK_CLI-}"

  kill "$_listener" 2>/dev/null
  wait "$_listener" 2>/dev/null

  # The code stub has to go before the git wrapper is exercised: that wrapper
  # decides which fallbacks to pass on *every call*, so a `code` on PATH — even
  # a stub — is enough to make it stop adding a terminal merge tool.
  command rm -f -- "$SPEC_TMP/stub-bin/code"
  rehash
else
  spec_skip 'code socket selection' 'python3 is not available to hold a socket open'
fi

spec_section 'git wrapper'

# The wrapper only exists when delta or code is missing — on a fully equipped
# machine plain git is already correct and no function should shadow it.
if (( _had_delta && _had_code )); then
  refute_function 'no git wrapper is installed when every tool is present' git
else
  assert_function 'git is wrapped when a tool it relies on is missing' git

  spec_stub git "printf '%s\n' \"\$@\" > ${(qqq)_record}" >/dev/null
  : >| "$_record"
  git status >/dev/null 2>&1
  typeset -g _git_args="$(<$_record)"

  if (( ! _had_delta )); then
    assert_contains 'git is told to page through less when delta is missing' \
      'core.pager=less' "$_git_args"
  fi
  if (( ! _had_code )); then
    assert_contains 'git is given a terminal merge tool when code is missing' \
      'merge.tool=' "$_git_args"
  fi
  assert_contains 'the real subcommand still gets through' 'status' "$_git_args"
fi

spec_unstub

spec_section 'GIT_PAGER'

# GIT_PAGER in the environment overrides core.pager, which is how delta ends up
# silently switched off for a whole shell.
assert_empty 'a GIT_PAGER that bypasses delta is cleared' \
  "$(GIT_PAGER=cat spec_zsh -i -c 'print -r -- ${GIT_PAGER-}' 2>/dev/null)"

assert_eq 'a GIT_PAGER that already uses delta is left alone' \
  'delta --side-by-side' \
  "$(GIT_PAGER='delta --side-by-side' spec_zsh -i -c 'print -r -- ${GIT_PAGER-}' 2>/dev/null)"

spec_section 'aliases stand in for tools by their real name'

if (( $+commands[eza] )); then
  assert_contains 'ls is eza' 'eza' "${aliases[ls]-}"
  assert_contains 'll is a long listing' '-al' "${aliases[ll]-}"
  assert_contains 'directories are grouped first' '--group-directories-first' "${aliases[ls]-}"
else
  refute_alias 'ls is left alone when eza is missing' ls
fi

if (( $+commands[bat] )); then
  assert_alias 'cat is bat' cat 'bat'
elif (( $+commands[batcat] )); then
  assert_alias 'cat is batcat on Debian' cat 'batcat'
  assert_alias 'bat is batcat on Debian' bat 'batcat'
else
  refute_alias 'cat is left alone when bat is missing' cat
fi

# fd is packaged as fdfind on Debian and Ubuntu because the name was taken.
if (( ! $+commands[fd] && $+commands[fdfind] )); then
  assert_alias 'fd is fdfind on Debian' fd 'fdfind'
fi

assert_contains 'grep colours its output' '--color=auto' "${aliases[grep]-}"

spec_section 'fzf pickers know what to list and how to preview it'

if spec_have fzf; then
  # Unset means "fall back to fzf's own walker", which still works — so these
  # are only asserted where fd, the tool they are built on, exists.
  if (( $+commands[fd] || $+commands[fdfind] )); then
    assert_contains 'Ctrl-T lists hidden files too' '--hidden' \
      "$(spec_env_value FZF_CTRL_T_COMMAND)"
    assert_contains 'Ctrl-T skips .git' '--exclude .git' \
      "$(spec_env_value FZF_CTRL_T_COMMAND)"
    assert_contains 'Alt-C lists only directories' '--type d' \
      "$(spec_env_value FZF_ALT_C_COMMAND)"
  fi

  if (( $+commands[fzf-preview] )); then
    assert_contains 'Ctrl-T previews the highlighted path' 'fzf-preview' \
      "$(spec_env_value FZF_CTRL_T_OPTS)"
    assert_contains 'Alt-C previews the highlighted directory' 'fzf-preview' \
      "$(spec_env_value FZF_ALT_C_OPTS)"
  fi
fi

spec_section 'fzf-preview'

if (( $+commands[fzf-preview] )); then
  # A preview pane that comes up empty or spills an error is worse than a plain
  # one, so each kind of target is checked for something recognisable.
  assert_contains 'a directory shows what is in it' 'zsh_tools_spec' \
    "$(FZF_PREVIEW_COLUMNS=80 fzf-preview "$SPEC_REPO/tests" 2>&1)"

  assert_contains 'a text file shows its contents' 'shellcheck shell' \
    "$(FZF_PREVIEW_COLUMNS=80 fzf-preview "$SPEC_REPO/tests/zsh_tools_spec.zsh" 2>&1)"

  # "path:line" is what the st-* pickers pass; the window has to land on the
  # line, not at the top of the file.
  typeset -g _numbered="$SPEC_TMP/numbered.txt"
  : >| "$_numbered"
  for i in {1..400}; do print -r -- "line-$i" >> "$_numbered"; done
  typeset -g _line_preview
  _line_preview=$(FZF_PREVIEW_COLUMNS=80 FZF_PREVIEW_LINES=20 fzf-preview "$_numbered:300" 2>&1)
  assert_contains 'a line reference previews around that line' 'line-300' "$_line_preview"
  refute_contains 'a line reference does not preview from the top' 'line-1 ' "$_line_preview"

  assert_contains 'a binary reports its type instead of its bytes' 'size:' \
    "$(fzf-preview "${commands[zsh]}" 2>&1)"

  # fzf runs the preview for whatever is highlighted, including a path that has
  # just been deleted; it must not spill a shell error into the pane.
  typeset -g _missing_preview
  _missing_preview=$(fzf-preview "$SPEC_TMP/definitely-not-here" 2>&1)
  assert_eq 'a missing path previews cleanly' 0 "$?"
  assert_contains 'a missing path says so' 'no such file' "$_missing_preview"
else
  spec_skip 'fzf-preview' 'fzf-preview is not on PATH (~/.local/bin not stowed?)'
fi

spec_section 'man pages'

if (( $+commands[bat] || $+commands[batcat] )); then
  assert_contains 'man pages are rendered by bat' 'bat' "$(spec_env_value MANPAGER)"
  assert_eq 'groff is told not to add overstrike escapes' '-c' "$(spec_env_value MANROFFOPT)"
fi
