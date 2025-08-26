# Repository Structure

```

dotfiles/
shell/               # shells, gitconfig, aliases
devtools/            # CLI tools (ripgrep, fd, fzf, etc.)
nvim/                # Neovim config
Code/                # VS Code settings/keybindings
kitty/               # Kitty terminal
lf/                  # lf file manager
hammerspoon/         # macOS automation
visual_studio/       # VS settings (Windows)
vsvim/               # VsVim settings (Windows)
kinesis-advantage2/  # keyboard firmware/layouts
savant-elite2/       # foot pedal config

```

**Naming:** Each top‑level folder under `dotfiles/` is a **package**.  
**Linking target:** By default we link into `$HOME` (or the equivalent on Windows).  
**Why this layout?** It mirrors final paths so stow/PowerShell can place clean symlinks without custom logic.

See **packages.md** for per‑package details.
