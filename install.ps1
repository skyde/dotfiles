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

# Install VS Code extensions if available
if (Get-Command code -ErrorAction SilentlyContinue) {
    Write-Host "Installing VS Code extensions..." -ForegroundColor Yellow
    if (Test-Path "vscode_extensions.txt") {
        Get-Content "vscode_extensions.txt" | ForEach-Object {
            if ($_.Trim()) {
                Write-Host "Installing extension: $_"
                & code --install-extension $_ --force
            }
        }
    }
}

# Install common development tools (optional)
# Set $env:INSTALL_APPS=1 to auto-install, or $env:INSTALL_APPS=0 to skip
if ($env:INSTALL_APPS) {
    $installApps = $env:INSTALL_APPS
} else {
    Write-Host ""
    $installApps = Read-Host "Install common development tools via winget? (y/N)"
}

if ($installApps -match "^[Yy1]") {
    Write-Host "Installing common development tools..." -ForegroundColor Yellow
    $apps = @(
        "Git.Git",
        "BurntSushi.ripgrep.MSVC", 
        "sharkdp.fd",
        "sharkdp.bat",
        "dandavison.delta",
        "Neovim.Neovim",
        "Microsoft.PowerShell"
    )
    
    foreach ($app in $apps) {
        Write-Host "Installing $app..."
        try {
            winget install $app --silent --accept-package-agreements --accept-source-agreements
        } catch {
            Write-Host "Warning: Failed to install $app" -ForegroundColor Yellow
        }
    }
}

Write-Host "Done! Dotfiles installed with automation." -ForegroundColor Green
