# -------- fast PATH (prefer user bins; include Homebrew on Apple Silicon)
# Use array 'path' (zsh feature) with uniqueness to avoid string scans.
if [ -n "$ZSH_VERSION" ]; then
  typeset -U path PATH
fi
path=("$HOME/.local/bin" "$HOME/local/bin" "$HOME/bin" "/opt/homebrew/bin" "/usr/local/bin" $path)

# Custom scripts
export PATH="$HOME/.local/bin:$HOME/local/bin:$PATH"

# Additional custom scripts
export PATH="$HOME/bin:$PATH"

# Go programs
export PATH="$HOME/go/bin:$PATH"

# Rust programs
export PATH="$HOME/.cargo/bin:$PATH"

# Custom
export PATH="$HOME/depot_tools:$PATH"
export SKIP_GCE_AUTH_FOR_GIT=1

# Set DISPLAY to the correct value
if [[ -z "${DISPLAY}" ]]; then
  export DISPLAY=:$(
    find /tmp/.X11-unix -maxdepth 1 -mindepth 1 -name 'X*' |
      grep -o '[0-9]\+$' | head -n 1
  )
fi

if (( $+commands[fzf] )); then
  export FZF_DEFAULT_COMMAND='rg --files --follow'
  if [[ -r "$HOME/.config/fzf/tokyonight.sh" ]]; then
    source "$HOME/.config/fzf/tokyonight.sh"
  fi
fi

# ripgrep: hidden files, smart case, ignore common junk
export RIPGREP_CONFIG_PATH=~/.ripgreprc
export BAT_THEME="Visual Studio Dark+"
