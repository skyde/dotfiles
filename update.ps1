# Update dotfiles from remote repository
$ErrorActionPreference = 'Stop'

Write-Host "Updating dotfiles from remote..." -ForegroundColor Green

# Save current directory
$originalDir = Get-Location

try {
    # Go to dotfiles directory
    Set-Location $PSScriptRoot

    # Pull latest changes
    Write-Host "Pulling latest changes..." -ForegroundColor Yellow
    git pull

    # Apply the updated dotfiles
    Write-Host "Applying updated dotfiles..." -ForegroundColor Yellow
    # Pass through any additional arguments along with --restow
    & "$PSScriptRoot\apply.ps1" --restow @args

    Write-Host "✅ Dotfiles updated successfully!" -ForegroundColor Green
} catch {
    Write-Host "❌ Update failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    # Return to original directory
    Set-Location $originalDir
}
