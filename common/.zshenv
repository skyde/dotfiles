# -------- fast PATH (prefer user bins; include Homebrew on Apple Silicon)
# Use array 'path' (zsh feature) with uniqueness to avoid string scans.
typeset -U path PATH
path=(
  "$HOME/.local/bin"
  "$HOME/local/bin"
  "$HOME/bin"
  "$HOME/go/bin"
  "$HOME/.cargo/bin"
  "$HOME/depot_tools"
  "/opt/homebrew/bin"
  "/usr/local/bin"
  $path
)
export SKIP_GCE_AUTH_FOR_GIT=1

# Set DISPLAY to the correct value
if [[ -z "${DISPLAY:-}" ]]; then
  _dotfiles_x11_unix_dir="${DOTFILES_X11_UNIX_DIR:-/tmp/.X11-unix}"
  if [[ -d "$_dotfiles_x11_unix_dir" ]]; then
    _dotfiles_x_display="$(
      find "$_dotfiles_x11_unix_dir" -maxdepth 1 -mindepth 1 -name 'X*' 2>/dev/null |
        sed -n 's#.*/X\([0-9][0-9]*\)$#\1#p' |
        head -n 1
    )"
    if [[ -n "$_dotfiles_x_display" ]]; then
      export DISPLAY=":$_dotfiles_x_display"
    fi
  fi
  unset _dotfiles_x11_unix_dir _dotfiles_x_display
fi

if (( $+commands[fzf] )); then
  export FZF_DEFAULT_COMMAND='rg --files --follow'
  export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:-} \
    --reverse \
    --ansi \
    --info=inline \
    --style=minimal \
    --no-cycle \
    --color=prompt:#80a0ff,pointer:#ff5000,marker:#afff5f,hl:215,hl+:215"
fi

# ripgrep: hidden files, smart case, ignore common junk
export RIPGREP_CONFIG_PATH=~/.ripgreprc
export BAT_THEME="Visual Studio Dark+"
