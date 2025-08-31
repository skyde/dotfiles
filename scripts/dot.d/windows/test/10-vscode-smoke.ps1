Param()
$ErrorActionPreference = 'Stop'
# Minimal VS Code user files smoke via existing bootstrap helper
& (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..\..\bootstrap.ps1') -OnlyVSCode
Write-Host 'Windows VS Code smoke OK' -ForegroundColor Green

