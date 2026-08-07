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

    # A native command's exit code does not raise, whatever
    # $ErrorActionPreference says: $PSNativeCommandUseErrorActionPreference is
    # still off by default as of PowerShell 7.4. So the try/catch below never
    # saw a stow failure — every conflict printed
    # "✅ Stow operation completed" and exited 0 with nothing stowed at all.
    if ($LASTEXITCODE -ne 0) {
        throw "stow exited $LASTEXITCODE for package '$Package'"
    }
}

try {
    # Always install common package
    Invoke-StowPackage -Package "common" -ExtraArgs $args
    # Windows-specific package
    Invoke-StowPackage -Package "windows" -ExtraArgs $args

    # Mirrors the tail of apply.sh. Windows had no dotfiles-local support here
    # at all; update.ps1 tried to cover it by running a dotfiles-local
    # install.ps1, a name this repo has never used on either platform.
    $localApply = Join-Path $env:USERPROFILE "dotfiles-local\apply.ps1"
    if (Test-Path $localApply) {
        Write-Host "🔗 Found dotfiles-local, applying..."
        & $localApply @args
    }

    Write-Host "✅ Stow operation completed" -ForegroundColor Green
} catch {
    Write-Host "❌ Stow operation failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
