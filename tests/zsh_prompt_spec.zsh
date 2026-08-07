# shellcheck shell=bash
# The prompt, and the on-disk cache that keeps `tool init zsh` out of startup.
#
# Run with: tests/run-zsh-specs.sh prompt

spec_section 'prompt'

assert_nonempty 'a prompt is set' "$PS1"
assert_nonempty 'a continuation prompt is set' "$PS2"

if spec_have starship; then
  assert_contains 'the prompt is starship' 'starship' "$PS1"
  assert_function 'starship installed its precmd hook' prompt_starship_precmd

  # The cache bakes in the value of `starship prompt --continuation` to save a
  # fork. If that ever diverges from what starship would print, multi-line
  # commands get the wrong continuation marker — which is subtle enough that
  # only a test would catch it.
  assert_eq 'the cached continuation prompt matches starship' \
    "$(starship prompt --continuation)" "$PS2"
else
  spec_skip 'starship prompt assertions' 'starship is not installed'

  # The fallback prompt matters most on a machine where starship is missing, so
  # it is checked whenever that is the case for real.
  assert_contains 'the fallback prompt shows the working directory' '%~' "$PS1"
  assert_function 'the fallback prompt tracks git state' vcs_info
fi

# Whichever prompt is in play, a bare machine must still get a usable one rather
# than zsh's default `host%`.
spec_section 'the prompt on a machine with no optional tools'

typeset -g _bare_prompt
_bare_prompt=$(PATH=$(spec_bare_path) spec_zsh -i -c 'print -r -- $PS1' 2>/dev/null)
assert_contains 'the fallback prompt is used when starship is missing' '%~' "$_bare_prompt"
assert_contains 'the fallback prompt reports the last exit status' '%(?.' "$_bare_prompt"

# What the fallback actually *draws*, not what its format string says. vcs_info
# needs a precmd hook, a zstyle and prompt_subst all in agreement, and a mistake
# in any of the three shows up as a prompt with no branch on it — which nobody
# would notice on a machine where starship is installed.
if spec_can_pty; then
  typeset -g _bare_drawn _branch
  _branch=$(command git -C "$SPEC_REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)
  _bare_drawn=$(PATH=$(spec_bare_path) spec_pty_raw 'true\n' '' 0.7)
  assert_contains 'the fallback prompt draws the working directory' \
    "$SPEC_REPO" "$_bare_drawn"
  if [[ -n $_branch ]]; then
    assert_contains 'the fallback prompt draws the git branch' \
      "$_branch" "$_bare_drawn"
  fi
fi

spec_section 'the init cache'

assert_function '_zcache_source is available' _zcache_source
assert_nonempty 'the cache directory is set' "$ZSH_CACHE_DIR"
assert "the cache directory exists" '[[ -d $ZSH_CACHE_DIR ]]'

if spec_have starship; then
  assert 'the starship init is cached on disk' \
    '[[ -s $ZSH_CACHE_DIR/starship-init.zsh ]]'
  assert 'the cached starship init is byte-compiled' \
    '[[ -s $ZSH_CACHE_DIR/starship-init.zsh.zwc ]]'
  assert 'the cached init does not re-run starship for the continuation prompt' \
    '! grep -q "PROMPT2=\\\$(" $ZSH_CACHE_DIR/starship-init.zsh'
fi

if spec_have zoxide; then
  assert 'the zoxide init is cached on disk' \
    '[[ -s $ZSH_CACHE_DIR/zoxide-init.zsh ]]'
  assert_function 'zoxide is initialized eagerly, so z works immediately' __zoxide_z
fi

spec_section 'the init cache rebuilds when it should'

# Exercised with a generator of our own rather than a real tool, so the
# behaviour is checked the same way on every machine.
typeset -g _gen_count=0
_spec_generator() {
  (( ++_gen_count ))
  print -r -- "typeset -g SPEC_CACHE_VALUE=generation-$_gen_count"
}

typeset -g _dep="$SPEC_TMP/fake-dependency"
: >| "$_dep"
command rm -f -- "$ZSH_CACHE_DIR"/spec-cache.zsh(N) "$ZSH_CACHE_DIR"/spec-cache.zsh.zwc(N)

_zcache_source spec-cache "$_dep" -- _spec_generator
assert_eq 'the first call generates' 'generation-1' "${SPEC_CACHE_VALUE-}"
assert_eq 'the generator ran exactly once' 1 "$_gen_count"
assert 'a cache file was written' '[[ -s $ZSH_CACHE_DIR/spec-cache.zsh ]]'
assert 'the cache file was byte-compiled' '[[ -s $ZSH_CACHE_DIR/spec-cache.zsh.zwc ]]'

_zcache_source spec-cache "$_dep" -- _spec_generator
assert_eq 'a warm call does not run the generator again' 1 "$_gen_count"
assert_eq 'a warm call still sets the value' 'generation-1' "${SPEC_CACHE_VALUE-}"

# Backdating the cache is the portable way to say "the dependency is newer":
# `touch -t` takes the same POSIX timestamp on Linux and macOS, and unlike
# touching the dependency it cannot tie on a filesystem with coarse timestamps.
command touch -t 200001010000 "$ZSH_CACHE_DIR/spec-cache.zsh"
_zcache_source spec-cache "$_dep" -- _spec_generator
assert_eq 'an upgraded dependency rebuilds the cache' 2 "$_gen_count"
assert_eq 'the rebuilt cache is what gets sourced' 'generation-2' "${SPEC_CACHE_VALUE-}"

spec_section 'the init cache survives a failing generator'

_spec_failing_generator() {
  print -r -- 'typeset -g SPEC_FALLBACK_VALUE=from-fallback'
  return 1
}

command rm -f -- "$ZSH_CACHE_DIR"/spec-broken.zsh(N)
_zcache_source spec-broken "$_dep" -- _spec_failing_generator
# The tool failed, so nothing is cached — but the shell still gets the output,
# because a prompt that is missing entirely is much worse than a slow one.
assert_eq 'output is still evaluated when the cache cannot be written' \
  'from-fallback' "${SPEC_FALLBACK_VALUE-}"
assert 'no cache is written from a failed generation' \
  '[[ ! -e $ZSH_CACHE_DIR/spec-broken.zsh ]]'
assert 'no temporary file is left behind' \
  'local -a leftovers=( $ZSH_CACHE_DIR/spec-broken.zsh.*(N) ); (( ! ${#leftovers} ))'

spec_section 'completion is initialised, and can rebuild'

assert_function 'compdef is available for lazy completion definitions' compdef
assert 'the completion dump lives in the cache directory' \
  '[[ -s $ZSH_CACHE_DIR/zcompdump-$ZSH_VERSION ]]'
assert 'the completion dump is byte-compiled' \
  '[[ -s $ZSH_CACHE_DIR/zcompdump-$ZSH_VERSION.zwc ]]'
assert 'a stamp records when the slow completion pass last ran' \
  '[[ -e $ZSH_CACHE_DIR/compinit-stamp ]]'

# The stamp, not the dump, is what decides between the fast and the slow path.
# Backdate it and the next shell must do the full pass — otherwise a newly
# installed tool's completions would never be picked up.
command touch -t 200001010000 "$ZSH_CACHE_DIR/compinit-stamp"
spec_zsh -i -c exit >/dev/null 2>&1
assert 'a stale stamp is refreshed by the next shell' \
  '[[ -n $ZSH_CACHE_DIR/compinit-stamp(#qNmh-1) ]]'
