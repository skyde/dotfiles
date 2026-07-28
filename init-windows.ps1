# Windows-specific setup script
# Requires PowerShell 7+

Write-Host "Running Windows-specific setup..."

# Get the directory where this script is located
$ScriptDir = $PSScriptRoot

Write-Host "Configuring Windows-specific settings..."

# -------- Add .local/bin to PATH for custom scripts
$localBin = "$env:USERPROFILE\.local\bin"
if (Test-Path $localBin) {
    $userPath = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    if (-not ($userPath -split ';' | Where-Object { $_ -eq $localBin })) {
        [System.Environment]::SetEnvironmentVariable('PATH', "$localBin;$userPath", 'User')
        Write-Host "Added ~/.local/bin to user PATH"
    } else {
        Write-Host "~/.local/bin is already in your user PATH"
    }
    # Also add to current session
    if (-not ($env:PATH -split ';' | Where-Object { $_ -eq $localBin })) {
        $env:PATH = "$localBin;$env:PATH"
    }
} else {
    Write-Host "~/.local/bin does not exist yet (will be created by stow)"
}

# -------- Ensure Yazi uses Git's file.exe for MIME detection
$gitFile = "$env:ProgramFiles\Git\usr\bin\file.exe"
if (Test-Path $gitFile) {
    $current = [System.Environment]::GetEnvironmentVariable('YAZI_FILE_ONE', 'User')
    if ($current -ne $gitFile) {
        [System.Environment]::SetEnvironmentVariable('YAZI_FILE_ONE', $gitFile, 'User')
        Write-Host "Set YAZI_FILE_ONE to $gitFile"
    } else {
        Write-Host "YAZI_FILE_ONE is already set to $gitFile"
    }
    $env:YAZI_FILE_ONE = $gitFile
} else {
    Write-Warning "file.exe not found at $gitFile. Install Git for Windows first."
}

# -------- Ensure LLVM (clang) is in PATH for C compiler support
$llvmBin = "$env:ProgramFiles\LLVM\bin"
if (Test-Path "$llvmBin\clang.exe") {
    $userPath = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    if (-not ($userPath -split ';' | Where-Object { $_ -eq $llvmBin })) {
        [System.Environment]::SetEnvironmentVariable('PATH', "$userPath;$llvmBin", 'User')
        Write-Host "Added LLVM to user PATH. You may need to restart your terminal or log out/in for this to take effect."
    } else {
        Write-Host "LLVM is already in your user PATH."
    }
    if (-not ($env:PATH -split ';' | Where-Object { $_ -eq $llvmBin })) {
        $env:PATH += ";$llvmBin"
        Write-Host "Temporarily added LLVM to PATH for this session."
    }
    $clangVersion = & "$llvmBin\clang.exe" --version 2>$null | Select-Object -First 1
    Write-Host "clang is available: $clangVersion"
} else {
    Write-Host "LLVM/clang not found (optional - needed for C/C++ development)"
}

# -------- Check for JetBrainsMono Nerd Font installation
$fontInstalled = (Get-ChildItem -Path "$env:WINDIR\Fonts" -Include "*JetBrainsMono*NF*.ttf" -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
if (-not $fontInstalled) {
    # Also check user fonts directory
    $userFonts = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
    if (Test-Path $userFonts) {
        $fontInstalled = (Get-ChildItem -Path $userFonts -Include "*JetBrainsMono*NF*.ttf" -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
    }
}
if (-not $fontInstalled) {
    Write-Warning "JetBrainsMono Nerd Font is not installed."
    Write-Host "  Install with: winget install JetBrains.Mono"
    Write-Host "  Or download from: https://github.com/ryanoasis/nerd-fonts/releases"
} else {
    Write-Host "JetBrainsMono Nerd Font is installed"
}

# -------- Configure key repeat behavior for Vim and general usage
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

# -------- Install yazi if not present (optional - requires user confirmation)
if (-not (Get-Command yazi -ErrorAction SilentlyContinue)) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $install = Read-Host "Yazi file manager not found. Install with winget? (y/N)"
        if ($install -match "^[Yy]") {
            Write-Host "Installing Yazi..."
            winget install sxyazi.yazi --silent --accept-package-agreements --accept-source-agreements
        }
    } else {
        Write-Host "Yazi not found. Install manually or via winget: winget install sxyazi.yazi"
    }
} else {
    Write-Host "Yazi is already installed"
}

# -------- Configure Windows Terminal settings (if installed)
$wtSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (Test-Path $wtSettingsPath) {
    Write-Host "Windows Terminal is installed. Consider configuring it for better terminal experience."
} else {
    # Check for Windows Terminal Preview
    $wtPreviewSettingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
    if (Test-Path $wtPreviewSettingsPath) {
        Write-Host "Windows Terminal Preview is installed."
    }
}

# -------- Set up bat cache for custom theme (if bat is installed)
if (Get-Command bat -ErrorAction SilentlyContinue) {
    Write-Host "Building bat cache for custom theme..."
    & bat cache --build 2>$null
}

Write-Host ""
Write-Host "Windows-specific setup complete!"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Restart your terminal for PATH changes to take effect"
Write-Host "  2. Run 'pwsh' to use PowerShell 7 (recommended)"
Write-Host "  3. Your custom scripts are in ~/.local/bin/"
