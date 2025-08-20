# Ultra-simple dotfiles installer for Windows
$ErrorActionPreference = 'Stop'

Write-Host "Installing dotfiles..." -ForegroundColor Green

# Check for stow
if (-not (Get-Command stow -ErrorAction SilentlyContinue)) {
    Write-Host "Please install stow first: winget install stefansundin.gnu-stow" -ForegroundColor Red
    exit 1
}

# Install common configs
Set-Location "$PSScriptRoot\dotfiles\common"
Get-ChildItem -Directory | ForEach-Object {
    Write-Host "Installing $($_.Name)..."
    try {
        & stow --target="$env:USERPROFILE" $_.Name
    } catch {
        Write-Host "Warning: $($_.Name) may already exist" -ForegroundColor Yellow
    }
}

# Install Windows-specific configs
Set-Location "..\windows"
Get-ChildItem -Directory | ForEach-Object {
    Write-Host "Installing Windows config: $($_.Name)..."
    try {
        & stow --target="$env:USERPROFILE" $_.Name
    } catch {
        Write-Host "Warning: $($_.Name) may already exist" -ForegroundColor Yellow
    }
}

Write-Host "Done! Dotfiles installed." -ForegroundColor Green
