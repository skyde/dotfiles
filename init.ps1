# Simple dotfiles installer for Windows
$ErrorActionPreference = 'Stop'
$noPersist = $args -contains '--no-persist'
if ($noPersist) {
    Write-Host "No-persist mode enabled; user environment settings will not be changed." -ForegroundColor Yellow
}

function Get-InstallChoice {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt
    )

    if ($env:AUTO_INSTALL -eq '1') { return $true }
    if ($env:AUTO_INSTALL -eq '0') { return $false }

    $answer = Read-Host "$Prompt (y/N)"
    return $answer -match '^[Yy]'
}

function Test-ApplyOnlyMode {
    param([string[]]$Arguments)

    foreach ($arg in $Arguments) {
        switch -Regex ($arg) {
            '^--no$|^--no-act$|^--simulate$|^-n$' { return $true }
            '^--delete$|-D$' { return $true }
        }
    }

    return $false
}

function Get-ExternalCommand {
    param([Parameter(Mandatory = $true)][string]$Name)
    return Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Test-CommandExists {
    param([Parameter(Mandatory = $true)][string]$Name)
    return $null -ne (Get-ExternalCommand $Name)
}

function Enable-GitLongPaths {
    $git = Get-ExternalCommand git
    if (-not $git) {
        Write-Host "  Git not found; cannot enable long path support" -ForegroundColor Yellow
        return
    }

    if ($script:noPersist) {
        Write-Host "  Would enable Git long path support (skipped in no-persist mode)" -ForegroundColor Yellow
        return
    }

    try {
        & $git.Source config --global core.longpaths true
        if ($LASTEXITCODE -ne 0) {
            throw "git config exited with $LASTEXITCODE"
        }
        Write-Host "  Enabled Git long path support" -ForegroundColor Green
    } catch {
        Write-Host "  Warning: failed to enable Git long path support: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Add-PathEntryToFront {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$PersistUser
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return
    }

    $entries = @($env:PATH -split ';' | Where-Object {
        $_ -and -not $_.Equals($Path, [StringComparison]::OrdinalIgnoreCase)
    })
    $env:PATH = (@($Path) + $entries) -join ';'

    if ($PersistUser -and -not $script:noPersist) {
        $userEntries = @([System.Environment]::GetEnvironmentVariable('PATH', 'User') -split ';' | Where-Object {
            $_ -and -not $_.Equals($Path, [StringComparison]::OrdinalIgnoreCase)
        })
        [System.Environment]::SetEnvironmentVariable('PATH', ((@($Path) + $userEntries) -join ';'), 'User')
    }
}

function Add-DotfilesLocalBinToSessionPath {
    Add-PathEntryToFront -Path (Join-Path $env:USERPROFILE ".local\bin") -PersistUser
}

function Get-VSCodeCommand {
    $candidates = @(
        $env:VSCODE_CLI,
        (Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code\bin\code.cmd"),
        (Join-Path $env:ProgramFiles "Microsoft VS Code\bin\code.cmd"),
        (Join-Path $env:USERPROFILE ".local\bin\code.cmd")
    ) | Where-Object { $_ }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    $command = Get-ExternalCommand code
    if ($command -and $command.Source -notmatch '\\cursor\\') {
        return $command.Source
    }

    return $null
}

function Test-ScoopAppInstalled {
    param([Parameter(Mandatory = $true)][string]$App)

    if (-not (Test-CommandExists scoop)) {
        return $false
    }

    try {
        $rows = (& scoop list 2>$null | Out-String)
        return $rows -match "(?m)^\s*$([regex]::Escape($App))\s+\S+\s+\S+" -and
            $rows -notmatch "(?m)^\s*$([regex]::Escape($App))\s+.*Install failed"
    } catch {
        return $false
    }
}

function Test-UsableInstalledCommand {
    param(
        [Parameter(Mandatory = $true)][string]$App,
        [Parameter(Mandatory = $true)][string]$CommandName
    )

    if (Test-ScoopAppInstalled -App $App) {
        return $true
    }

    $command = Get-ExternalCommand $CommandName
    if (-not $command) {
        return $false
    }

    $source = $command.Source
    $dotfilesLocalBin = Join-Path $env:USERPROFILE ".local\bin"
    $codexToolPath = Join-Path $env:LOCALAPPDATA "OpenAI\Codex"

    if ($source -and $source.StartsWith($dotfilesLocalBin, [StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    if ($source -and $source.StartsWith($codexToolPath, [StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    return $true
}

function Test-WingetPackageInstalled {
    param([Parameter(Mandatory = $true)][string]$Id)

    if (-not (Test-CommandExists winget)) {
        return $false
    }

    try {
        $result = & winget list --id $Id --source winget --accept-source-agreements 2>$null | Out-String
        return $LASTEXITCODE -eq 0 -and $result -match [regex]::Escape($Id)
    } catch {
        return $false
    }
}

function Ensure-ScoopBucket {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Test-CommandExists scoop)) {
        return
    }

    $buckets = (& scoop bucket list 2>$null | Out-String)
    if ($buckets -notmatch "(?m)^\s*$([regex]::Escape($Name))\s") {
        Write-Host "Adding Scoop bucket: $Name" -ForegroundColor Cyan
        & scoop bucket add $Name | Out-Null
    }
}

function Install-ScoopApp {
    param(
        [Parameter(Mandatory = $true)][string]$App,
        [string]$CommandName = $App
    )

    if (Test-UsableInstalledCommand -App $App -CommandName $CommandName) {
        Write-Host "  $CommandName already available" -ForegroundColor DarkGray
        return
    }

    if (-not (Test-CommandExists scoop)) {
        Write-Host "  Scoop not found; cannot install $App" -ForegroundColor Yellow
        return
    }

    Write-Host "  Installing $App via Scoop" -ForegroundColor Cyan
    try {
        & scoop install $App
        if ($LASTEXITCODE -ne 0) {
            throw "scoop install exited with $LASTEXITCODE"
        }
    } catch {
        Write-Host "  Warning: failed to install $App via Scoop: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Install-WingetApp {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$CommandName
    )

    if ((Test-CommandExists $CommandName) -or (Test-WingetPackageInstalled -Id $Id)) {
        Write-Host "  $CommandName already available" -ForegroundColor DarkGray
        return
    }

    if (-not (Test-CommandExists winget)) {
        Write-Host "  Winget not found; cannot install $Id" -ForegroundColor Yellow
        return
    }

    Write-Host "  Installing $Id via Winget" -ForegroundColor Cyan
    try {
        & winget install --id $Id --source winget --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "winget install exited with $LASTEXITCODE"
        }
    } catch {
        Write-Host "  Warning: failed to install $Id via Winget: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Install-GitForWindows {
    $gitRoot = Join-Path $env:ProgramFiles "Git"
    $gitBash = Join-Path $gitRoot "bin\bash.exe"

    if (Test-Path -LiteralPath $gitBash -PathType Leaf) {
        Write-Host "  Git for Windows already available" -ForegroundColor DarkGray
    } elseif (Test-CommandExists winget) {
        Write-Host "  Installing Git for Windows via Winget" -ForegroundColor Cyan
        try {
            & winget install --id Git.Git --source winget --silent --accept-package-agreements --accept-source-agreements
            if ($LASTEXITCODE -ne 0) {
                throw "winget install exited with $LASTEXITCODE"
            }
        } catch {
            Write-Host "  Warning: failed to install Git for Windows via Winget: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } elseif (Test-CommandExists scoop) {
        Install-ScoopApp -App 'git' -CommandName 'git'
    } else {
        Write-Host "  Git not found and neither Winget nor Scoop is available" -ForegroundColor Yellow
    }

    foreach ($path in @(
        (Join-Path $gitRoot "cmd"),
        (Join-Path $gitRoot "bin"),
        (Join-Path $gitRoot "usr\bin")
    )) {
        Add-PathEntryToFront -Path $path -PersistUser
    }

    Enable-GitLongPaths
}

function Test-JetBrainsMonoNerdFontInstalled {
    $fontPaths = @(
        "$env:WINDIR\Fonts",
        (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts")
    ) | Where-Object { Test-Path -LiteralPath $_ }

    if (-not $fontPaths) {
        return $false
    }

    return $null -ne (Get-ChildItem -Path $fontPaths -Include "*JetBrainsMono*Nerd*.ttf", "*JetBrainsMono*NF*.ttf" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Add-UserPathEntry {
    param([Parameter(Mandatory = $true)][string]$Path)

    Add-PathEntryToFront -Path $Path -PersistUser
}

function Install-Portable7ZipCli {
    if (Test-CommandExists 7z) {
        Write-Host "  7z already available" -ForegroundColor DarkGray
        return
    }

    $localBin = Join-Path $env:USERPROFILE ".local\bin"
    $target = Join-Path $localBin "7z.exe"

    Write-Host "  Installing portable 7z CLI" -ForegroundColor Cyan
    try {
        New-Item -ItemType Directory -Path $localBin -Force | Out-Null
        Invoke-WebRequest -Uri "https://www.7-zip.org/a/7zr.exe" -OutFile $target -UseBasicParsing
        Add-UserPathEntry -Path $localBin
    } catch {
        Write-Host "  Warning: failed to install portable 7z CLI: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Install-PortableNodeLts {
    $existing = Get-ExternalCommand node
    $codexToolPath = Join-Path $env:LOCALAPPDATA "OpenAI\Codex"
    if ($existing -and $existing.Source -and -not $existing.Source.StartsWith($codexToolPath, [StringComparison]::OrdinalIgnoreCase) -and $existing.Source -notmatch '\\WindowsApps\\OpenAI\.Codex_') {
        Write-Host "  node already available" -ForegroundColor DarkGray
        return
    }

    $installRoot = Join-Path $env:USERPROFILE ".local\opt\nodejs"
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-node-$([guid]::NewGuid())"

    Write-Host "  Installing portable Node.js LTS" -ForegroundColor Cyan
    try {
        $index = Invoke-RestMethod -Uri "https://nodejs.org/dist/index.json"
        $release = $index | Where-Object { $_.lts } | Select-Object -First 1
        if (-not $release) {
            throw "No LTS release found in Node.js index"
        }

        $version = $release.version
        $archive = "node-$version-win-x64.zip"
        $url = "https://nodejs.org/dist/$version/$archive"
        $zipPath = Join-Path $tempRoot $archive
        $extractPath = Join-Path $tempRoot "extract"

        New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
        Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

        $expanded = Get-ChildItem -LiteralPath $extractPath -Directory | Select-Object -First 1
        if (-not $expanded) {
            throw "Node.js archive did not contain an install directory"
        }

        Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path (Split-Path -Parent $installRoot) -Force | Out-Null
        Move-Item -LiteralPath $expanded.FullName -Destination $installRoot
        Add-UserPathEntry -Path $installRoot
        Write-Host "  Installed Node.js $version" -ForegroundColor Green
    } catch {
        Write-Host "  Warning: failed to install portable Node.js LTS: $($_.Exception.Message)" -ForegroundColor Yellow
    } finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-PortableGo {
    if (Test-CommandExists go) {
        Write-Host "  go already available" -ForegroundColor DarkGray
        return
    }

    $installRoot = Join-Path $env:USERPROFILE ".local\opt\go"
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-go-$([guid]::NewGuid())"

    Write-Host "  Installing portable Go" -ForegroundColor Cyan
    try {
        $releases = Invoke-RestMethod -Uri "https://go.dev/dl/?mode=json"
        $release = $releases | Where-Object { $_.stable } | Select-Object -First 1
        if (-not $release) {
            throw "No stable Go release found"
        }

        $file = $release.files | Where-Object {
            $_.os -eq "windows" -and $_.arch -eq "amd64" -and $_.kind -eq "archive"
        } | Select-Object -First 1
        if (-not $file) {
            throw "No Windows amd64 Go archive found for $($release.version)"
        }

        $zipPath = Join-Path $tempRoot $file.filename
        $extractPath = Join-Path $tempRoot "extract"
        New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
        Invoke-WebRequest -Uri "https://go.dev/dl/$($file.filename)" -OutFile $zipPath -UseBasicParsing
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

        Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path (Split-Path -Parent $installRoot) -Force | Out-Null
        Move-Item -LiteralPath (Join-Path $extractPath "go") -Destination $installRoot
        Add-UserPathEntry -Path (Join-Path $installRoot "bin")
        Write-Host "  Installed Go $($release.version)" -ForegroundColor Green
    } catch {
        Write-Host "  Warning: failed to install portable Go: $($_.Exception.Message)" -ForegroundColor Yellow
    } finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-ZoektTools {
    if ((Test-CommandExists zoekt) -and (Test-CommandExists zoekt-index)) {
        Write-Host "  zoekt already available" -ForegroundColor DarkGray
        return
    }

    Install-PortableGo
    if (-not (Test-CommandExists go)) {
        Write-Host "  Go not found; cannot install Zoekt" -ForegroundColor Yellow
        return
    }

    $localBin = Join-Path $env:USERPROFILE ".local\bin"
    Write-Host "  Installing Zoekt tools via Go" -ForegroundColor Cyan
    try {
        New-Item -ItemType Directory -Path $localBin -Force | Out-Null
        $env:GOBIN = $localBin
        # Current upstream HEAD reverted Windows support, so pin the last tested Windows build.
        $zoektVersion = "v0.0.0-20250202210456-261aae37dce6"
        & go install "github.com/sourcegraph/zoekt/cmd/zoekt@$zoektVersion"
        if ($LASTEXITCODE -ne 0) { throw "go install zoekt exited with $LASTEXITCODE" }
        & go install "github.com/sourcegraph/zoekt/cmd/zoekt-index@$zoektVersion"
        if ($LASTEXITCODE -ne 0) { throw "go install zoekt-index exited with $LASTEXITCODE" }
        Add-UserPathEntry -Path $localBin
    } catch {
        Write-Host "  Warning: failed to install Zoekt tools: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Install-JetBrainsMonoNerdFont {
    if (Test-JetBrainsMonoNerdFontInstalled) {
        Write-Host "  JetBrainsMono Nerd Font already installed" -ForegroundColor DarkGray
        return
    }

    $fontUrl = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "dotfiles-jetbrainsmono-nf-$([guid]::NewGuid())"
    $zipPath = Join-Path $tempRoot "JetBrainsMono.zip"
    $extractPath = Join-Path $tempRoot "extract"
    $fontDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
    $fontRegPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"

    Write-Host "  Installing JetBrainsMono Nerd Font for current user" -ForegroundColor Cyan
    try {
        New-Item -ItemType Directory -Path $extractPath, $fontDir -Force | Out-Null
        Invoke-WebRequest -Uri $fontUrl -OutFile $zipPath -UseBasicParsing
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

        $fontFiles = Get-ChildItem -LiteralPath $extractPath -Filter "*.ttf" -Recurse |
            Where-Object { $_.Name -like "JetBrainsMono*" }

        foreach ($font in $fontFiles) {
            $destination = Join-Path $fontDir $font.Name
            Copy-Item -LiteralPath $font.FullName -Destination $destination -Force
            New-ItemProperty -Path $fontRegPath -Name "$($font.BaseName) (TrueType)" -Value $destination -PropertyType String -Force | Out-Null
        }

        Write-Host "  Installed $($fontFiles.Count) JetBrainsMono Nerd Font file(s)" -ForegroundColor Green
    } catch {
        Write-Host "  Warning: failed to install JetBrainsMono Nerd Font: $($_.Exception.Message)" -ForegroundColor Yellow
    } finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Enable-VSCodeRequiredExtensions {
    param([string[]]$Extensions)

    if (-not $Extensions -or $Extensions.Count -eq 0) {
        return
    }

    $stateDb = Join-Path $env:APPDATA "Code\User\globalStorage\state.vscdb"
    if (-not (Test-Path -LiteralPath $stateDb)) {
        return
    }

    $sqlite = Get-Command sqlite3 -ErrorAction SilentlyContinue
    if (-not $sqlite) {
        Write-Host "  Note: sqlite3 not found; manually re-enable any disabled required VS Code extensions." -ForegroundColor Yellow
        return
    }

    $disabledJson = & $sqlite.Source $stateDb "SELECT value FROM ItemTable WHERE key = 'extensionsIdentifiers/disabled';"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($disabledJson)) {
        return
    }

    try {
        $disabledItems = @(ConvertFrom-Json -InputObject $disabledJson)
    } catch {
        Write-Host "  Warning: could not parse VS Code disabled-extension state" -ForegroundColor Yellow
        return
    }

    $required = @{}
    foreach ($extension in $Extensions) {
        $required[$extension.ToLowerInvariant()] = $true
    }

    $disabledRequired = @($disabledItems | Where-Object {
        $_.id -and $required.ContainsKey($_.id.ToString().ToLowerInvariant())
    })
    if ($disabledRequired.Count -eq 0) {
        return
    }

    $remaining = @($disabledItems | Where-Object {
        -not ($_.id -and $required.ContainsKey($_.id.ToString().ToLowerInvariant()))
    })
    $newJson = if ($remaining.Count -eq 0) { "[]" } else { $remaining | ConvertTo-Json -Compress -Depth 4 }
    $escapedJson = $newJson.Replace("'", "''")

    & $sqlite.Source $stateDb "UPDATE ItemTable SET value = '$escapedJson' WHERE key = 'extensionsIdentifiers/disabled';" | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $enabled = ($disabledRequired | ForEach-Object { $_.id }) -join ", "
        Write-Host "  Re-enabled persisted VS Code extension(s): $enabled" -ForegroundColor Green
    } else {
        Write-Host "  Warning: failed to update VS Code disabled-extension state" -ForegroundColor Yellow
    }
}

function Disable-VSCodeConflictingExtensions {
    param([string[]]$Extensions)

    if (-not $Extensions -or $Extensions.Count -eq 0) {
        return
    }

    $stateDb = Join-Path $env:APPDATA "Code\User\globalStorage\state.vscdb"
    if (-not (Test-Path -LiteralPath $stateDb)) {
        return
    }

    $sqlite = Get-Command sqlite3 -ErrorAction SilentlyContinue
    if (-not $sqlite) {
        Write-Host "  Note: sqlite3 not found; manually disable conflicting VS Code extensions." -ForegroundColor Yellow
        return
    }

    $disabledJson = & $sqlite.Source $stateDb "SELECT value FROM ItemTable WHERE key = 'extensionsIdentifiers/disabled';"
    $hasDisabledRow = $LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($disabledJson)
    if (-not $hasDisabledRow) {
        $disabledJson = "[]"
    }

    try {
        $disabledItems = @(ConvertFrom-Json -InputObject $disabledJson)
    } catch {
        Write-Host "  Warning: could not parse VS Code disabled-extension state" -ForegroundColor Yellow
        return
    }

    $knownUuids = @{
        "asvetliakov.vscode-neovim" = "caf8995c-5426-4bf7-9d01-f7968ebd49bb"
        "jasew.vscode-helix-emulation" = "bbfec3b6-db49-48ca-ac93-b3141e35a9eb"
    }
    $disabled = @{}
    foreach ($item in $disabledItems) {
        if ($item.id) {
            $disabled[$item.id.ToString().ToLowerInvariant()] = $true
        }
    }

    $newItems = @($disabledItems)
    $added = @()
    foreach ($extension in $Extensions) {
        $id = $extension.Trim()
        if (-not $id) {
            continue
        }

        $key = $id.ToLowerInvariant()
        if ($disabled.ContainsKey($key)) {
            continue
        }

        $properties = [ordered]@{ id = $id }
        if ($knownUuids.ContainsKey($key)) {
            $properties.uuid = $knownUuids[$key]
        }
        $newItems += [pscustomobject]$properties
        $disabled[$key] = $true
        $added += $id
    }

    if ($added.Count -eq 0) {
        return
    }

    $newJson = $newItems | ConvertTo-Json -Compress -Depth 4
    $escapedJson = $newJson.Replace("'", "''")
    $sql = if ($hasDisabledRow) {
        "UPDATE ItemTable SET value = '$escapedJson' WHERE key = 'extensionsIdentifiers/disabled';"
    } else {
        "INSERT INTO ItemTable(key, value) VALUES('extensionsIdentifiers/disabled', '$escapedJson');"
    }

    & $sqlite.Source $stateDb $sql | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Disabled conflicting VS Code extension(s): $($added -join ', ')" -ForegroundColor Green
    } else {
        Write-Host "  Warning: failed to update VS Code disabled-extension state" -ForegroundColor Yellow
    }
}

Write-Host "Installing dotfiles..." -ForegroundColor Green

Push-Location $PSScriptRoot
try {
    # Apply dotfiles first so subsequent shells/tasks can see config paths.
    $global:LASTEXITCODE = 0
    & "$PSScriptRoot\apply.ps1" @args
    $applySucceeded = $?
    $applyExitCode = $LASTEXITCODE
    if (-not $applySucceeded -or $applyExitCode -ne 0) {
        Write-Host "Dotfile apply failed; stopping installer." -ForegroundColor Red
        exit $(if ($applyExitCode -ne 0) { $applyExitCode } else { 1 })
    }

    if (Test-ApplyOnlyMode -Arguments $args) {
        Write-Host "Skipping installer steps for apply-only mode." -ForegroundColor Yellow
        return
    }

    Add-DotfilesLocalBinToSessionPath
    Enable-GitLongPaths

    if (Get-InstallChoice "Install VS Code extensions?") {
        $codeCommand = Get-VSCodeCommand
        if ($codeCommand) {
            Write-Host "Installing VS Code extensions..." -ForegroundColor Yellow
            $requiredExtensions = @(Get-Content "vscode_extensions.txt" | ForEach-Object {
                $ext = $_.Trim()
                if ($ext -and (-not $ext.StartsWith("#"))) {
                    $ext
                }
            })
            Enable-VSCodeRequiredExtensions -Extensions $requiredExtensions
            foreach ($ext in $requiredExtensions) {
                Write-Host "  Installing: $ext" -ForegroundColor Cyan
                try {
                    & $codeCommand --install-extension $ext --force | Out-Null
                } catch {
                    Write-Host "    Warning: failed to install $ext" -ForegroundColor Yellow
                }
            }
            Enable-VSCodeRequiredExtensions -Extensions $requiredExtensions
            if (Test-Path "vscode_conflicting_extensions.txt") {
                $conflictingExtensions = @(Get-Content "vscode_conflicting_extensions.txt" | ForEach-Object {
                    $ext = $_.Trim()
                    if ($ext -and (-not $ext.StartsWith("#"))) {
                        $ext
                    }
                })
                Disable-VSCodeConflictingExtensions -Extensions $conflictingExtensions
            }
            Write-Host "[ok] VS Code extensions installed" -ForegroundColor Green
        } else {
            Write-Host "VS Code not found, skipping extensions" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Skipping VS Code extensions" -ForegroundColor Yellow
    }

    if (Get-InstallChoice "Install common development tools?") {
        Write-Host "Installing common tools..." -ForegroundColor Yellow

        Ensure-ScoopBucket extras
        Install-GitForWindows

        $scoopApps = @(
            @{ App = 'ripgrep'; Command = 'rg' },
            @{ App = 'wget'; Command = 'wget' },
            @{ App = 'fzf'; Command = 'fzf' },
            @{ App = 'bat'; Command = 'bat' },
            @{ App = 'jq'; Command = 'jq' },
            @{ App = 'neovim'; Command = 'nvim' },
            @{ App = 'win32yank'; Command = 'win32yank.exe' },
            @{ App = 'delta'; Command = 'delta' },
            @{ App = 'eza'; Command = 'eza' },
            @{ App = 'fd'; Command = 'fd' },
            @{ App = 'zoxide'; Command = 'zoxide' },
            @{ App = 'starship'; Command = 'starship' },
            @{ App = 'lf'; Command = 'lf' },
            @{ App = 'glow'; Command = 'glow' },
            @{ App = 'yazi'; Command = 'yazi' },
            @{ App = 'lazygit'; Command = 'lazygit' },
            @{ App = 'wezterm'; Command = 'wezterm' }
        )

        foreach ($entry in $scoopApps) {
            Install-ScoopApp -App $entry.App -CommandName $entry.Command
        }

        Install-Portable7ZipCli
        Install-PortableNodeLts
        Install-ZoektTools
        Install-WingetApp -Id 'tree-sitter.tree-sitter-cli' -CommandName 'tree-sitter'
        Install-WingetApp -Id 'aristocratos.btop4win' -CommandName 'btop'

        Install-JetBrainsMonoNerdFont
    } else {
        Write-Host "Skipping common development tools" -ForegroundColor Yellow
    }

    $windowsInit = Join-Path $PSScriptRoot 'init-windows.ps1'
    if (Test-Path $windowsInit) {
        & $windowsInit @args
    }

    Write-Host "Done!" -ForegroundColor Green
} finally {
    Pop-Location
}
