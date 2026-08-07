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

# -------- editor
#
# In .zshenv rather than .zshrc because .zshrc is only read by *interactive*
# shells. `git commit` invoked from a script, `sudoedit`, `crontab -e`, and
# anything else that shells out to `zsh -c` all read EDITOR too, and every one
# of them used to fall back to whatever the system default was (usually vi)
# while an interactive shell got nvim.
export EDITOR="nvim"
export VISUAL="$EDITOR"

# -------- pager
#
# -R  keep colour escapes (delta, bat, git) instead of printing them literally
# -F  don't page output that already fits on one screen
# -i  case-insensitive search until you type an uppercase letter
# -M  a status line with position, so long output tells you where you are
# LESSHISTFILE=- stops less from dropping a ~/.lesshst in HOME.
export PAGER="less"
export LESS="-RFiM"
export LESSHISTFILE="-"

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
  # Layout + Tokyo Night colours, shared with bash. See docs/tokyonight.md.
  # shellcheck disable=SC1091
  [ -r "$HOME/.config/shell/theme.sh" ] && . "$HOME/.config/shell/theme.sh"
fi

# ripgrep: hidden files, smart case, ignore common junk
export RIPGREP_CONFIG_PATH=~/.ripgreprc
export BAT_THEME="Visual Studio Dark+"

# Man pages through bat, so they get the same theme as everything else.
#
# Debian/Ubuntu ship the binary as `batcat` (the name `bat` belongs to another
# package), which is why both are checked. `col -bx` strips the overstrike
# backspaces groff emits for bold and underline — without it bat renders
# "^Hf^Ho^Ho". MANROFFOPT=-c stops groff from re-adding them via its own
# colour handling, which otherwise leaves stray escapes on newer groff.
if (( $+commands[bat] )); then
  export MANPAGER="sh -c 'col -bx | bat --language=man --style=plain --color=always'"
  export MANROFFOPT="-c"
elif (( $+commands[batcat] )); then
  export MANPAGER="sh -c 'col -bx | batcat --language=man --style=plain --color=always'"
  export MANROFFOPT="-c"
fi
