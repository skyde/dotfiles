function Get-Adv2Drive {
    # Look at every mounted removable volume
    $vols = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'Removable' }

    foreach ($v in $vols) {
        # known labels
        if ($v.FileSystemLabel -match '^(ADVANTAGE2|KINESIS[\s-]?KB)$') { return $v }

        # fallback: SmartSet folders
        $root = "$($v.DriveLetter):\"
        if ( (Test-Path -LiteralPath (Join-Path $root 'active')) -and
             (Test-Path -LiteralPath (Join-Path $root 'firmware')) ) {
            return $v
        }
    }
    return $null
}

$adv = Get-Adv2Drive
if (-not $adv) {
    Write-Warning "No Kinesis Advantage2 v-drive found. If you need to sync keyboard layouts press Prog+Shift+Esc to enter power user mode, then Prog+F1 to mount. Then re-run 'yadm pull'."
    return
}

$target = Join-Path ("$($adv.DriveLetter):\") 'active'
New-Item -ItemType Directory -Path $target -Force | Out-Null

$sourceRoot = "$env:USERPROFILE"
$source     = Join-Path $sourceRoot 'kinesis-advantage2\layouts'

Write-Host "Syncing Kinesis Advantage 2 layouts -> $target" -ForegroundColor Cyan
Copy-Item -Path (Join-Path $source '*.txt') -Destination $target -Recurse -Force -ErrorAction Stop
Write-Host "Sync complete" -ForegroundColor Green
