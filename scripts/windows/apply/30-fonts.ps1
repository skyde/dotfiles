Param()
$ErrorActionPreference = 'Stop'

$fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
if (-not (Test-Path $fontDir)) { New-Item -ItemType Directory -Force -Path $fontDir | Out-Null }
$src = Join-Path $env:DOT_REPO 'fonts'
if (Test-Path $src) {
  Get-ChildItem -Path (Join-Path $src '*.ttf') -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $fontDir $_.Name) -Force
  }
}

