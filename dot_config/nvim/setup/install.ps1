param(
    [string]$ConfigDir = "$env:LOCALAPPDATA\nvim"
)

function Install-WingetPackage {
    param([string]$Id)
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Error "winget not found. Please install winget and rerun the script."
        exit 1
    }
    winget install --id $Id -e --source winget
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Output "Git not found. Installing Git..."
    Install-WingetPackage "Git.Git"
}

if (-not (Test-Path $ConfigDir)) {
    Write-Output "Setting up Neovim config in $ConfigDir"
    git clone "$(Split-Path -Path $PSScriptRoot -Parent)" $ConfigDir
} else {
    Write-Output "Neovim config already exists at $ConfigDir"
}

$packages = @(
    "Neovim.Neovim",
    "sharkdp.fd",
    "wez.wezterm",
    "BusyBox.BusyBox"
)
foreach ($pkg in $packages) {
    Install-WingetPackage $pkg
}

# Ensure BusyBox directory is in PATH
$busyboxPath = "$env:ProgramFiles\BusyBox"
if (Test-Path $busyboxPath) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath -notlike "*$busyboxPath*") {
        Write-Output "Adding BusyBox to user PATH..."
        [Environment]::SetEnvironmentVariable('Path', "$userPath;$busyboxPath", 'User')
    }
}

# Install Fira Code Nerd Font for WezTerm
Write-Output "Ensuring Fira Code Nerd Font is installed for WezTerm..."
$fontInstalled = (Get-ChildItem -Path "C:\Windows\Fonts" -Include "FiraCodeNerdFont*.ttf","FiraCodeNerdFont*.otf" -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
if (-not $fontInstalled) {
    $fontUrl = "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/FiraCode.zip"
    $fontZip = "$env:TEMP\FiraCodeNerdFont.zip"
    $fontDir = "$env:TEMP\FiraCodeNerdFont"
    Write-Output "Downloading Fira Code Nerd Font..."
    Invoke-WebRequest -Uri $fontUrl -OutFile $fontZip
    Expand-Archive -Path $fontZip -DestinationPath $fontDir -Force
    $fontFiles = Get-ChildItem -Path $fontDir -Include "*.ttf","*.otf" -Recurse
    foreach ($file in $fontFiles) {
        $destFont = Join-Path "C:\Windows\Fonts" $file.Name
        if (Test-Path $destFont) {
            Write-Output "Font $($file.Name) already exists, skipping."
            continue
        }
        Write-Output "Installing font: $($file.Name)"
        try {
            Copy-Item $file.FullName -Destination "C:\Windows\Fonts" -Force -ErrorAction Stop
            $shellApp = New-Object -ComObject Shell.Application
            $shellApp.Namespace(0x14).CopyHere($file.FullName)
        } catch {
            Write-Warning "Could not install $($file.Name): $_.Exception.Message. Skipping."
            continue
        }
    }
    Remove-Item $fontZip -Force
    Remove-Item $fontDir -Recurse -Force
    Write-Output "Fira Code Nerd Font install step complete."
} else {
    Write-Output "Fira Code Nerd Font already installed."
}

# Install win32yank.exe for clipboard support
Write-Output "Ensuring win32yank.exe is available for Neovim clipboard integration..."
$win32yankDir = "$env:LOCALAPPDATA\nvim\bin"
$win32yankExe = Join-Path $win32yankDir 'win32yank.exe'
if (Test-Path $win32yankExe) { Remove-Item $win32yankExe -Force }
if (-not (Test-Path $win32yankDir)) { New-Item -ItemType Directory -Path $win32yankDir | Out-Null }
$win32yankUrl = "https://github.com/equalsraf/win32yank/releases/download/v0.0.4/win32yank-x64.zip"
$win32yankZip = "$env:TEMP\win32yank-x64.zip"
Invoke-WebRequest -Uri $win32yankUrl -OutFile $win32yankZip
Expand-Archive -Path $win32yankZip -DestinationPath $win32yankDir -Force
Remove-Item $win32yankZip -Force
if (-not (Test-Path $win32yankExe)) {
    Write-Warning "win32yank.exe failed to install. Clipboard integration may not work."
} else {
    Write-Output "win32yank.exe installed to $win32yankDir."
}
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$win32yankDir*") {
    Write-Output "Adding $win32yankDir to user PATH..."
    [Environment]::SetEnvironmentVariable('Path', "$win32yankDir;$userPath", 'User')
}

# Launch Neovim once to install plugins
Write-Output "Running Neovim headless to sync plugins..."
Start-Process nvim -ArgumentList '--headless', '+Lazy! sync', '+qa' -Wait
Write-Output "Neovim is ready."
