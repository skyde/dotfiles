# Update dotfiles from their remotes and restow them.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptArguments = @($args)

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

if (-not $env:USERPROFILE) {
    Write-Host '❌ USERPROFILE is not set.' -ForegroundColor Red
    exit 1
}

$originalLocation = (Get-Location).Path
try {
    Set-Location -LiteralPath $PSScriptRoot
    Write-Host 'Updating dotfiles from remote...' -ForegroundColor Green

    Write-Host 'Pulling latest changes...' -ForegroundColor Yellow
    Invoke-NativeCommand -Command 'git' -ArgumentList @('pull', '--ff-only')

    $localDotfiles = Join-Path $env:USERPROFILE 'dotfiles-local'
    if (Test-Path -LiteralPath (Join-Path $localDotfiles '.git')) {
        Write-Host 'Updating dotfiles-local from remote...' -ForegroundColor Yellow
        Invoke-NativeCommand -Command 'git' -ArgumentList @('-C', $localDotfiles, 'pull', '--ff-only')
    }

    Write-Host 'Applying updated dotfiles...' -ForegroundColor Yellow
    $applyArguments = @('--restow') + $scriptArguments
    & (Join-Path $PSScriptRoot 'apply.ps1') @applyArguments
    if (-not $?) {
        throw 'apply.ps1 failed.'
    }

    Write-Host '✅ Dotfiles updated successfully!' -ForegroundColor Green
} catch {
    Write-Host "❌ Update failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    Set-Location -LiteralPath $originalLocation
}
