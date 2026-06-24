# -------- PSReadLine options
Set-PSReadLineOption -EditMode Emacs
Set-PSReadLineOption -HistoryNoDuplicates:$true
Set-PSReadLineOption -MaximumHistoryCount 100000

# History saving
Set-PSReadLineOption -HistorySaveStyle SaveIncrementally
Set-PSReadLineOption -HistorySavePath "$HOME\.powershell_history"

# Key bindings (Emacs + Ctrl+←/→ for word jumps)
Set-PSReadLineKeyHandler -Key Ctrl+RightArrow  -Function ForwardWord
Set-PSReadLineKeyHandler -Key Ctrl+LeftArrow   -Function BackwardWord
Set-PSReadLineKeyHandler -Key Ctrl+_ -Function Undo

# Inline suggestions (history-based)
Set-PSReadLineOption -PredictionSource History

# -------- Starship prompt (only if installed)
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (& starship init powershell)
} else {
    Write-Host "starship not found. Install with: winget install starship"
}

# -------- zoxide init + override cd (only if installed)
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init --cmd cd powershell | Out-String) })
    Set-Alias z cd
} else {
    Write-Host "zoxide not found. Install with: winget install ajeetdsouza.zoxide"
}

# -------- fzf-powered history search (Ctrl-R)
if (Get-Command fzf -ErrorAction SilentlyContinue) {
    Set-PSReadLineKeyHandler -Key Ctrl+r -ScriptBlock {
        $line = $null
        $cursor = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        $history = Get-Content (Get-PSReadLineOption).HistorySavePath -ErrorAction SilentlyContinue |
            Select-Object -Unique |
            Where-Object { $_ -match $line }

        if ($history) {
            $selected = $history | fzf --height=80% --reverse --tiebreak=index --no-sort --query=$line
            if ($selected) {
                [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert($selected)
            }
        }
    }
}

# -------- aliases - bat / batcat
if (Get-Command bat -ErrorAction SilentlyContinue) {
    function cat { & bat @Args }
}

# -------- aliases - eza ls replacements
if (Get-Command eza -ErrorAction SilentlyContinue) {
    function ls { & eza --color=auto --group-directories-first @Args }
    function ll { & eza -al --color=auto --group-directories-first @Args }
    function la { & eza -a --color=auto --group-directories-first @Args }
    function tree { & eza --tree --icons --group-directories-first @Args }
}

# -------- ripgrep with better defaults
function rg {
    & rg.exe --hidden --smart-case --colors match:fg:yellow --glob '!.git' --glob '!node_modules' @Args
}

# -------- file managers that cd to the last visited dir

# Yazi file manager with directory change on exit (matches zsh 'e' function)
function e {
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        & yazi @Args --cwd-file="$tmp"
        $cwd = Get-Content $tmp -ErrorAction SilentlyContinue
        if ($cwd -and $cwd -ne $PWD.Path) {
            Set-Location $cwd
        }
    }
    finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}

# lf file manager with directory change on exit
function lf {
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        & lf.exe -last-dir-path $tmp @Args
        $dir = Get-Content $tmp -ErrorAction SilentlyContinue
        if ($dir -and $dir -ne $PWD.Path) {
            Set-Location $dir
        }
    }
    finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}

# -------- lazygit alias (matches zsh 'gg' function)
function gg { & lazygit }

# -------- editor
$env:EDITOR = "nvim"
$env:VISUAL = $env:EDITOR

# -------- machine-specific overrides
$localProfile = "$HOME\.powershell_profile.local.ps1"
if (Test-Path $localProfile) {
    . $localProfile
}
