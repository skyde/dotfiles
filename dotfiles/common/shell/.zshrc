# shellcheck shell=zsh
if [[ -o interactive ]]; then
  stty -ixon -ixoff
fi

export PATH=/Users/skydebreuil/Projects/depot_tools:$PATH

# Path setup (add custom bins before system paths)
for d in "$HOME/.local/bin" "$HOME/bin" "/usr/local/bin"; do
  if [[ -d $d ]] && [[ ":$PATH:" != *":$d:"* ]]; then
    export PATH="$d:$PATH"
  fi
done

# Default editor
export EDITOR="nvim"
export VISUAL="$EDITOR"

# Shell Options
setopt autocd             # Enter directory just by typing its name
# Disable automatic command correction
# setopt correct
setopt nocaseglob         # Case insensitive globbing
setopt extended_glob      # Extended globbing
setopt hist_ignore_all_dups  # Don’t store duplicate history
setopt share_history         # Share command history between sessions
setopt inc_append_history     # Append to history file immediately
setopt hist_ignore_space      # Ignore commands starting with spaces
setopt globdots               # Include dotfiles in globbing

# History
HISTSIZE=50000
SAVEHIST=50000
HISTFILE=~/.zsh_history

# # Key Bindings
# bindkey -v                # Use vim keybindings
# KEYTIMEOUT=1              # Reduce delay for ESC
# bindkey -M vicmd '_' vi-beginning-of-line  # '_' moves to start of line in normal mode

bindkey -e                # Use emacs keybindings
bindkey '^[[1;5C' forward-word     # Ctrl+Right
bindkey '^[[1;5D' backward-word    # Ctrl+Left

# Bootstrap Starship
eval "$(starship init zsh)"

# Zsh Plugins: autosuggestions & syntax-highlighting
# Load from common installation paths without relying on brew
for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
  for dir in "/usr/local/share/$plugin" "/opt/homebrew/share/$plugin" "/usr/share/$plugin"; do
    if [[ -r "$dir/$plugin.zsh" ]]; then
      source "$dir/$plugin.zsh"
      break
    fi
  done
done

# Autocomplete
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# zoxide
eval "$(zoxide init zsh)"

# FZF integration
if command -v fzf >/dev/null; then
  for dir in \
    "/usr/share/fzf" \
    "/usr/local/opt/fzf/shell" \
    "/opt/homebrew/opt/fzf/shell" \
    "/usr/share/doc/fzf/examples" \
    "$HOME/.fzf"; do
    if [[ -r "$dir/key-bindings.zsh" ]]; then
      source "$dir/key-bindings.zsh"
      break
    fi
  done
  for dir in \
    "/usr/share/fzf" \
    "/usr/local/opt/fzf/shell" \
    "/opt/homebrew/opt/fzf/shell" \
    "/usr/share/doc/fzf/examples" \
    "$HOME/.fzf"; do
    if [[ -r "$dir/completion.zsh" ]]; then
      source "$dir/completion.zsh"
      break
    fi
  done
  if command -v fd >/dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git --color=always'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  fi
  # if [[ $FIND_IT_FASTER_ACTIVE -eq 1 ]]; then
    # export FZF_DEFAULT_OPTS='--reverse --style=minimal --delimiter : --with-nth 1,4.. --ansi --no-hscroll --keep-right --hscroll-off=60'
    # export FZF_DEFAULT_OPTS='--bind=preview-up:ignore,preview-down:ignore,preview-page-up:ignore,preview-page-down:ignore'
    # "FZF_DEFAULT_OPTS": "--delimiter : --with-nth 1,4.. --ansi --no-hscroll --keep-right --hscroll-off=60"
  # fi
fi

if (( $+commands[fzf] )); then
  function _fzf_history_widget() {
    local selected
    selected=$(
      fc -nrl 1 |                  \
      awk '!seen[$0]++' |          \
      fzf  --height=80%            \
           --reverse               \
           --tiebreak=index        \
           --no-sort               \
           --prompt='History> '    \
           --style=minimal    \
           --query="$LBUFFER"      
    ) || return

    LBUFFER=$selected
    zle redisplay
  }

  zle -N _fzf_history_widget
  bindkey '^R' _fzf_history_widget
fi

# Safer Git defaults on hosts where some tools are unavailable (e.g., corp machines)
# - If delta is missing, fall back to less and plain diffs for interactive mode
# - If VS Code is missing, use Neovim/Vim mergetools instead of the vscode tool
if ! command -v delta >/dev/null || ! command -v code >/dev/null; then
  function git() {
    local -a cfg
    cfg=()
    if ! command -v delta >/dev/null; then
      cfg+=( -c core.pager=less -c interactive.diffFilter=cat )
    fi
    if ! command -v code >/dev/null; then
      if command -v nvim >/dev/null; then
        cfg+=( -c merge.tool=nvimdiff3 -c difftool.tool=nvimdiff )
      else
        cfg+=( -c merge.tool=vimdiff -c difftool.tool=vimdiff )
      fi
    fi
    command git "${cfg[@]}" "$@"
  }
fi

# Aliases
alias z='cd'
alias grep="grep --color=auto"
alias stow_apply='~/dotfiles/apply.sh'
alias stow_init='~/dotfiles/init.sh'
# Favor hidden files but ignore common junk, colorized output
alias rg='rg --hidden --smart-case --colors match:fg:yellow --glob "!.git" --glob "!node_modules"'
# Use modern replacements if available
if command -v bat >/dev/null; then
  alias cat='bat'
elif command -v batcat >/dev/null; then
  # Debian/Ubuntu ship the binary as 'batcat'
  alias bat='batcat'
  alias cat='batcat'
fi
if command -v eza >/dev/null; then
  alias ls='eza --color=auto --group-directories-first'
  alias ll='eza -al --color=auto --group-directories-first'
  alias la='eza -a --color=auto --group-directories-first'
fi
if [[ -z $(command -v fd 2>/dev/null) && -n $(command -v fdfind 2>/dev/null) ]]; then
  alias fd='fdfind'
fi

# Open lf in the current directory and change to its exit path
lfcd() {
  local tmp="$(mktemp -t lfcd.XXXXXX)" dir
  lf "$@" -last-dir-path="$tmp"
  dir=$(cat "$tmp")
  rm -f -- "$tmp"
  [ -n "$dir" ] && [ "$dir" != "$PWD" ] && builtin cd -- "$dir"
}
alias lf='lfcd'

# Load machine-specific overrides, if present
# shellcheck disable=SC1090
[[ -r "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
