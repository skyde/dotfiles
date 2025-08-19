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


# Favor hidden files but ignore common junk, colorized output
function rg {
    & rg.exe --hidden --smart-case --colors match:fg:yellow --glob '!.git' --glob '!node_modules' @Args
}

