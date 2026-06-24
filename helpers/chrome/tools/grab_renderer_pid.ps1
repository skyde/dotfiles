param(
  [string]$Chrome = "$PSScriptRoot/../out/Default/chrome.exe",
  [string]$Url = "https://example.test/",
  [string]$OutFile = ".vscode\.renderer_pid",
  [string]$ProfileDir = ".vscode\chrome-native-profile",
  [int]$TimeoutSeconds = 120
)

$OutParent = Split-Path -Parent $OutFile
if (-not $OutParent) { $OutParent = "." }
if ($OutParent) { New-Item -Force -ItemType Directory -Path $OutParent | Out-Null }
$OutPath = Resolve-Path -LiteralPath $OutFile -ErrorAction SilentlyContinue
if (-not $OutPath) {
  New-Item -Force -ItemType File -Path $OutFile | Out-Null
  $OutPath = Resolve-Path -LiteralPath $OutFile
}

$ProfilePath = Resolve-Path -LiteralPath $ProfileDir -ErrorAction SilentlyContinue
if (-not $ProfilePath) {
  New-Item -Force -ItemType Directory -Path $ProfileDir | Out-Null
  $ProfilePath = Resolve-Path -LiteralPath $ProfileDir
}

$ChromePath = Resolve-Path -LiteralPath $Chrome -ErrorAction SilentlyContinue
if (-not $ChromePath) {
  throw "Chrome executable not found at $Chrome"
}

Set-Content -Path $OutPath.Path -Value ""

$arguments = @(
  "--user-data-dir=$($ProfilePath.Path)",
  "--no-first-run",
  "--no-default-browser-check",
  "--renderer-process-limit=1",
  "--wait-for-debugger-children=renderer",
  "--enable-logging=stderr",
  "--log-file=$($OutParent)\renderer-native.log",
  $Url
)

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $ChromePath.Path
$psi.Arguments = ($arguments -join ' ')
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$process = [System.Diagnostics.Process]::Start($psi)

$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
$rendererPid = $null

while ([DateTime]::UtcNow -lt $deadline) {
  $children = Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $process.Id -and $_.CommandLine -like "*--type=renderer*" }
  if ($children) {
    $rendererPid = $children[0].ProcessId
    break
  }
  Start-Sleep -Milliseconds 200
}

if (-not $rendererPid) {
  $process.Kill()
  throw "Timed out waiting for renderer"
}

Set-Content -Path $OutPath.Path -Value $rendererPid
