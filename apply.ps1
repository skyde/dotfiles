# Stow wrapper for dotfiles management on Windows
$ErrorActionPreference = 'Stop'

function Get-StowCommand {
    if (Get-Command stow -ErrorAction SilentlyContinue) {
        return "stow"
    }
    if (Get-Command winstow -ErrorAction SilentlyContinue) {
        return "winstow"
    }
    return $null
}

$stowCommand = Get-StowCommand
if (-not $stowCommand) {
    Write-Host "Installing a stow-compatible tool..." -ForegroundColor Yellow
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            winget install --id MathiasCodes.Winstow --exact --silent --accept-package-agreements --accept-source-agreements | Out-Null
        } catch {
            Write-Host "Warning: failed to install Winstow via winget: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "winget not found. Please install Winstow manually: winget install MathiasCodes.Winstow" -ForegroundColor Red
    }

    $stowCommand = Get-StowCommand
    if (-not $stowCommand) {
        Write-Host "No stow-compatible command found (expected 'stow' or 'winstow')." -ForegroundColor Red
        exit 1
    }
}

# Go to script directory
Set-Location $PSScriptRoot

function Invoke-StowPackage {
    param(
        [Parameter(Mandatory=$true)][string]$Package,
        [string[]]$ExtraArgs
    )

    if (-not (Test-Path $Package)) { return }

    Write-Host "📦 Installing $Package package"
    & $stowCommand --target=$env:USERPROFILE --verbose @ExtraArgs $Package
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
