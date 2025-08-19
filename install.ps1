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

# Ensure source files exist so links are not broken
foreach ($name in 'settings.json','keybindings.json','tasks.json') {
    Ensure-FileExists -Path (Join-Path $vscodeDotConfigUser $name)
}

$vscodePairs = @(
    (Join-Path $vscodeDotConfigUser 'settings.json') + '::' + (Join-Path $vscodeAppDataUser 'settings.json'),
    (Join-Path $vscodeDotConfigUser 'keybindings.json') + '::' + (Join-Path $vscodeAppDataUser 'keybindings.json'),
    (Join-Path $vscodeDotConfigUser 'tasks.json') + '::' + (Join-Path $vscodeAppDataUser 'tasks.json')
)
Invoke-SymlinkPairs -Pairs $vscodePairs
