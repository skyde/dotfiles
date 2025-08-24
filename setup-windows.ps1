# Windows-specific setup script
# Requires PowerShell 7+

Write-Host "🪟 Running Windows-specific setup..."

Write-Host "Configuring Windows-specific settings..."

# Ensure Yazi uses Git's file.exe for MIME detection
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

# Ensure LLVM (clang) is in PATH for C compiler support
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
    $clangVersion = & "$llvmBin\clang.exe" --version
    Write-Host "clang is available: $clangVersion"
} else {
    Write-Warning "LLVM is installed but clang.exe was not found in $llvmBin. You may need to reinstall or check your LLVM installation."
}

# Check for JetBrainsMono Nerd Font installation
$fontName = "JetBrainsMono Nerd Font"
$fontInstalled = (Get-ChildItem -Path "$env:WINDIR\Fonts" -Include "*JetBrainsMono*NF*.ttf" -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
if (-not $fontInstalled) {
    Write-Warning "JetBrainsMono-NF font is not installed. Please install it manually from https://github.com/ryanoasis/nerd-fonts/releases."
} else {
    Write-Host "JetBrainsMono-NF font is already installed."
}

# Configure key repeat behavior for Vim and general usage
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

Write-Host "✅ Windows-specific setup complete!"
