# Dotfiles

Personal dotfiles for my development environment, managed with [chezmoi](https://www.chezmoi.io/). Chezmoi bootstraps a vanilla [LazyVim](https://lazyvim.github.io) configuration for Neovim and also sets up tools like Helix, Kitty, VS Code, and more so they can be reproduced on any machine.

## Installation with chezmoi

Install these dotfiles using [chezmoi](https://www.chezmoi.io/). Below are example commands for different platforms.

### macOS

```bash
# Install Homebrew from https://brew.sh if it's not already present
brew install chezmoi
chezmoi init F286
# Review changes if desired
chezmoi diff
chezmoi apply
```

### Linux

```bash
sudo apt-get update -qq && sudo apt-get install -y git chezmoi
chezmoi init F286
# Review changes if desired
chezmoi diff
chezmoi apply
```

### Windows

```powershell
winget install twpayne.chezmoi
chezmoi init F286
# Review changes if desired
chezmoi diff
chezmoi apply
```

If `chezmoi` is already installed, you can also apply these dotfiles directly:

```bash
chezmoi init --apply https://github.com/F286/dotfiles.git
```

Or install `chezmoi` and apply in one step:

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply https://github.com/F286/dotfiles.git
```

Replace `USERNAME` with the GitHub owner of this repository if using a fork.
