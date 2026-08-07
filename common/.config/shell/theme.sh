# shellcheck shell=bash
# Tokyo Night (night) colours for shell tooling.
# Sourced by both ~/.zshenv and ~/.bashrc-custom so the two shells cannot drift.
# Palette reference: docs/tokyonight.md
#
# Declared as bash rather than sh for shellcheck's benefit only. The two files
# above are the only things that ever source this, so zsh and bash are the only
# shells it runs in, and both understand the $'\033' quoting the man-page
# section needs. Building those escapes the POSIX way costs a subshell each,
# and this file is on the startup path of every non-interactive zsh that every
# script and tool spawns -- the same reason .zshenv works so hard to avoid
# forks.
#
# Everything here is a variable assignment. No process is started, no file is
# read, and nothing depends on a tool being installed: a colour set for a tool
# that is absent simply never gets read.

# --- Palette ---------------------------------------------------------------
# The accents as SGR truecolor fragments, so the settings below read as colour
# names instead of digit soup. Foreground is 38;2;R;G;B, background 48;2;R;G;B,
# which is why these carry no prefix.
_tn_bg='26;27;38'          # #1a1b26  page background
_tn_bg_dark='22;22;30'     # #16161e  dark surfaces
_tn_bg_high='41;46;66'     # #292e42  subtle fill
_tn_bg_visual='40;52;87'   # #283457  selection
_tn_gutter='59;66;97'      # #3b4261  separators
_tn_fg='192;202;245'       # #c0caf5  default text
_tn_dark3='84;92;126'      # #545c7e  line numbers, indices
_tn_comment='86;95;137'    # #565f89  comments, muted text
_tn_dark5='115;122;162'    # #737aa2  tertiary text
_tn_red='247;118;142'      # #f7768e
_tn_green='158;206;106'    # #9ece6a
_tn_yellow='224;175;104'   # #e0af68
_tn_blue='122;162;247'     # #7aa2f7
_tn_magenta='187;154;247'  # #bb9af7
_tn_cyan='125;207;255'     # #7dcfff
_tn_orange='255;158;100'   # #ff9e64
_tn_purple='157;124;216'   # #9d7cd8
_tn_teal='26;188;156'      # #1abc9c

# --- fzf -------------------------------------------------------------------
# The pointer stays #ff5000, the same hot orange as the terminal and Neovim
# cursor. It is deliberately not a Tokyo Night colour: it is the "you are here"
# marker across every tool, so it has to win against the rest of the palette.
#
# bg and gutter are left at -1 (terminal default) rather than pinned to #1a1b26
# so fzf stays transparent inside tmux popups instead of painting a background
# that is a shade off from whatever is behind it.
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
# `disabled` is the query colour when fzf is run with --disabled, which is how
# st, st-rg and st-zoekt work: the query does not filter the list, it is fed
# back into ripgrep or zoekt on every keystroke. fzf dims it by default, which
# reads as "this input is inert" on the one field driving the whole search. It
# is the same colour as a normal query because that is what it is.
_fzf_tn="$_fzf_tn --color=disabled:#c0caf5"

# --style=minimal needs fzf 0.58 (Jan 2025). That is a real floor for this
# options string as a whole: fzf exits on an option it does not know, so an
# older build does not fall back to an unstyled picker, it refuses to start.
# Kept anyway, because it is the newer of the two intentions expressed here and
# the one the current setup is built around.
#
# --info=inline used to sit in this line and did nothing: --style is applied
# where it appears in the argument list, and the minimal preset resets the info
# style, so a preceding --info was always overwritten. Dropped rather than
# moved after --style, so the rendering does not change.
#
# The colours above are built up in pieces rather than as one multi-line
# string: newlines in FZF_DEFAULT_OPTS only work from fzf 0.48, and one option
# per line stays readable without depending on that.
FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS --reverse --ansi --style=minimal --no-cycle $_fzf_tn"
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

# --- ls, eza, and the zsh completion menu -----------------------------------
# LS_COLORS is the same data as common/.config/lf/colors, in the same format,
# because that file *is* an LS_COLORS table -- lf simply reads one. Keeping the
# two in step means a .zip is the same red whether you meet it in lf, in yazi,
# in `ls`, in `eza`, or in a zsh completion menu, which is four more places
# than lf's colours used to reach.
#
# It is spelled out here rather than read from that file at startup: a `cat` on
# the path of every non-interactive shell is exactly the kind of cost the rest
# of this setup goes out of its way to avoid. `tests/check-theme.py palette`
# sources this file and diffs the result against lf's, so the copy cannot
# quietly drift.
#
# Grouped and ordered as lf's file is, so the two can be read side by side.
_ls="ln=38;2;$_tn_cyan:mh=38;2;$_tn_cyan:or=38;2;$_tn_red;1"
_ls="$_ls:di=38;2;$_tn_blue;1:ex=38;2;$_tn_green:fi=38;2;$_tn_fg"
_ls="$_ls:pi=38;2;$_tn_yellow:so=38;2;$_tn_magenta"
_ls="$_ls:bd=38;2;$_tn_yellow;48;2;$_tn_bg_high:cd=38;2;$_tn_yellow;48;2;$_tn_bg_high"
_ls="$_ls:su=38;2;$_tn_bg_dark;48;2;$_tn_red:sg=38;2;$_tn_bg_dark;48;2;$_tn_yellow"
_ls="$_ls:tw=38;2;$_tn_bg_dark;48;2;$_tn_green:ow=38;2;$_tn_blue;48;2;$_tn_bg_visual"
_ls="$_ls:st=38;2;$_tn_fg;48;2;$_tn_blue"

# archives → red
for _e in tar tgz gz bz2 xz zst zip 7z rar deb rpm dmg; do
	_ls="$_ls:*.$_e=38;2;$_tn_red"
done
# images and video → magenta
for _e in png jpg jpeg gif webp svg ico mp4 mkv mov webm; do
	_ls="$_ls:*.$_e=38;2;$_tn_magenta"
done
# audio → purple
for _e in mp3 flac wav m4a ogg; do
	_ls="$_ls:*.$_e=38;2;$_tn_purple"
done
# documents → orange
for _e in pdf epub djvu docx xlsx pptx; do
	_ls="$_ls:*.$_e=38;2;$_tn_orange"
done
# source code → green
for _e in c h cc cpp hpp cs go rs py rb js ts tsx jsx lua sh zsh bash ps1; do
	_ls="$_ls:*.$_e=38;2;$_tn_green"
done
# config and data → yellow
for _e in json toml yaml yml ini conf cfg xml; do
	_ls="$_ls:*.$_e=38;2;$_tn_yellow"
done
# docs and notes → foreground
for _e in md txt rst; do
	_ls="$_ls:*.$_e=38;2;$_tn_fg"
done
# noise → comment grey
for _e in log bak tmp swp o pyc lock; do
	_ls="$_ls:*.$_e=38;2;$_tn_comment"
done
LS_COLORS="$_ls"
export LS_COLORS
unset _ls _e

# eza paints the columns either side of the filename too, and those are its
# own setting -- LS_COLORS says nothing about them, so out of the box they are
# eza's defaults sitting beside Tokyo Night filenames.
#
# The permission bits use the same colour per column that yazi's status bar
# does (type blue, read yellow, write red, execute green), so `ll` and yazi
# describe a file's mode identically. "You" is teal in the user and group
# columns, which is the colour starship already gives your username.
_eza="ur=38;2;$_tn_yellow:uw=38;2;$_tn_red:ux=38;2;$_tn_green:ue=38;2;$_tn_green"
_eza="$_eza:gr=38;2;$_tn_yellow:gw=38;2;$_tn_red:gx=38;2;$_tn_green"
_eza="$_eza:tr=38;2;$_tn_yellow:tw=38;2;$_tn_red:tx=38;2;$_tn_green"
_eza="$_eza:su=38;2;$_tn_orange:sf=38;2;$_tn_orange:xa=38;2;$_tn_dark5"
# Sizes step warmer as they grow, so a big file catches the eye in a long list.
_eza="$_eza:sn=38;2;$_tn_green:sb=38;2;$_tn_dark5"
_eza="$_eza:nb=38;2;$_tn_green:nk=38;2;$_tn_green:nm=38;2;$_tn_yellow"
_eza="$_eza:ng=38;2;$_tn_orange:nt=38;2;$_tn_red"
_eza="$_eza:uu=38;2;$_tn_teal:un=38;2;$_tn_dark5"
_eza="$_eza:gu=38;2;$_tn_teal:gn=38;2;$_tn_dark5"
_eza="$_eza:da=38;2;$_tn_comment:in=38;2;$_tn_dark3:bl=38;2;$_tn_dark3"
_eza="$_eza:hd=38;2;$_tn_blue;1:xx=38;2;$_tn_gutter:lp=38;2;$_tn_cyan"
# The git column, in the same language the rest of the setup uses for git:
# teal for new (docs/tokyonight.md gives teal to "untracked / new"), yellow for
# modified, red for deleted, magenta for renamed.
_eza="$_eza:ga=38;2;$_tn_teal:gm=38;2;$_tn_yellow:gd=38;2;$_tn_red"
_eza="$_eza:gv=38;2;$_tn_magenta:gt=38;2;$_tn_cyan"
EZA_COLORS="$_eza"
export EZA_COLORS
unset _eza

# --- grep -------------------------------------------------------------------
# Both shells alias grep to --color=auto, and GNU grep's default match colour
# is bold red -- which in this palette is the colour of deletions and errors,
# on the one thing on screen that is neither.
#
# So a match is the same inverted yellow block it is in fzf, in delta --grep
# and in ripgrep: see the note above about why matches invert rather than
# recolour. The surrounding fields borrow delta's grep styling exactly, so
# `grep -rn`, `rg` and `git grep` produce three sets of output that line up.
_grep="ms=1;7;38;2;$_tn_yellow:mc=1;7;38;2;$_tn_yellow"
_grep="$_grep:fn=38;2;$_tn_blue:ln=38;2;$_tn_dark3:bn=38;2;$_tn_dark3"
_grep="$_grep:se=38;2;$_tn_gutter"
GREP_COLORS="$_grep"
export GREP_COLORS
unset _grep

# --- less, and therefore man ------------------------------------------------
# less renders a man page's bold and underline through these, and unset they
# come out as the terminal's raw bold and underline: a man page is one of the
# few things left on screen with no theme at all.
#
# The mapping follows what each attribute actually means in a man page rather
# than what it is called: bold is the thing being defined (a flag, a function
# name), so it is the primary accent; underline marks a value you substitute,
# so it is cyan, the colour used for links and parameters elsewhere.
#
# `so` is standout, which less uses for two unrelated things -- the status line
# at the bottom and search matches. Inverted yellow serves both, and matches
# how a search hit looks in every other tool here.
LESS_TERMCAP_md=$'\033[1;38;2;'"$_tn_blue"'m'     # bold: defined terms
LESS_TERMCAP_mb=$'\033[1;38;2;'"$_tn_red"'m'      # blink, which man uses for nothing good
LESS_TERMCAP_me=$'\033[0m'
LESS_TERMCAP_us=$'\033[4;38;2;'"$_tn_cyan"'m'     # underline: substitutable values
LESS_TERMCAP_ue=$'\033[0m'
LESS_TERMCAP_so=$'\033[1;38;2;'"$_tn_bg"';48;2;'"$_tn_yellow"'m'
LESS_TERMCAP_se=$'\033[0m'
export LESS_TERMCAP_md LESS_TERMCAP_mb LESS_TERMCAP_me
export LESS_TERMCAP_us LESS_TERMCAP_ue LESS_TERMCAP_so LESS_TERMCAP_se

# groff hands man's output to less as overstruck text unless told otherwise,
# and some builds of man strip the escapes above along the way. Asking for the
# escapes directly is what makes the colours survive that path.
GROFF_NO_SGR=1
export GROFF_NO_SGR

# --- zsh line editor --------------------------------------------------------
# Inert in bash; zsh-autosuggestions reads it when the plugin loads.
#
# The default is fg=8, which this theme deliberately lightened to #85899c so
# that de-emphasised CLI output stays readable -- at 4.9:1 that is almost as
# bright as the command you are actually typing, and the suggestion ends up
# competing with your own input. Comment grey is the colour this palette
# already uses for "present, not yours to read yet".
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#565f89"
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE

unset _tn_bg _tn_bg_dark _tn_bg_high _tn_bg_visual _tn_gutter
unset _tn_fg _tn_dark3 _tn_comment _tn_dark5
unset _tn_red _tn_green _tn_yellow _tn_blue _tn_magenta _tn_cyan
unset _tn_orange _tn_purple _tn_teal
