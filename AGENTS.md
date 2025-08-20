# Agent Guidelines

This repo stores dotfiles managed with GNU Stow. Use the provided scripts and keep changes safe and reproducible.

## Required checks

1. Dry-run stow and ensure no errors:
	- `./apply.sh --no` (from the repo root)
2. If your change might adopt existing files, preview adoption:
	- `./apply.sh --no --adopt`
3. If you changed already-installed packages, verify a restow preview:
	- `./apply.sh --no --restow`

## Optional checks

- Run ShellCheck on modified shell scripts if available: `shellcheck <changed .sh files>`
- Run Stylua on modified Neovim Lua files if available: `stylua dotfiles/common/nvim/.config/nvim`
- For cross-platform confidence, optionally run the workflow helper: `./test-all-platforms.sh [cycles]`

## Commit and PR guidelines

- Use concise commit messages summarizing the change.
- In the PR description, list the affected packages/scripts and any notable behavior changes.
- Call out anything requiring manual steps (rare) or platform-specific notes.

## Repository layout tips

- Cross-platform packages live under `dotfiles/common/` (e.g., `shell`, `devtools`, `nvim`, `Code`, `kitty`, `lf`).
- OS-specific configs live under `dotfiles/mac/` and `dotfiles/windows/` (e.g., `mac/hammerspoon`, `windows/Documents`).
- Neovim configuration is under `dotfiles/common/nvim/.config/nvim`.
- VS Code extensions are listed in `vscode_extensions.txt` and installed by scripts.

Avoid committing secrets or personal data.

## Handy commands

- First-time setup: `./init.sh`
- Apply changes normally: `./apply.sh`
- Preview only: `./apply.sh --no`
- Restow existing installs: `./apply.sh --restow`
- Preview adoption (taking over real files): `./apply.sh --no --adopt`
- Update from remote and restow: `./update.sh`
