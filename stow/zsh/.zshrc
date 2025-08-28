# shellcheck shell=bash
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
source "$ZSH/oh-my-zsh.sh"

export PATH="$HOME/.local/bin:$PATH:/Users/freedebreuil/tools/depot_tools"

# shellcheck source=$HOME/.config/shell/00-editor.sh
# shellcheck disable=SC1091
[ -f "$HOME/.config/shell/00-editor.sh" ] && . "$HOME/.config/shell/00-editor.sh"

# Load FZF theme if available
[ -f "$HOME/.config/fzf/tokyonight.zsh" ] && source "$HOME/.config/fzf/tokyonight.zsh"

# Tokyo Night theme for bat
export BAT_THEME="tokyonight_night"
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"
