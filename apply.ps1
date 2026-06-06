# Native Windows dotfile linker.
#
# GNU Stow is not consistently available on Windows package managers, and Git
# often checks repository symlinks out as tiny text files when core.symlinks is
# disabled. This script keeps the same package model as apply.sh while creating
# Windows links directly.
$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$targetRoot = (Resolve-Path -LiteralPath $env:USERPROFILE).Path

$dryRun = $false
$adopt = $false
$restow = $false
$delete = $false
$verbose = $false
$plannedDirectories = @{}
$conflicts = [System.Collections.Generic.List[string]]::new()
$managedStateDir = Join-Path $env:LOCALAPPDATA 'skyde-dotfiles'
$managedLinksPath = Join-Path $managedStateDir 'managed-links.json'
$managedLinksDirty = $false

foreach ($arg in $args) {
    switch -Regex ($arg) {
        '^--no$|^--no-act$|^--simulate$|^-n$' { $dryRun = $true; continue }
        '^--adopt$' { $adopt = $true; continue }
        '^--restow$|-R$' { $restow = $true; continue }
        '^--delete$|-D$' { $delete = $true; continue }
        '^--verbose(=.*)?$|^-v$' { $verbose = $true; continue }
    }
}

function Convert-ToRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $baseFull = [System.IO.Path]::GetFullPath($BasePath)
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    $separator = [string][System.IO.Path]::DirectorySeparatorChar
    if (-not $baseFull.EndsWith($separator)) {
        $baseFull += $separator
    }

    $baseUri = New-Object System.Uri($baseFull)
    $pathUri = New-Object System.Uri($pathFull)
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('\', '/')
}

function Resolve-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $combined = [System.IO.Path]::Combine($BasePath, $RelativePath)
    return [System.IO.Path]::GetFullPath($combined)
}

function Normalize-ManagedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetFullPath($Path)
}

function Read-ManagedLinks {
    if (-not (Test-Path -LiteralPath $managedLinksPath -PathType Leaf)) {
        return @{}
    }

    try {
        $json = Get-Content -LiteralPath $managedLinksPath -Raw
        if (-not $json.Trim()) {
            return @{}
        }
        $decoded = ConvertFrom-Json -InputObject $json
        $links = @{}
        foreach ($property in $decoded.PSObject.Properties) {
            $links[$property.Name] = $property.Value
        }
        return $links
    } catch {
        Write-Host "  Warning: could not read managed link state at $managedLinksPath" -ForegroundColor Yellow
        return @{}
    }
}

$managedLinks = Read-ManagedLinks

function Write-ManagedLinks {
    if ($dryRun -or -not $managedLinksDirty) {
        return
    }

    if (-not (Test-Path -LiteralPath $managedStateDir -PathType Container)) {
        New-Item -ItemType Directory -Path $managedStateDir -Force | Out-Null
    }

    $managedLinks |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $managedLinksPath -Encoding UTF8
}

function Register-ManagedLink {
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$SourcePath
    )

    if ($dryRun) {
        return
    }

    $targetKey = Normalize-ManagedPath -Path $TargetPath
    $sourceFull = Normalize-ManagedPath -Path $SourcePath
    $managedLinks[$targetKey] = [ordered]@{
        source = $sourceFull
        updated = (Get-Date).ToString('o')
    }
    $script:managedLinksDirty = $true
}

function Unregister-ManagedLink {
    param([Parameter(Mandatory = $true)][string]$TargetPath)

    if ($dryRun) {
        return
    }

    $targetKey = Normalize-ManagedPath -Path $TargetPath
    if ($managedLinks.ContainsKey($targetKey)) {
        $managedLinks.Remove($targetKey)
        $script:managedLinksDirty = $true
    }
}

function Test-ManagedLinkRecord {
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$SourcePath
    )

    $targetKey = Normalize-ManagedPath -Path $TargetPath
    if (-not $managedLinks.ContainsKey($targetKey)) {
        return $false
    }

    $record = $managedLinks[$targetKey]
    $recordSource = if ($record -is [System.Collections.IDictionary]) {
        $record['source']
    } else {
        $record.source
    }

    if (-not $recordSource) {
        return $false
    }

    $sourceFull = Normalize-ManagedPath -Path $SourcePath
    try {
        return [string]::Equals(
            (Normalize-ManagedPath -Path ([string]$recordSource)),
            $sourceFull,
            [StringComparison]::OrdinalIgnoreCase
        )
    } catch {
        return $false
    }
}

function Test-LinkLike {
    param([Parameter(Mandatory = $true)]$Item)

    return $null -ne $Item.LinkType -or (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Test-HardLink {
    param([Parameter(Mandatory = $true)]$Item)

    return [string]$Item.LinkType -eq 'HardLink'
}

function Get-RepoSymlinkMap {
    $map = @{}

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return $map
    }

    try {
        $gitRows = & git -C $repoRoot ls-files -s 2>$null
        foreach ($row in $gitRows) {
            if ($row -match '^120000\s+\S+\s+\d+\s+(.+)$') {
                $path = $Matches[1].Replace('\', '/')
                $map[$path] = $true
            }
        }
    } catch {
        # If git is unavailable or this is not a checkout, fall back to treating
        # files as regular files.
    }

    return $map
}

function Get-LinkSource {
    param(
        [Parameter(Mandatory = $true)][string]$Package,
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][hashtable]$RepoSymlinks
    )

    $repoRelative = Convert-ToRelativePath -BasePath $repoRoot -Path $SourcePath
    if (-not $RepoSymlinks.ContainsKey($repoRelative)) {
        return $SourcePath
    }

    $linkText = (Get-Content -LiteralPath $SourcePath -Raw).Trim()
    if (-not $linkText) {
        throw "Repository symlink placeholder is empty: $repoRelative"
    }

    $resolved = Resolve-RelativePath -BasePath (Split-Path -Parent $SourcePath) -RelativePath $linkText
    if (-not (Test-Path -LiteralPath $resolved)) {
        throw "Repository symlink placeholder points to a missing path: $repoRelative -> $linkText"
    }

    if ($verbose) {
        Write-Host "  Resolving repo symlink $repoRelative -> $linkText" -ForegroundColor DarkGray
    }

    return $resolved
}

function Test-SameFileContent {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )

    if (-not ((Test-Path -LiteralPath $Left -PathType Leaf) -and (Test-Path -LiteralPath $Right -PathType Leaf))) {
        return $false
    }

    $leftHash = Get-FileHash -LiteralPath $Left -Algorithm SHA256
    $rightHash = Get-FileHash -LiteralPath $Right -Algorithm SHA256
    return $leftHash.Hash -eq $rightHash.Hash
}

function Test-LinkTargetMatches {
    param(
        [Parameter(Mandatory = $true)]$Item,
        [Parameter(Mandatory = $true)][string]$ExpectedTarget
    )

    if (-not (Test-LinkLike -Item $Item)) {
        return $false
    }

    $actualTargets = @($Item.Target) | Where-Object { $_ }
    foreach ($actual in $actualTargets) {
        try {
            $actualFull = [System.IO.Path]::GetFullPath($actual)
            $expectedFull = [System.IO.Path]::GetFullPath($ExpectedTarget)
            if ([string]::Equals($actualFull, $expectedFull, [StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        } catch {
            if ([string]::Equals($actual, $ExpectedTarget, [StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
    }

    return $false
}

function New-ManagedLink {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    if ($dryRun) {
        Write-Host "  [DRY RUN] Link $TargetPath -> $SourcePath"
        return
    }

    try {
        New-Item -ItemType SymbolicLink -Path $TargetPath -Target $SourcePath -Force | Out-Null
    } catch {
        # File hard links are a practical fallback on developer-mode-disabled
        # Windows installs. The repo and profile normally live on C:.
        New-Item -ItemType HardLink -Path $TargetPath -Target $SourcePath -Force | Out-Null
    }
}

function Ensure-TargetDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if ($plannedDirectories.ContainsKey($fullPath)) {
        return
    }

    if (-not (Test-Path -LiteralPath $fullPath)) {
        if ($dryRun) {
            Write-Host "  [DRY RUN] Create directory $fullPath"
        } else {
            New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
        }
    }

    $plannedDirectories[$fullPath] = $true
}

function Add-Conflict {
    param([Parameter(Mandatory = $true)][string]$Message)

    if ($dryRun) {
        $conflicts.Add($Message)
        Write-Host "  [CONFLICT] $Message" -ForegroundColor Yellow
        return
    }

    throw $Message
}

function Invoke-DotfilesPackage {
    param([Parameter(Mandatory = $true)][string]$Package)

    $packageRoot = Join-Path $repoRoot $Package
    if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) {
        return
    }

    Write-Host "[package] Applying $Package package"
    $repoSymlinks = Get-RepoSymlinkMap

    $directories = Get-ChildItem -LiteralPath $packageRoot -Force -Recurse -Directory |
        Sort-Object FullName
    foreach ($dir in $directories) {
        $relative = Convert-ToRelativePath -BasePath $packageRoot -Path $dir.FullName
        $targetDir = Resolve-RelativePath -BasePath $targetRoot -RelativePath $relative

        if ($delete) {
            continue
        }

        Ensure-TargetDirectory -Path $targetDir
    }

    $files = Get-ChildItem -LiteralPath $packageRoot -Force -Recurse -File |
        Sort-Object FullName
    foreach ($file in $files) {
        $relative = Convert-ToRelativePath -BasePath $packageRoot -Path $file.FullName
        $targetPath = Resolve-RelativePath -BasePath $targetRoot -RelativePath $relative
        $sourcePath = Get-LinkSource -Package $Package -SourcePath $file.FullName -RepoSymlinks $repoSymlinks
        $targetParent = Split-Path -Parent $targetPath

        Ensure-TargetDirectory -Path $targetParent

        $existing = Get-Item -LiteralPath $targetPath -Force -ErrorAction SilentlyContinue

        if ($delete) {
            if ($existing -and (Test-LinkLike -Item $existing) -and (Test-LinkTargetMatches -Item $existing -ExpectedTarget $sourcePath)) {
                if ($dryRun) {
                    Write-Host "  [DRY RUN] Remove link $targetPath"
                } else {
                    Remove-Item -LiteralPath $targetPath -Force
                    Unregister-ManagedLink -TargetPath $targetPath
                }
            } elseif ($existing -and (Test-HardLink -Item $existing) -and (Test-SameFileContent -Left $sourcePath -Right $targetPath)) {
                if ($dryRun) {
                    Write-Host "  [DRY RUN] Remove hardlink $targetPath"
                } else {
                    Remove-Item -LiteralPath $targetPath -Force
                    Unregister-ManagedLink -TargetPath $targetPath
                }
            } elseif ($verbose -and $existing) {
                Write-Host "  Skipping unmanaged target $targetPath" -ForegroundColor DarkGray
            }
            continue
        }

        if (-not $existing) {
            New-ManagedLink -SourcePath $sourcePath -TargetPath $targetPath
            Register-ManagedLink -TargetPath $targetPath -SourcePath $sourcePath
            continue
        }

        if ((Test-LinkLike -Item $existing) -and (Test-LinkTargetMatches -Item $existing -ExpectedTarget $sourcePath)) {
            if ($verbose) {
                Write-Host "  Already linked $targetPath" -ForegroundColor DarkGray
            }
            Register-ManagedLink -TargetPath $targetPath -SourcePath $sourcePath
            continue
        }

        if ((Test-HardLink -Item $existing) -and (Test-SameFileContent -Left $sourcePath -Right $targetPath)) {
            if ($verbose) {
                Write-Host "  Already hard-linked $targetPath" -ForegroundColor DarkGray
            }
            Register-ManagedLink -TargetPath $targetPath -SourcePath $sourcePath
            continue
        }

        if (Test-LinkLike -Item $existing) {
            if ($restow) {
                if ($dryRun) {
                    Write-Host "  [DRY RUN] Replace link $targetPath -> $sourcePath"
                } else {
                    Remove-Item -LiteralPath $targetPath -Force
                    New-ManagedLink -SourcePath $sourcePath -TargetPath $targetPath
                    Register-ManagedLink -TargetPath $targetPath -SourcePath $sourcePath
                }
                continue
            }

            Add-Conflict -Message "Target is already a link managed elsewhere: $targetPath"
            continue
        }

        if ((Test-Path -LiteralPath $targetPath -PathType Leaf) -and (Test-SameFileContent -Left $sourcePath -Right $targetPath)) {
            if ($dryRun) {
                Write-Host "  [DRY RUN] Replace identical file with link $targetPath -> $sourcePath"
            } else {
                Remove-Item -LiteralPath $targetPath -Force
                New-ManagedLink -SourcePath $sourcePath -TargetPath $targetPath
                Register-ManagedLink -TargetPath $targetPath -SourcePath $sourcePath
            }
            continue
        }

        if ((Test-Path -LiteralPath $targetPath -PathType Leaf) -and (Test-ManagedLinkRecord -TargetPath $targetPath -SourcePath $sourcePath)) {
            if ($restow) {
                if ($dryRun) {
                    Write-Host "  [DRY RUN] Replace managed rewrite $targetPath -> $sourcePath"
                } else {
                    Remove-Item -LiteralPath $targetPath -Force
                    New-ManagedLink -SourcePath $sourcePath -TargetPath $targetPath
                    Register-ManagedLink -TargetPath $targetPath -SourcePath $sourcePath
                }
            } elseif ($dryRun) {
                Write-Host "  [DRY RUN] Adopt managed rewrite $targetPath into $sourcePath, then relink"
            } else {
                Copy-Item -LiteralPath $targetPath -Destination $sourcePath -Force
                Remove-Item -LiteralPath $targetPath -Force
                New-ManagedLink -SourcePath $sourcePath -TargetPath $targetPath
                Register-ManagedLink -TargetPath $targetPath -SourcePath $sourcePath
            }
            continue
        }

        if ($adopt -and (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
            if ($dryRun) {
                Write-Host "  [DRY RUN] Adopt $targetPath into $sourcePath"
            } else {
                Copy-Item -LiteralPath $targetPath -Destination $sourcePath -Force
                Remove-Item -LiteralPath $targetPath -Force
                New-ManagedLink -SourcePath $sourcePath -TargetPath $targetPath
                Register-ManagedLink -TargetPath $targetPath -SourcePath $sourcePath
            }
            continue
        }

        Add-Conflict -Message "Target exists and would be overwritten. Re-run with --adopt to take it into the repo, or move it aside first: $targetPath"
    }
}

try {
    Set-Location $repoRoot

    Invoke-DotfilesPackage -Package 'common'
    Invoke-DotfilesPackage -Package 'windows'

    if ($dryRun -and $conflicts.Count -gt 0) {
        Write-Host "[error] Dry run found $($conflicts.Count) conflict(s)" -ForegroundColor Red
        exit 1
    } elseif ($dryRun) {
        Write-Host "[ok] Dry run completed - no changes were made" -ForegroundColor Green
    } elseif ($delete) {
        Write-Host "[ok] Dotfile links removed" -ForegroundColor Green
    } else {
        Write-Host "[ok] Dotfile links applied" -ForegroundColor Green
    }

    Write-ManagedLinks
} catch {
    Write-Host "[error] Apply failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
