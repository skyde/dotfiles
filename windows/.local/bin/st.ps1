# st - Search Tool wrapper
# Uses st-zoekt if .zoekt index exists, otherwise falls back to st-rg
param(
    [switch]$code,
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Remaining
)

$args = @()
if ($code) { $args += "--code" }
$args += $Remaining

if (Test-Path ".zoekt") {
    & "$PSScriptRoot\st-zoekt.ps1" @args
} else {
    & "$PSScriptRoot\st-rg.ps1" @args
}
