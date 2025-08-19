# Agent Guidelines

This repository stores dotfiles managed by [yadm](https://yadm.io).
Follow these rules whenever you make changes:

## Required checks
1. Run `yadm --version` to ensure yadm is installed.
2. Run `yadm status --short` to verify repository state.
3. Run `.config/yadm/bootstrap` and ensure it exits without errors.

## Optional checks
- If `shellcheck` is available, run it on any modified shell scripts.
- If `stylua` is available, run it on modified Lua files under `.config/nvim`.

## Commit and PR guidelines
- Use concise commit messages summarizing the change.
- In the PR description, mention notable configuration or package changes and cite modified files.

## Repository layout tips
- OS specific configs live in `darwin/`, `linux/`, and `windows/`.
- Neovim configuration is in `.config/nvim`.
- Bootstrap scripts reside in `.config/yadm/bootstrap.d`.

Avoid committing secrets or personal data.
