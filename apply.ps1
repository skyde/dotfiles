# Stow wrapper for dotfiles management on Windows
$ErrorActionPreference = 'Stop'

# Install stow if needed
if (-not (Get-Command stow -ErrorAction SilentlyContinue)) {
    Write-Host "Installing stow..." -ForegroundColor Yellow
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        & winget install stefansundin.gnu-stow --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "winget failed to install GNU Stow (exit code $LASTEXITCODE)"
        }

        $wingetLinks = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"
        if (Test-Path $wingetLinks) {
            $env:PATH = "$wingetLinks$([IO.Path]::PathSeparator)$env:PATH"
        }
    } else {
        Write-Host "Please install stow first: winget install stefansundin.gnu-stow" -ForegroundColor Red
        exit 1
    }
}

if (-not (Get-Command stow -ErrorAction SilentlyContinue)) {
    throw "GNU Stow is unavailable after installation"
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
    & stow --target=$env:USERPROFILE --verbose @ExtraArgs $Package
    if ($LASTEXITCODE -ne 0) {
        throw "GNU Stow failed for package '$Package' (exit code $LASTEXITCODE)"
    }
}

try {
    # Always install common package
    Invoke-StowPackage -Package "common" -ExtraArgs $args
    # Windows-specific package
    Invoke-StowPackage -Package "windows" -ExtraArgs $args
    Write-Host "✅ Stow operation completed" -ForegroundColor Green
} catch {
    Write-Host "❌ Stow operation failed: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
