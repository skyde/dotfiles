# Windows-specific setup script
# Requires PowerShell 7+
$ErrorActionPreference = 'Stop'
$dryRun = $false
$noPersist = $false

foreach ($arg in $args) {
    switch -Regex ($arg) {
        '^--no$|^--no-act$|^--simulate$|^-n$' { $dryRun = $true; continue }
        '^--no-persist$' { $noPersist = $true; continue }
    }
}

Write-Host "[windows] Running Windows-specific setup..."

Write-Host "Configuring Windows-specific settings..."
if ($dryRun) {
    Write-Host "Preview mode enabled; no changes will be made."
}
if ($noPersist) {
    Write-Host "No-persist mode enabled; user environment and registry settings will not be changed."
}

function Add-PathEntryToFront {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$PersistUser
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return
    }

    if ($dryRun) {
        Write-Host "[DRY RUN] Ensure $Path is first in session PATH"
        if ($PersistUser -and -not $noPersist) {
            Write-Host "[DRY RUN] Ensure $Path is first in user PATH"
        }
        return
    }

    $entries = @($env:PATH -split ';' | Where-Object {
        $_ -and -not $_.Equals($Path, [StringComparison]::OrdinalIgnoreCase)
    })
    $env:PATH = (@($Path) + $entries) -join ';'

    if ($PersistUser -and -not $noPersist) {
        $userEntries = @([System.Environment]::GetEnvironmentVariable('PATH', 'User') -split ';' | Where-Object {
            $_ -and -not $_.Equals($Path, [StringComparison]::OrdinalIgnoreCase)
        })
        [System.Environment]::SetEnvironmentVariable('PATH', ((@($Path) + $userEntries) -join ';'), 'User')
    }
}

function Enable-GitLongPaths {
    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $git) {
        Write-Warning "Git not found; cannot enable Git long path support."
        return
    }

    if ($dryRun) {
        Write-Host "[DRY RUN] Enable Git long path support with core.longpaths=true"
        return
    }

    if ($noPersist) {
        Write-Host "Would enable Git long path support (skipped in no-persist mode)."
        return
    }

    try {
        & $git.Source config --global core.longpaths true
        if ($LASTEXITCODE -ne 0) {
            throw "git config exited with $LASTEXITCODE"
        }
        Write-Host "Enabled Git long path support for plugin checkouts."
    } catch {
        Write-Warning "Failed to enable Git long path support: $($_.Exception.Message)"
    }
}

# Ensure dotfile helper scripts are discoverable in new Windows terminals.
$localBin = Join-Path $env:USERPROFILE ".local\bin"
Add-PathEntryToFront -Path $localBin -PersistUser
Write-Host "Ensured $localBin is first in user/session PATH."

if (-not $dryRun) {
    foreach ($entry in ([System.Environment]::GetEnvironmentVariable('PATH', 'User') -split ';')) {
        if ($entry -and -not (($env:PATH -split ';') -contains $entry)) {
            $env:PATH += ";$entry"
        }
    }
}

$gitRoot = Join-Path $env:ProgramFiles "Git"
if (Test-Path -LiteralPath $gitRoot -PathType Container) {
    foreach ($path in @(
        (Join-Path $gitRoot "cmd"),
        (Join-Path $gitRoot "bin"),
        (Join-Path $gitRoot "usr\bin")
    )) {
        Add-PathEntryToFront -Path $path -PersistUser
    }
    Write-Host "Ensured Git for Windows tools are available for shells and plugin checkouts."
} else {
    Write-Warning "Git for Windows not found under $gitRoot. Install Git for Windows first."
}
Enable-GitLongPaths

function Test-LinkTargetMatches {
    param(
        [Parameter(Mandatory = $true)]$Item,
        [Parameter(Mandatory = $true)][string]$ExpectedTarget
    )

    $targets = @($Item.Target) | Where-Object { $_ }
    foreach ($target in $targets) {
        try {
            $actual = [System.IO.Path]::GetFullPath($target)
            $expected = [System.IO.Path]::GetFullPath($ExpectedTarget)
            if ([string]::Equals($actual, $expected, [StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        } catch {
            if ([string]::Equals($target, $ExpectedTarget, [StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
    }

    return $false
}

function Ensure-DirectoryLink {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Target
    )

    if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
        if ($dryRun) {
            Write-Host "[DRY RUN] Create target config directory: $Target"
        } else {
            New-Item -ItemType Directory -Path $Target -Force | Out-Null
        }
    }

    $existing = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($existing) {
        $isLink = $null -ne $existing.LinkType -or (($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
        if ($isLink -and (Test-LinkTargetMatches -Item $existing -ExpectedTarget $Target)) {
            Write-Host "Config link already exists: $Path -> $Target"
            return
        }

        Write-Warning "Skipping config link because path already exists: $Path"
        return
    }

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        if ($dryRun) {
            Write-Host "[DRY RUN] Create parent config directory: $parent"
        } else {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
    }

    if ($dryRun) {
        Write-Host "[DRY RUN] Link config: $Path -> $Target"
        return
    }

    try {
        New-Item -ItemType SymbolicLink -Path $Path -Target $Target -Force | Out-Null
    } catch {
        New-Item -ItemType Junction -Path $Path -Target $Target -Force | Out-Null
    }
    Write-Host "Linked config: $Path -> $Target"
}

# Native Windows builds of these tools look in AppData by default. Keep those
# locations pointing at the same ~/.config trees used on Linux and macOS.
Ensure-DirectoryLink -Path (Join-Path $env:LOCALAPPDATA 'nvim') -Target (Join-Path $env:USERPROFILE '.config\nvim')
Ensure-DirectoryLink -Path (Join-Path $env:APPDATA 'lf') -Target (Join-Path $env:USERPROFILE '.config\lf')
Ensure-DirectoryLink -Path (Join-Path $env:APPDATA 'bat') -Target (Join-Path $env:USERPROFILE '.config\bat')
Ensure-DirectoryLink -Path (Join-Path $env:APPDATA 'lazygit') -Target (Join-Path $env:USERPROFILE '.config\lazygit')
Ensure-DirectoryLink -Path (Join-Path (Join-Path $env:APPDATA 'yazi') 'config') -Target (Join-Path $env:USERPROFILE '.config\yazi')

# Ensure Yazi uses Git's file.exe for MIME detection
$gitFile = "$env:ProgramFiles\Git\usr\bin\file.exe"
if (Test-Path $gitFile) {
    $current = [System.Environment]::GetEnvironmentVariable('YAZI_FILE_ONE', 'User')
    if ($current -ne $gitFile) {
        if ($dryRun) {
            Write-Host "[DRY RUN] Set user YAZI_FILE_ONE to $gitFile"
        } elseif ($noPersist) {
            Write-Host "Would set user YAZI_FILE_ONE to $gitFile (skipped in no-persist mode)"
        } else {
            [System.Environment]::SetEnvironmentVariable('YAZI_FILE_ONE', $gitFile, 'User')
            Write-Host "Set YAZI_FILE_ONE to $gitFile"
        }
    } else {
        Write-Host "YAZI_FILE_ONE is already set to $gitFile"
    }
    if (-not $dryRun) {
        $env:YAZI_FILE_ONE = $gitFile
    }
} else {
    Write-Warning "file.exe not found at $gitFile. Install Git for Windows first."
}

# Ensure LLVM (clang) is in PATH for C compiler support
$llvmBin = "$env:ProgramFiles\LLVM\bin"
if (Test-Path "$llvmBin\clang.exe") {
    $userPath = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    if (-not ($userPath -split ';' | Where-Object { $_ -eq $llvmBin })) {
        if ($dryRun) {
            Write-Host "[DRY RUN] Add LLVM to user PATH: $llvmBin"
        } elseif ($noPersist) {
            Write-Host "Would add LLVM to user PATH: $llvmBin (skipped in no-persist mode)"
        } else {
            [System.Environment]::SetEnvironmentVariable('PATH', "$userPath;$llvmBin", 'User')
            Write-Host "Added LLVM to user PATH. You may need to restart your terminal or log out/in for this to take effect."
        }
    } else {
        Write-Host "LLVM is already in your user PATH."
    }
    if (-not $dryRun -and -not ($env:PATH -split ';' | Where-Object { $_ -eq $llvmBin })) {
        $env:PATH += ";$llvmBin"
        Write-Host "Temporarily added LLVM to PATH for this session."
    }
    $clangVersion = & "$llvmBin\clang.exe" --version
    Write-Host "clang is available: $clangVersion"
} else {
    Write-Warning "LLVM is installed but clang.exe was not found in $llvmBin. You may need to reinstall or check your LLVM installation."
}

# Check for JetBrainsMono Nerd Font installation
$fontName = "JetBrainsMono Nerd Font"
$fontPaths = @(
    "$env:WINDIR\Fonts",
    (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts")
) | Where-Object { Test-Path -LiteralPath $_ }
$fontInstalled = (Get-ChildItem -Path $fontPaths -Include "*JetBrainsMono*Nerd*.ttf", "*JetBrainsMono*NF*.ttf" -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
if (-not $fontInstalled) {
    Write-Warning "JetBrainsMono-NF font is not installed. Please install it manually from https://github.com/ryanoasis/nerd-fonts/releases."
} else {
    Write-Host "JetBrainsMono-NF font is already installed."
}

# Configure key repeat behavior for Vim and general usage
if ($dryRun) {
    Write-Host "[DRY RUN] Set Windows key repeat registry values."
} elseif ($noPersist) {
    Write-Host "Would set Windows key repeat registry values (skipped in no-persist mode)."
} else {
    Write-Host "Setting Windows key repeat registry values..."
    try {
        $keyboardRegPath = "HKCU:\Control Panel\Keyboard"
        # Shorter delay before key repeat starts (0 = shortest)
        Set-ItemProperty -Path $keyboardRegPath -Name "KeyboardDelay" -Value "0"
        # Faster repeat rate (31 = fastest)
        Set-ItemProperty -Path $keyboardRegPath -Name "KeyboardSpeed" -Value "31"
        Write-Host "Key repeat settings applied. You may need to sign out and back in for changes to take effect."
    } catch {
        Write-Warning "Failed to update key repeat settings: $_"
    }
}

Write-Host "[ok] Windows-specific setup complete!"
