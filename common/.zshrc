
# shellcheck shell=zsh

# -------- editor
export EDITOR="nvim"
export VISUAL="$EDITOR"

# -------- interactive TTY tweaks (skip in non‑tty to avoid extra 'stty' call)
if [[ -o interactive && -t 0 && "${DOTFILES_TEST_SKIP_COMPLETION:-0}" != 1 ]]; then
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
bindkey '^[[127;5u' backward-kill-word  # Ctrl+Backspace
bindkey '^[[3;5~' kill-word             # Ctrl+Delete
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X' edit-command-line          # Ctrl+X edits current prompt

# -------- completion (cached)
# Cache to XDG location and compile the dump for speed.
if [[ -o interactive && -t 0 && "${DOTFILES_TEST_SKIP_COMPLETION:-0}" != 1 ]]; then
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
fi

# # -------- prompt (Starship)
if (( $+commands[starship] )); then
  eval "$(starship init zsh)"
fi

# -------- zoxide (smart cd)
if (( $+commands[zoxide] )); then
  # Initialize immediately so `z` works on the very first command
  eval "$(zoxide init zsh)"
fi

_dotfiles_tmux_client_live() {
  [[ -n "${TMUX:-}" ]] || return 1
  (( $+commands[tmux] )) || return 1
  tmux display-message -p '#{pane_id}' >/dev/null 2>&1
}

_dotfiles_fzf_supports_tmux() {
  local help

  help="$(fzf --help 2>/dev/null || true)"
  [[ "$help" == *--tmux* ]]
}

_dotfiles_fzf_history_candidates() {
  local line seen=$'\n'

  fc -nrl 1 2>/dev/null | while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    [[ "$seen" == *$'\n'"$line"$'\n'* ]] && continue
    seen="${seen}${line}"$'\n'
    print -r -- "$line"
  done
}

# -------- fzf-powered history search (Ctrl-R)
if [[ -o interactive && -t 0 ]] && (( $+commands[fzf] )); then
  _fzf_ctrl_r_opts="--height=80% --min-height=20 --layout=reverse --wrap --prompt='History> ' --with-nth=2.. --preview='printf \"%s\n\" {2..}' --preview-window='down,4,wrap,hidden' --bind='alt-p:toggle-preview' --header='Ctrl-R sort | Alt-R all | Alt-P preview | Ctrl-/ wrap'"
  # Prefer fzf's native tmux popup for Ctrl-R, unless local config opts into
  # fzf-tmux through FZF_TMUX/FZF_TMUX_OPTS.
  if [[ "${FZF_TMUX:-0}" == 0 && -z "${FZF_TMUX_OPTS:-}" ]] &&
    _dotfiles_tmux_client_live &&
    _dotfiles_fzf_supports_tmux; then
    _tmux_version="${$(tmux -V 2>/dev/null)#tmux }"
    if [[ "$_tmux_version" =~ '^([4-9]|[1-9][0-9])\.' || "$_tmux_version" =~ '^3\.([3-9]|[1-9][0-9])' ]]; then
      _fzf_ctrl_r_opts="--tmux=center,90%,70% $_fzf_ctrl_r_opts"
    fi
  fi
  export FZF_CTRL_R_OPTS="$_fzf_ctrl_r_opts${FZF_CTRL_R_OPTS:+ $FZF_CTRL_R_OPTS}"

  _fzf_loaded=0
  _fzf_restore_ctrl_t=0
  _fzf_restore_alt_c=0
  # Load fzf's maintained history widget, but keep other zle bindings at their
  # defaults unless the user explicitly configured those fzf widgets.
  if [[ -z "${FZF_CTRL_T_COMMAND+x}" ]]; then
    FZF_CTRL_T_COMMAND=
    _fzf_restore_ctrl_t=1
  fi
  if [[ -z "${FZF_ALT_C_COMMAND+x}" ]]; then
    FZF_ALT_C_COMMAND=
    _fzf_restore_alt_c=1
  fi

  if [[ "${DOTFILES_TEST_SKIP_FZF_SHELL_DIRS:-0}" != 1 ]]; then
    for _fzf_shell_dir in \
      "/opt/homebrew/opt/fzf/shell" \
      "/usr/local/opt/fzf/shell" \
      "/usr/share/fzf" \
      "/usr/share/doc/fzf/examples" \
      "$HOME/.fzf/shell" \
      "$HOME/.fzf"
    do
      if [[ -r "$_fzf_shell_dir/key-bindings.zsh" ]]; then
        source "$_fzf_shell_dir/key-bindings.zsh"
        _fzf_loaded=1
        break
      fi
    done
  fi

  if (( ! _fzf_loaded )); then
    _fzf_zsh_integration="$(fzf --zsh 2>/dev/null)"
    if [[ -n "$_fzf_zsh_integration" ]]; then
      # `fzf --zsh` also emits completion setup; only Ctrl-R is intended here.
      eval "${_fzf_zsh_integration%%$'\n### completion.zsh ###'*}"
      _fzf_loaded=1
    fi
  fi

  if (( ! _fzf_loaded )); then
    _fzf_history_widget_fallback() {
      local selected
      selected=$(
        _dotfiles_fzf_history_candidates | \
        fzf --height=80% --layout=reverse --min-height=20 \
            --tiebreak=index --no-sort --scheme=history --wrap \
            --preview='printf "%s\n" {}' --preview-window='down,4,wrap,hidden' \
            --bind='ctrl-r:toggle-sort,alt-p:toggle-preview' \
            --header='Ctrl-R sort | Alt-P preview | Ctrl-/ wrap' \
            --prompt='History> ' --style=minimal --query="$LBUFFER"
      ) || return
      BUFFER=$selected
      CURSOR=${#BUFFER}
      zle reset-prompt
    }
    zle -N _fzf_history_widget_fallback
    bindkey '^R' _fzf_history_widget_fallback
  fi
  (( _fzf_restore_ctrl_t )) && unset FZF_CTRL_T_COMMAND
  (( _fzf_restore_alt_c )) && unset FZF_ALT_C_COMMAND
  unset _fzf_ctrl_r_opts _fzf_loaded _fzf_shell_dir _fzf_zsh_integration _fzf_restore_ctrl_t _fzf_restore_alt_c _tmux_version
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
  local socket socket_dir found=0
  if (( $+commands[nc] )); then
    local -a sockets=()
    [[ -n "${VSCODE_IPC_HOOK_CLI:-}" ]] && sockets+=("${VSCODE_IPC_HOOK_CLI}")
    socket_dir="${DOTFILES_VSCODE_IPC_DIR:-/run/user/$UID}"
    if [[ -d "$socket_dir" ]]; then
      sockets+=("$socket_dir"/vscode-ipc-*.sock(N))
    fi
    for socket in "${sockets[@]}"; do
      if [[ -S "$socket" ]] && nc -z -U "$socket" >/dev/null 2>&1; then
        export VSCODE_IPC_HOOK_CLI="$socket"
        found=1
        break
      fi
    done
    (( found )) || unset VSCODE_IPC_HOOK_CLI
  fi
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
  local tmp cwd yazi_cmd rc
  tmp="$(mktemp -t yazi-cwd.XXXXXX)"
  if [[ -x "$HOME/.local/bin/yazi" ]]; then
    yazi_cmd="$HOME/.local/bin/yazi"
  elif (( $+commands[yazi] )); then
    yazi_cmd="$commands[yazi]"
  else
    print -u2 "e: yazi not found"
    rm -f -- "$tmp"
    return 127
  fi
  "$yazi_cmd" "$@" --cwd-file="$tmp"
  rc=$?
  if [[ -r "$tmp" ]]; then
    cwd="$(<"$tmp")"
  else
    cwd=""
  fi
  rm -f -- "$tmp"
  if (( rc == 0 )) && [[ -n $cwd && $cwd != "$PWD" ]]; then
    builtin cd -- "$cwd" || return
  fi
  return "$rc"
}

lfcd() {
  local tmp dir rc
  tmp="$(mktemp -t lfcd.XXXXXX)"
  if ((! $+commands[lf] )); then
    print -u2 "lfcd: lf not found"
    rm -f -- "$tmp"
    return 127
  fi
  "$commands[lf]" -last-dir-path "$tmp" -- "$@"
  rc=$?
  if [[ -r "$tmp" ]]; then
    dir="$(<"$tmp")"
  else
    dir=""
  fi
  rm -f -- "$tmp"
  if (( rc == 0 )) && [[ -n $dir && $dir != "$PWD" ]]; then
    builtin cd -- "$dir" || return
  fi
  return "$rc"
}
alias lf='lfcd'

# Keep inherited pager settings from overriding the git wrapper's fallback
# `-c core.pager=less` when delta is unavailable.
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
