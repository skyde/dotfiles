# Agent Guidelines

This repository stores dotfiles managed by [chezmoi](https://github.com/twpayne/chezmoi).
Follow these rules whenever you make changes:

## Required checks
1. Run `chezmoi apply --dry-run -S .` and ensure it finishes without errors.
2. Run `chezmoi doctor -S .` and confirm all tests pass.

If `chezmoi` is missing, install it via your package manager or from https://github.com/twpayne/chezmoi.

## Optional checks
- If `shellcheck` is available, run it on any modified shell scripts.
- If `stylua` is available, run it on modified Lua files under `dot_config/nvim`.

## Commit and PR guidelines
- Use concise commit messages summarizing the change.
- In the PR description, mention notable configuration or package changes and cite modified files.

## Repository layout tips
- OS specific configs live in `darwin/`, `linux/`, and `windows/`.
- Neovim configuration is in `dot_config/nvim`.
- Template files reside in `.chezmoitemplates`.

Avoid committing secrets or personal data.
