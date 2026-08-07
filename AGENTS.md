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

- Run ShellCheck on modified shell scripts if available. The repo is clean at
  `--severity=warning` and CI enforces that, so keep it there. Note most of the
  shell here is *not* named `*.sh` — the tools in `common/.local/bin` have no
  extension, and `.bashrc-custom` has no shebang either; CI selects by shebang
  or by a leading `# shellcheck shell=` directive. `.zshrc` and `.zshenv` are
  exempt because ShellCheck cannot parse zsh.
- Run Stylua on modified Neovim Lua files if available: `stylua common/.config/nvim`
  (the tree is clean, so `stylua --check common/.config/nvim` should report nothing)
- Run the Neovim specs if you touched the Lua config: `./tests/run-nvim-specs.sh`
  (self-contained, no plugins required), and `./tests/check-nvim-keymaps.sh` to
  invoke every binding against the real config.
- If you changed a keybinding or `docs/nvim-vscode-parity.md`, run
  `./tests/check-doc-keymaps.py` — it fails when the table documents a key the
  config does not actually map.
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

- `lib/run_ensure.sh` provides `have`, `confirm_change`, `ensure_brew`, `ensure_cask` and `ensure_apt`, and sources `lib/cask_app_map.sh` for the cask→`.app` mapping. `init-linux.sh`, `init-macos.sh` and `install-fast-syntax-highlighting.sh` all source it, and `init.sh` runs the first two — so changing either file affects a real install path. (This note used to say they were unused; they are not.)
- Note that `lib/run_ensure.sh` sets `-euo pipefail`, which applies to whatever sources it.

Avoid committing secrets or personal data.

## Handy commands

- First-time setup: `./init.sh`
- Apply changes normally: `./apply.sh`
- Preview only: `./apply.sh --no`
- Restow existing installs: `./apply.sh --restow`
- Preview adoption (taking over real files): `./apply.sh --no --adopt`
- Update from remote and restow: `./update.sh`
