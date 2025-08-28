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

This will install stow (if needed), stow the packages under `stow/` to `$HOME`, install tools (neovim + LazyVim starter, ripgrep, bat, lazygit, kitty on macOS, wezterm), install Nerd Fonts, rebuild bat cache, and ensure your shell picks up `~/.config/shell/00-editor.sh`.

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
  - `zsh`, `ripgrep`, `shell`, `fzf`, `local-bin`, `kitty` (macOS), `wezterm`, `lazygit`, `helix`, `bat`, `hammerspoon` (macOS)
- Neovim is installed fresh from the LazyVim starter (same behavior as before). If you’d prefer to stow the bundled `stow/nvim` instead, comment out the LazyVim section in `scripts/bootstrap.sh` and add `nvim` to the stowed packages.
- Fonts are installed from `fonts/` into the appropriate user directory.
- VS Code user files are created by the Windows bootstrap; on macOS/Linux you can copy from `.chezmoitemplates/` or adapt the bootstrap if you want them auto-managed.
