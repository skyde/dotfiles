Param(
  [Parameter(Position=0)][ValidateSet('apply','update','restow','delete','diff','test')]
  [string]$Command = 'apply',
  [Parameter(ValueFromRemainingArguments=$true)]
  [string[]]$Args
)

$ErrorActionPreference = 'Stop'
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Repo = Resolve-Path $PSScriptRoot

function Write-Info([string]$Msg) { Write-Host $Msg -ForegroundColor Cyan }
function Write-Warn([string]$Msg) { Write-Host $Msg -ForegroundColor Yellow }
function Write-Err([string]$Msg)  { Write-Host $Msg -ForegroundColor Red }

switch ($Command) {
  'test' {
    Write-Info 'dot.ps1 test: running tests in ./tests (Unix-only Stow tests)'
    $tests = Join-Path $Repo 'tests'
    if (-not (Test-Path $tests)) { Write-Err 'tests/ not found'; exit 1 }
    if ($IsWindows) {
      Write-Warn 'Stow-based tests are Unix-only. Run them under WSL or a Unix shell.'
      Write-Info 'Running Windows smoke: Ensure-VSCodeFiles via bootstrap.ps1 -OnlyVSCode'
      & (Join-Path $Repo 'scripts' 'bootstrap.ps1') -OnlyVSCode
      Write-Host '✅ Windows VS Code smoke OK.' -ForegroundColor Green
      break
    }
    Push-Location $tests
    try {
      npm install
      npm test
    } finally {
      Pop-Location
    }
    break
  }
  'apply' {
    Write-Info 'dot.ps1 apply: delegating to scripts/bootstrap.ps1 for Windows'
    & (Join-Path $Repo 'scripts' 'bootstrap.ps1')
    break
  }
  'update' {
    Write-Info 'dot.ps1 update: pulling repo then applying'
    try { git -C $Repo pull --ff-only } catch {}
    & (Join-Path $Repo 'scripts' 'bootstrap.ps1')
    break
  }
  'restow' {
    Write-Info 'dot.ps1 restow: re-running apply to ensure files are up-to-date'
    & (Join-Path $Repo 'scripts' 'bootstrap.ps1')
    break
  }
  'delete' {
    Write-Warn 'dot.ps1 delete: no Stow on Windows. Remove files manually if needed.'
    break
  }
  'diff' {
    Write-Warn 'dot.ps1 diff: Stow dry-run not applicable on Windows.'
    Write-Info 'Use -WhatIf in scripts/bootstrap.ps1 for a lightweight preview.'
    break
  }
}

