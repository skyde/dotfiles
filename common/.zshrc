# shellcheck shell=zsh

# --- interactive TTY tweaks
[[ -o interactive ]] && stty -ixon -ixoff

# --- PATH (prefer user bins; include Homebrew on Apple Silicon)
for d in "$HOME/.local/bin" "$HOME/bin" "/opt/homebrew/bin" "/usr/local/bin"; do
  [[ -d $d ]] && [[ :$PATH: != *":$d:"* ]] && PATH="$d:$PATH"
done
export PATH

# --- editor
export EDITOR="nvim"
export VISUAL="$EDITOR"

# --- shell options
setopt autocd nocaseglob extended_glob globdots
setopt hist_ignore_all_dups hist_ignore_space
setopt share_history inc_append_history append_history

# --- history
HISTSIZE=1000000
SAVEHIST=1000000
HISTFILE="$HOME/.zsh_history"

# --- key bindings
bindkey -e                              # Emacs keybindings
bindkey '^[[1;5C' forward-word          # Ctrl+Right
bindkey '^[[1;5D' backward-word         # Ctrl+Left

# --- completion
autoload -Uz compinit
compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# --- prompt (Starship)
eval "$(starship init zsh)"

# --- zoxide (smart cd)
if command -v zoxide >/dev/null; then
  eval "$(zoxide init zsh)"
fi

# --- FZF integration
_source_first() {  # source the first readable file from args
  local f; for f in "$@"; do [[ -r $f ]] && source "$f" && return 0; done; return 1
}
if command -v fzf >/dev/null; then
  _source_first \
    "/usr/share/fzf/key-bindings.zsh" \
    "/usr/local/opt/fzf/shell/key-bindings.zsh" \
    "/opt/homebrew/opt/fzf/shell/key-bindings.zsh" \
    "/usr/share/doc/fzf/examples/key-bindings.zsh" \
    "$HOME/.fzf/shell/key-bindings.zsh" "$HOME/.fzf/key-bindings.zsh"
  _source_first \
    "/usr/share/fzf/completion.zsh" \
    "/usr/local/opt/fzf/shell/completion.zsh" \
    "/opt/homebrew/opt/fzf/shell/completion.zsh" \
    "/usr/share/doc/fzf/examples/completion.zsh" \
    "$HOME/.fzf/shell/completion.zsh" "$HOME/.fzf/completion.zsh"
  if command -v fd >/dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS \
      --reverse \
      --ansi \
      --tiebreak=pathname \
      --info=inline \
      --no-cycle \
      --color=prompt:#80a0ff,pointer:#ff5000,marker:#afff5f \
      --delimiter=: \
      --preview='bat --style=numbers --color=always --line-range :500 {}' \
      --preview-window=right,55%"
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  fi
fi

# --- fzf-powered history search (Ctrl-R), deduped & reverse-chronological
if (( $+commands[fzf] )); then
  _fzf_history_widget() {
    local selected
    selected=$( \
      fc -nrl 1 | awk '!seen[$0]++' | \
      fzf --height=80% --reverse --tiebreak=index --no-sort \
          --prompt='History> ' --style=minimal --query="$LBUFFER" \
    ) || return
    LBUFFER=$selected
    zle redisplay
  }
  zle -N _fzf_history_widget
  bindkey '^R' _fzf_history_widget
fi

# --- safer Git defaults where tools may be missing
if ! command -v delta >/dev/null || ! command -v code >/dev/null; then
  git() {
    local -a cfg=()
    if ! command -v delta >/dev/null; then
      cfg+=(-c core.pager=less -c interactive.diffFilter=cat)
    fi
    if ! command -v code >/dev/null; then
      if command -v nvim >/dev/null; then
        cfg+=(-c merge.tool=nvimdiff3 -c difftool.tool=nvimdiff)
      else
        cfg+=(-c merge.tool=vimdiff -c difftool.tool=vimdiff)
      fi
    fi
    command git "${cfg[@]}" "$@"
  }
fi

# --- aliases
alias grep='grep --color=auto'
alias stow_apply='$HOME/dotfiles/apply.sh'
alias stow_init='$HOME/dotfiles/init.sh'
alias stow_update='$HOME/dotfiles/update.sh && $HOME/dotfiles/apply.sh'
alias stow_update_init_auto='$HOME/dotfiles/update.sh && AUTO_INSTALL=1 $HOME/dotfiles/init.sh'

# ripgrep: hidden files, smart case, ignore common junk
alias rg='rg --hidden --smart-case --colors match:fg:yellow --glob "!.git" --glob "!node_modules"'

# bat / batcat
if command -v bat >/dev/null; then
  alias cat='bat'
elif command -v batcat >/dev/null; then
  alias bat='batcat'
  alias cat='batcat'
fi

# eza ls replacements
if command -v eza >/dev/null; then
  alias ls='eza --color=auto --group-directories-first'
  alias ll='eza -al --color=auto --group-directories-first'
  alias la='eza -a --color=auto --group-directories-first'
  alias tree='eza --tree --icons --group-directories-first'
fi

# fd on Debian/Ubuntu where it's named fdfind
if [[ -z $(command -v fd 2>/dev/null) && -n $(command -v fdfind 2>/dev/null) ]]; then
  alias fd='fdfind'
fi

# --- file managers that cd to the last visited dir
y() {
  local tmp cwd
  tmp="$(mktemp -t yazi-cwd.XXXXXX)"
  command yazi "$@" --cwd-file="$tmp"
  cwd="$(<"$tmp")"
  rm -f -- "$tmp"
  [[ -n $cwd && $cwd != "$PWD" ]] && builtin cd -- "$cwd"
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

gg() {
  command lazygit
}

# --- plugins (load AFTER compinit & prompt; keep syntax-highlighting last)
for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
  for dir in "/opt/homebrew/share/$plugin" "/usr/local/share/$plugin" "/usr/share/$plugin"; do
    if [[ -r "$dir/$plugin.zsh" ]]; then
      source "$dir/$plugin.zsh"
      break
    fi
  done
done

# --- machine-specific overrides
# shellcheck disable=SC1090
[[ -r "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
