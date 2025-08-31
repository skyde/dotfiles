Param()
$ErrorActionPreference = 'Stop'

function Ensure-VSCodeFiles {
  $roots = @(
    (Join-Path $env:APPDATA 'Code\User'),
    (Join-Path $env:APPDATA 'Code - Insiders\User')
  )
  foreach ($UserDir in $roots) {
    if (-not $env:DOT_DRYRUN) {
      New-Item -ItemType Directory -Force -Path $UserDir | Out-Null
    }
    $repo = $env:DOT_REPO
    $settingsSrc = Join-Path $repo 'vscode\settings.json'
    $extSrc      = Join-Path $repo 'vscode\extensions.json'
    $kbSrc       = Join-Path $repo 'vscode\keybindings.json'
    if (Test-Path $settingsSrc) { Copy-Item $settingsSrc (Join-Path $UserDir 'settings.json') -Force }
    if (Test-Path $extSrc)      { Copy-Item $extSrc      (Join-Path $UserDir 'extensions.json') -Force }
    if (Test-Path $kbSrc)       { Copy-Item $kbSrc       (Join-Path $UserDir 'keybindings.json') -Force }
  }
}

Ensure-VSCodeFiles

