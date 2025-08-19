$ErrorActionPreference = 'Stop'

param(
    [switch]$DryRun
)

$home = $env:USERPROFILE

# Load helpers
. "$PSScriptRoot/install_helpers.ps1"
if ($DryRun) { $Global:DotfilesDryRun = $true }

# ------------------------------
# Packages to stow
# ------------------------------

$packages = @('bash','zsh','tmux','git','kitty','lazygit','starship','lf','nvim','vsvim','visual_studio','vimium_c','Documents','Code')

foreach ($pkg in $packages) {
    Restow-Package -Package $pkg -Target $home
}

if (Test-Path 'nvim-win') { Restow-Package -Package 'nvim-win' -Target $env:LOCALAPPDATA }
if (Test-Path 'lf-win')   { Restow-Package -Package 'lf-win'   -Target $env:APPDATA }
if (Test-Path 'Code-win') { Restow-Package -Package 'Code-win' -Target $env:APPDATA }

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
