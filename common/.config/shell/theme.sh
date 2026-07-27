# shellcheck shell=sh
# Tokyo Night (night) colours for shell tooling.
# Sourced by both ~/.zshenv and ~/.bashrc-custom so the two shells cannot drift.
# Palette reference: docs/tokyonight.md

# --- fzf -------------------------------------------------------------------
# The pointer stays #ff5000, the same hot orange as the terminal and Neovim
# cursor. It is deliberately not a Tokyo Night colour: it is the "you are here"
# marker across every tool, so it has to win against the rest of the palette.
#
# bg and gutter are left at -1 (terminal default) rather than pinned to #1a1b26
# so fzf stays transparent inside tmux popups instead of painting a background
# that is a shade off from whatever is behind it.
#
# Built up in pieces rather than one multi-line string: fzf only learned to
# accept newlines in FZF_DEFAULT_OPTS in 0.48, and these dotfiles land on boxes
# with older builds.
_fzf_tn='--color=fg:#c0caf5,fg+:#c0caf5,bg:-1,bg+:#283457'
_fzf_tn="$_fzf_tn --color=hl:#7aa2f7,hl+:#7dcfff,info:#bb9af7,marker:#9ece6a"
_fzf_tn="$_fzf_tn --color=prompt:#7aa2f7,spinner:#ff9e64,pointer:#ff5000"
_fzf_tn="$_fzf_tn --color=header:#7aa2f7,border:#292e42,separator:#292e42"
_fzf_tn="$_fzf_tn --color=scrollbar:#3b4261,gutter:-1,label:#565f89,query:#c0caf5"

FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS --reverse --ansi --info=inline --style=minimal --no-cycle $_fzf_tn"
export FZF_DEFAULT_OPTS
unset _fzf_tn
