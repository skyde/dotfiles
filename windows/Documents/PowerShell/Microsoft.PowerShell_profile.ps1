# PSReadLine options
try {
    Set-PSReadLineOption -EditMode Emacs
    Set-PSReadLineOption -HistoryNoDuplicates:$true
    Set-PSReadLineOption -MaximumHistoryCount 100000
} catch {
    Write-Verbose "PSReadLine base options unavailable: $_"
}

# Prefer dotfile-managed user scripts in interactive shells.
function Add-PathEntryToFront {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return
    }

    $entries = @($env:Path -split ';' | Where-Object {
        $_ -and -not $_.Equals($Path, [StringComparison]::OrdinalIgnoreCase)
    })
    $env:Path = (@($Path) + $entries) -join ';'
}

$dotfilesLocalBin = Join-Path $HOME ".local\bin"
Add-PathEntryToFront -Path $dotfilesLocalBin
foreach ($entry in ([System.Environment]::GetEnvironmentVariable('PATH', 'User') -split ';')) {
    if ($entry -and -not (($env:Path -split ';') -contains $entry)) {
        $env:Path += ";$entry"
    }
}
$gitUsrBin = Join-Path $env:ProgramFiles "Git\usr\bin"
Add-PathEntryToFront -Path $gitUsrBin
Add-PathEntryToFront -Path $dotfilesLocalBin

$gitFile = Join-Path $gitUsrBin "file.exe"
if (-not $env:YAZI_FILE_ONE -and (Test-Path -LiteralPath $gitFile -PathType Leaf)) {
    $env:YAZI_FILE_ONE = $gitFile
}

# Replace -SaveHistoryInBackground with incremental history saving
try {
    Set-PSReadLineOption -HistorySaveStyle SaveIncrementally
    Set-PSReadLineOption -HistorySavePath "$HOME\.powershell_history"
} catch {
    Write-Verbose "PSReadLine history options unavailable: $_"
}

# Key bindings (Emacs + Ctrl+←/→ for word jumps)
try {
    Set-PSReadLineKeyHandler -Key Ctrl+RightArrow  -Function ForwardWord
    Set-PSReadLineKeyHandler -Key Ctrl+LeftArrow   -Function BackwardWord
} catch {
    Write-Verbose "PSReadLine key handlers unavailable: $_"
}

# Starship prompt (only if installed)
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (& starship init powershell)
} else {
    Write-Verbose "starship not found. Install with: winget install starship"
}

# Inline suggestions (history-based)
try {
    Set-PSReadLineOption -PredictionSource History
} catch {
    Write-Verbose "PSReadLine predictions unavailable: $_"
}
# Set-PSReadLineOption -PredictionViewStyle ListView

# zoxide init + override cd (only if installed)
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init --cmd cd powershell | Out-String) })
    # optional: keep “z” alias too
    Set-Alias z cd
} else {
    Write-Verbose "zoxide not found. Install with: winget install ajeetdsouza.zoxide"
}


# Favor hidden files but ignore common junk, colorized output
function rg {
    & rg.exe --hidden --smart-case --colors match:fg:yellow --glob '!.git' --glob '!node_modules' @Args
}

function Invoke-GitBashTool {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tool,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$ToolArgs
    )

    $gitBash = Join-Path $env:ProgramFiles "Git\bin\bash.exe"
    if (-not (Test-Path $gitBash)) {
        throw "Git Bash not found at $gitBash"
    }

    & $gitBash -lc 'source "$HOME/.local/bin/dotfiles-windows-env" 2>/dev/null || true; tool="$1"; shift; exec "$tool" "$@"' bash $Tool @ToolArgs
}

function st { Invoke-GitBashTool st @Args }
function st-rg { Invoke-GitBashTool st-rg @Args }
function st-zoekt { Invoke-GitBashTool st-zoekt @Args }
function ff { Invoke-GitBashTool ff @Args }
Remove-Item Alias:si -Force -ErrorAction SilentlyContinue
function si { Invoke-GitBashTool si @Args }
function sz { Invoke-GitBashTool sz @Args }
function git-copy { Invoke-GitBashTool git-copy @Args }
function tmux-session { Invoke-GitBashTool tmux-session @Args }
function kill-tmux { Invoke-GitBashTool kill-tmux @Args }
