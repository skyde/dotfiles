#!/usr/bin/env sh
# lf passes: $1=file, $2=width, $3=height, $4=x, $5=y
# Basic text preview with bat; ignore x/y and use width for wrapping.
exec bat --color=always --style=numbers,changes --paging=never \
         --terminal-width="${2:-80}" -- "$1"
