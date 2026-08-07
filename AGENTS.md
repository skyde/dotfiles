# Agent Guidelines

This repo stores dotfiles managed with GNU Stow. Use the provided scripts and keep changes safe and reproducible.

## Required checks

1. Dry-run stow and ensure no errors:
   - `./apply.sh --no` (from the repo root)
2. If your change might adopt existing files, preview adoption:
   - `./apply.sh --no --adopt`
3. If you changed already-installed packages, verify a restow preview:
   - `./apply.sh --no --restow`

## Required checks for the shell

If you touched `common/.zshrc`, `common/.zshenv`, `common/.bashrc-custom`,
`common/.config/shell/`, or anything in `common/.local/bin` that fzf runs:

4. Run the zsh specs: `./tests/run-zsh-specs.sh`
   They start a shell in a throwaway HOME whose dotfiles are symlinks into the
   checkout, and the ones that need a line editor drive a real terminal — so a
   binding is tested by pressing the key, and completion by pressing Tab. See
   `docs/zsh.md` for what each spec file covers.
5. If the change could affect startup: `./tests/zsh-startup-bench.sh`
   The number that matters is time to prompt (~50ms with the plugins
   installed). `--profile` shows where it goes; `--to-exit` is the older
   measurement and no longer the interesting one.

Both are also run by `.github/workflows/zsh.yml`, on Linux and macOS with the
optional tools installed and on Linux with none of them — that last one matters,
because "works on a fresh clone before ./init.sh has run" is a property this
config is meant to have.

## Optional checks

- Run ShellCheck on modified shell scripts if available: `shellcheck <changed .sh files>`
- Run Stylua on modified Neovim Lua files if available: `stylua common/nvim/.config/nvim`
- Run the Neovim specs if you touched the Lua config: `./tests/run-nvim-specs.sh`
  (self-contained, no plugins required), and `./tests/check-nvim-keymaps.sh` to
  invoke every binding against the real config.
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

Optional helpers present but not wired into the local scripts:

- `lib/run_ensure.sh` and `lib/cask_app_map.sh` are optional utilities for package management. They are not invoked by `init.sh`/`apply.sh` in this repo but can be sourced manually if desired.

Avoid committing secrets or personal data.

## Handy commands

- First-time setup: `./init.sh`
- Apply changes normally: `./apply.sh`
- Preview only: `./apply.sh --no`
- Restow existing installs: `./apply.sh --restow`
- Preview adoption (taking over real files): `./apply.sh --no --adopt`
- Update from remote and restow: `./update.sh`
