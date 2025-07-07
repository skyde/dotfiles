# Automatically update dotfiles using chezmoi on each PowerShell start
if (Get-Command chezmoi -ErrorAction SilentlyContinue) {
    try {
        chezmoi update --init | Out-Null
    } catch {
        Write-Warning "chezmoi update failed: $_"
    }
}
