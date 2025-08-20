# Simple dotfiles installer for Windows
$ErrorActionPreference = 'Stop'

Write-Host "Installing dotfiles..." -ForegroundColor Green

# Use apply.ps1 with --adopt to handle conflicts
& "$PSScriptRoot\apply.ps1" --adopt

# Install VS Code extensions
$codeCommand = Get-Command code -ErrorAction SilentlyContinue
if ($codeCommand) {
    if (Test-Path "vscode_extensions.txt") {
        if ($env:AUTO_INSTALL -eq "1") {
            $installExtensions = "y"
        } elseif ($env:AUTO_INSTALL -eq "0") {
            $installExtensions = "n"
        } else {
            $installExtensions = Read-Host "Install VS Code extensions? (y/N)"
        }
        
        if ($installExtensions -match "^[Yy]") {
            Write-Host "Installing VS Code extensions..." -ForegroundColor Yellow
            Get-Content "vscode_extensions.txt" | ForEach-Object {
                $ext = $_.Trim()
                if ($ext -and (-not $ext.StartsWith("#"))) {
                    Write-Host "  Installing: $ext" -ForegroundColor Cyan
                    try {
                        & code --install-extension $ext --force | Out-Null
                    } catch {
                        Write-Host "    Warning: Failed to install $ext" -ForegroundColor Yellow
                    }
                }
            }
            Write-Host "✅ VS Code extensions installed" -ForegroundColor Green
        } else {
            Write-Host "Skipping VS Code extensions" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "VS Code not found, skipping extensions" -ForegroundColor Yellow
}

# Install common development tools
if ($env:AUTO_INSTALL -eq "1") {
    $installApps = "y"
} elseif ($env:AUTO_INSTALL -eq "0") {
    $installApps = "n"
} else {
    $installApps = Read-Host "Install common development tools? (y/N)"
}

if ($installApps -match "^[Yy]") {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Installing common apps..." -ForegroundColor Yellow
        $apps = @(
            "Git.Git",
            "BurntSushi.ripgrep.MSVC", 
            "sharkdp.fd",
            "sharkdp.bat",
            "dandavison.delta",
            "Neovim.Neovim",
            "Microsoft.PowerShell",
            "Starship.Starship"
        )
        
        foreach ($app in $apps) {
            Write-Host "Installing $app..." -ForegroundColor Cyan
            try {
                winget install $app --silent --accept-package-agreements --accept-source-agreements | Out-Null
            } catch {
                Write-Host "Warning: Failed to install $app" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "Winget not found. Please install from Microsoft Store or enable it." -ForegroundColor Red
    }
}

Write-Host "Done! 🎉" -ForegroundColor Green
