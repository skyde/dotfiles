# ff - File Finder with fzf
# Usage: ff [--code]
#   --code   open files in VS Code; default opens in nvim.
param(
    [switch]$code
)

# Verify required tools
foreach ($cmd in @('fzf', 'bat')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "error: $cmd not found in PATH"
        exit 1
    }
}

# Build fzf arguments
$enterBinding = if ($code) {
    "enter:execute-silent(code -r -g {1}:{2})"
} else {
    "enter:become(nvim {1})"
}

$escBinding = "esc:clear-query"

# Use fd if available, otherwise fall back to dir
$findCmd = if (Get-Command fd -ErrorAction SilentlyContinue) {
    "fd --type f --hidden --exclude .git"
} else {
    "dir /s /b /a-d"
}

& $findCmd | fzf `
    --tiebreak=pathname `
    --delimiter ':' `
    --bind $enterBinding `
    --bind $escBinding `
    --preview 'bat --style=numbers --color=always --line-range :500 {}' `
    --preview-window 'right,55%'
