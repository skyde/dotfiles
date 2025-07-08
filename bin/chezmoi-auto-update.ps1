#!/usr/bin/env pwsh
if (Get-Command chezmoi -ErrorAction SilentlyContinue) {
    chezmoi update --init | Out-Null
}
