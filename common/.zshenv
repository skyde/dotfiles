# -------- fast PATH (prefer user bins; include Homebrew on Apple Silicon)
#
# One assignment, highest precedence first. `typeset -U` keeps the array
# unique, so a directory already present further down is dropped rather than
# duplicated. This replaced six successive `export PATH="...:$PATH"` lines
# that each rebuilt and re-split the whole string, and which re-listed
# .local/bin, local/bin and bin that the first line had already added — the
# resulting order was the accident of which line ran last. The order below is
# exactly what that sequence produced, kept verbatim so nothing that depends
# on it shifts.
typeset -U path PATH
path=(
  "$HOME/depot_tools"
  "$HOME/.cargo/bin"   # Rust
  "$HOME/go/bin"       # Go
  "$HOME/bin"
  "$HOME/.local/bin"   # custom scripts
  "$HOME/local/bin"
  /opt/homebrew/bin    # Homebrew on Apple Silicon
  /usr/local/bin
  $path
)

export SKIP_GCE_AUTH_FOR_GIT=1

# Point DISPLAY at the first live X socket, for X11 forwarding.
#
# Guarded on the socket directory existing, and matched with a zsh glob rather
# than find|grep|head. This file is sourced by *every* zsh, including the
# non-interactive ones every script and tool spawns, and the unguarded version
# cost three processes each time. Worse, on a machine with no X11 at all — any
# Mac — `find` wrote "No such file or directory" to the stderr of every one of
# those shells, and the empty command substitution still exported `DISPLAY=:`,
# a malformed display spec that an X client reaching for it would choke on.
# Now: no processes, no output, and DISPLAY is only set when a socket is real.
if [[ -z ${DISPLAY} && -d /tmp/.X11-unix ]]; then
  _x_sockets=(/tmp/.X11-unix/X<->(N))
  (( $#_x_sockets )) && export DISPLAY=":${_x_sockets[1]##*/X}"
  unset _x_sockets
fi

if (( $+commands[fzf] )); then
  export FZF_DEFAULT_COMMAND='rg --files --follow'
fi

# Tokyo Night colours for the shell's tooling, shared with bash.
# See docs/tokyonight.md.
#
# Outside the fzf guard above, and deliberately: this file themes ls, eza,
# grep, man pages and the line editor as well as fzf's own layout, and a box
# without fzf installed still has every one of those. It starts no processes
# and reads no files, so it is safe on the path of every non-interactive zsh.
# shellcheck disable=SC1091
[ -r "$HOME/.config/shell/theme.sh" ] && . "$HOME/.config/shell/theme.sh"

# ripgrep: hidden files, smart case, ignore common junk
export RIPGREP_CONFIG_PATH=~/.ripgreprc
export BAT_THEME="Visual Studio Dark+"
