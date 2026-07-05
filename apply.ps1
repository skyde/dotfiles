# Stow wrapper for dotfiles management on Windows
$ErrorActionPreference = 'Stop'

function Install-Stow {
    if (Get-Command stow -ErrorAction SilentlyContinue) {
        return
    }

    Write-Host "Installing stow..." -ForegroundColor Yellow
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            winget install stefansundin.gnu-stow --silent --accept-package-agreements --accept-source-agreements
        } catch {
            Write-Host "winget install failed, trying Chocolatey fallback" -ForegroundColor Yellow
        }
    }

    if ((-not (Get-Command stow -ErrorAction SilentlyContinue)) -and (Get-Command choco -ErrorAction SilentlyContinue)) {
        try {
            choco install stow -y
            $chocoProfile = Join-Path $env:ChocolateyInstall "helpers\chocolateyProfile.psm1"
            if (Test-Path $chocoProfile) {
                Import-Module $chocoProfile
                refreshenv
            }
        } catch {
            Write-Host "Chocolatey install failed" -ForegroundColor Yellow
        }
    }

    if (-not (Get-Command stow -ErrorAction SilentlyContinue)) {
        Write-Host "Please install GNU Stow first, then rerun apply.ps1." -ForegroundColor Red
        exit 1
    }
}

# Install stow if needed
Install-Stow

# Go to script directory
Set-Location $PSScriptRoot

function Invoke-StowPackage {
    param(
        [Parameter(Mandatory=$true)][string]$Package,
        [string[]]$ExtraArgs
    )

    if (-not (Test-Path $Package)) { return }

    Write-Host "📦 Installing $Package package"
    & stow --target=$env:USERPROFILE --verbose @ExtraArgs $Package
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
