# Dotfiles (GNU Stow)

Personal dotfiles for my development environment, now managed with GNU [stow](https://www.gnu.org/software/stow/). A bootstrap script installs core tools (LazyVim, ripgrep, bat, kitty/wezterm, lazygit), fonts (JetBrainsMono Nerd Font), and symlinks configs using stow. The setup supports macOS, Linux, and Windows (PowerShell).

## Quick Start

Clone the repo and run the bootstrap for your OS.

### macOS / Linux

```bash
git clone https://github.com/F286/dotfiles.git
cd dotfiles
scripts/bootstrap.sh
```

This installs stow (if needed), stows the packages under `stow/` to `$HOME`, installs tools (Neovim + LazyVim starter, ripgrep, bat, lazygit, kitty on macOS, wezterm), installs Nerd Fonts, rebuilds bat cache, and ensures your shell picks up `~/.config/shell/00-editor.sh`.

### Windows

```powershell
git clone https://github.com/F286/dotfiles.git
cd dotfiles
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
scripts\bootstrap.ps1
```

This installs ripgrep/bat/wezterm/neovim via winget, installs Nerd Fonts, sets VS Code settings/keybindings/extensions, and bootstraps LazyVim.

## Notes

- Stow packages live under `stow/`. On macOS/Linux, the bootstrap uses `stow -d stow -t $HOME` to link:
  - `zsh`, `ripgrep`, `shell`, `fzf`, `local-bin`, `kitty`, `wezterm`, `lazygit`, `helix`, `bat`, `nvim`, plus `hammerspoon` and `macos` on macOS.
- Neovim is installed fresh from the LazyVim starter, then the `stow/nvim` package overlays custom keymaps/plugins on top of it.
- Fonts are installed from `fonts/` into the appropriate user directory.
- VS Code user files:
  - macOS/Linux: symlinked via Stow from `vscode/` using packages `vscode-macos` and `vscode-linux` (includes both Code and Code - Insiders), so edits in the repo reflect immediately.
  - Windows: copied from `vscode/` for both `Code\User` and `Code - Insiders\User` by `scripts/bootstrap.ps1`.
