# Dotfiles

Personal dotfiles for my development environment, managed with [chezmoi](https://www.chezmoi.io/). Configurations for tools like Neovim, VS Code, and more are kept under version control so they can be reproduced on any machine.

## Installation with chezmoi

Install these dotfiles using [chezmoi](https://www.chezmoi.io/):

```bash
# If chezmoi is already installed
chezmoi init --apply https://github.com/USERNAME/dotfiles.git

# Or install chezmoi and apply in one step
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply https://github.com/USERNAME/dotfiles.git
```

Replace `USERNAME` with the GitHub owner of this repository if using a fork.
