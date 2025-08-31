# Dotfiles (GNU Stow)

Personal dotfiles for my development environment, now managed with GNU [stow](https://www.gnu.org/software/stow/). The `./dot` CLI runs small, ordered hooks to install core tools (LazyVim, ripgrep, bat, kitty/wezterm, lazygit), install fonts (JetBrainsMono Nerd Font), and symlink configs using Stow. The setup supports macOS, Linux and Windows (PowerShell).

## Quick Start

Clone the repo and run the dot CLI for your OS.

### macOS / Linux

```bash
git clone https://github.com/F286/dotfiles.git
cd dotfiles
./dot apply
```

This installs stow (if needed), stows the packages under `stow/` to `$HOME`, installs tools (Neovim + LazyVim starter, ripgrep, bat, lazygit, kitty on macOS, wezterm), installs Nerd Fonts, rebuilds bat cache, and ensures your shell picks up `~/.config/shell/00-editor.sh`.

### Windows

```powershell
git clone https://github.com/F286/dotfiles.git
cd dotfiles
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
./dot.ps1 apply
```

This installs ripgrep/bat/wezterm/neovim via winget, installs Nerd Fonts, sets VS Code settings/keybindings/extensions, and bootstraps LazyVim.

## Using the `dot` CLI

The repository includes a `dot` script at the top level which orchestrates platform hooks and wraps GNU Stow. It works similarly to [chezmoi](https://www.chezmoi.io/): instead of running `stow` directly, you call `./dot` with a subcommand. The script automatically chooses sensible default packages for your OS (by inspecting subdirectories under `stow/`) when none are given and honours the `STOW_FLAGS` environment variable (default: `--no-folding`). You can pass `--dry-run` to preview what would be done without making changes and `--target DIR` to change the target directory from `$HOME`.

### Subcommands

* `apply` – symlink the selected packages into the target directory.
* `update` – run `git pull` on the repo and then restow the packages.
* `restow` – remove and re-apply the symlinks for the selected packages.
* `delete` – remove the symlinks created by stow for the selected packages.
* `diff` – show what would change when applying packages (dry-run mode).
* `test` – run the unit tests located in the `./tests` directory.

When you omit package names, `dot` determines an appropriate set based on your operating system. For example, on macOS it skips Linux-specific packages and vice versa.

### Examples

```bash
# Apply all appropriate packages for your OS
./dot apply

# Apply only a subset of packages (e.g. zsh and nvim)
./dot apply zsh nvim

# Pull the latest changes and restow everything
./dot update

# Remove a package’s symlinks
./dot delete kitty

# Preview changes without touching the filesystem
./dot diff zsh
 
# Run the TypeScript unit tests
./dot test
```

### Hook Layout

The `./dot` CLI is a generic orchestrator that discovers and runs hooks under `scripts/<platform>/<subcommand>/` in lexical order (use numeric prefixes like `10-…`, `20-…`). This keeps repo‑specific logic out of `dot` so it can be reused in other repos.

- Platforms: `common/`, `unix/` (macOS+Linux), `darwin/`, `linux/`, `windows/`
- Subcommands: `apply/`, `restow/`, `delete/`, `test/` (and `diff/` via `apply` honoring dry‑run)
- Environment to hooks: `DOT_CMD`, `DOT_OS`, `DOT_REPO`, `DOT_TARGET`, `DOT_DRYRUN`

See `scripts/README.md` for authoring details and conventions.

## Notes

* Stow packages live under `stow/`. On macOS/Linux, the hooks use `stow -d stow -t $HOME` to link:
  * `zsh`, `ripgrep`, `shell`, `fzf`, `local-bin`, `kitty`, `wezterm`, `lazygit`, `helix`, `bat`, `nvim`, plus `hammerspoon` and `macos` on macOS.
* Neovim is installed fresh from the LazyVim starter, then the `stow/nvim` package overlays custom keymaps/plugins on top of it.
* Fonts are installed from `fonts/` into the appropriate user directory.
* VS Code user files:
  * macOS/Linux: symlinked via Stow from `stow/vscode-macos` and `stow/vscode-linux` (includes both Code and Code - Insiders), so edits in the repo reflect immediately.
  * Windows: copied from `vscode/` for both `Code\User` and `Code - Insiders\User` by Windows apply hooks under `scripts/windows/apply/`.

### Windows usage

On Windows, use the PowerShell wrapper for a similar experience:

```powershell
# Apply (installs tools and VS Code files via hooks)
./dot.ps1 apply

# Update repo and apply
./dot.ps1 update

# Run the Windows smoke checks (Unix Stow tests must run under WSL)
./dot.ps1 test
```
