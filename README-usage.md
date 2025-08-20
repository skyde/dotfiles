# Dotfiles Usage Guide

## Scripts

### `install.sh` - First-time setup

```bash
./install.sh
```

- Installs dotfiles with `--adopt` (takes over existing files)
- Installs VS Code extensions
- Optionally installs common development tools

### `update.sh` - Stow wrapper

```bash
./update.sh [STOW_OPTIONS]
```

Direct wrapper around stow with sensible defaults. Passes all arguments to stow.

## Common Operations

### 📦 **First install**

```bash
./install.sh
```

### 🔍 **Preview changes**

```bash
./update.sh --no              # Dry-run, see what would happen
./update.sh --no --verbose    # Dry-run with detailed output
```

### 🔄 **Update existing**

```bash
./update.sh --restow          # Re-install everything
./update.sh                   # Normal stow (only new packages)
```

### ⚠️ **Handle conflicts**

```bash
./update.sh --adopt           # Take over existing files
./update.sh --no --adopt      # Preview what would be adopted
```

### 🗑️ **Remove dotfiles**

```bash
./update.sh --delete          # Remove all symlinks
```

### 🎯 **Advanced operations**

```bash
./update.sh --restow --verbose=2    # Verbose restow
./update.sh --ignore="*.log"        # Ignore log files
./update.sh --no --adopt --verbose  # Preview adoption with details
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
./install.sh

# See what would happen before adopting conflicts
./update.sh --no --adopt

# Actually adopt conflicts
./update.sh --adopt

# Update after making changes to dotfiles
./update.sh --restow

# Remove everything
./update.sh --delete
```
