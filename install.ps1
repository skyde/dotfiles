$ErrorActionPreference = 'Stop'

param(
    [switch]$DryRun
)

# Simple dotfiles installer using stow (PowerShell)
# Much simpler than the complex install.ps1

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Home = $env:USERPROFILE

Write-Host "=== Installing dotfiles with stow ===" -ForegroundColor Green

# Check if stow is installed
if (-not (Get-Command stow -ErrorAction SilentlyContinue)) {
    Write-Host "Error: GNU Stow is not installed." -ForegroundColor Red
    Write-Host "Install it with: winget install stefansundin.gnu-stow"
    exit 1
}

# Function to stow packages from a directory
function Install-Packages {
    param(
        [string]$Directory,
        [string]$Target = $Home
    )
    
    if (-not (Test-Path $Directory)) {
        Write-Host "Directory $Directory not found, skipping" -ForegroundColor Yellow
        return
    }
    
    Write-Host "Installing packages from $Directory..."
    Set-Location $Directory
    
    Get-ChildItem -Directory | ForEach-Object {
        $package = $_.Name
        Write-Host "  Installing $package"
        
        if ($DryRun) {
            Write-Host "    DRY_RUN: stow --target=`"$Target`" `"$package`"" -ForegroundColor Cyan
        } else {
            try {
                & stow --target="$Target" "$package"
            } catch {
                Write-Host "    Warning: Failed to stow $package (may already exist)" -ForegroundColor Yellow
            }
        }
    }
    
    Set-Location $ScriptDir
}

# Install common packages (all platforms)
Install-Packages -Directory (Join-Path $ScriptDir "dotfiles\common")

# Install Windows-specific packages
if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    Write-Host "Detected Windows"
    Install-Packages -Directory (Join-Path $ScriptDir "dotfiles\windows")
}

Write-Host "=== Installation complete! ===" -ForegroundColor Green
Write-Host "Tip: Use '-DryRun' parameter to preview changes"
