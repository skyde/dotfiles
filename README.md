# Dotfiles

This repository contains configuration files for multiple platforms.

The VS Code settings and keybindings are defined in `.chezmoitemplates`. Copies of
these templates are placed under each platform's default settings directory so
chezmoi installs them correctly on macOS, Linux and Windows:

- `Library/Application Support/Code/User/` (macOS)
- `dot_config/Code/User/` (Linux)
- `AppData/Roaming/Code/User/` (Windows)

Running `chezmoi apply` will copy the template to the appropriate location on
whichever OS you're using.

By default chezmoi is configured to create symlinks instead of copying files.
The setting is defined in `dot_config/chezmoi/chezmoi.toml`:

```toml
mode = "symlink"
```

## Neovim

On macOS, common Command shortcuts work in Neovim:

- **⌘C** copies the current selection to the system clipboard.
- **⌘X** cuts the selection.
- **⌘V** pastes the clipboard in Normal, Visual and Insert modes.
- **⌘A** selects the entire buffer.
