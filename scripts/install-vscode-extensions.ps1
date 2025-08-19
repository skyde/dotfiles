$ErrorActionPreference = 'Stop'

# Install VS Code (or Cursor) extensions from vscode_extensions.txt
$repo = Split-Path -Parent $PSScriptRoot
$extensionsFile = Join-Path $repo 'vscode_extensions.txt'

if (Get-Command 'code' -ErrorAction SilentlyContinue) {
    $codeCmd = 'code'
} elseif (Get-Command 'cursor' -ErrorAction SilentlyContinue) {
    $codeCmd = 'cursor'
} else {
    Write-Host "VS Code 'code' or 'cursor' command not found, skipping extension install"
    return
}

Get-Content $extensionsFile | ForEach-Object {
    $ext = $_.Trim()
    if ($ext) {
        Write-Host "Installing VS Code extension: $ext"
        & $codeCmd --install-extension $ext --force
    }
}
