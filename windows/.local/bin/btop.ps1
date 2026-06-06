$BtopExe = $null
$WingetPackages = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
if (Test-Path -LiteralPath $WingetPackages) {
  $BtopExe = Get-ChildItem -LiteralPath $WingetPackages -Directory -Filter "aristocratos.btop4win_*" -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName "btop4win\btop4win.exe" } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
}

if (-not $BtopExe) {
  $Command = Get-Command btop4win.exe -ErrorAction SilentlyContinue
  if ($Command) {
    $BtopExe = $Command.Source
  }
}

if (-not $BtopExe) {
  Write-Error "btop.ps1: btop4win.exe not found"
  exit 1
}

if ($MyInvocation.ExpectingInput) {
  $input | & $BtopExe @args
} else {
  & $BtopExe @args
}
exit $LASTEXITCODE
