#!/usr/bin/env sh
# lf passes: $1=file, $2=width, $3=height, $4=x, $5=y
# Basic text preview with bat; ignore x/y and use width for wrapping.
#
# COLORTERM is forced for the same reason as in yazi's bat-preview plugin and
# in fzf_history_highlight (see common/.config/shell/theme.sh): bat decides
# 24-bit versus the 256-colour cube from it, and it is not reliably set under
# tmux, the VS Code terminal, or over ssh. Without it this pane still looks
# plausible — it just quietly renders code in approximated colours while the
# yazi preview beside it, the Ctrl-R history picker and VS Code all show the
# real ones. It was the only one of the three shelling out to bat without it.
#
# No --theme here on purpose, exactly as in the yazi plugin: bat resolves
# BAT_THEME itself, so this pane follows that one setting along with everything
# else. See docs/tokyonight.md.
COLORTERM=truecolor
export COLORTERM

# Fall back to plain text rather than an error when bat is missing, which is
# what the yazi previewer does.
if command -v bat >/dev/null 2>&1; then
	exec bat --color=always --style=numbers,changes --paging=never \
		--terminal-width="${2:-80}" -- "$1"
fi
exec cat -- "$1"
