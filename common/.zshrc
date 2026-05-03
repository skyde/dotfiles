
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
bindkey '^X' edit-command-line          # Ctrl+X edits current prompt

# -------- help on current command (Esc h)
unalias run-help 2>/dev/null
autoload -Uz run-help
bindkey '^[h' run-help

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

zstyle ':completion:*' verbose yes
zstyle ':completion:*' menu select
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

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
    selected=$(
      fc -nrl 1 | awk '!seen[$0]++' | \
      fzf --height=80% --reverse --tiebreak=index --no-sort \
          --prompt='History> ' --style=minimal --query="$LBUFFER"
    ) || return
    LBUFFER=$selected
    zle redisplay
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

# -------- show --help for command in current buffer (Ctrl-X h)
show-help-for-buffer() {
  emulate -L zsh

  local -a words helpcmd
  words=(${(z)BUFFER})

  while (( $#words )); do
    case "${words[1]}" in
      sudo|command|exec|noglob|time)
        shift words
        ;;
      env)
        shift words
        while (( $#words )) && [[ "${words[1]}" == *=* ]]; do
          shift words
        done
        ;;
      *=*)
        shift words
        ;;
      *)
        break
        ;;
    esac
  done

  if (( $#words == 0 )); then
    zle -M "No command found"
    return
  fi

  local cmd="${words[1]}"
  helpcmd=("$cmd")

  case "$cmd" in
    git|docker|kubectl|cargo|npm|pnpm|yarn|go|gh|brew)
      shift words
      local w
      for w in "${words[@]}"; do
        case "$w" in
          -*|">"|"<"|"|"|"&&"|"||"|";")
            break
            ;;
          *)
            helpcmd+=("$w")
            ;;
        esac
        (( $#helpcmd >= 3 )) && break
      done
      ;;
  esac

  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/zsh-help.XXXXXX")" || return

  zle -I

  "${helpcmd[@]}" --help >"$tmp" 2>&1

  if [[ -s "$tmp" ]]; then
    less -R "$tmp"
  else
    man "$cmd" 2>/dev/null
  fi

  rm -f "$tmp"
  zle reset-prompt
}

zle -N show-help-for-buffer
bindkey '^Xh' show-help-for-buffer

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
