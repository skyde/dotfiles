param(
  [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

function Ensure-Command {
  param([string]$Name, [scriptblock]$Install)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    Write-Host "Installing $Name..." -ForegroundColor Cyan
    & $Install
  }
}

function Install-WingetPackage {
  param([string]$Id)
  winget install --id $Id -e --accept-package-agreements --accept-source-agreements | Out-Null
}

function Install-Fonts {
  $FontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
  New-Item -ItemType Directory -Force -Path $FontDir | Out-Null
  $SourceFontDir = (Resolve-Path "$PSScriptRoot\..\fonts").Path
  if (-not (Test-Path $SourceFontDir)) { return }
  Get-ChildItem -Path "$SourceFontDir\*.ttf" | ForEach-Object {
    $dest = Join-Path $FontDir $_.Name
    Copy-Item $_.FullName $dest -Force
    # Register in user registry
    try {
      Add-Type -AssemblyName System.Drawing
      $pfc = New-Object System.Drawing.Text.PrivateFontCollection
      $pfc.AddFontFile($dest)
      $fontName = $pfc.Families[0].Name
      $regPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
      New-Item -Path $regPath -Force | Out-Null
      New-ItemProperty -Path $regPath -Name "$fontName (TrueType)" -Value ($_.Name) -PropertyType String -Force | Out-Null
    } catch { }
  }
}

function Ensure-VSCodeFiles {
  $UserDir = Join-Path $env:APPDATA "Code\User"
  New-Item -ItemType Directory -Force -Path $UserDir | Out-Null

  # settings.json
  $settingsSrc = Join-Path $PSScriptRoot "..\.chezmoitemplates\vscode-settings.json"
  if (Test-Path $settingsSrc) {
    Copy-Item $settingsSrc (Join-Path $UserDir 'settings.json') -Force
  }

  # extensions.json
  $extSrc = Join-Path $PSScriptRoot "..\.chezmoitemplates\vscode-extensions.json"
  if (Test-Path $extSrc) {
    Copy-Item $extSrc (Join-Path $UserDir 'extensions.json') -Force
  }

  # keybindings.json (strip mac-only section)
  $kbSrc = Join-Path $PSScriptRoot "..\.chezmoitemplates\vscode-keybindings.json"
  if (Test-Path $kbSrc) {
    $lines = Get-Content $kbSrc
    $out = New-Object System.Collections.Generic.List[string]
    $skip = $false
    foreach ($line in $lines) {
      if ($line -match "\{\{.*eq .*darwin.*\}\}") { $skip = $true; continue }
      if ($line -match "\{\{.*end.*\}\}") { $skip = $false; continue }
      if (-not $skip) { $out.Add($line) }
    }
    $out | Set-Content (Join-Path $UserDir 'keybindings.json') -Encoding UTF8
  }
}

function Install-Tools {
  Ensure-Command rg { Install-WingetPackage "BurntSushi.ripgrep.MSVC" }
  Ensure-Command bat { Install-WingetPackage "sharkdp.bat" }
  Ensure-Command wezterm { Install-WingetPackage "wez.wezterm" }
  Ensure-Command hx { Install-WingetPackage "Helix.Helix" }
  # Neovim + LazyVim
  Ensure-Command nvim { Install-WingetPackage "Neovim.Neovim" }
  $nvimDir = Join-Path $env:USERPROFILE ".config\nvim"
  if (Test-Path $nvimDir) { Remove-Item $nvimDir -Recurse -Force }
  git clone https://github.com/LazyVim/starter $nvimDir | Out-Null
  Remove-Item (Join-Path $nvimDir ".git") -Recurse -Force -ErrorAction SilentlyContinue
  try {
    git config --global core.editor "nvim"
    git config --global sequence.editor "nvim"
  } catch {}
}

if ($WhatIf) {
  Write-Host "Would install tools, fonts, and VS Code files" -ForegroundColor Yellow
  exit 0
}

Install-Tools
Install-Fonts
Ensure-VSCodeFiles

Write-Host "✅ Windows bootstrap complete." -ForegroundColor Green
