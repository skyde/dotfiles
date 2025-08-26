# Usage & Operations

This page covers the day‑to‑day commands, flags, and patterns.

---

## Prerequisites

- **macOS/Linux:** `git`, `stow` (installed by `init-macos.sh`/`init-linux.sh` if missing)
- **Windows:** PowerShell 5+ (built‑in), Developer Mode recommended (or run as Administrator)

---

## 1) Bootstrap a machine

### macOS
```bash
./init-macos.sh
```

* Installs `git`, `stow`, and base tools as needed.
* Performs basic macOS configuration (e.g., defaults) when applicable.

### Linux

```bash
./init-linux.sh
```

* Installs `git`, `stow` via your package manager.
* Ensures the environment is ready for linking.

### Windows

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\init-windows.ps1
```

* Prepares the environment (developer mode checks, etc.).
* Ensures linking will work for your user.

---

## 2) Apply dotfiles

### Default packages

```bash
# macOS/Linux
./apply.sh
```

```powershell
# Windows
.\apply.ps1
```

Reads `packages.txt` and links those packages.

### Select packages explicitly

```bash
./apply.sh shell nvim Code
```

```powershell
.\apply.ps1 -Packages shell,nvim,Code
```

### Safe‑run & reconcile

```bash
./apply.sh --no       # dry run: show actions only
./apply.sh --restow   # re-link after changes
./apply.sh --delete   # unlink previously stowed files
```

> Tip: When files already exist, prefer **adopting** them into the repo, not clobbering. On macOS/Linux:

```bash
# Example: adopt existing ~/.zshrc into dotfiles/shell
stow --adopt -t "$HOME" shell
git add -A && git commit -m "Adopt shell configs"
```

---

## 3) Update

```bash
./update.sh
```

* Pulls latest changes and re‑applies.
* Use on all platforms after you modify the repo elsewhere.

Windows:

```powershell
.\update.ps1
```

---

## 4) VS Code extensions

List your desired extensions in `vscode_extensions.txt`. The scripts will install them on apply/update when supported.

---

## 5) Adding a new package

1. Create a folder: `dotfiles/<packageName>/`
2. Inside it, mirror real paths (e.g., `dotfiles/foo/.config/foo/config.toml`)
3. Test on one machine:

   ```bash
   ./apply.sh foo
   ```
4. Commit and push.

---

## 6) Uninstall / unlink

```bash
./apply.sh --delete shell nvim
```

---

## 7) Windows symlink notes

* With **Developer Mode** enabled, unprivileged symlinks work. Otherwise, run PowerShell as Administrator.
* If a path is locked by another application, close it and retry.
* Some Windows apps prefer config under `%APPDATA%` or `%LOCALAPPDATA%`; the package mirrors the destination.

---

## 8) Conventions

* Keep “secrets” in secure stores (e.g., 1Password, macOS Keychain, Windows Credential Manager). Don’t commit secrets.
* Favor small, focused packages.
* Re‑run `./apply.sh --restow` after renaming/moving files.

