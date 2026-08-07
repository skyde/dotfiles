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

# Starship prompt (only if installed)
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (& starship init powershell)
} else {
    Write-Host "⚠️  starship not found. Install with: winget install starship"
}

# Inline suggestions (history-based)
Set-PSReadLineOption -PredictionSource History
# Set-PSReadLineOption -PredictionViewStyle ListView

# Tokyo Night for the command line, matching the zsh side's
# ~/.config/fsh/tokyonight.ini role for role. Palette: docs/tokyonight.md.
#
# PSReadLine's defaults are the eight console colours, so the Windows prompt was
# the last command line here still unthemed. The roles are the same ones the
# palette doc assigns: green for what will run, magenta for keywords, yellow for
# strings, cyan for parameters, purple for variables, orange for numbers, blue5
# for operators, comment grey for comments.
#
# Escape is written as [char]27 rather than the `e sequence so this works on
# Windows PowerShell 5.1 as well as PowerShell 7.
$e = [char]27
Set-PSReadLineOption -Colors @{
    Command            = "$e[38;2;158;206;106m"  # #9ece6a
    Keyword            = "$e[38;2;187;154;247m"  # #bb9af7
    String             = "$e[38;2;224;175;104m"  # #e0af68
    Parameter          = "$e[38;2;125;207;255m"  # #7dcfff
    Variable           = "$e[38;2;157;124;216m"  # #9d7cd8
    Number             = "$e[38;2;255;158;100m"  # #ff9e64
    Operator           = "$e[38;2;137;221;255m"  # #89ddff
    Comment            = "$e[38;2;86;95;137m"    # #565f89
    Type               = "$e[38;2;122;162;247m"  # #7aa2f7
    Member             = "$e[38;2;192;202;245m"  # #c0caf5
    Default            = "$e[38;2;192;202;245m"  # #c0caf5
    Error              = "$e[38;2;247;118;142m"  # #f7768e
    # A match, inverted, exactly as in fzf, ripgrep, grep and delta --grep.
    Emphasis           = "$e[1;7;38;2;224;175;104m"
    Selection          = "$e[48;2;40;52;87m"     # bg_visual, the shared fill
    # The ghost text, in the same comment grey zsh-autosuggestions gets. The
    # default is bright black, which competes with what you are actually typing.
    InlinePrediction   = "$e[38;2;86;95;137m"
    ListPrediction     = "$e[38;2;86;95;137m"
    ListPredictionSelected = "$e[48;2;40;52;87m"
}

# zoxide init + override cd (only if installed)
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init --cmd cd powershell | Out-String) })
    # optional: keep “z” alias too
    Set-Alias z cd
} else {
    Write-Host "⚠️  zoxide not found. Install with: winget install ajeetdsouza.zoxide"
}


# apply.ps1 stows `common` into the user profile, so ~/.ripgreprc is already on
# disk here — Windows just never pointed ripgrep at it, because the variable
# that does so is set in .zshenv and PowerShell does not read that. Setting it
# here gives Windows the same excludes and the same match colours as every
# other platform, from the one file, instead of a second set that has to be
# kept in step by hand.
$rgConfig = Join-Path $HOME '.ripgreprc'
if (Test-Path $rgConfig) { $env:RIPGREP_CONFIG_PATH = $rgConfig }

# Favor hidden files but ignore common junk. The colours deliberately are not
# repeated here: they used to be `--colors match:fg:yellow`, which is plain
# console yellow and, being a later flag, would override the inverted-yellow
# match that ~/.ripgreprc now sets. These flags are harmless duplicates of the
# config so that rg still behaves sensibly if it is missing.
function rg {
    & rg.exe --hidden --smart-case --glob '!.git' --glob '!node_modules' @Args
}

