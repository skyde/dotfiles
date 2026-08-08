# Agent Guidelines

This repo stores dotfiles managed with GNU Stow. Use the provided scripts and keep changes safe and reproducible.

## Required checks

1. Dry-run stow and ensure no errors:
   - `./apply.sh --no` (from the repo root)
2. If your change might adopt existing files, preview adoption:
   - `./apply.sh --no --adopt`
3. If you changed already-installed packages, verify a restow preview:
   - `./apply.sh --no --restow`

## Checks for the Neovim config

```bash
./tests/check-nvim.sh          # specs, format, types — under a minute
./tests/check-nvim.sh --all    # and the three that need the plugins installed
```

That is the whole list below in one command, with a summary at the end. Run it
on any change to `common/.config/nvim/lua`. Everything it runs also runs in CI
(`.github/workflows/neovim.yml`), so a change that passes locally passes there.
The individual scripts, if you want one on its own — the first two need nothing
but `nvim`, the rest need the tool named and each skips cleanly when it is
missing:

- `./tests/run-nvim-specs.sh` — the specs. Self-contained: no plugins, no
  network, no system clipboard, everything built in a tempdir. Run these on any
  change to `common/.config/nvim/lua`. The jj, Mercurial and ripgrep blocks skip
  when the tool is missing; CI installs all three and sets
  `NVIM_CHECKS_NO_SKIP=1`, which turns a skip into a failure so a backend cannot
  quietly stop being covered. Install jj locally before touching `util.vcs` —
  jj is first in the detection order.
- `stylua --check --config-path common/.config/nvim/stylua.toml common/.config/nvim tests`
  — formatting. Drop `--check` to apply it.
- `./tests/check-nvim-types.sh` — lua-language-server over the config: undefined
  globals and fields, wrong arity, unchecked nils, deprecated Neovim APIs. Must
  report zero problems, at Hint — the strictest level the tool has. Skips
  without the binary, and honours `NVIM_CHECKS_NO_SKIP=1` the same way. CI pins
  the version it installs; bump it by installing the new one locally, running
  this, then editing the workflow.
- `./tests/check-nvim-keymaps.sh` — invokes every parity binding against the
  real config. Needs the plugins installed.
- `./tests/check-nvim-syntax-roles.sh` — C++ and Python colour the same
  construct the same way. Needs the plugins and the tree-sitter parsers.
- `python3 tests/check-footpedal-keys.py` — drives the Shift+Fn macro keys
  through a real terminal into a real Neovim. Needs the plugins: the keys are
  registered on VeryLazy.

## Benchmarks

- `./tests/bench-nvim-vcs.sh [files]` — what the changed-files view costs on a
  big listing: time to first paint, time until every background pass has
  finished, and forty files of scrubbing. Informational, never a gate; CI prints
  it beside the startup cost.

## Optional checks

- Run ShellCheck on modified shell scripts if available: `shellcheck <changed .sh files>`
- For cross-platform confidence, optionally run the workflow helper: `./test-all-platforms.sh [cycles]`

## Commit and PR guidelines

- Use concise commit messages summarizing the change.
- In the PR description, list the affected packages/scripts and any notable behavior changes.
- Call out anything requiring manual steps (rare) or platform-specific notes.

## Repository layout tips

- `common/`, `mac/` and `windows/` are the three Stow packages, each mirroring
  `$HOME` directly — so a file's path inside a package is where it lands (e.g.
  `common/.zshrc` -> `~/.zshrc`, `common/.config/kitty/kitty.conf` ->
  `~/.config/kitty/kitty.conf`).
- Neovim configuration is under `common/.config/nvim`; its specs and checks are
  in `tests/`.
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
