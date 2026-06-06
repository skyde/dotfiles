$NodeExe = Join-Path $env:USERPROFILE ".local\opt\nodejs\node.exe"
if (-not (Test-Path -LiteralPath $NodeExe)) {
  Write-Error "node.ps1: portable node.exe not found"
  exit 1
}

if ($MyInvocation.ExpectingInput) {
  $input | & $NodeExe @args
} else {
  & $NodeExe @args
}
exit $LASTEXITCODE
