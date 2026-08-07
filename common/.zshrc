
# shellcheck shell=zsh

# -------- editor
export EDITOR="nvim"
export VISUAL="$EDITOR"

# -------- interactive TTY tweaks (skip in non‑tty to avoid extra 'stty' call)
if [[ -o interactive && -t 0 ]]; then
  stty -ixon -ixoff
fi

# -------- shell options
setopt autocd nocaseglob extended_glob globdots
setopt hist_ignore_all_dups hist_ignore_space
setopt share_history inc_append_history append_history

# -------- history
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

# -------- completion (cached)
# Cache to XDG location and compile the dump for speed.
zmodload -i zsh/complist
autoload -Uz compinit
: "${XDG_CACHE_HOME:=$HOME/.cache}"
ZSH_CACHE_DIR="$XDG_CACHE_HOME/zsh"
mkdir -p -- "$ZSH_CACHE_DIR"
_compdump="$ZSH_CACHE_DIR/zcompdump-$ZSH_VERSION"

# Fast path: if dump exists, use curtailed checks (-C). Otherwise, build it.
if [[ -s $_compdump ]]; then
  compinit -C -d "$_compdump"
else
  compinit -d "$_compdump"
fi

# Byte-compile the dump (only when updated)
if [[ -s $_compdump && ( ! -s $_compdump.zwc || $_compdump -nt $_compdump.zwc ) ]]; then
  zcompile "$_compdump"
fi
unset _compdump

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# Colour the completion list from the same LS_COLORS that ls, eza, fd, lf and
# yazi use (built in ~/.config/shell/theme.sh), so a directory in the Tab menu
# is the same blue as a directory everywhere else. Without this zstyle the menu
# is the one file listing in the setup rendered in plain foreground.
#
# `ma` is not an LS_COLORS key — it is zsh's own, for the highlighted entry
# under the cursor in `menu select`. It gets bg_visual, the same fill as fzf's
# bg+, tmux's mode-style and yazi's hovered row.
#
# Unquoted on purpose: (s.:.) has to yield one word per entry, and inside
# double quotes it would come back as a single space-joined string. Nothing
# globs here — zsh does not run filename generation over the result of a
# parameter expansion, so the `*.py=...` entries pass through intact.
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS} 'ma=48;2;40;52;87'
# Group headers and the "no matches" line, in the palette's muted greys.
zstyle ':completion:*:descriptions' format $'\033[38;2;122;162;247;1m%d\033[0m'
zstyle ':completion:*:messages'     format $'\033[38;2;115;122;162m%d\033[0m'
zstyle ':completion:*:warnings'     format $'\033[38;2;247;118;142mno matches: %d\033[0m'

# # -------- prompt (Starship)
eval "$(starship init zsh)"

# -------- zoxide (smart cd)
if (( $+commands[zoxide] )); then
  # Initialize immediately so `z` works on the very first command
  eval "$(zoxide init zsh)"
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

# The suggestion trailing the cursor defaults to `fg=8` — ANSI bright black.
# That default assumes bright black is dark, and here it is not: kitty and
# wezterm deliberately lighten colour8 to #85899c because Tokyo Night's
# #414868 is unreadable for de-emphasised CLI output (docs/tokyonight.md). The
# side effect is that the ghost text came out nearly as bright as what you had
# actually typed. Naming the comment grey directly makes it a suggestion again,
# and keeps colour8 free to stay readable for the tools that need it.
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#565f89'

_source_zsh_plugin "zsh-autosuggestions" "zsh-autosuggestions.zsh"

# Prefer fast-syntax-highlighting (usually installs to zsh-fast-syntax-highlighting)
# but some package managers might use fast-syntax-highlighting
if ! _source_zsh_plugin "zsh-fast-syntax-highlighting" "fast-syntax-highlighting.plugin.zsh" && \
   ! _source_zsh_plugin "fast-syntax-highlighting" "fast-syntax-highlighting.plugin.zsh"; then
  # Fallback to standard zsh-syntax-highlighting
  _source_zsh_plugin "zsh-syntax-highlighting" "zsh-syntax-highlighting.zsh"
fi

unset -f _source_zsh_plugin

# -------- command line syntax colours
# The command line is source code, so it follows the same rule the rest of the
# repo does: chrome is Tokyo Night, code is Visual Studio Dark+
# (docs/tokyonight.md). This is not an abstract principle here — Ctrl-R pipes
# history through bat with BAT_THEME, so the very same command is already being
# painted in Dark+ one keystroke earlier. Colouring the prompt from the same
# set means accepting a history entry no longer recolours it.
#
# The exception is the two things Dark+ has no vocabulary for, because they are
# facts about your machine rather than about syntax: whether a command exists
# and whether a path exists. Those keep Tokyo Night's chrome roles — red for a
# word that will fail, the muted grey for a path that is still a prefix.
#
# Written once and applied to whichever highlighter loaded above. The two
# plugins share most key names; the handful each one has to itself lands in the
# other's array unread, which is harmless.
typeset -gA _tn_cli_styles=(
  default                       'fg=#d4d4d4'
  # Only ever reached with `setopt interactivecomments`; without it a `#` on
  # the command line is an ordinary word to zsh, and the highlighter is right
  # to leave it alone. Set anyway so the two shells agree if that ever changes.
  comment                       'fg=#6a9955'
  # Commands: the thing being called, in Dark+'s function yellow. A word that
  # resolves to nothing is the one place Tokyo Night's red overrides.
  command                       'fg=#dcdcaa'
  builtin                       'fg=#dcdcaa'
  function                      'fg=#dcdcaa'
  alias                         'fg=#dcdcaa'
  suffix-alias                  'fg=#dcdcaa'
  global-alias                  'fg=#dcdcaa'
  hashed-command                'fg=#dcdcaa'
  arg0                          'fg=#dcdcaa'
  back-quoted-argument          'fg=#dcdcaa'
  unknown-token                 'fg=#f7768e'
  # Control words, and the precommands (sudo, command, noglob) that read as
  # control over the command that follows.
  reserved-word                 'fg=#c586c0'
  precommand                    'fg=#c586c0'
  # Strings, and the things that interrupt them.
  single-quoted-argument        'fg=#ce9178'
  double-quoted-argument        'fg=#ce9178'
  dollar-quoted-argument        'fg=#ce9178'
  rc-quote                      'fg=#ce9178'
  dollar-double-quoted-argument 'fg=#9cdcfe'
  back-double-quoted-argument   'fg=#d7ba7d'
  back-dollar-quoted-argument   'fg=#d7ba7d'
  # Variables and assignments.
  variable                      'fg=#9cdcfe'
  assign                        'fg=#9cdcfe'
  mathvar                       'fg=#9cdcfe'
  # Metacharacters that expand to something else, in the gold Dark+ uses for
  # escape sequences — a glob and a \n are the same kind of "not literal".
  globbing                      'fg=#d7ba7d'
  history-expansion             'fg=#d7ba7d'
  # Options modify the command the way a storage modifier modifies a
  # declaration, and take the blue Dark+ gives those.
  single-hyphen-option          'fg=#569cd6'
  double-hyphen-option          'fg=#569cd6'
  # Numbers.
  mathnum                       'fg=#b5cea8'
  named-fd                      'fg=#b5cea8'
  numeric-fd                    'fg=#b5cea8'
  matherr                       'fg=#f7768e'
  # Plumbing stays the plain text colour: | ; && > are structure, not content.
  redirection                   'fg=#d4d4d4'
  commandseparator              'fg=#d4d4d4'
  # Paths. Underline is the "this exists" signal, so a real path is legible
  # without spending a hue on it; a prefix that has not resolved to anything
  # yet is muted instead. The separators take the same quiet grey, which is
  # the rule the file listings already follow — eza's `xx` and yazi's
  # perm_sep — so the segments of a long path carry the eye, not the slashes.
  path                          'fg=#d4d4d4,underline'
  path-to-dir                   'fg=#d4d4d4,underline'
  path_prefix                   'fg=#565f89'
  path_pathseparator            'fg=#565f89'
  path_prefix_pathseparator     'fg=#565f89'
  pathseparator                 'fg=#565f89'
)

if (( ${+FAST_HIGHLIGHT_STYLES} )); then
  for _tn_k _tn_v in "${(@kv)_tn_cli_styles}"; do
  	FAST_HIGHLIGHT_STYLES[$_tn_k]=$_tn_v
  done
fi
if (( ${+ZSH_HIGHLIGHT_STYLES} )); then
  for _tn_k _tn_v in "${(@kv)_tn_cli_styles}"; do
  	ZSH_HIGHLIGHT_STYLES[$_tn_k]=$_tn_v
  done
fi
unset _tn_k _tn_v _tn_cli_styles

# -------- machine-specific overrides
# shellcheck disable=SC1090
[[ -r "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# Dynamic Tmux Title
[[ -f ~/.local/bin/tmux-title.zsh ]] && source ~/.local/bin/tmux-title.zsh
