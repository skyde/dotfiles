Param()
$ErrorActionPreference = 'Stop'

# Ensure VS Code user files using the same logic as apply/20-ensure-vscode.ps1
$repo = $env:DOT_REPO
$roots = @(
  (Join-Path $env:APPDATA 'Code\User'),
  (Join-Path $env:APPDATA 'Code - Insiders\User')
)
foreach ($UserDir in $roots) {
  New-Item -ItemType Directory -Force -Path $UserDir | Out-Null
  $settingsSrc = Join-Path $repo 'vscode\settings.json'
  $extSrc      = Join-Path $repo 'vscode\extensions.json'
  $kbSrc       = Join-Path $repo 'vscode\keybindings.json'
  if (Test-Path $settingsSrc) { Copy-Item $settingsSrc (Join-Path $UserDir 'settings.json') -Force }
  if (Test-Path $extSrc)      { Copy-Item $extSrc      (Join-Path $UserDir 'extensions.json') -Force }
  if (Test-Path $kbSrc)       { Copy-Item $kbSrc       (Join-Path $UserDir 'keybindings.json') -Force }
  # Smoke asserts
  if (-not (Test-Path (Join-Path $UserDir 'settings.json')))    { throw 'settings.json missing' }
  if (-not (Test-Path (Join-Path $UserDir 'extensions.json')))  { throw 'extensions.json missing' }
  if (-not (Test-Path (Join-Path $UserDir 'keybindings.json'))) { throw 'keybindings.json missing' }
}
Write-Host 'Windows VS Code smoke OK' -ForegroundColor Green
