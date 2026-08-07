# shellcheck shell=sh
# Tokyo Night (night) colours for shell tooling.
# Sourced by both ~/.zshenv and ~/.bashrc-custom so the two shells cannot drift.
# Palette reference: docs/tokyonight.md
#
# Sourced unconditionally, not from inside an `if fzf` guard: most of what is
# below (LS_COLORS, the man page colours) has nothing to do with fzf, and the
# fzf half costs nothing but a few hundred bytes of environment on a box that
# has no fzf installed.

# --- palette ---------------------------------------------------------------
# The hexes as SGR parameters, since none of the tools below take hex.
# 38;2;R;G;B is a truecolor foreground, 48;2;R;G;B a background.
_tn_fg='38;2;192;202;245'      # fg       #c0caf5
_tn_fg_dark='38;2;169;177;214' # fg_dark  #a9b1d6
_tn_comment='38;2;86;95;137'   # comment  #565f89
_tn_dark5='38;2;115;122;162'   # dark5    #737aa2
_tn_gutter='38;2;59;66;97'     # fg_gutter #3b4261
_tn_red='38;2;247;118;142'     # red      #f7768e
_tn_green='38;2;158;206;106'   # green    #9ece6a
_tn_yellow='38;2;224;175;104'  # yellow   #e0af68
_tn_blue='38;2;122;162;247'    # blue     #7aa2f7
_tn_magenta='38;2;187;154;247' # magenta  #bb9af7
_tn_cyan='38;2;125;207;255'    # cyan     #7dcfff
_tn_orange='38;2;255;158;100'  # orange   #ff9e64
_tn_purple='38;2;157;124;216'  # purple   #9d7cd8
_tn_teal='38;2;26;188;156'     # teal     #1abc9c

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

# --- ls / eza / fd / zsh completion ----------------------------------------
# One LS_COLORS, honoured by GNU ls, eza, fd and (via a zstyle in ~/.zshrc)
# zsh's own completion menu. Without it those four fall back to their built-in
# palettes, which is why a directory used to be a different blue in `ls` than
# in lf, yazi and the completion list.
#
# This table is the same one as common/.config/lf/colors, key for key and
# extension for extension — lf reads LS_COLORS from the environment but keeps
# its own file for the times it is launched without one, and yazi's
# [filetype] rules say the same thing again in yazi's own schema. Three copies
# of one table is two too many to keep in step by hand, so
# tests/check-theme.py compares them and fails on any drift. Change one, change
# all three, run the test.
#
# Built through a helper rather than one 3KB literal so the categories stay
# diffable against lf/colors. No subprocesses: the loop is a shell builtin and
# this file is sourced by every shell, including non-interactive ones.
#
# Every expansion below is braced, and that is load-bearing rather than a style
# choice. LS_COLORS is colon-separated, and zsh reads a colon after an unbraced
# `$var` as the start of a history modifier: `$_tn_yellow:so=...` is parsed as
# the `:s` substitution modifier with `o` for a delimiter, which aborts the
# assignment with "bad substitution". bash has no such rule, so an unbraced
# version looks perfectly fine until a zsh reads it — and then quietly loses
# every entry after the first colon-plus-letter. ${_tn_yellow} ends the
# expansion before the colon and both shells agree again.
_tn_ext() { # _tn_ext <sgr> <ext>...
	_tn_c=$1
	shift
	for _tn_e in "$@"; do
		LS_COLORS="${LS_COLORS}:*.${_tn_e}=${_tn_c}"
	done
}

# File kinds. The paired fg/bg entries spell out both halves: a background is
# only legible against a foreground picked for it, so su/sg/tw/st put bg_dark
# or fg on top of the accent rather than leaving the terminal's own colour.
LS_COLORS="di=${_tn_blue};1:ln=${_tn_cyan}:mh=${_tn_cyan}:or=${_tn_red};1"
LS_COLORS="${LS_COLORS}:ex=${_tn_green}:fi=${_tn_fg}:pi=${_tn_yellow}:so=${_tn_magenta}"
LS_COLORS="${LS_COLORS}:bd=${_tn_yellow};48;2;41;46;66:cd=${_tn_yellow};48;2;41;46;66"
LS_COLORS="${LS_COLORS}:su=38;2;22;22;30;48;2;247;118;142"
LS_COLORS="${LS_COLORS}:sg=38;2;22;22;30;48;2;224;175;104"
LS_COLORS="${LS_COLORS}:tw=38;2;22;22;30;48;2;158;206;106"
LS_COLORS="${LS_COLORS}:ow=${_tn_blue};48;2;40;52;87"
LS_COLORS="${LS_COLORS}:st=${_tn_fg};48;2;122;162;247"

_tn_ext "${_tn_red}" tar tgz gz bz2 xz zst zip 7z rar deb rpm dmg
_tn_ext "${_tn_magenta}" png jpg jpeg gif webp svg ico mp4 mkv mov webm
_tn_ext "${_tn_purple}" mp3 flac wav m4a ogg
_tn_ext "${_tn_orange}" pdf epub djvu docx xlsx pptx
_tn_ext "${_tn_green}" c h cc cpp hpp cs go rs py rb js ts tsx jsx lua sh zsh bash ps1
_tn_ext "${_tn_yellow}" json toml yaml yml ini conf cfg xml
_tn_ext "${_tn_fg}" md txt rst
_tn_ext "${_tn_comment}" log bak tmp swp o pyc lock

export LS_COLORS
unset -f _tn_ext
unset _tn_c _tn_e

# eza draws columns LS_COLORS has no vocabulary for. These are its own keys
# (`man eza_colors`), applied on top of LS_COLORS rather than replacing it —
# no leading `reset`, so any extension not in the table above keeps eza's
# built-in colour, which is ANSI-indexed and therefore already Tokyo Night by
# way of the terminal palette.
#
# The permission columns deliberately match yazi's [status] perm_* keys, so
# drwxr-xr-x reads the same in `ls -l` as it does in yazi's footer: read
# yellow, write red, execute green, and the dashes between them in the gutter
# grey that yazi calls perm_sep.
EZA_COLORS="ur=${_tn_yellow}:uw=${_tn_red}:ux=${_tn_green}:ue=${_tn_green}"
EZA_COLORS="${EZA_COLORS}:gr=${_tn_yellow}:gw=${_tn_red}:gx=${_tn_green}"
EZA_COLORS="${EZA_COLORS}:tr=${_tn_yellow}:tw=${_tn_red}:tx=${_tn_green}"
EZA_COLORS="${EZA_COLORS}:su=${_tn_orange}:sf=${_tn_orange}:xx=${_tn_gutter}"
# Sizes, owners and dates are context, not content: quieter than the names.
EZA_COLORS="${EZA_COLORS}:sn=${_tn_fg_dark}:sb=${_tn_dark5}:df=${_tn_dark5}:ds=${_tn_dark5}"
EZA_COLORS="${EZA_COLORS}:uu=${_tn_teal}:un=${_tn_dark5}:gu=${_tn_dark5}:gn=${_tn_comment}"
EZA_COLORS="${EZA_COLORS}:lc=${_tn_comment}:lm=${_tn_orange}:da=${_tn_comment}:in=${_tn_comment}"
EZA_COLORS="${EZA_COLORS}:bl=${_tn_comment}:hd=${_tn_blue};1:lp=${_tn_cyan}:bO=${_tn_red};4"
# Git flags follow the same meanings the rest of the repo uses: teal is new or
# untracked (docs/tokyonight.md), yellow modified, red deleted, magenta moved.
EZA_COLORS="${EZA_COLORS}:ga=${_tn_teal}:gm=${_tn_yellow}:gd=${_tn_red}:gv=${_tn_magenta}"
EZA_COLORS="${EZA_COLORS}:gt=${_tn_cyan}:gi=${_tn_comment}:gc=${_tn_orange}"
export EZA_COLORS

# --- man pages -------------------------------------------------------------
# less renders man's bold/underline/standout with the terminal's defaults,
# which on this palette means near-white bold and an underline you cannot
# distinguish from a URL. LESS_TERMCAP_* replaces those three with palette
# colours, so a man page reads like every other pane.
#
# The values are raw escape sequences; printf builds them so this stays POSIX
# (no $'...' in sh). \033 rather than \e for the same reason: dash's printf
# does not know \e.
LESS_TERMCAP_md=$(printf '\033[%sm' "1;$_tn_blue")    # bold: headings, names
LESS_TERMCAP_me=$(printf '\033[0m')                   # end of every mode
LESS_TERMCAP_us=$(printf '\033[4;%sm' "$_tn_green")   # underline: arguments
LESS_TERMCAP_ue=$(printf '\033[0m')
LESS_TERMCAP_so=$(printf '\033[%s;48;2;41;46;66m' "$_tn_orange") # the prompt line
LESS_TERMCAP_se=$(printf '\033[0m')
export LESS_TERMCAP_md LESS_TERMCAP_me LESS_TERMCAP_us LESS_TERMCAP_ue
export LESS_TERMCAP_so LESS_TERMCAP_se

# GROFF_NO_SGR is what makes the above take effect on modern groff: without
# it groff emits SGR sequences of its own and less never consults termcap.
export GROFF_NO_SGR=1

unset _tn_fg _tn_fg_dark _tn_comment _tn_dark5 _tn_gutter
unset _tn_red _tn_green _tn_yellow _tn_blue _tn_magenta _tn_cyan
unset _tn_orange _tn_purple _tn_teal
