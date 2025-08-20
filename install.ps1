$ErrorActionPreference = 'Stop'

param(
    [switch]$DryRun
)

$home = $env:USERPROFILE

# Load helpers
. "$PSScriptRoot/install_helpers.ps1"
if ($DryRun) { $Global:DotfilesDryRun = $true }

# ------------------------------
# Auto-discover packages by layout
# ------------------------------

function Discover-And-Stow([string]$Root, [string]$Target) {
    if (-not (Test-Path $Root)) { return }
    Get-ChildItem -Path $Root -Directory | ForEach-Object {
        Restow-Package -Package $_.FullName -Target $Target
    }
}

Discover-And-Stow -Root (Join-Path $PSScriptRoot 'dotfiles/common') -Target $home

if ($IsWindows) {
    Discover-And-Stow -Root (Join-Path $PSScriptRoot 'dotfiles/windows') -Target $home
}

# ------------------------------
# Cross-OS bridges (reusable via data)
# ------------------------------

$vscodeDotConfigUser = Join-Path $home '.config\Code\User'
Ensure-Directory -Path $vscodeDotConfigUser

$vscodeAppDataUser = Join-Path $env:APPDATA 'Code\User'
Ensure-Directory -Path $vscodeAppDataUser

# Link the entire User directory so new files are automatically covered
Invoke-SymlinkPairs -Pairs @(
    $vscodeDotConfigUser + '::' + $vscodeAppDataUser
)
