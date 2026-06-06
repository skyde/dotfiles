# Update dotfiles from remote repository
$ErrorActionPreference = 'Stop'

Write-Host "Updating dotfiles from remote..." -ForegroundColor Green

$previewOnly = $args -contains "--no" -or $args -contains "--dry-run" -or $args -contains "--preview"

# Save current directory
$originalDir = Get-Location

function Assert-LastCommandSucceeded {
    param(
        [Parameter(Mandatory = $true)][string]$Description,
        [int]$ExitCode = $LASTEXITCODE,
        [bool]$Succeeded = $?
    )

    if (-not $Succeeded -or $ExitCode -ne 0) {
        $code = if ($ExitCode -ne 0) { $ExitCode } else { 1 }
        throw "$Description failed with exit code $code"
    }
}

try {
    # Go to dotfiles directory
    Set-Location $PSScriptRoot

    # Pull latest changes
    Write-Host "Pulling latest changes..." -ForegroundColor Yellow
    $global:LASTEXITCODE = 0
    if ($previewOnly) {
        git pull --dry-run
    } else {
        git pull
    }
    Assert-LastCommandSucceeded -Description "git pull"

    # Check for dotfiles-local and update if present
    $localDotfiles = Join-Path $env:USERPROFILE "dotfiles-local"
    if (Test-Path (Join-Path $localDotfiles ".git")) {
        Write-Host "Updating dotfiles-local from remote..." -ForegroundColor Yellow
        $global:LASTEXITCODE = 0
        if ($previewOnly) {
            git -C $localDotfiles pull --dry-run
        } else {
            git -C $localDotfiles pull
        }
        Assert-LastCommandSucceeded -Description "dotfiles-local git pull"

        $localApply = Join-Path $localDotfiles "apply.ps1"
        if (Test-Path $localApply) {
            Write-Host "Running dotfiles-local apply script..." -ForegroundColor Yellow
            $global:LASTEXITCODE = 0
            & $localApply --restow @args
            Assert-LastCommandSucceeded -Description "dotfiles-local apply"
        }
    }

    # Apply the updated dotfiles
    Write-Host "Applying updated dotfiles..." -ForegroundColor Yellow
    # Pass through any additional arguments along with --restow
    $global:LASTEXITCODE = 0
    & "$PSScriptRoot\apply.ps1" --restow @args
    Assert-LastCommandSucceeded -Description "dotfiles apply"

    Write-Host "[ok] Dotfiles updated successfully!" -ForegroundColor Green
} catch {
    Write-Host "[error] Update failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    # Return to original directory
    Set-Location $originalDir
}
