# st-zoekt - Interactive Zoekt search with fzf
# Usage: st-zoekt [--code] [PATH]
#   --code   open matches in VS Code; default opens in nvim.
#   PATH     directory within the tree; defaults to $PWD.
param(
    [switch]$code,
    [string]$Path = $PWD
)

# Verify required tools
foreach ($cmd in @('zoekt', 'fzf', 'rg', 'bat')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "error: $cmd not found in PATH"
        exit 1
    }
}

# Resolve the target directory
$root = $Path
if (Test-Path $root -PathType Leaf) {
    $root = Split-Path $root -Parent
}
$root = (Resolve-Path $root).Path
$indexDir = Join-Path $root ".zoekt"

if (-not (Test-Path $indexDir)) {
    Write-Error "error: no Zoekt index found at: $indexDir"
    Write-Host "hint: run 'si `"$root`"' first to build the index."
    exit 1
}

# Build fzf arguments
$enterBinding = if ($code) {
    "enter:execute-silent(code -r -g {1}:{2})"
} else {
    "enter:become(nvim +{2} {1})"
}

$escBinding = "esc:clear-query"

# Reload command using zoekt and rg for coloring
$reloadCmd = "zoekt -index_dir `"$indexDir`" -- {q} | rg --passthru --smart-case --color=always -- {q}"

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
