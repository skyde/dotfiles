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
# Matched substrings are reverse-video yellow *blocks*, not merely a different
# foreground colour. fzf's highlight replaces only the foreground of the matched
# characters, and in the Ctrl-R picker those characters have already been
# coloured by bat — a blue fg on a line that is already blue, grey and cyan is
# almost impossible to pick out. Inverting fg/bg cannot be lost that way: the
# match reads as a solid block whatever the syntax theme did underneath. hl+ is
# the brighter yellow so matches on the current line, which sits on bg+
# (#283457) rather than the terminal background, keep the same contrast.
_fzf_tn="$_fzf_tn --color=hl:#e0af68:bold:reverse,hl+:#faba4a:bold:reverse"
_fzf_tn="$_fzf_tn --color=info:#bb9af7,marker:#9ece6a"
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
# Which bat, resolved once here rather than checked inside the function below.
#
# Two reasons, and on Debian and Ubuntu both bite at once. The binary is named
# `batcat` there, so looking only for `bat` finds nothing and the highlighting
# silently degrades to plain text — on the distros these dotfiles install bat
# from. And once ~/.zshrc has aliased `bat=batcat` for interactive use, a
# call-time `command -v bat` starts *succeeding*, because zsh's `command -v`
# reports aliases: the guard passed while the function body — parsed here, from
# ~/.zshenv, long before that alias existed — still resolved `bat` as a command
# and failed with "command not found: bat" on every keystroke in Ctrl-R.
#
# This file is sourced before any alias is defined, so the lookup is honest.
_fzf_bat=
if command -v bat >/dev/null 2>&1; then
	_fzf_bat=bat
elif command -v batcat >/dev/null 2>&1; then
	_fzf_bat=batcat
fi

fzf_history_highlight() {
	if [ -n "$_fzf_bat" ]; then
		COLORTERM=truecolor "$_fzf_bat" --color=always --language=bash \
			--style=plain --paging=never --wrap=never
	else
		command cat
	fi
}

# Preview pane for the same picker: re-highlight the focused entry, wrapped, so
# a long command is readable in full rather than cut off at the pane edge.
# Single-quoted on purpose — {} and FZF_PREVIEW_COLUMNS are expanded by fzf when
# it runs the preview, not by this shell when the string is defined.
# shellcheck disable=SC2016,SC2089
if [ -n "$_fzf_bat" ]; then
	FZF_HISTORY_PREVIEW='printf "%s\n" {} | COLORTERM=truecolor '"$_fzf_bat"' --color=always --language=bash --style=plain --paging=never --wrap=character --terminal-width=${FZF_PREVIEW_COLUMNS:-80}'
else
	FZF_HISTORY_PREVIEW='printf "%s\n" {}'
fi
# shellcheck disable=SC2090
export FZF_HISTORY_PREVIEW
