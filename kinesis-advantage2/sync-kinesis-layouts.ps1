# Copy *.txt layouts to the Kinesis Advantage2 v-drive.
# Works even if the drive label is ADVANTAGE2, KINESIS KB, or blank.

function Get-Adv2Drive {
    # Look at every mounted removable volume
    $vols = Get-Volume -ErrorAction SilentlyContinue |
            Where-Object { $_.DriveType -eq 'Removable' }

    foreach ($v in $vols) {
        # 1️⃣ known labels
        if ($v.FileSystemLabel -match '^(ADVANTAGE2|KINESIS[\s-]?KB)$') { return $v }

        # 2️⃣ fallback: SmartSet folders
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
    Write-Warning "No Kinesis Advantage2 v-drive found. If you need to sync keyboard layouts press Prog+Shift+Esc to enter power user mode, then Prog+F1 to mount."
    return
}

$target = Join-Path ("$($adv.DriveLetter):\") 'active'
New-Item -ItemType Directory -Path $target -Force | Out-Null

$source = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) 'layouts'

Write-Host "Syncing Kinesis Advantage2 layouts -> $target" -ForegroundColor Cyan
Copy-Item -Path (Join-Path $source '*.txt') -Destination $target -Recurse -Force -ErrorAction Stop
Write-Host "Sync complete" -ForegroundColor Green
