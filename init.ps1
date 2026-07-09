# Interactive dotfiles bootstrapper for Windows.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptArguments = @($args)

function Get-UserConfirmation {
    param([Parameter(Mandatory = $true)][string]$Prompt)

    if ($env:AUTO_INSTALL -eq '1') {
        return 'y'
    }
    if ($env:AUTO_INSTALL -eq '0') {
        return 'n'
    }
    return Read-Host $Prompt
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$ArgumentList = @()
    )

    $global:LASTEXITCODE = 0
    & $Command @ArgumentList
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "'$Command' failed with exit code $exitCode"
    }
}

$originalLocation = (Get-Location).Path
try {
    Set-Location -LiteralPath $PSScriptRoot
    Write-Host 'Installing dotfiles...' -ForegroundColor Green

    & (Join-Path $PSScriptRoot 'apply.ps1') @scriptArguments
    if (-not $?) {
        throw 'apply.ps1 failed.'
    }

    $extensionsFile = Join-Path $PSScriptRoot 'vscode_extensions.txt'
    if ((Get-Command code -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $extensionsFile -PathType Leaf)) {
        $installExtensions = Get-UserConfirmation 'Install VS Code extensions? (y/N)'
        if ($installExtensions -match '^[Yy]') {
            Write-Host 'Installing VS Code extensions...' -ForegroundColor Yellow
            foreach ($line in Get-Content -LiteralPath $extensionsFile) {
                $extension = $line.Trim()
                if (-not $extension -or $extension.StartsWith('#')) {
                    continue
                }

                Write-Host "  Installing: $extension" -ForegroundColor Cyan
                try {
                    Invoke-NativeCommand -Command 'code' -ArgumentList @('--install-extension', $extension, '--force')
                } catch {
                    Write-Host "    Warning: Failed to install ${extension}: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
            Write-Host '✅ VS Code extension processing completed' -ForegroundColor Green
        } else {
            Write-Host 'Skipping VS Code extensions' -ForegroundColor Yellow
        }
    } else {
        Write-Host 'VS Code not found, skipping extensions' -ForegroundColor Yellow
    }

    $installApps = Get-UserConfirmation 'Install common development tools? (y/N)'
    if ($installApps -match '^[Yy]') {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Host 'Winget not found. Install App Installer from the Microsoft Store.' -ForegroundColor Red
        } else {
            Write-Host 'Installing common apps...' -ForegroundColor Yellow
            $apps = @(
                'Git.Git',
                'BurntSushi.ripgrep.MSVC',
                'junegunn.fzf',
                'sharkdp.bat',
                'Neovim.Neovim',
                'dandavison.delta',
                'eza-community.eza',
                'JesseDuffield.lazygit',
                'sharkdp.fd',
                'ajeetdsouza.zoxide',
                'Starship.Starship',
                'gokcehan.lf'
            )

            foreach ($app in $apps) {
                Write-Host "Installing $app..." -ForegroundColor Cyan
                try {
                    Invoke-NativeCommand -Command 'winget' -ArgumentList @(
                        'install',
                        $app,
                        '--silent',
                        '--accept-package-agreements',
                        '--accept-source-agreements'
                    )
                } catch {
                    Write-Host "Warning: Failed to install ${app}: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
    }

    Write-Host 'Done! 🎉' -ForegroundColor Green
} finally {
    Set-Location -LiteralPath $originalLocation
}
