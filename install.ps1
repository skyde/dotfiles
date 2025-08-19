$ErrorActionPreference = 'Stop'

$home = $env:USERPROFILE
$packages = @('bash','zsh','tmux','git','kitty','lazygit','starship','lf','nvim','vsvim','visual_studio','vimium_c','Documents')

foreach ($pkg in $packages) {
    if (Test-Path $pkg) {
        stow --restow --target $home $pkg
    }
}

if (Test-Path 'nvim-win') {
    stow --restow --target $env:LOCALAPPDATA nvim-win
}
if (Test-Path 'lf-win') {
    stow --restow --target $env:APPDATA lf-win
}
if (Test-Path 'Code-win') {
    stow --restow --target $env:APPDATA Code-win
}
