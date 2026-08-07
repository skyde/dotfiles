
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
#
# All of them live here, before the plugins at the bottom of the file, because
# zsh-autosuggestions wraps the widgets that are bound when it loads.
#
# The full list, and what each key does, is in docs/zsh.md. Every binding below
# is checked by tests/zsh_keys_spec.zsh, which presses the key in a real terminal
# rather than asking bindkey what it thinks.
bindkey -e                              # Emacs keybindings
bindkey '^_' undo                       # Ctrl+_
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^G' edit-command-line          # Ctrl+G opens current prompt in $EDITOR
bindkey '^X^E' edit-command-line        # Ctrl+X Ctrl+E (standard)

# ---- keys whose escape sequence depends on the terminal
#
# Home, End, Delete and the arrows arrive as one sequence in a terminal's normal
# mode and another in "application" mode, and terminfo only knows the second.
# Which mode you are in depends on the terminal, on tmux, and on whether
# something earlier in the session sent smkx — so both forms are bound, along
# with terminfo's answer where there is one. Unbound, Home does not go to the
# start of the line: it inserts a tilde.
#
# Only sequences that belong to one key are listed. \eOC, for instance, is the
# plain Right arrow in application mode, so binding it to forward-word would
# break the arrow itself.
zmodload -i zsh/terminfo

_bindkey_all() {
  local widget=$1 seq
  shift
  for seq in "$@"; do
    [[ -n $seq ]] && bindkey -- "$seq" "$widget"
  done
}

_bindkey_all beginning-of-line "${terminfo[khome]}" '^[[H' '^[[1~' '^[OH'
_bindkey_all end-of-line       "${terminfo[kend]}"  '^[[F' '^[[4~' '^[OF'
_bindkey_all delete-char       "${terminfo[kdch1]}" '^[[3~'
# Ctrl-Right / Ctrl-Left in xterm, older xterm, and rxvt; plus Alt-Right and
# Alt-Left, which several terminals send instead.
_bindkey_all forward-word  '^[[1;5C' '^[[5C' '^[Oc' '^[[1;3C'
_bindkey_all backward-word '^[[1;5D' '^[[5D' '^[Od' '^[[1;3D'

# ---- Up and Down search the history for what you have already typed
#
# Type `git com` and press Up: only the git commands that start that way come
# back, rather than every command in order. With nothing typed it is the plain
# history walk, so nothing is lost. The cursor lands at the end of the recalled
# line, which is where you want it to carry on typing.
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
_bindkey_all up-line-or-beginning-search   "${terminfo[kcuu1]}" '^[[A' '^[OA'
_bindkey_all down-line-or-beginning-search "${terminfo[kcud1]}" '^[[B' '^[OB'
bindkey '^P' up-line-or-beginning-search
bindkey '^N' down-line-or-beginning-search

unset -f _bindkey_all

# ---- what counts as a word
#
# The default WORDCHARS includes / and =, so Ctrl-W on `rm -rf /a/b/c` deletes
# the entire path in one go and Alt-B walks over `FOO=bar` as a single word.
# Removing those two makes both operate on one path component, or on the name
# and the value, which is nearly always what was meant. The rest of the default
# is left alone.
WORDCHARS=${WORDCHARS//[\/=]/}

# ---- Alt-S: add or remove a sudo in front of the line
#
# For the moment after you press Enter and are told permission was denied: Up,
# Alt-S, Enter. On an empty line it pulls the last command back first, so the
# whole recovery is Alt-S, Enter.
_toggle_sudo_prefix() {
  [[ -z $BUFFER ]] && zle up-history
  if [[ $BUFFER == 'sudo '* ]]; then
    BUFFER=${BUFFER#sudo }
    (( CURSOR -= 5 ))
  else
    BUFFER="sudo $BUFFER"
    (( CURSOR += 5 ))
  fi
}
zle -N _toggle_sudo_prefix
bindkey '^[s' _toggle_sudo_prefix

# ---- Ctrl-Z at an empty prompt returns to the job you suspended
#
# Ctrl-Z out of an editor, run something, Ctrl-Z back into it — the same key both
# ways instead of `fg`. With something typed it leaves the line alone, and with
# no suspended job it does nothing, because "fg: no job control" is a worse
# answer than silence. zsh/parameter is what provides $jobstates.
zmodload -i zsh/parameter
_fg_or_ignore() {
  if [[ -n $BUFFER ]] || (( ! ${#jobstates} )); then
    return 0
  fi
  BUFFER='fg'
  zle accept-line
}
zle -N _fg_or_ignore
bindkey '^Z' _fg_or_ignore

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

#
# `-i` on the full pass: when compinit's security audit finds a completion
# directory that is group-writable or owned by someone else, it wants to *ask*
# whether to use it — and a shell with no terminal to ask on prints
#
#   not interactive and can't open terminal
#   compinit: initialization aborted
#
# and carries on with no completion system at all. This is not hypothetical: it
# is what happened on a GitHub runner, and a group-writable
# /usr/local/share/zsh/site-functions is the normal state of a Homebrew install.
# With -i those directories are dropped from the search path silently and the
# rest of the completions still load. Run `compaudit` to see what is being
# skipped; `chmod go-w` on what it names brings those completions back.
if [[ -s $_compdump && -n $_compstamp(#qNmh-20) ]]; then
  compinit -C -d "$_compdump"
else
  compinit -i -d "$_compdump"
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

# ---- how completion behaves
#
# The two options first: complete_in_word lets you fix the middle of a word
# (put the cursor after "confi" in "confiration" and complete) instead of only
# ever appending at the end, and always_to_end puts the cursor after the word
# once a completion is inserted rather than leaving it mid-word.
setopt complete_in_word always_to_end
setopt no_list_beep

# An arrow-navigable menu, and Shift-Tab to walk back up it.
zstyle ':completion:*' menu select
bindkey '^[[Z' reverse-menu-complete

# What Tab is willing to match. One specification rather than a list of
# increasingly lenient ones, and every part of it checked against a real
# terminal — tests/zsh_completion_spec.zsh presses Tab and reads the buffer back.
#
#   m:{[:lower:][:upper:]}={[:upper:][:lower:]}
#       case-insensitive both ways, so `TESTS/<Tab>` finds tests/ and
#       `readme<Tab>` still finds README.
#   r:|[._-]=** r:|=**
#       words separated by . _ or -, so `z_t_s<Tab>` completes
#       zsh_tools_spec.zsh and `f-p<Tab>` completes fzf-preview.
#
# Two things about this were only found by trying it:
#
# The `**` is not a typo for `*`. Written `r:|[._-]=* r:|=*` — the form most
# configs carry — the rule matches nothing at all, silently.
#
# And a matcher-list of several entries does not behave as advertised. The
# documentation describes the entries as tried in turn until one produces
# matches; in practice only the first is ever applied, and with the conventional
# leading '' ("try exact first") nothing after it has any effect. Hence one entry
# that does all of it.
#
# Substring-anywhere matching ('l:|=** r:|=**') was in that list and is
# deliberately gone. As the only entry it does work, and it ruins ordinary
# completion: `te<Tab>` then has every file *containing* "te" as a candidate, no
# common prefix to insert, and nothing happens. fzf's `**<Tab>` is the better
# tool for searching rather than completing.
zstyle ':completion:*' matcher-list \
  'm:{[:lower:][:upper:]}={[:upper:][:lower:]} r:|[._-]=** r:|=**'

# _match completes a word that contains glob characters: `ls a*d<Tab>` fills in
# a.md.
#
# _extensions and _approximate (typo tolerance) were both tried here and neither
# could be shown to do anything — no correction offered for a one-character
# mistake, no extension list for a bare `*.` — so they are left out rather than
# carried as decoration that also lengthens every completion.
zstyle ':completion:*' completer _complete _match
zstyle ':completion:*:match:*' original only

# Results grouped under headings, with the description of each group shown.
# Without group-name a completion that can offer files, parameters and options
# prints them as one undifferentiated list.
zstyle ':completion:*' group-name ''
zstyle ':completion:*' verbose yes
zstyle ':completion:*:descriptions' format '%F{blue}%B%d%b%f'
zstyle ':completion:*:messages' format '%F{magenta}%d%f'
zstyle ':completion:*:warnings' format '%F{red}no matches for %d%f'
zstyle ':completion:*:corrections' format '%F{yellow}%d (errors: %e)%f'

# Colour the file names in the completion list the way ls does. LS_COLORS is
# only exported on machines that run dircolors, so the fallback spells out the
# handful that matter: directories, symlinks, executables and the world-writable
# ones worth noticing.
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS:-di=1;34:ln=1;36:so=1;35:pi=33:ex=1;32:bd=1;33:cd=1;33:su=1;31:sg=1;31:tw=1;34:ow=1;34}

# Completions that shell out to a package manager or a remote host are worth
# caching — the alternative is a fresh `apt-cache pkgnames` on every Tab.
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$ZSH_CACHE_DIR/zcompcache"

# Offer a completion for a command installed since this shell started, instead
# of insisting it does not exist until you run `rehash`.
zstyle ':completion:*' rehash true

# Directories: offer . and .., squeeze duplicate slashes, and do not offer the
# directory you are already in as a way of getting to itself.
zstyle ':completion:*' special-dirs true
zstyle ':completion:*' squeeze-slashes true
zstyle ':completion:*:cd:*' ignore-parents parent pwd

# `kill <Tab>` lists this user's processes, with the pid picked out, rather than
# asking for a number and offering nothing.
zstyle ':completion:*:*:kill:*' menu yes select
zstyle ':completion:*:*:kill:*' force-list always
zstyle ':completion:*:*:kill:*:processes' \
  command 'ps -u "$USER" -o pid,%cpu,tty,cputime,cmd'
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'

# Man pages grouped by section, so `man mount<Tab>` separates the command from
# the syscall.
zstyle ':completion:*:manuals' separate-sections true
zstyle ':completion:*:manuals.*' insert-sections true

# The completion system's own internals are not useful answers to `<function
# name><Tab>`.
zstyle ':completion:*:functions' ignored-patterns '_*'

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

# -------- fzf
if (( $+commands[fzf] )); then
  # fzf's own shell integration — Ctrl-T to paste a path, Alt-C to cd into a
  # directory, and the ** completion trigger — was sourced by .bashrc-custom but
  # never by .zshrc, so the shell actually in use was the one missing it.
  #
  # fzf ships that integration two ways. `fzf --zsh` prints it on stdout (0.48
  # and later); older builds install it as files, in a directory that depends
  # entirely on who packaged it. The generator below tries the first and falls
  # back to hunting for the second, and its result goes through the same cache as
  # the other init scripts — so a warm start reads one compiled file and spawns
  # nothing, and upgrading fzf invalidates it.
  #
  # Loaded only with a terminal attached. Everything in it is a zle widget,
  # which a `zsh -i -c ...` shell — what an editor or a tool uses to run one
  # command — can never reach; and fzf's files end by restoring the entire
  # option array in a single eval, which without a terminal tries to set the
  # read-only `zle` option and prints "can't change option: zle" on stderr. That
  # line would then land in the middle of the output of every such command.
  _fzf_init_text() {
    local integration dir file
    if integration=$(fzf --zsh 2>/dev/null) && [[ -n $integration ]]; then
      print -r -- "$integration"
      return 0
    fi
    # Same locations as .bashrc-custom looks in, plus Homebrew's.
    #
    # The cache holds `source` lines rather than the text of those thousand-odd
    # lines. Copying them in so they would be byte-compiled with the rest was
    # measured and made no difference: what the two files cost is running them —
    # defining the widgets, saving and restoring the option array — not parsing
    # them. `source` lines keep the file that is read the file that shipped.
    for file in key-bindings.zsh completion.zsh; do
      for dir in /usr/share/fzf /usr/share/doc/fzf/examples \
        /opt/homebrew/opt/fzf/shell /usr/local/opt/fzf/shell \
        "$HOME/.fzf/shell" "$HOME/.fzf"; do
        if [[ -r $dir/$file ]]; then
          print -r -- "source ${(q)dir}/$file"
          break
        fi
      done
    done
  }
  [[ -t 0 ]] && _zcache_source fzf-init "$commands[fzf]" -- _fzf_init_text
  unset -f _fzf_init_text

  # ---- history search (Ctrl-R), deduped & reverse-chronological
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
  # Bound after the integration above, which puts fzf's own fzf-history-widget
  # on Ctrl-R. This one wins on purpose: it dedupes, syntax-highlights the list
  # and previews the focused entry wrapped.
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
#
# A long-lived shell (tmux, screen, a reattached ssh session) outlives the VS
# Code window that started it, and the socket in its environment dies with that
# window. Every later `code .` from that shell then writes to a socket nobody is
# listening on and hangs. So each call picks the newest socket that answers.
#
# Liveness is probed with zsocket, from zsh's own zsh/net/socket module, rather
# than `nc -z -U`: nc is missing from plenty of minimal images and containers —
# where the old probe silently failed for every candidate and no socket was ever
# selected — and this way there is no process spawned per candidate either.
if zmodload -F zsh/net/socket b:zsocket 2>/dev/null; then
  _vscode_socket_answers() {
    zsocket -- "$1" 2>/dev/null || return 1
    # zsocket leaves the connected descriptor in $REPLY; nothing is sent on it,
    # the successful connect is the whole answer.
    exec {REPLY}>&-
    return 0
  }
elif (( $+commands[nc] )); then
  _vscode_socket_answers() { command nc -z -U "$1" >/dev/null 2>&1; }
else
  # Nothing to probe with: prefer the newest socket over giving up, which is
  # what the caller gets anyway if no socket is chosen.
  _vscode_socket_answers() { return 0; }
fi

code() {
  local socket dir
  local -a candidates
  candidates=("${VSCODE_IPC_HOOK_CLI:-}")
  # VSCODE_IPC_SOCKET_DIRS is a colon-separated override, used by the specs; the
  # default covers Linux (/run/user/$UID, where VS Code Server puts them) and
  # macOS, where they land in $TMPDIR instead.
  for dir in ${(s.:.)${VSCODE_IPC_SOCKET_DIRS:-/run/user/$UID:${TMPDIR:-/tmp}}}; do
    candidates+=($dir/vscode-ipc-*.sock(NOm))
  done
  for socket in $candidates; do
    if [[ -S $socket ]] && _vscode_socket_answers "$socket"; then
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
#
# A child process cannot change its parent's directory, so both of these ask the
# file manager to write where it ended up into a temp file and cd there
# afterwards.
#
# Neither ends with `... && builtin cd -- "$dir" || return`. That reads as "cd if
# there is somewhere to go", but the `||` applies to the whole chain: quitting in
# the directory you started in made the test false and ran `return` with $? still
# 1, so an ordinary look around a directory left the prompt showing an error
# marker for a command that did exactly what it was asked.
e() {
  local tmp cwd yazi_cmd
  # ~/.local/bin first: install-yazi.sh puts a current build there, which is
  # usually newer than a distro package that may also be installed.
  if [[ -x $HOME/.local/bin/yazi ]]; then
    yazi_cmd=$HOME/.local/bin/yazi
  else
    yazi_cmd=${commands[yazi]-}
  fi
  if [[ -z $yazi_cmd ]]; then
    print -ru2 -- "e: yazi is not installed (run ./install-yazi.sh)"
    return 127
  fi

  # `|| return` on mktemp, because an unwritable TMPDIR left $tmp empty, which
  # turned into --cwd-file= and a confusing error from yazi itself.
  tmp=$(mktemp -t yazi-cwd.XXXXXX) || return
  "$yazi_cmd" "$@" --cwd-file="$tmp"
  cwd=$(<"$tmp")
  command rm -f -- "$tmp"
  if [[ -n $cwd && $cwd != "$PWD" ]]; then
    builtin cd -- "$cwd"
  fi
}

lfcd() {
  local tmp dir
  if (( ! $+commands[lf] )); then
    print -ru2 -- "lf: not installed (it is in packages.txt; run ./init.sh)"
    return 127
  fi
  tmp=$(mktemp -t lfcd.XXXXXX) || return
  command lf -last-dir-path "$tmp" -- "$@"
  dir=$(<"$tmp")
  command rm -f -- "$tmp"
  if [[ -n $dir && $dir != "$PWD" ]]; then
    builtin cd -- "$dir"
  fi
}
alias lf='lfcd'

# -------- keep git's own configuration in charge of paging
#
# GIT_PAGER in the environment beats core.pager in git config, so any ancestor
# process that exports GIT_PAGER=cat — some IDE terminals and git wrappers do —
# switches delta off for every git command in this shell, and nothing says why:
# diffs simply come out unstyled. ./doctor-delta.sh reports exactly this case.
# Clearing it hands the decision back to ~/.config/git/config.
#
# A value that already routes through delta is kept, since that one was a
# deliberate choice (`GIT_PAGER='delta --side-by-side' git log`, say) and used to
# be thrown away along with the rest.
case ${GIT_PAGER-} in
  '' | *delta*) ;;
  *) unset GIT_PAGER ;;
esac

# "$@" so `gg log`, `gg -f`, `gg status` reach lazygit instead of being dropped.
gg() { command lazygit "$@"; }

# -------- plugins (load AFTER everything else; keep syntax-highlighting last)
#
# zsh-autosuggestions reads these when it loads, so they have to be set first.
#
# The suggestion colour is Tokyo Night's comment grey, the same one used for
# muted text everywhere else (docs/tokyonight.md). The plugin's default is fg=8 —
# the terminal's "bright black", which upstream Tokyo Night puts at #414868, and
# which the note in that document calls close to unreadable for exactly this kind
# of de-emphasised text. Naming the colour also means the suggestion looks the
# same in a terminal whose ANSI 8 has been adjusted and in one that is untouched.
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#565f89'

# History first, and what completion would offer when the history has nothing.
# The completion strategy is what suggests a flag or a path you have never typed
# before.
ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# By default the plugin re-binds its widget wrappers before every prompt, so that
# a binding added at runtime still gets a suggestion. Everything in this file
# binds before the plugin loads, so that pass has nothing to find; skipping it
# takes work out of every prompt. The cost of the setting is that a `bindkey`
# typed at the prompt afterwards will not suggest until the next shell.
ZSH_AUTOSUGGEST_MANUAL_REBIND=1

# No suggestions for a pasted paragraph: the search is over the whole history and
# the answer for a 500-character buffer is never useful.
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=60

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

# -------- terminal title: where you are, and what is running
#
# This replaces a `source ~/.local/bin/tmux-title.zsh` that had nothing to
# source: no such file exists here or in the repository. It would not have done
# anything for tmux either — .tmux.conf sets allow-rename off and names windows
# itself through automatic-rename-format, so a window title from the shell is
# ignored on purpose. What was missing is the *terminal's* title: the kitty tab
# and the OS window, which say "zsh" for every window without this.
#
# At the prompt the title is the directory. While a command runs it is the
# command and the directory, so a window in the middle of a long build says so
# from the tab bar.
case $TERM in
  xterm* | rxvt* | screen* | tmux* | alacritty* | kitty* | wezterm* | vte* | konsole* | foot* | ansi)
    # OSC 0 sets the icon name and the window title together, which is what tab
    # titles are taken from in every terminal here.
    _title_set() { print -n -- $'\e]0;'"$1"$'\a'; }

    # ${(%):-%~} expands the prompt escape without a fork, giving ~ for $HOME.
    _title_precmd() { _title_set "${(%):-%~}"; }

    _title_preexec() {
      local cmd=${1//[[:cntrl:]]/ }
      # Truncated, because a title longer than the tab is worse than a short
      # one: the part that identifies the window scrolls out of view.
      (( ${#cmd} > 40 )) && cmd="${cmd[1,39]}…"
      # The command is concatenated rather than interpolated into a prompt
      # string: `print -P` on a command line containing %~ or %F would expand
      # those too.
      _title_set "$cmd — ${(%):-%~}"
    }

    autoload -Uz add-zsh-hook
    add-zsh-hook precmd _title_precmd
    add-zsh-hook preexec _title_preexec
    ;;
esac

# -------- machine-specific overrides
#
# Last, so a machine can override anything above it.
# shellcheck disable=SC1090
[[ -r "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
