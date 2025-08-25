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

function Invoke-StowPackage {
    param(
        [Parameter(Mandatory=$true)][string]$Package,
        [string[]]$ExtraArgs
    )

    if (-not (Test-Path $Package)) { return }

    Write-Host "📦 Installing $Package package"
    # --no-folding ensures individual files are linked rather than entire directories
    & stow --target=$env:USERPROFILE --verbose --no-folding @ExtraArgs $Package
}

try {
    # Always install common package
    Invoke-StowPackage -Package "common" -ExtraArgs $args
    # Windows-specific package
    Invoke-StowPackage -Package "windows" -ExtraArgs $args
    Write-Host "✅ Stow operation completed" -ForegroundColor Green
} catch {
    Write-Host "❌ Stow operation failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
