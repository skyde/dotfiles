# Sky’s Dotfiles — macOS · Linux · Windows

Developer‑friendly, cross‑platform dotfiles. One command to bootstrap a new machine, then manage configs with safe, repeatable symlinks.

- **Batteries included:** shell, dev tools, Neovim, VS Code, Kitty, lf; macOS extras (Hammerspoon); Windows extras (VS/VsVim, Kinesis Advantage2, Savant Elite2).  
- **Cross‑platform scripts:** `init.*`, `apply.*`, `update.*` (shell + PowerShell).  
- **Safe by default:** dry‑runs, adopt existing files, delete/restow when needed.

> These dotfiles use GNU **stow** for symlink management on macOS/Linux, and a PowerShell workflow on Windows.

---

## TL;DR Quick Start

### macOS
```bash
# 1) Get the repo
git clone https://github.com/skyde/dotfiles.git ~/dotfiles
cd ~/dotfiles

# 2) Bootstrap (installs git/stow if needed, sets sensible defaults)
./init-macos.sh

# 3) Link configs (default package set in packages.txt)
./apply.sh
```

### Linux (Debian/Ubuntu shown; use your package manager as needed)

```bash
git clone https://github.com/skyde/dotfiles.git ~/dotfiles
cd ~/dotfiles
./init-linux.sh
./apply.sh
```

### Windows (PowerShell)

```powershell
git clone https://github.com/skyde/dotfiles.git $HOME\dotfiles
cd $HOME\dotfiles

# Recommended: enable Developer Mode (no admin needed) or run PowerShell as Administrator
# Allow local scripts
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

# Bootstrap & link
.\init-windows.ps1
.\apply.ps1
```

---

## What gets installed?

Default packages are listed in `packages.txt`. As of today, the set includes:

* **Common:** `shell`, `devtools`, `nvim`, `Code`, `kitty`, `lf`
* **macOS:** `hammerspoon`
* **Windows:** `Documents`, `vsvim`, `visual_studio`, `kinesis-advantage2`, `savant-elite2`

You can add/remove packages in `packages.txt` or pass packages explicitly to `apply` (see **Usage**).
See **[docs/packages.md](docs/packages.md)** for what each package contains and where it links to.

---

## How it works (first principles)

* **Source of truth:** files live in `dotfiles/<package>/…` mirroring their final paths (e.g., `dotfiles/nvim/.config/nvim/init.lua`).
* **Linking:** on macOS/Linux we use **stow** to place **symlinks** into `$HOME` (or other targets). On Windows, `apply.ps1` uses PowerShell to create symlinks/shortcuts where needed.
* **Idempotent:** re‑running `apply` makes the working machine converge on the repo state (use `--restow` when you change files).
* **Safe adoption:** prefer adopting pre‑existing files rather than overwriting (see **Usage** for the `--adopt` flow with stow).

---

## Everyday commands

```bash
# macOS/Linux
./apply.sh                 # link default packages from packages.txt
./apply.sh shell nvim      # link specific packages
./apply.sh --restow        # restow (after changing files)
./apply.sh --delete        # unlink previously stowed files (careful!)
./apply.sh --no            # dry run (show what would happen)

./update.sh                # pull latest + re-apply
```

```powershell
# Windows
.\apply.ps1                # link default packages
.\apply.ps1 -Packages nvim,Code
.\update.ps1
```

More switches and examples are in **[README-usage.md](README-usage.md)**.

---

## Directory layout

```
dotfiles/
  shell/           # shells, gitconfig, aliases…
  devtools/        # tool config (ripgrep/fd/fzf/etc.)
  nvim/            # Neovim config
  Code/            # VS Code settings/keybindings/snippets
  kitty/           # kitty terminal
  lf/              # lf file manager
  hammerspoon/     # macOS automation
  visual_studio/   # Windows VS settings
  vsvim/           # VsVim settings
  kinesis-advantage2/  # keyboard firmware/layout files
  savant-elite2/       # foot pedal config
```

Other useful files:

* `vscode_extensions.txt` – extensions auto‑installed by the scripts
* `install-yazi.sh` – helper to install the `yazi` TUI file manager
* `init-*.sh` / `apply.*` / `update.*` – cross platform entry points (shell + PowerShell)

---

## Platform notes

* **macOS:** Homebrew is used where appropriate; Hammerspoon config is optional.
* **Linux:** Package installation uses your system’s package manager; everything else is stow‑driven.
* **Windows:** Enable Developer Mode or run an elevated PowerShell to allow symlinks; Visual Studio/VsVim settings and device configs (Kinesis, Savant) live under `dotfiles/…`.

Details in **[docs/platform-notes.md](docs/platform-notes.md)**.

---

## Troubleshooting

Most issues boil down to “file already exists” or symlink permissions. See **[docs/troubleshooting.md](docs/troubleshooting.md)** for quick fixes and `stow --adopt` guidelines.

---

## CI

The repo includes GitHub Actions to test fresh installs, script validation, edge cases, and performance across macOS, Linux, and Windows. See **[docs/ci.md](docs/ci.md)** for the matrix and quality gates.

---

## License

MIT.

