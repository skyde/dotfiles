# Dotfiles Usage Guide

## Scripts

### `init.sh` / `init.ps1` - First-time setup

**Unix/Linux/macOS:**

```bash
./init.sh
```

**Windows:**

```powershell
./init.ps1
```

- Installs dotfiles with `--adopt` (takes over existing files)
- Prompts to install VS Code extensions
- Prompts to install common development tools

### `apply.sh` / `apply.ps1` - Stow wrapper

**Unix/Linux/macOS:**

```bash
./apply.sh [STOW_OPTIONS]
```

**Windows:**

```powershell
./apply.ps1 [STOW_OPTIONS]
```

Direct wrapper around stow with sensible defaults. Passes all arguments to stow.

### `update.sh` / `update.ps1` - Update from remote

**Unix/Linux/macOS:**

```bash
./update.sh
# or
stow_update
```

**Windows:**

```powershell
./update.ps1
```

Pulls latest changes from the repository and applies them using `--restow`.

## Common Operations

### 📦 **First install**

**Unix/Linux/macOS:**

```bash
./init.sh
```

**Windows:**

```powershell
./init.ps1
```

### 🔍 **Preview changes**

**Unix/Linux/macOS:**

```bash
./apply.sh --no              # Dry-run, see what would happen
./apply.sh --no --verbose    # Dry-run with detailed output
```

**Windows:**

```powershell
./apply.ps1 --no             # Dry-run, see what would happen
./apply.ps1 --no --verbose   # Dry-run with detailed output
```

### 🔄 **Update existing**

**Unix/Linux/macOS:**

```bash
./update.sh                  # Pull latest from repo and apply
./apply.sh --restow          # Re-install everything
./apply.sh                   # Normal stow (only new packages)
```

**Windows:**

```powershell
./update.ps1                 # Pull latest from repo and apply
./apply.ps1 --restow         # Re-install everything
./apply.ps1                  # Normal stow (only new packages)
```

### ⚠️ **Handle conflicts**

**Unix/Linux/macOS:**

```bash
./apply.sh --adopt           # Take over existing files
./apply.sh --no --adopt      # Preview what would be adopted
```

**Windows:**

```powershell
./apply.ps1 --adopt          # Take over existing files
./apply.ps1 --no --adopt     # Preview what would be adopted
```

### 🗑️ **Remove dotfiles**

**Unix/Linux/macOS:**

```bash
./apply.sh --delete          # Remove all symlinks
```

**Windows:**

```powershell
./apply.ps1 --delete         # Remove all symlinks
```

### 🎯 **Advanced operations**

**Unix/Linux/macOS:**

```bash
./apply.sh --restow --verbose=2    # Verbose restow
./apply.sh --ignore="*.log"        # Ignore log files
./apply.sh --no --adopt --verbose  # Preview adoption with details
```

**Windows:**

```powershell
./apply.ps1 --restow --verbose=2   # Verbose restow
./apply.ps1 --ignore="*.log"       # Ignore log files
./apply.ps1 --no --adopt --verbose # Preview adoption with details
```

## Stow Arguments Reference

| Flag             | Description                 |
| ---------------- | --------------------------- |
| `--no`           | Dry-run (simulate only)     |
| `--verbose`      | Show what's happening       |
| `--adopt`        | Take over existing files    |
| `--restow`       | Re-install (unlink + link)  |
| `--delete`       | Remove symlinks             |
| `--ignore=REGEX` | Skip files matching pattern |

## Examples

**Unix/Linux/macOS:**

```bash
# First time setup
./init.sh

# Update from remote repository
./update.sh

# See what would happen before adopting conflicts
./apply.sh --no --adopt

# Actually adopt conflicts
./apply.sh --adopt

# Update after local changes to dotfiles
./apply.sh --restow

# Remove everything
./apply.sh --delete
```

**Windows:**

```powershell
# First time setup
./init.ps1

# Update from remote repository
./update.ps1

# See what would happen before adopting conflicts
./apply.ps1 --no --adopt

# Actually adopt conflicts
./apply.ps1 --adopt

# Update after local changes to dotfiles
./apply.ps1 --restow

# Remove everything
./apply.ps1 --delete
```
