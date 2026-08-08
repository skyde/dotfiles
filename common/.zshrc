
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

# fast-syntax-highlighting keeps a work dir, and on the very first startup it
# curls a "secondary theme" into it from raw.githubusercontent.com and later
# sources that file — see the `secondary_theme.zsh` block in its plugin file.
# The table below switches the secondary theme off, so the download would only
# ever be fetched to sit unread; pinning the directory and leaving the file in
# place is what stops a network round trip from being part of opening a shell.
# Defaulted rather than assigned, so a FAST_WORK_DIR already exported from
# ~/.zshenv or the environment still wins — the point here is to have *a* known
# directory before the plugin loads, not to insist on this one.
typeset -g FAST_WORK_DIR="${FAST_WORK_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/fast-syntax-highlighting}"
# ...and only pre-create when the value is a plain path. fast-syntax-highlighting
# accepts XDG:/LOCAL:/HOME:/OPT: prefixes and expands them itself, later; taking
# `mkdir -p` to one of those would create a literal directory named `HOME:` in
# whatever the shell's cwd happens to be at startup. Someone using the prefix
# vocabulary has chosen their own work dir anyway, so the download-suppression
# is simply skipped for them.
if [[ $FAST_WORK_DIR != (XDG|LOCAL|HOME|OPT):* && ! -e $FAST_WORK_DIR/secondary_theme.zsh ]]; then
  { mkdir -p -- "$FAST_WORK_DIR" && : >| "$FAST_WORK_DIR/secondary_theme.zsh" } 2>/dev/null
fi

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
  # The verb after the command — `git commit`, `docker run`, `apt-get install`.
  # fast-syntax-highlighting knows these from its per-command grammars, and it
  # is the single most-typed token that had no colour of its own here: left
  # unset it fell through to the plugin's `fg=yellow`, i.e. raw ANSI colour3,
  # from neither palette. It takes Dark+'s type/class teal, which nothing else
  # on the command line uses and which PSReadLine already spends on `Type`.
  # A subcommand really is the closest thing a command line has to a type: it
  # picks which grammar the rest of the words are read in.
  subcommand                    'fg=#4ec9b0'
  builtin                       'fg=#dcdcaa'
  function                      'fg=#dcdcaa'
  alias                         'fg=#dcdcaa'
  suffix-alias                  'fg=#dcdcaa'
  global-alias                  'fg=#dcdcaa'
  hashed-command                'fg=#dcdcaa'
  arg0                          'fg=#dcdcaa'
  # A substitution runs a command, so its wrapper — `$(`, `)`, the backticks,
  # the `<(` of a process substitution — is marked as one rather than left to
  # read as punctuation.
  #
  # Only zsh-syntax-highlighting has these three keys, so this is the fallback
  # highlighter's rendering. fast-syntax-highlighting has no delimiter roles at
  # all: it hands the parentheses to the bracket-matcher, so under it `$(` and
  # `)` come out in the depth-1 gold below. Both readings are defensible — one
  # says "this is a command", the other "this is a nesting level" — and neither
  # plugin can be made to say the other, so the keys are set for the one that
  # reads them and the difference is written down here.
  back-quoted-argument          'fg=#dcdcaa'
  back-quoted-argument-delimiter 'fg=#dcdcaa'
  command-substitution-delimiter 'fg=#dcdcaa'
  process-substitution-delimiter 'fg=#dcdcaa'
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
  globbing-ext                  'fg=#d7ba7d'
  history-expansion             'fg=#d7ba7d'
  # Options modify the command the way a storage modifier modifies a
  # declaration, and take the blue Dark+ gives those.
  single-hyphen-option          'fg=#569cd6'
  double-hyphen-option          'fg=#569cd6'
  # The value an option carries. fast-syntax-highlighting marks the part
  # after `=` in `--opt=value` with these two keys everywhere, and marks the
  # free-standing value after an option for commands whose grammar declares
  # which options take one (git, and the subcommand tools registered below).
  # Both keys were unset, and unset is not "left alone" here: neither the
  # plugin's embedded defaults nor its default theme define them, so the
  # region got an empty style — `--exclude=node_modules` painted the option
  # blue and dropped the value in the terminal's raw foreground, from
  # neither palette. A value is a literal, so it reads as one: string orange,
  # or number green when the whole value is digits (measured: `--jobs=8`
  # lands on optarg-number, `--target=x86_64-…` on optarg-string).
  optarg-string                 'fg=#ce9178'
  optarg-number                 'fg=#b5cea8'
  # Numbers. named-fd/numeric-fd are zsh-syntax-highlighting's keys for the
  # descriptor in `exec {fd}<file`; exec-descriptor is
  # fast-syntax-highlighting's name for the same role, and was the one of the
  # three left unset.
  mathnum                       'fg=#b5cea8'
  named-fd                      'fg=#b5cea8'
  numeric-fd                    'fg=#b5cea8'
  exec-descriptor               'fg=#b5cea8'
  matherr                       'fg=#f7768e'
  # Plumbing is structure, not content — so it recedes rather than taking a
  # hue of its own. Previously it was #d4d4d4, the same as an ordinary
  # argument, which meant `cat f.txt | grep -i foo > out.log` painted the four
  # words and the two operators in one flat colour and the shape of the
  # pipeline had to be read character by character. dark5 is one step down
  # from plain text and already in use two screens up for completion
  # messages. This is the rule the path separators below already follow: the
  # segments carry the eye, the joints stay out of the way.
  redirection                   'fg=#737aa2'
  commandseparator              'fg=#737aa2'
  here-string-tri               'fg=#737aa2'
  subtle-separator              'fg=#737aa2'
  # Paths. Underline is the "this exists" signal, so a real path is legible
  # without spending a hue on it; a prefix that has not resolved to anything
  # yet is muted instead. The separators take the same quiet grey, which is
  # the rule the file listings already follow — eza's `xx` and yazi's
  # perm_sep — so the segments of a long path carry the eye, not the slashes.
  path                          'fg=#d4d4d4,underline'
  path-to-dir                   'fg=#d4d4d4,underline'
  autodirectory                 'fg=#d4d4d4,underline'
  path_prefix                   'fg=#565f89'
  path_pathseparator            'fg=#565f89'
  path_prefix_pathseparator     'fg=#565f89'
  pathseparator                 'fg=#565f89'
  # -------- shell structure
  # Everything below was previously left unset, which is not the same as
  # leaving it alone: both plugins ship defaults for these, and those defaults
  # are ANSI-indexed (`fg=green`, `fg=yellow,bold`) or worse, backgrounds
  # (`bg=blue`, `bg=18`). So a `case` block or a here-string was painted out of
  # a palette this repo does not use, in the middle of a line that otherwise
  # came from Dark+. They are named here so the whole line comes from one
  # table — and so the constructs that were flat before now have some shape.
  #
  # Grouping constructs are control flow, so they take the same magenta as the
  # reserved words they belong to.
  double-paren                  'fg=#c586c0'
  single-sq-bracket             'fg=#c586c0'
  double-sq-bracket             'fg=#c586c0'
  case-parentheses              'fg=#c586c0'
  # A case pattern is a glob, and is coloured as one.
  case-condition                'fg=#d7ba7d'
  case-input                    'fg=#9cdcfe'
  # for/while headers: the variable and the counter keep the colours those
  # things have everywhere else, the `;` joins the plumbing above.
  for-loop-variable             'fg=#9cdcfe'
  for-loop-number               'fg=#b5cea8'
  for-loop-operator             'fg=#d4d4d4'
  for-loop-separator            'fg=#737aa2'
  assign-array-bracket          'fg=#9cdcfe'
  # A here-string is a string; the `<<<` that introduces it is plumbing.
  here-string-text              'fg=#ce9178'
  here-string-var               'fg=#9cdcfe'
  # fast-syntax-highlighting's one key for two things: a backslash escape and a
  # `$var` interpolation, both inside double quotes. It was grouped with the
  # escapes on the strength of the plugin's own default pairing it with
  # `back-dollar-quoted-argument` — but measuring it says the interpolation is
  # what actually reaches it (`echo "$HOME/x"` painted `$HOME`, while the `\t`
  # in `echo "a\tb"` was never marked at all). Interpolation is also the far
  # more common case and the one the docs promise in blue, so blue it is.
  back-or-dollar-double-quoted-argument 'fg=#9cdcfe'
  # Bracket pairs, in VS Code's own bracket-pair-colourisation colours — the
  # command line is code, and this is what the editor does with nesting.
  # zsh-syntax-highlighting cycles through as many levels as are defined and
  # fast-syntax-highlighting uses three, so the first three carry the load and
  # 4/5 repeat rather than inventing two more hues.
  bracket-level-1               'fg=#ffd700'
  bracket-level-2               'fg=#da70d6'
  bracket-level-3               'fg=#179fff'
  bracket-level-4               'fg=#ffd700'
  bracket-level-5               'fg=#da70d6'
  bracket-error                 'fg=#f7768e'
  # The pair either side of the cursor. fg_gutter is a neutral fill no other
  # role claims — deliberately not bg_visual, which means "this row is
  # selected" in five other tools.
  paired-bracket                'bg=#3b4261'
  cursor-matchingbracket        'bg=#3b4261'
  # The hint a chroma leaves when it recognises (or fails to recognise) a
  # subcommand: the same muted grey / Tokyo Night red split used everywhere
  # else for "fine" versus "this will not work".
  correct-subtle                'fg=#565f89'
  incorrect-subtle              'fg=#f7768e'
  subtle-bg                     'bg=#292e42'
  # Not a colour: the name of a *second* style table that
  # fast-syntax-highlighting switches to for anything it treats as an embedded
  # shell — most visibly the inside of `$(…)`. It ships pointing at the theme
  # it downloads on first run, so `date` in `echo $(date)` came out fg=180,
  # a 256-colour tan from a file fetched off the internet, while the same word
  # outside the parentheses was #dcdcaa. Emptied, the highlighter never
  # switches, and a nested command reads exactly like a top-level one.
  secondary                     ''
  # The base coat fast-syntax-highlighting lays under a string it re-enters
  # as code — the quoted body of `eval "…"` or `zsh -c "…"` — before painting
  # the real styles on top. Unset it was another no-style hole: the quotes
  # and the gaps between repainted words fell back to the terminal's raw
  # foreground. Same value as `default` above, which is the `secondary ''`
  # decision again: code inside a string reads exactly like code outside it.
  recursive-base                'fg=#d4d4d4'
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

# The subcommand teal above only fires for commands the highlighter has a
# grammar for, and its built-in list froze around 2019: brew, apt, pip, npm
# and tmux are in it, while the tools that arrived since are not — so
# `cargo build` or `kubectl get pods` painted the verb as a plain argument
# and a long invocation lost its main anchor. The generic subcommand grammar
# is data, not code: registering a command is one hash entry pointing at the
# chroma the built-in list already uses for npm and friends. gn and gclient
# are the Chromium checkout's tools (docs/chromium-clangd.md).
if (( ${+FAST_HIGHLIGHT} )); then
  for _tn_c in cargo rustup go kubectl helm terraform gh docker-compose \
               pnpm bun deno uv poetry pipx conda just mise dotnet az \
               gcloud flutter gn gclient; do
    FAST_HIGHLIGHT[chroma-$_tn_c]='→chroma/-subcommand.ch'
  done
  unset _tn_c
fi

# -------- machine-specific overrides
# shellcheck disable=SC1090
[[ -r "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# Dynamic Tmux Title
[[ -f ~/.local/bin/tmux-title.zsh ]] && source ~/.local/bin/tmux-title.zsh
