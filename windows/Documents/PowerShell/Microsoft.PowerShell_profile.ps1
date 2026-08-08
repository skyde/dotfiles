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

# Command line colours — the Windows half of what ~/.zshrc does for zsh.
# See docs/tokyonight.md: chrome is Tokyo Night, code is Visual Studio Dark+,
# and the command line is code. The roles below are the same table zsh uses,
# so a pipeline reads the same on both platforms.
#
# Two exceptions, and they are the same two: Error is Tokyo Night's red and
# InlinePrediction the comment grey, because "this will fail" and "this is a
# suggestion, not what you typed" are facts about the session rather than
# about syntax, and Dark+ has no vocabulary for either.
#
# Values are hex where a foreground is all that is needed, and an escape
# sequence where a background is (PSReadLine takes either; a bare hex string
# only ever sets the foreground). `e is PowerShell 6+; on Windows PowerShell
# 5.1 it would need $([char]0x1b), but this profile already assumes 7.x.
Set-PSReadLineOption -Colors @{
    Default            = '#d4d4d4'
    Comment            = '#6a9955'
    String             = '#ce9178'
    Keyword            = '#c586c0'
    Command            = '#dcdcaa'
    Parameter          = '#569cd6'
    Variable           = '#9cdcfe'
    Member             = '#9cdcfe'
    Type               = '#4ec9b0'
    Number             = '#b5cea8'
    Operator           = '#d4d4d4'
    ContinuationPrompt = '#565f89'
    Error              = '#f7768e'
    InlinePrediction   = '#565f89'
    ListPrediction     = '#565f89'
    # bg_visual #283457, the same fill as fzf's bg+, tmux's mode-style and
    # zsh's completion menu.
    Selection              = "`e[48;2;40;52;87m"
    ListPredictionSelected = "`e[48;2;40;52;87m"
    # A history-search match is an inverted yellow block here too — bold,
    # reverse, yellow #e0af68. Same gesture as fzf's hl, delta's grep match
    # and ripgrep's.
    Emphasis = "`e[1;7;38;2;224;175;104m"
}

# zoxide init + override cd (only if installed)
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init --cmd cd powershell | Out-String) })
    # optional: keep “z” alias too
    Set-Alias z cd
} else {
    Write-Host "⚠️  zoxide not found. Install with: winget install ajeetdsouza.zoxide"
}


# Favor hidden files but ignore common junk, colorized output.
#
# The colours repeat what ~/.ripgreprc sets on the Unix side rather than
# reading that file, because RIPGREP_CONFIG_PATH is not set here and this
# wrapper is what stands in for it. Keep the two in step: a match is an
# inverted yellow block, the path is blue and the line number dark3, matching
# delta's grep styling. rg takes decimal triples, so the hexes are in the
# comments — bg #1a1b26 on yellow #e0af68, path #7aa2f7, line #545c7e.
# The triples have to be quoted. In argument mode PowerShell reads an
# unquoted comma as an array separator, so match:fg:26,27,38 would reach
# rg.exe as three separate arguments and it would refuse to start.
function rg {
    & rg.exe --hidden --smart-case `
        --colors 'match:fg:26,27,38' `
        --colors 'match:bg:224,175,104' `
        --colors 'match:style:bold' `
        --colors 'path:fg:122,162,247' `
        --colors 'line:fg:84,92,126' `
        --colors 'column:fg:84,92,126' `
        --glob '!.git' --glob '!node_modules' @Args
}

