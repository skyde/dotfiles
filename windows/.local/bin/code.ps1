$Candidates = @()
if ($env:VSCODE_CLI) {
  $Candidates += $env:VSCODE_CLI
}
$Candidates += Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code\bin\code.cmd"
$Candidates += Join-Path $env:ProgramFiles "Microsoft VS Code\bin\code.cmd"

$CodeCli = $Candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $CodeCli) {
  Write-Error "code.ps1: Visual Studio Code CLI not found"
  exit 1
}

if ($MyInvocation.ExpectingInput) {
  $input | & $CodeCli @args
} else {
  & $CodeCli @args
}
exit $LASTEXITCODE
