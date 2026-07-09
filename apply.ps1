# Stow wrapper for dotfiles management on Windows.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptArguments = @($args)
$stowCommandName = if ($env:DOTFILES_STOW_COMMAND) { $env:DOTFILES_STOW_COMMAND } else { 'stow' }
$dryRun = $false
$stowArguments = @()

foreach ($argument in $scriptArguments) {
    if ($argument -in @('--no', '--simulate', '--no-act', '-n')) {
        $dryRun = $true
    }

    if ($argument -eq '--no-act') {
        $stowArguments += '--no'
    } elseif ($argument -notin @('--yes', '-y')) {
        $stowArguments += $argument
    }
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

function Ensure-Stow {
    if (Get-Command $stowCommandName -ErrorAction SilentlyContinue) {
        return
    }

    if ($dryRun) {
        throw 'GNU Stow is required to preview dotfile changes; install it and retry.'
    }

    if ($stowCommandName -ne 'stow') {
        throw "Configured Stow command '$stowCommandName' was not found."
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'GNU Stow is missing. Install it with: winget install stefansundin.gnu-stow'
    }

    Write-Host 'Installing GNU Stow...' -ForegroundColor Yellow
    Invoke-NativeCommand -Command 'winget' -ArgumentList @(
        'install',
        'stefansundin.gnu-stow',
        '--silent',
        '--accept-package-agreements',
        '--accept-source-agreements'
    )

    if (-not (Get-Command stow -ErrorAction SilentlyContinue)) {
        throw "GNU Stow was installed, but 'stow' is not available in this session. Open a new shell and retry."
    }
}

function Invoke-StowPackage {
    param(
        [Parameter(Mandatory = $true)][string]$Package,
        [string[]]$ExtraArgs = @()
    )

    if (-not (Test-Path -LiteralPath $Package -PathType Container)) {
        return
    }

    Write-Host "📦 Applying $Package package"
    $commandArguments = @("--target=$env:USERPROFILE", '--verbose=1') + @($ExtraArgs) + @($Package)
    Invoke-NativeCommand -Command $stowCommandName -ArgumentList $commandArguments
}

if (-not $env:USERPROFILE) {
    Write-Host '❌ USERPROFILE is not set.' -ForegroundColor Red
    exit 1
}

$originalLocation = (Get-Location).Path
try {
    Set-Location -LiteralPath $PSScriptRoot
    Ensure-Stow

    Invoke-StowPackage -Package 'common' -ExtraArgs $stowArguments
    Invoke-StowPackage -Package 'windows' -ExtraArgs $stowArguments

    $localApply = Join-Path $env:USERPROFILE 'dotfiles-local\apply.ps1'
    if (Test-Path -LiteralPath $localApply -PathType Leaf) {
        Write-Host '🔗 Found dotfiles-local, applying...'
        & $localApply @scriptArguments
        if (-not $?) {
            throw 'dotfiles-local apply.ps1 failed.'
        }
    }

    if ($dryRun) {
        Write-Host '✅ Dry run completed - no changes were made' -ForegroundColor Green
    } else {
        Write-Host '✅ Stow operation completed' -ForegroundColor Green
    }
} catch {
    Write-Host "❌ Stow operation failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    Set-Location -LiteralPath $originalLocation
}
