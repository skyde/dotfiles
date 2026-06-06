$NodeRoot = Join-Path $env:USERPROFILE ".local\opt\nodejs"
$NodeExe = Join-Path $NodeRoot "node.exe"
$NpmCli = Join-Path $NodeRoot "node_modules\npm\bin\npm-cli.js"
if (-not (Test-Path -LiteralPath $NodeExe) -or -not (Test-Path -LiteralPath $NpmCli)) {
  Write-Error "npm.ps1: portable npm installation not found"
  exit 1
}

if ($MyInvocation.ExpectingInput) {
  $input | & $NodeExe $NpmCli @args
} else {
  & $NodeExe $NpmCli @args
}
exit $LASTEXITCODE
