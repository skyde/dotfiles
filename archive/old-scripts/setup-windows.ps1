# Requires PowerShell 7+
$ErrorActionPreference = 'Stop'

# Build $COMMON_APPS array from file lines
$repo = Split-Path -Parent $PSScriptRoot
$COMMON_APPS = Get-Content (Join-Path $repo 'common_apps.txt') | Where-Object { $_.Trim() -ne '' }

Write-Host 'Running Windows setup...'

function Confirm-Change([string]$verb, [string]$name, [int]$present) {
    if ($present -eq 1) { return $true }
    $response = Read-Host "${verb} ${name}? [y/N]"
    return $response -match '^(y|Y)(es)?$'
}

function Ensure-Winget([string]$name, [string]$id) {
    $present = winget list --id $id --exact 2>$null | Select-String $id
    if ($present) {
        if (Confirm-Change 'Update' $name 1) {
            winget upgrade --id $id --exact --accept-source-agreements --accept-package-agreements | Out-Null
        }
    } else {
        if (Confirm-Change 'Install' $name 0) {
            winget install --id $id --exact --accept-source-agreements --accept-package-agreements | Out-Null
        }
    }
}

if (Get-Command winget -ErrorAction SilentlyContinue) {
    $wingetAppMap = @{
        'git'      = 'Git.Git'
        'ripgrep'  = 'BurntSushi.ripgrep.MSVC'
        'fd'       = 'sharkdp.fd'
        'fzf'      = 'junegunn.fzf'
        'bat'      = 'sharkdp.bat'
        'delta'    = 'dandavison.delta'
        'eza'      = 'eza-community.eza'
        'less'     = 'jftuga.less'
        'llvm'     = 'LLVM.LLVM'
        'nvim'     = 'Neovim.Neovim'
        'starship' = 'Starship.Starship'
        'zoxide'   = 'ajeetdsouza.zoxide'
        'lf'       = 'gokcehan.lf'
        'lazygit'  = 'JesseDuffield.lazygit'
    }
    foreach ($pkg in $COMMON_APPS) {
        if ($wingetAppMap.ContainsKey($pkg)) {
            Ensure-Winget $pkg $wingetAppMap[$pkg]
        } else {
            Write-Host "No winget mapping for $pkg, skipping."
        }
    }
} else {
    Write-Warning 'winget is not available. Skipping winget app installs.'
}

# Set default shell hint
[Environment]::SetEnvironmentVariable('SHELL', 'pwsh', 'User')
Write-Host '✔  SHELL=pwsh (User scope) set.'

# Fonts hint for JetBrainsMono NF
$fontCount = (Get-ChildItem -Path "$env:WINDIR\Fonts" -Include '*JetBrainsMono*NF*.ttf' -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
if ($fontCount -eq 0) {
    Write-Warning 'JetBrainsMono Nerd Font not found. Install from https://github.com/ryanoasis/nerd-fonts/releases.'
}
