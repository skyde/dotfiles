
# shellcheck shell=zsh
#
# Interactive zsh. EDITOR, PATH and the rest of the environment live in
# ~/.zshenv, which every shell reads; this file is only for the parts that need
# a human at a keyboard. See docs/zsh.md for the tour and the key bindings.

# -------- interactive TTY tweaks (skip in non‑tty to avoid extra 'stty' call)
#
# -ixon frees Ctrl-S (used below to toggle sort in the Ctrl-R picker) and Ctrl-Q
# from XON/XOFF flow control, where they would otherwise freeze and unfreeze the
# terminal instead of reaching zle.
if [[ -o interactive && -t 0 ]]; then
  stty -ixon -ixoff
fi

# -------- shell options
#
# Globbing and navigation.
setopt autocd nocaseglob extended_glob globdots
setopt numeric_glob_sort        # file2 before file10, not file10 before file2
setopt interactive_comments     # '#' starts a comment, so pasted commands survive
setopt no_beep no_flow_control  # silence, and Ctrl-S/Ctrl-Q belong to zle

# `cd` keeps a stack, so `cd -<Tab>` offers where you have been. pushd_silent
# because otherwise every single cd prints the whole stack, and pushd_minus so
# `cd -2` means "two back" rather than counting from the other end.
setopt auto_pushd pushd_ignore_dups pushd_silent pushd_minus

# -------- history
#
# hist_verify makes an expansion (`!!`, `!$`, `!vim`) land on the command line
# for a look before it runs, instead of running the moment you hit Enter.
setopt hist_ignore_all_dups hist_ignore_space hist_reduce_blanks hist_verify
setopt hist_save_no_dups hist_expire_dups_first
setopt extended_history         # record when each command ran, and how long it took
setopt share_history            # implies inc_append_history: shells see each other's lines
# NOTE: very large values slow startup because zsh loads history on launch.
HISTSIZE=100000
SAVEHIST=100000
HISTFILE="$HOME/.zsh_history"

# -------- key bindings
bindkey -e                              # Emacs keybindings
bindkey '^_' undo                       # Ctrl+_
bindkey '^[[1;5C' forward-word          # Ctrl+Right
bindkey '^[[1;5D' backward-word         # Ctrl+Left
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^G' edit-command-line          # Ctrl+G opens current prompt in $EDITOR
bindkey '^X^E' edit-command-line        # Ctrl+X Ctrl+E (standard)

# -------- cache directory
: "${XDG_CACHE_HOME:=$HOME/.cache}"
ZSH_CACHE_DIR="$XDG_CACHE_HOME/zsh"
# Tested first: `mkdir -p` on a directory that already exists still forks a
# process, and this one exists on every startup but the very first.
[[ -d $ZSH_CACHE_DIR ]] || mkdir -p -- "$ZSH_CACHE_DIR"

# -------- cached `eval "$(tool init zsh)"`
#
# Every `eval "$(starship init zsh)"` style line costs a fork, an exec, and a
# parse of a few hundred lines of shell on *every* new shell, to produce output
# that only changes when the tool is upgraded or its config is edited. This
# captures that output once, byte-compiles it, and sources the compiled copy
# afterwards.
#
#   _zcache_source <name> <dependency>... -- <command> [args...]
#
# The cache is rebuilt when it is missing or when any listed dependency is
# newer than it, so upgrading the tool (or editing its config) takes effect on
# the next shell without a manual cache clear. Missing dependencies are ignored:
# a path that is not there cannot have changed.
#
# Generation writes to a temporary file and renames, because the alternative —
# redirecting straight into the cache — leaves a half-written file behind if the
# terminal is closed mid-write, and every later shell would then source that
# fragment and fail in a way that looks nothing like its cause.
_zcache_source() {
  local name=$1 cache dep tmp
  shift
  local -a deps=()
  while (( $# )) && [[ $1 != -- ]]; do
    deps+=("$1")
    shift
  done
  shift  # the --

  cache="$ZSH_CACHE_DIR/$name.zsh"

  local stale=0
  [[ -s $cache ]] || stale=1
  if (( ! stale )); then
    for dep in $deps; do
      [[ -n $dep && -e $dep && $dep -nt $cache ]] && { stale=1; break }
    done
  fi

  if (( stale )); then
    tmp="$cache.$$"
    if "$@" >| "$tmp" 2>/dev/null && [[ -s $tmp ]]; then
      command mv -f -- "$tmp" "$cache"
      # -R so the compiled file stays usable when the source is deleted, and
      # because a mapped .zwc would keep the file open for the shell's lifetime.
      zcompile -R -- "$cache" 2>/dev/null
    else
      command rm -f -- "$tmp"
      # Fall back to evaluating the output directly rather than leaving the
      # shell without a prompt because a cache write failed (read-only HOME,
      # full disk).
      eval "$("$@" 2>/dev/null)"
      return
    fi
  fi

  source "$cache"
}

# -------- completion
#
# The dump is cached under $XDG_CACHE_HOME and byte-compiled, and the expensive
# security/rebuild pass runs at most once a day.
#
# `compinit -C` skips checking whether any completion function is newer than the
# dump. That is the difference between a ~4ms and a ~40ms startup, but taken
# unconditionally — as this did before — the dump never gets rebuilt at all: a
# newly installed tool's completions stay invisible until you remember to delete
# the cache by hand. The glob qualifier below reads "modified less than 20 hours
# ago"; when it matches, take the fast path, otherwise do the full pass. 20
# rather than 24 so that a shell opened at the same time each morning still
# refreshes daily.
zmodload -i zsh/complist
autoload -Uz compinit

_compdump="$ZSH_CACHE_DIR/zcompdump-$ZSH_VERSION"
_compstamp="$ZSH_CACHE_DIR/compinit-stamp"

if [[ -s $_compdump && -n $_compstamp(#qNmh-20) ]]; then
  compinit -C -d "$_compdump"
else
  compinit -d "$_compdump"
  # A stamp file rather than the dump's own mtime: compinit only rewrites the
  # dump when the set of completions actually changed, so on a quiet machine the
  # dump would stay old and every shell would take the slow path forever.
  # `: >|` is a builtin redirection — it creates and truncates without forking.
  : >| "$_compstamp"
fi

# Byte-compile the dump (only when updated)
if [[ -s $_compdump && ( ! -s $_compdump.zwc || $_compdump -nt $_compdump.zwc ) ]]; then
  zcompile "$_compdump"
fi
unset _compdump _compstamp

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# -------- prompt (Starship)
#
# Guarded, because an unguarded `eval "$(starship init zsh)"` on a machine
# where starship is not installed yet prints "command not found: starship" from
# ~/.zshrc on *every* new shell — including the ones ssh and tmux open — and
# leaves you on zsh's bare `machine%` prompt with no hint of what went wrong.
# That is the state of a freshly cloned dotfiles checkout before ./init.sh has
# run, which is exactly when a working shell matters most.
#
# The fallback is deliberately plain but not useless: cwd, the git branch when
# there is one, and a marker that turns red when the last command failed.
if (( $+commands[starship] )); then
  # starship's init script ends with PROMPT2="$(starship prompt --continuation)",
  # a second fork whose answer is a fixed string from starship.toml. Both the
  # init text and that string are baked into the cache, so a warm start runs no
  # starship at all until the first prompt is drawn.
  #
  # Filtering the line out with ${lines:#PROMPT2=*} instead of sed keeps this
  # fork-free, and degrades harmlessly if starship ever stops emitting it: the
  # filter removes nothing and the value appended below is still correct.
  _starship_init_text() {
    local -a lines
    lines=( ${(f)"$(starship init zsh)"} )
    lines=( ${lines:#PROMPT2=*} )
    print -r -- ${(F)lines}
    # STARSHIP_SHELL has to be set for this call: it is what tells starship to
    # wrap its colour escapes in zsh's %{...%} so the shell does not count them
    # as printable width. The real init exports it before reaching this line;
    # the cache generator has to do it explicitly, and without it continuation
    # lines put the cursor in the wrong column.
    print -r -- "PROMPT2=${(qqq)$(STARSHIP_SHELL=zsh starship prompt --continuation)}"
  }
  _zcache_source starship-init \
    "$commands[starship]" "${STARSHIP_CONFIG:-$HOME/.config/starship.toml}" \
    -- _starship_init_text
  unset -f _starship_init_text
else
  autoload -Uz vcs_info
  zstyle ':vcs_info:*' enable git
  zstyle ':vcs_info:git:*' formats ' %F{magenta}%b%f'
  zstyle ':vcs_info:git:*' actionformats ' %F{magenta}%b%f %F{red}(%a)%f'
  # Filtered rather than appended so re-sourcing ~/.zshrc does not stack up
  # copies of the same hook.
  precmd_functions=(${precmd_functions:#vcs_info} vcs_info)
  setopt prompt_subst
  PS1='%F{blue}%~%f${vcs_info_msg_0_}
%(?.%F{green}.%F{red})❯%f '
  RPS1=''
fi

# -------- zoxide (smart cd)
if (( $+commands[zoxide] )); then
  # Initialized immediately, not lazily, so `z` works on the very first command;
  # cached so that costs a file read rather than a fork.
  _zcache_source zoxide-init "$commands[zoxide]" -- zoxide init zsh
fi

# -------- fzf-powered history search (Ctrl-R), deduped & reverse-chronological
if (( $+commands[fzf] )); then
  _fzf_history_widget() {
    local selected
    # --ansi is passed explicitly, not just inherited from FZF_DEFAULT_OPTS:
    # without it fzf would hand back the highlighted line *including* the escape
    # sequences and paste those onto the command line.
    # Ranking: match quality first, recency second. --scheme=history keeps the
    # scoring tuned for command lines, and --tiebreak=index breaks ties by
    # position in the input, which is reverse-chronological — so equally good
    # matches are still newest-first.
    #
    # There is deliberately no --no-sort here. That flag threw the match score
    # away entirely and kept pure reverse-chronological order, which meant a
    # recent line with the query's letters scattered through it outranked an
    # older line containing the query verbatim. Ctrl-S toggles sorting off for
    # the times when walking back through history is what you actually want, and
    # fzf's own 'foo (exact), ^foo, foo$ operators still apply on top.
    selected=$(
      fc -nrl 1 2>/dev/null | LC_ALL=C awk 'length && !seen[$0]++' | \
      fzf_history_highlight | \
      fzf --height=80% --layout=reverse --min-height=20 --ansi \
          --scheme=history --tiebreak=index --wrap \
          --preview="$FZF_HISTORY_PREVIEW" --preview-window='down,4,wrap' \
          --bind='ctrl-/:toggle-preview' --bind='ctrl-s:toggle-sort' \
          --prompt='History> ' --style=minimal --query="$LBUFFER"
    ) || return
    BUFFER=$selected
    CURSOR=${#BUFFER}
    zle reset-prompt
  }
  zle -N _fzf_history_widget
  bindkey '^R' _fzf_history_widget
fi

# -------- safer Git defaults where tools may be missing
if ((! $+commands[delta] )) || ((! $+commands[code] )); then
  git() {
    local -a cfg=()
    ((! $+commands[delta] )) && cfg+=(-c core.pager=less -c interactive.diffFilter=cat)
    if ((! $+commands[code] )); then
      if (( $+commands[nvim] )); then
        cfg+=(-c merge.tool=nvimdiff3 -c difftool.tool=nvimdiff)
      else
        cfg+=(-c merge.tool=vimdiff -c difftool.tool=vimdiff)
      fi
    fi
    command git "${cfg[@]}" "$@"
  }
fi

# -------- VS Code Remote SSH: pick a live IPC socket before delegating to code
code() {
  local socket
  for socket in "${VSCODE_IPC_HOOK_CLI:-}" /run/user/$UID/vscode-ipc-*.sock(NOm); do
    if [[ -S "$socket" ]] && nc -z -U "$socket" >/dev/null 2>&1; then
      export VSCODE_IPC_HOOK_CLI="$socket"
      break
    fi
  done
  command code "$@"
}

# -------- aliases
alias grep='grep --color=auto'

# bat / batcat
if (( $+commands[bat] )); then
  alias cat='bat'
elif (( $+commands[batcat] )); then
  alias bat='batcat'
  alias cat='batcat'
fi

# eza ls replacements
if (( $+commands[eza] )); then
  alias ls='eza --color=auto --group-directories-first'
  alias ll='eza -al --color=auto --group-directories-first'
  alias la='eza -a --color=auto --group-directories-first'
  alias tree='eza --tree --icons --group-directories-first'
fi

# fd on Debian/Ubuntu where it's named fdfind
if ((! $+commands[fd] )) && (( $+commands[fdfind] )); then
  alias fd='fdfind'
fi

# -------- file managers that cd to the last visited dir
e() {
  local tmp cwd yazi_cmd
  tmp="$(mktemp -t yazi-cwd.XXXXXX)"
  if [[ -x "$HOME/.local/bin/yazi" ]]; then
    yazi_cmd="$HOME/.local/bin/yazi"
  else
    yazi_cmd="$(command -v yazi)"
  fi
  "$yazi_cmd" "$@" --cwd-file="$tmp"
  cwd="$(<"$tmp")"
  rm -f -- "$tmp"
  [[ -n $cwd && $cwd != "$PWD" ]] && builtin cd -- "$cwd" || return
}

lfcd() {
  local tmp dir
  tmp="$(mktemp -t lfcd.XXXXXX)"
  command lf -last-dir-path "$tmp" -- "$@"
  dir="$(<"$tmp")"
  rm -f -- "$tmp"
  [[ -n $dir && $dir != "$PWD" ]] && builtin cd -- "$dir"
}
alias lf='lfcd'

# TODO: This needs to be set for some reason to get everything
# to work in the terminal - find the root cause & remove this
unset GIT_PAGER

gg() { command lazygit; }

# -------- plugins (load AFTER everything else; keep syntax-highlighting last)
_source_zsh_plugin() {
  local plugin_name="$1"
  local init_file="$2"
  # Prioritize Homebrew (Apple Silicon then Intel), then system locations, then user local
  local -a locations=(
    "/opt/homebrew/share"
    "/usr/local/share"
    "/usr/share/zsh/plugins"
    "/usr/share"
    "$HOME/.local/share"
  )

  for loc in "${locations[@]}"; do
    local plugin_path="$loc/$plugin_name/$init_file"
    if [[ -r "$plugin_path" ]]; then
      source "$plugin_path"
      return 0
    fi
  done
  return 1
}

_source_zsh_plugin "zsh-autosuggestions" "zsh-autosuggestions.zsh"

# Prefer fast-syntax-highlighting (usually installs to zsh-fast-syntax-highlighting)
# but some package managers might use fast-syntax-highlighting
if ! _source_zsh_plugin "zsh-fast-syntax-highlighting" "fast-syntax-highlighting.plugin.zsh" && \
   ! _source_zsh_plugin "fast-syntax-highlighting" "fast-syntax-highlighting.plugin.zsh"; then
  # Fallback to standard zsh-syntax-highlighting
  _source_zsh_plugin "zsh-syntax-highlighting" "zsh-syntax-highlighting.zsh"
fi

unset -f _source_zsh_plugin

# -------- machine-specific overrides
# shellcheck disable=SC1090
[[ -r "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# Dynamic Tmux Title
[[ -f ~/.local/bin/tmux-title.zsh ]] && source ~/.local/bin/tmux-title.zsh
