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
    $clangVersion = (& "$llvmBin\clang.exe" --version | Select-Object -First 1)
    Write-Host "clang is available: $clangVersion"
} elseif (Test-Path $llvmBin) {
    Write-Warning "LLVM is installed but clang.exe was not found in $llvmBin. You may need to reinstall or check your LLVM installation."
} else {
    # The old else-branch asserted "LLVM is installed" whenever clang.exe was
    # absent — which is exactly what a machine without LLVM looks like, so the
    # message told you to reinstall something you had never installed.
    Write-Warning "LLVM not found at $llvmBin. Install it with: winget install LLVM.LLVM"
}

# Check for JetBrainsMono Nerd Font installation.
#
# Matched on the names Nerd Fonts actually ships. The old pattern was
# "*JetBrainsMono*NF*.ttf", which requires the literal text "NF" after the
# family name; current releases are called JetBrainsMonoNerdFont-Regular.ttf,
# JetBrainsMonoNerdFontMono-Bold.ttf and so on, none of which contain it. The
# check matched nothing and warned on every run, even with the font installed.
#
# Per-user installs land in %LOCALAPPDATA%\Microsoft\Windows\Fonts and were not
# looked at either, so a font installed without admin rights read as missing.
$fontDirs = @(
    (Join-Path $env:WINDIR 'Fonts'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts')
) | Where-Object { $_ -and (Test-Path $_) }

$fontInstalled = @(
    $fontDirs | ForEach-Object {
        Get-ChildItem -Path $_ -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'JetBrainsMono*Nerd*Font*.ttf' -or $_.Name -like 'JetBrainsMono*Nerd*Font*.otf' }
    }
).Count -gt 0

if (-not $fontInstalled) {
    Write-Warning "JetBrainsMono Nerd Font is not installed. Install it from https://github.com/ryanoasis/nerd-fonts/releases, or with: winget install DEVCOM.JetBrainsMonoNerdFont"
} else {
    Write-Host "JetBrainsMono Nerd Font is already installed."
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
