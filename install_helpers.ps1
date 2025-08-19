$ErrorActionPreference = 'Stop'

if ($null -eq $Global:DotfilesDryRun) { $Global:DotfilesDryRun = $false }

function Ensure-ParentDirectory {
    param([Parameter(Mandatory)][string]$Path)
    $parent = Split-Path -Parent $Path
    if ($parent) {
        if ($Global:DotfilesDryRun) {
            Write-Host "DRY_RUN: New-Item -ItemType Directory -Force -Path $parent"
        } else {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
    }
}

function Backup-Conflict {
    param([Parameter(Mandatory)][string]$Target)
    if (Test-Path $Target) {
        $item = Get-Item $Target -Force
        if (-not $item.PSIsContainer -and -not $item.LinkType) {
            if ($Global:DotfilesDryRun) {
                Write-Host "DRY_RUN: Move-Item -Force -Path $Target -Destination $Target.bak"
            } else {
                Move-Item -Force -Path $Target -Destination "$Target.bak"
            }
        } elseif ($item.PSIsContainer -and -not $item.LinkType) {
            if ($Global:DotfilesDryRun) {
                Write-Host "DRY_RUN: Move-Item -Force -Path $Target -Destination $Target.bak"
            } else {
                Move-Item -Force -Path $Target -Destination "$Target.bak"
            }
        }
    }
}

function Ensure-SymlinkWithBackup {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )
    Ensure-ParentDirectory -Path $Destination
    if (Test-Path $Destination) {
        $item = Get-Item $Destination -Force
        if ($item.LinkType) {
            try {
                $dstResolved = (Resolve-Path $Destination).Path
                $srcResolved = (Resolve-Path $Source).Path
                if ($dstResolved -eq $srcResolved) { return }
            } catch { }
        }
        Backup-Conflict -Target $Destination
    }
    if ($Global:DotfilesDryRun) {
        Write-Host "DRY_RUN: New-Item -ItemType SymbolicLink -Path $Destination -Target $Source -Force"
    } else {
        try {
            New-Item -ItemType SymbolicLink -Path $Destination -Target $Source -Force | Out-Null
        } catch {
            try {
                New-Item -ItemType HardLink -Path $Destination -Target $Source -Force | Out-Null
            } catch {
                throw "Failed to link $Destination -> $Source. Enable Developer Mode or run as Administrator."
            }
        }
    }
}

function Restow-Package {
    param(
        [Parameter(Mandatory)][string]$Package,
        [string]$Target
    )
    if (-not $Target) { $Target = $env:USERPROFILE }
    if (-not (Test-Path $Package)) { return }
    $hasFiles = Get-ChildItem -Path $Package -Recurse -File | Select-Object -First 1
    if ($null -eq $hasFiles) { return }
    if ($Global:DotfilesDryRun) {
        Write-Host "DRY_RUN: stow --restow --target $Target $Package"
    } else {
        stow --restow --target $Target $Package
    }
}

function Invoke-SymlinkPairs {
    param([Parameter(Mandatory)][string[]]$Pairs)
    foreach ($pair in $Pairs) {
        $parts = $pair -split '::', 2
        $src = $parts[0]
        $dst = $parts[1]
        Ensure-SymlinkWithBackup -Source $src -Destination $dst
    }
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if ($Global:DotfilesDryRun) {
        Write-Host "DRY_RUN: New-Item -ItemType Directory -Path $Path -Force"
    } else {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Ensure-FileExists {
    param([Parameter(Mandatory)][string]$Path)
    $dir = Split-Path -Parent $Path
    if ($dir) { Ensure-Directory -Path $dir }
    if (-not (Test-Path $Path)) {
        if ($Global:DotfilesDryRun) {
            Write-Host "DRY_RUN: New-Item -ItemType File -Path $Path -Force"
        } else {
            New-Item -ItemType File -Path $Path -Force | Out-Null
        }
    }
}


