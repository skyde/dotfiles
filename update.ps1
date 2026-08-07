# Update dotfiles from remote repository
$ErrorActionPreference = 'Stop'

Write-Host "Updating dotfiles from remote..." -ForegroundColor Green

# Save current directory
$originalDir = Get-Location

try {
    # Go to dotfiles directory
    Set-Location $PSScriptRoot

    # Pull latest changes.
    #
    # A failed pull must not stop the apply, matching update.sh: offline, on a
    # branch with no upstream, or with a conflicting local edit, restowing what
    # is already checked out is still worth doing and is usually the reason for
    # running this.
    Write-Host "Pulling latest changes..." -ForegroundColor Yellow
    $pullFailed = $false
    git pull
    if ($LASTEXITCODE -ne 0) {
        $pullFailed = $true
        Write-Warning "git pull failed; applying the currently checked-out dotfiles instead"
    }

    # Check for dotfiles-local and update if present. Its apply script is
    # deliberately not run here — apply.ps1 does that, the way apply.sh does,
    # and running it in both places ran the user's own script twice per update.
    # This used to reach for a dotfiles-local install.ps1, a name neither this
    # repo nor its shell counterpart has ever used.
    $localDotfiles = Join-Path $env:USERPROFILE "dotfiles-local"
    if (Test-Path (Join-Path $localDotfiles ".git")) {
        Write-Host "Updating dotfiles-local from remote..." -ForegroundColor Yellow
        git -C $localDotfiles pull
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "could not update dotfiles-local; continuing"
        }
    }

    # Apply the updated dotfiles
    Write-Host "Applying updated dotfiles..." -ForegroundColor Yellow
    # Pass through any additional arguments along with --restow
    & "$PSScriptRoot\apply.ps1" --restow @args
    if ($LASTEXITCODE -ne 0) {
        throw "apply.ps1 exited $LASTEXITCODE"
    }

    if ($pullFailed) {
        Write-Host "⚠️  Dotfiles applied, but the update could not be pulled — see the warning above." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "✅ Dotfiles updated successfully!" -ForegroundColor Green
} catch {
    Write-Host "❌ Update failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    # Return to original directory
    Set-Location $originalDir
}
