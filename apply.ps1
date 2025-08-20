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

# Get all package directories
$packages = Get-ChildItem -Directory | ForEach-Object { $_.Name }

# Pass all arguments directly to stow with sensible defaults
$stowArgs = @("--target=$env:USERPROFILE", "--verbose") + $args + $packages

try {
    & stow @stowArgs
    Write-Host "✅ Stow operation completed" -ForegroundColor Green
} catch {
    Write-Host "❌ Stow operation failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
