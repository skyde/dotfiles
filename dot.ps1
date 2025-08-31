Param(
  [Parameter(Position=0)][ValidateSet('apply','update','restow','delete','diff','test')]
  [string]$Command = 'apply',
  [string]$Target = $env:USERPROFILE,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$hooksRoot = Join-Path $repo 'scripts\dot.d'
$env:DOT_OS = 'windows'
$env:DOT_REPO = $repo
$env:DOT_TARGET = $Target
if ($DryRun) { $env:DOT_DRYRUN = '1' } else { $env:DOT_DRYRUN = $null }

function Invoke-Hooks([string]$Stage) {
  $platforms = @('common','windows')
  $ran = $false
  foreach ($p in $platforms) {
    $dir = Join-Path $hooksRoot "$p\$Stage"
    if (Test-Path $dir) {
      Get-ChildItem -Path $dir -File | Sort-Object Name | ForEach-Object {
        $env:DOT_CMD = $Command
        Write-Host ("dot.ps1: running {0}/{1}/{2}" -f $p,$Stage,$_.Name) -ForegroundColor Cyan
        & $_.FullName
        $ran = $true
      }
    }
  }
  if (-not $ran) { Write-Host ("dot.ps1: no hooks for {0}" -f $Stage) }
}

switch ($Command) {
  'test' {
    Write-Host 'dot.ps1 test: Windows smoke (Unix tests require WSL)' -ForegroundColor Cyan
    Invoke-Hooks 'test'
    break
  }
  'apply'   { Invoke-Hooks 'apply';  break }
  'restow'  { Invoke-Hooks 'restow'; break }
  'delete'  { Invoke-Hooks 'delete'; break }
  'update'  { try { git -C $repo pull --ff-only } catch {} ; Invoke-Hooks 'restow'; break }
  'diff'    { Write-Host 'dot.ps1 diff: not supported on Windows' -ForegroundColor Yellow; break }
}
