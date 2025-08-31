# Troubleshooting

## “File already exists” / conflicts
- Prefer adoption over clobbering:
  ```bash
  stow --adopt -t "$HOME" <package>
  ```

* Or explicitly unlink then restow:

  ```bash
  ./apply.sh --delete <package>
  ./apply.sh <package>
  ```

## Windows: symlink permissions

* Enable Developer Mode or run elevated PowerShell.
* If a path is locked (e.g., by VS/Code), close the app first.

## Neovim or Kitty not seeing a font/symbols

* Install a Nerd Font and set it in your terminal emulator.
* Restart terminal/editor after linking.

## VS Code extensions didn’t install

* Ensure `code` CLI is on PATH.
* Re-run `./apply.sh Code` (or `\.\apply.ps1 -Packages Code`).

## General sanity checks

```bash
./apply.sh --no          # dry-run to see actions
stow -nvt "$HOME" <pkg>  # show what stow would do
```
