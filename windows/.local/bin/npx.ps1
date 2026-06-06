$NodeRoot = Join-Path $env:USERPROFILE ".local\opt\nodejs"
$NodeExe = Join-Path $NodeRoot "node.exe"
$NpxCli = Join-Path $NodeRoot "node_modules\npm\bin\npx-cli.js"
if (-not (Test-Path -LiteralPath $NodeExe) -or -not (Test-Path -LiteralPath $NpxCli)) {
  Write-Error "npx.ps1: portable npx installation not found"
  exit 1
}

if ($MyInvocation.ExpectingInput) {
  $input | & $NodeExe $NpxCli @args
} else {
  & $NodeExe $NpxCli @args
}
exit $LASTEXITCODE
