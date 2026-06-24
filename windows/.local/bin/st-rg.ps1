# st-rg - Interactive ripgrep search with fzf
# Usage: st-rg [--code] [PATH]
#   --code   open matches in VS Code; default opens in nvim.
#   PATH     directory or file to use as the search root; defaults to $PWD.
param(
    [switch]$code,
    [string]$Path = $PWD
)

# Verify required tools
foreach ($cmd in @('rg', 'fzf', 'bat')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "error: $cmd not found in PATH"
        exit 1
    }
}

# Resolve the target directory
$target = $Path
if (Test-Path $target -PathType Leaf) {
    $target = Split-Path $target -Parent
}
$root = (Resolve-Path $target).Path

# Build fzf arguments
$enterBinding = if ($code) {
    "enter:execute-silent(code -r -g {1}:{2})"
} else {
    "enter:become(nvim +{2} {1})"
}

$escBinding = "esc:clear-query"

# Note: On Windows, the reload command needs to use PowerShell syntax
# We use a simplified approach that works in fzf on Windows
$reloadCmd = "rg --line-number --column --with-filename --no-heading --color=always --smart-case -- {q} `"$root`""

& fzf `
    --ansi `
    --tiebreak=index `
    --disabled `
    --delimiter ':' `
    --bind "start:reload:$reloadCmd" `
    --bind "change:reload:$reloadCmd" `
    --bind $enterBinding `
    --bind $escBinding `
    --preview "bat --style=numbers --color=always --paging=never --line-range :500 {1}" `
    --preview-window 'bottom,30%'
