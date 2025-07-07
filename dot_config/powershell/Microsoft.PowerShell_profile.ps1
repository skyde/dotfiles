# Auto update dotfiles on PowerShell start
$script = Join-Path $HOME 'bin/chezmoi-auto-update.ps1'
if (Test-Path $script) {
    & $script
}
