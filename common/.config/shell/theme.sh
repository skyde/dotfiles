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

# --- Ctrl-R history highlighting ------------------------------------------
# Syntax-highlight the history entries in the Ctrl-R picker with the same
# BAT_THEME as bat, delta, VS Code and the yazi preview.
#
# --wrap=never is not optional: if bat wrapped, one long history entry would
# arrive at fzf as several lines and become several separate, unrunnable
# candidates. One input line must stay one output line.
#
# fzf strips the escape sequences back out of the value it returns (given
# --ansi), so what lands on the command line is the original command, byte for
# byte — the colour is display-only.
#
# COLORTERM is forced for the same reason as in the yazi previewer: bat decides
# 24-bit vs the 256-colour cube from it, and it is not reliably set under tmux,
# the VS Code terminal, or over ssh. Without it the history quietly renders in
# approximated colours that do not match anything else.
fzf_history_highlight() {
	if command -v bat >/dev/null 2>&1; then
		COLORTERM=truecolor bat --color=always --language=bash \
			--style=plain --paging=never --wrap=never
	else
		cat
	fi
}

# Preview pane for the same picker: re-highlight the focused entry, wrapped, so
# a long command is readable in full rather than cut off at the pane edge.
# Single-quoted on purpose — {} and FZF_PREVIEW_COLUMNS are expanded by fzf when
# it runs the preview, not by this shell when the string is defined.
# shellcheck disable=SC2016,SC2089
if command -v bat >/dev/null 2>&1; then
	FZF_HISTORY_PREVIEW='printf "%s\n" {} | COLORTERM=truecolor bat --color=always --language=bash --style=plain --paging=never --wrap=character --terminal-width=${FZF_PREVIEW_COLUMNS:-80}'
else
	FZF_HISTORY_PREVIEW='printf "%s\n" {}'
fi
# shellcheck disable=SC2090
export FZF_HISTORY_PREVIEW
