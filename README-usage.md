# Dotfiles Usage Guide

## Scripts

### `init.sh` - First-time setup

```bash
./init.sh
```

- Installs dotfiles with `--adopt` (takes over existing files)
- Installs VS Code extensions
- Optionally installs common development tools

### `apply.sh` - Stow wrapper

```bash
./apply.sh [STOW_OPTIONS]
```

Direct wrapper around stow with sensible defaults. Passes all arguments to stow.

### `update.sh` - Update from remote
```bash
./update.sh
# or
stow_update
```
Pulls latest changes from the repository and applies them using `--restow`.

## Common Operations

### 📦 **First install**

```bash
./init.sh
```

### 🔍 **Preview changes**

```bash
./apply.sh --no              # Dry-run, see what would happen
./apply.sh --no --verbose    # Dry-run with detailed output
```

### 🔄 **Update existing**

```bash
stow_update                  # Pull latest from repo and apply
./apply.sh --restow          # Re-install everything
./apply.sh                   # Normal stow (only new packages)
```

### ⚠️ **Handle conflicts**

```bash
./apply.sh --adopt           # Take over existing files
./apply.sh --no --adopt      # Preview what would be adopted
```

### 🗑️ **Remove dotfiles**

```bash
./apply.sh --delete          # Remove all symlinks
```

### 🎯 **Advanced operations**

```bash
./apply.sh --restow --verbose=2    # Verbose restow
./apply.sh --ignore="*.log"        # Ignore log files
./apply.sh --no --adopt --verbose  # Preview adoption with details
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
