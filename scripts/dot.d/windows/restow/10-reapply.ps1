Param()
$ErrorActionPreference = 'Stop'
# Restow equivalent on Windows: re-run apply hooks
& (Join-Path $env:DOT_REPO 'dot.ps1') apply

