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
- If you touched a colour anywhere, run `./tests/check-theme.py` (needs only
  python3 and a POSIX shell). The theme is spread across a dozen tools that
  each want it in a different dialect; the test is what keeps them agreeing.
  `./doctor-theme.sh` is the runtime companion, for when the theme looks wrong
  on one machine rather than wrong in the repo. See `docs/tokyonight.md`.
- If you upgraded a themed tool, run `./tests/audit-theme-keys.py`. It asks
  upstream which keys it still reads and reports the ones we set that it does
  not — the failure `check-theme.py` cannot see, because a colour nobody reads
  is still a valid colour. Needs the network, so it is not an every-change
  check.
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
