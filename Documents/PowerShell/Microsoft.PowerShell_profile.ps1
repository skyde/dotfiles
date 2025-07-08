# PSReadLine options
Set-PSReadLineOption -EditMode Emacs
Set-PSReadLineOption -HistoryNoDuplicates:$true
Set-PSReadLineOption -MaximumHistoryCount 5000

# Replace -SaveHistoryInBackground with incremental history saving
Set-PSReadLineOption -HistorySaveStyle SaveIncrementally
Set-PSReadLineOption -HistorySavePath "$HOME\.powershell_history"

# Key bindings (Emacs + Ctrl+←/→ for word jumps)
Set-PSReadLineKeyHandler -Key Ctrl+RightArrow  -Function ForwardWord
Set-PSReadLineKeyHandler -Key Ctrl+LeftArrow   -Function BackwardWord

# Auto-update dotfiles on startup using helper script
$updateScript = "$HOME/bin/chezmoi-auto-update.ps1"
if (Test-Path $updateScript) { & $updateScript }

# Starship prompt (only if installed)
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (& starship init powershell)
} else {
    Write-Host "⚠️  starship not found. Install with: winget install starship"
}

# Inline suggestions (history-based)
Set-PSReadLineOption -PredictionSource History
# Set-PSReadLineOption -PredictionViewStyle ListView

# zoxide init + override cd (only if installed)
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init --cmd cd powershell | Out-String) })
    # optional: keep “z” alias too
    Set-Alias z cd
} else {
    Write-Host "⚠️  zoxide not found. Install with: winget install ajeetdsouza.zoxide"
}

