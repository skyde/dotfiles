Param()
$ErrorActionPreference = 'Stop'
$src = Join-Path $env:DOT_REPO 'stow\vsvim\.vsvimrc'
if (Test-Path $src) {
  $dest = Join-Path $env:USERPROFILE '.vsvimrc'
  Copy-Item $src $dest -Force
  Write-Host "[vsvim] ensured $dest" -ForegroundColor Cyan
}

