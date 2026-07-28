# PSReadLine options
Set-PSReadLineOption -EditMode Emacs
Set-PSReadLineOption -HistoryNoDuplicates:$true
Set-PSReadLineOption -MaximumHistoryCount 100000

# Replace -SaveHistoryInBackground with incremental history saving
Set-PSReadLineOption -HistorySaveStyle SaveIncrementally
Set-PSReadLineOption -HistorySavePath "$HOME\.powershell_history"

# Key bindings (Emacs + Ctrl+←/→ for word jumps)
Set-PSReadLineKeyHandler -Key Ctrl+RightArrow  -Function ForwardWord
Set-PSReadLineKeyHandler -Key Ctrl+LeftArrow   -Function BackwardWord

# Prefer Neovim while respecting machine-specific overrides.
if ([string]::IsNullOrWhiteSpace($env:EDITOR)) {
    $env:EDITOR = 'nvim'
}
if ([string]::IsNullOrWhiteSpace($env:VISUAL)) {
    $env:VISUAL = $env:EDITOR
}

# Stow places the cross-platform editor wrappers here. Add the directory once
# for this session, then expose native batch wrappers to the P4 client.
$localBin = Join-Path $HOME '.local\bin'
if (Test-Path -LiteralPath $localBin) {
    $normalizedLocalBin = $localBin.TrimEnd('\')
    $pathEntries = @($env:PATH -split ';' | ForEach-Object { $_.TrimEnd('\') })
    if ($pathEntries -notcontains $normalizedLocalBin) {
        $env:PATH = "$localBin;$env:PATH"
    }

    $p4DiffWrapper = Join-Path $localBin 'nvim-diff.cmd'
    if ([string]::IsNullOrWhiteSpace($env:P4DIFF) -and (Test-Path -LiteralPath $p4DiffWrapper)) {
        $env:P4DIFF = 'nvim-diff.cmd'
    }

    $p4MergeWrapper = Join-Path $localBin 'nvim-p4merge.cmd'
    if ([string]::IsNullOrWhiteSpace($env:P4MERGE) -and (Test-Path -LiteralPath $p4MergeWrapper)) {
        $env:P4MERGE = 'nvim-p4merge.cmd'
    }
}

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
