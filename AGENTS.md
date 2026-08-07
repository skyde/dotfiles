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

- Run ShellCheck on modified shell scripts if available. Most of the shell here
  is not named `*.sh` (`common/.local/bin` has no extensions, `.bashrc-custom`
  has no shebang), so CI selects by shebang or `# shellcheck shell=` directive
  and enforces `--severity=warning`.
- Run Stylua on modified Neovim Lua files if available: `stylua common/.config/nvim`
- Run the Neovim specs if you touched the Lua config: `./tests/run-nvim-specs.sh`
  (self-contained, no plugins required), and `./tests/check-nvim-keymaps.sh` to
  invoke every binding against the real config.
- After a keybinding change: `./tests/check-doc-keymaps.py` (the parity table
  must not document a key the config does not map).
- After a `common/.config/yazi` change: `./tests/check-yazi-config.py` (yazi
  discards a whole config file over one stale key and falls back to presets).
- For cross-platform confidence, optionally run the workflow helper: `./test-all-platforms.sh [cycles]`

## Commit and PR guidelines

- Use concise commit messages summarizing the change.
- In the PR description, list the affected packages/scripts and any notable behavior changes.
- Call out anything requiring manual steps (rare) or platform-specific notes.

## Repository layout tips

- Cross-platform packages live under `common/` (e.g., `shell`, `devtools`, `nvim`, `Code`, `kitty`, `lf`).
- OS-specific configs live under `mac/` and `windows/` (e.g., `mac/hammerspoon`, `windows/Documents`).
- Neovim configuration is under `common/nvim/.config/nvim`.
- VS Code extensions are listed in `vscode_extensions.txt` and installed by scripts.

Shared helpers:

- `lib/run_ensure.sh` (which sources `lib/cask_app_map.sh`) is sourced by `init-linux.sh`, `init-macos.sh` and `install-fast-syntax-highlighting.sh`, and `init.sh` runs the first two — so it is on a real install path. It sets `-euo pipefail` for whatever sources it.

Avoid committing secrets or personal data.

## Handy commands

- First-time setup: `./init.sh`
- Apply changes normally: `./apply.sh`
- Preview only: `./apply.sh --no`
- Restow existing installs: `./apply.sh --restow`
- Preview adoption (taking over real files): `./apply.sh --no --adopt`
- Update from remote and restow: `./update.sh`
