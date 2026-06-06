$BashExe = Join-Path $env:ProgramFiles "Git\usr\bin\bash.exe"
if (-not (Test-Path -LiteralPath $BashExe)) {
  $BashExe = "bash.exe"
}

& $BashExe (Join-Path $PSScriptRoot "tmux") @args
exit $LASTEXITCODE
