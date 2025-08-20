# Stow wrapper for dotfiles management on Windows
$ErrorActionPreference = 'Stop'

# Install stow if needed
if (-not (Get-Command stow -ErrorAction SilentlyContinue)) {
    Write-Host "Installing stow..." -ForegroundColor Yellow
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install stefansundin.gnu-stow --silent --accept-package-agreements --accept-source-agreements
    } else {
        Write-Host "Please install stow first: winget install stefansundin.gnu-stow" -ForegroundColor Red
        exit 1
    }
}

# Go to dotfiles directory
$dotfilesPath = Join-Path $PSScriptRoot "dotfiles"
Set-Location $dotfilesPath

function Invoke-StowDir {
    param(
        [Parameter(Mandatory=$true)][string]$Dir,
        [string[]]$ExtraArgs
    )

    if (-not (Test-Path $Dir)) { return }

    Push-Location $Dir
    try {
        $packages = Get-ChildItem -Directory | ForEach-Object { $_.Name }
        if ($packages.Count -eq 0) { return }
        Write-Host "📦 Installing $Dir packages: $($packages -join ', ')"
        & stow --target=$env:USERPROFILE --verbose @ExtraArgs @packages
    } finally {
        Pop-Location
    }
}

try {
    # Always install common packages
    Invoke-StowDir -Dir "common" -ExtraArgs $args
    # Windows-specific packages
    Invoke-StowDir -Dir "windows" -ExtraArgs $args
    Write-Host "✅ Stow operation completed" -ForegroundColor Green
} catch {
    Write-Host "❌ Stow operation failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
