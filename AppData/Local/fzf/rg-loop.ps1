$ErrorActionPreference = "Stop"

$root = (git rev-parse --show-toplevel) 2>$null
if (-not $root) { $root = (Get-Location).Path }
Set-Location $root

while ($true) {
  $line = fzf --phony --query "" `
          --bind "change:reload:rg --column --line-number --no-heading --smart-case --color=always {q} || true" `
          --delimiter ":" `
          --preview 'bat --style=numbers --color=always --line-range :200 {1} --highlight-line {2}' `
          --ansi --layout=reverse --height=100% --border --prompt "ripgrep> "
  if ($LASTEXITCODE -ne 0) { break }
  if ($line) {
    $parts = $line -split ":",3
    $file = $parts[0]; $lineNo = $parts[1]
    code -g "$file`:$lineNo"
  }
}
