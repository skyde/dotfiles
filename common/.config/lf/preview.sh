#!/usr/bin/env sh
# lf passes: $1=file, $2=width, $3=height, $4=x, $5=y
# Basic text preview with bat; ignore x/y and use width for wrapping.
#
# Debian and Ubuntu install bat as `batcat`, so `exec bat …` printed
# "bat: command not found" into lf's preview pane for every file on the distros
# init.sh installs bat from. Try both names, and fall back to plain cat so the
# pane shows the file rather than an error.
for bin in bat batcat; do
	if command -v "$bin" >/dev/null 2>&1; then
		exec "$bin" --color=always --style=numbers,changes --paging=never \
			--terminal-width="${2:-80}" -- "$1"
	fi
done

exec cat -- "$1"
