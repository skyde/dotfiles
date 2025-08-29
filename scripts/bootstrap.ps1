param(
  [switch]$WhatIf,
  [switch]$OnlyVSCode
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
  $roots = @(
    (Join-Path $env:APPDATA "Code\User"),
    (Join-Path $env:APPDATA "Code - Insiders\User")
  )
  foreach ($UserDir in $roots) {
    New-Item -ItemType Directory -Force -Path $UserDir | Out-Null

    # settings.json
    $settingsSrc = Join-Path $PSScriptRoot "..\vscode\settings.json"
    if (Test-Path $settingsSrc) {
      Copy-Item $settingsSrc (Join-Path $UserDir 'settings.json') -Force
    }

    # extensions.json
    $extSrc = Join-Path $PSScriptRoot "..\vscode\extensions.json"
    if (Test-Path $extSrc) {
      Copy-Item $extSrc (Join-Path $UserDir 'extensions.json') -Force
    }

    # keybindings.json
    $kbSrc = Join-Path $PSScriptRoot "..\vscode\keybindings.json"
    if (Test-Path $kbSrc) {
      Copy-Item $kbSrc (Join-Path $UserDir 'keybindings.json') -Force
    }
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

function Ensure-VsVimRc {
  try {
    $src = Join-Path $PSScriptRoot "..\stow\vsvim\.vsvimrc"
    if (Test-Path $src) {
      $dest = Join-Path $env:USERPROFILE ".vsvimrc"
      Copy-Item $src $dest -Force
    }
  } catch {}
}

if ($WhatIf) {
  Write-Host "Would install tools, fonts, and VS Code files" -ForegroundColor Yellow
  exit 0
}

if ($OnlyVSCode) {
  Ensure-VSCodeFiles
  Write-Host "✅ Ensured VS Code user files only." -ForegroundColor Green
  exit 0
}

Install-Tools
Install-Fonts
Ensure-VSCodeFiles
Ensure-VsVimRc

Write-Host "✅ Windows bootstrap complete." -ForegroundColor Green
