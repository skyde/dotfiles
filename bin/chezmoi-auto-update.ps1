#!/usr/bin/env pwsh
if (Get-Command chezmoi -ErrorAction SilentlyContinue) {
    $status = chezmoi git status --porcelain
    if (-not $status) {
        chezmoi update --init | Out-Null
    } else {
        Write-Verbose "chezmoi has local changes, skipping auto update." -Verbose
    }
}
