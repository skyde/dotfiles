# Requires: pwsh 7, fzf, rg, fd, bat, code
$ErrorActionPreference = "Stop"

$root = (git rev-parse --show-toplevel) 2>$null
if (-not $root) { $root = (Get-Location).Path }

$cacheDir = Join-Path $env:LOCALAPPDATA "fzf"
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null

$bytes = [System.Text.Encoding]::UTF8.GetBytes($root)
$hash  = [System.BitConverter]::ToString([System.Security.Cryptography.SHA1]::Create().ComputeHash($bytes)).Replace("-",""").ToLower()
$cache = Join-Path $cacheDir "files-$hash.txt"

function Gen-List {
  if (Test-Path (Join-Path $root ".git")) {
    git -C $root ls-files -co --exclude-standard
  } elseif (Get-Command fd -ErrorAction SilentlyContinue) {
    fd --type f --hidden --follow --exclude .git $root
  } elseif (Get-Command rg -ErrorAction SilentlyContinue) {
    rg --files --hidden --follow --glob '!.git' $root
  } else {
    Get-ChildItem -Path $root -Recurse -File -Force | Where-Object { $_.FullName -notmatch '\\.git\\' } | Select-Object -ExpandProperty FullName
  }
}

if (-not (Test-Path $cache)) { Gen-List | Set-Content -Encoding UTF8 $cache }

while ($true) {
  $sel = Get-Content -Raw $cache | fzf --ansi --layout=reverse --height=100% --border `
        --prompt "files> " --preview "bat --style=numbers --color=always --line-range :200 {}" --preview-window=right:66%:wrap
  if ($LASTEXITCODE -ne 0) { break }
  if ($sel) { code -r --% "$sel" }
  Start-Job {
    param($root, $cache)
    if (Test-Path (Join-Path $root ".git")) {
      git -C $root ls-files -co --exclude-standard | Set-Content -Encoding UTF8 $cache
    } elseif (Get-Command fd -ErrorAction SilentlyContinue) {
      fd --type f --hidden --follow --exclude .git $root | Set-Content -Encoding UTF8 $cache
    } elseif (Get-Command rg -ErrorAction SilentlyContinue) {
      rg --files --hidden --follow --glob '!.git' $root | Set-Content -Encoding UTF8 $cache
    } else {
      Get-ChildItem -Path $root -Recurse -File -Force | Where-Object { $_.FullName -notmatch '\\.git\\' } | Select-Object -ExpandProperty FullName | Set-Content -Encoding UTF8 $cache
    }
  } -ArgumentList $root, $cache | Out-Null
}
