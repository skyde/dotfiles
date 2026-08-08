#!/bin/bash
# Diagnose the Tokyo Night theme on this machine.
#
# tests/check-theme.py checks that the configs in the repo agree with each
# other. This checks the other half: that those configs actually reached this
# machine, that the shell exported what they set, and that this terminal can
# render it. Run it when something looks off in one place and right in
# another, and read the FAILs top to bottom.
#
# Written against macOS's bash 3.2, so keep new bashisms out of here.
#
# Palette reference: docs/tokyonight.md

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n      -> %s\n' "$1" "$2"; }
warn() { printf 'WARN  %s\n      -> %s\n' "$1" "$2"; }

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"

echo "TERM=$TERM  COLORTERM=${COLORTERM:-unset}"
echo

# --- 1. can this terminal show the theme at all? ---------------------------
#
# Nearly every colour in the setup is a 24-bit value. On a terminal that only
# understands the 256-colour cube they are approximated, which looks plausible
# and is subtly wrong everywhere at once — the hardest kind of problem to
# notice. bat in particular decides from COLORTERM alone.
case "$COLORTERM" in
truecolor | 24bit) pass "COLORTERM=$COLORTERM (24-bit colour)" ;;
"") fail "COLORTERM is not set" "tools like bat downgrade to 256 colours; set COLORTERM=truecolor, and check whether tmux/ssh is dropping it" ;;
*) warn "COLORTERM=$COLORTERM is not truecolor or 24bit" "24-bit colours may be approximated" ;;
esac

# --- 2. did the dotfiles get applied here? ---------------------------------
check_file() {
	if [ -e "$1" ]; then
		pass "$1"
	else
		fail "$1 is missing" "${2:-the dotfiles are not applied here — run ./apply.sh}"
	fi
}

echo
echo "-- config files --"
check_file "$config_home/shell/theme.sh"
check_file "$HOME/.ripgreprc"
check_file "$HOME/.tmux.conf"
check_file "$config_home/git/config"
check_file "$config_home/starship.toml"
check_file "$config_home/lf/colors"
check_file "$config_home/yazi/theme.toml"
check_file "$config_home/lazygit/config.yml"
check_file "$config_home/btop/themes/tokyo-night.theme"
check_file "$config_home/kitty/themes/tokyonight_night.conf"
check_file "$config_home/glow/tokyonight.json"

# --- 3. did this shell actually export what theme.sh sets? -----------------
#
# Every variable below is exported, so this script inherits it from the shell
# that launched it. An empty one means theme.sh was never sourced here — most
# often because the shell predates the change, or because ~/.zshenv is not
# being read (a login shell that only reads ~/.profile, say).
echo
echo "-- environment --"
check_env() { # check_env <name> <expected substring> <what it is>
	eval "value=\${$1}"
	if [ -z "$value" ]; then
		fail "$1 is not set" "open a new shell; if it is still unset, check that ~/.zshenv (or ~/.bashrc-custom) is being read — that is where these are exported, directly or by sourcing ~/.config/shell/theme.sh"
	elif [ -n "$2" ] && [ "${value#*"$2"}" = "$value" ]; then
		fail "$1 is set but does not contain $2" "something else is overwriting it after theme.sh ran"
	else
		pass "$1 ($3)"
	fi
}

# 38;2;122;162;247 is blue #7aa2f7 — the directory colour, and a cheap proof
# that this LS_COLORS is ours rather than a distro default or dircolors output.
check_env LS_COLORS "38;2;122;162;247" "ls, eza, fd, completion menu"
check_env EZA_COLORS "" "eza's own columns"
check_env BAT_THEME "Visual Studio Dark+" "bat, delta, yazi preview, Ctrl-R"
check_env FZF_DEFAULT_OPTS "#ff5000" "fzf, including the cursor-orange pointer"
check_env LESS_TERMCAP_md "" "man page bold"
check_env GROFF_NO_SGR "1" "without it less never consults termcap"
check_env RIPGREP_CONFIG_PATH "" "ripgrep's colours and excludes"
# glow's style cannot live in glow.yml — the path there is never expanded — so
# the environment is the only place it can come from. See docs/tokyonight.md.
check_env GLOW_STYLE "glow" "glow's markdown rendering"

if [ -n "$RIPGREP_CONFIG_PATH" ] && [ ! -e "$RIPGREP_CONFIG_PATH" ]; then
	fail "RIPGREP_CONFIG_PATH points at $RIPGREP_CONFIG_PATH, which does not exist" \
		"rg silently ignores a missing config, so its colours fall back to the defaults"
fi

# Same trap as ripgrep's, and worse: glow *errors out* rather than falling back,
# so a stale path here means glow does not render at all.
if [ -n "$GLOW_STYLE" ] && [ ! -e "$GLOW_STYLE" ]; then
	fail "GLOW_STYLE points at $GLOW_STYLE, which does not exist" \
		"glow fails with 'unable to create renderer' rather than falling back to a default style"
fi

# --- 4. what it actually looks like ----------------------------------------
#
# The checks above prove the values are present. Only your eye can prove they
# render, so the rest is swatches.
esc=$(printf '\033')
reset="${esc}[0m"

block() { # block <r;g;b> <label>
	printf '%s[48;2;%sm    %s %s\n' "$esc" "$1" "$reset" "$2"
}

echo
echo "-- palette (24-bit; each block should differ from its neighbours) --"
block "26;27;38" "bg          #1a1b26"
block "22;22;30" "bg_dark     #16161e"
block "41;46;66" "bg_highlight #292e42"
block "40;52;87" "bg_visual   #283457"
block "247;118;142" "red         #f7768e"
block "158;206;106" "green       #9ece6a"
block "224;175;104" "yellow      #e0af68"
block "122;162;247" "blue        #7aa2f7"
block "187;154;247" "magenta     #bb9af7"
block "125;207;255" "cyan        #7dcfff"
block "255;158;100" "orange      #ff9e64"
block "255;80;0" "cursor      #ff5000"

# The 16 ANSI slots come from the *terminal*, not from any file here, so this
# is the one section that says whether kitty/wezterm/VS Code picked up the
# theme. Slot 8 is the one to look at: it should be legible grey (#85899c),
# not the near-invisible upstream #414868.
echo
echo "-- terminal's own 16 ANSI colours (0-7 normal, 8-15 bright) --"
i=0
while [ "$i" -lt 8 ]; do
	printf '%s[4%sm    %s' "$esc" "$i" "$reset"
	i=$((i + 1))
done
printf '\n'
i=0
while [ "$i" -lt 8 ]; do
	printf '%s[10%sm    %s' "$esc" "$i" "$reset"
	i=$((i + 1))
done
printf '\n'
printf '%s[90mbright black (slot 8) should be readable grey, not near-invisible%s\n' "$esc" "$reset"

echo
echo "-- house styles --"
printf 'a filter match:   alpha %s[1;7;38;2;224;175;104mmatch%s beta   (fzf, ripgrep, delta --grep)\n' "$esc" "$reset"
printf 'an in-buffer one: alpha %s[38;2;192;202;245;48;2;61;89;161mmatch%s beta   (less, tmux copy mode, nvim)\n' "$esc" "$reset"
printf 'man page bold:    %sHEADING%s\n' "${LESS_TERMCAP_md:-${esc}[1m}" "$reset"
printf 'man page arg:     %sfilename%s\n' "${LESS_TERMCAP_us:-${esc}[4m}" "$reset"
printf 'a directory:      %s[1;38;2;122;162;247msrc/%s\n' "$esc" "$reset"
printf 'a broken symlink: %s[1;38;2;247;118;142mdangling%s\n' "$esc" "$reset"

echo
echo "For agreement between the configs themselves, run tests/check-theme.py."
