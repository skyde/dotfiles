# Agent Guidelines

This repository stores dotfiles managed by GNU Stow.
Follow these rules whenever you make changes:

## Required checks
1. Run `stow --no-folding --simulate --target=/tmp/stow-test <packages>` and ensure it finishes without errors.

## Optional checks
- If `shellcheck` is available, run it on any modified shell scripts.
- If `stylua` is available, run it on modified Lua files under `nvim/.config/nvim`.

## Commit and PR guidelines
- Use concise commit messages summarizing the change.
- In the PR description, mention notable configuration or package changes and cite modified files.

## Repository layout tips
- OS specific configs live in dedicated stow packages like `Code-mac` or `nvim-win`.
- Neovim configuration is in `nvim/.config/nvim`.

Avoid committing secrets or personal data.
