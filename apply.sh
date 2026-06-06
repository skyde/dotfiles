#!/bin/bash
# Stow wrapper for dotfiles management
set -e

usage() {
    cat <<'EOF'
Usage: ./apply.sh [stow options]

Apply dotfile symlinks with GNU Stow.

Common options:
  -n, --no, --no-act, --simulate  Preview changes without writing links
  -D, --delete                    Remove stowed links
  --adopt                         Adopt existing target files into the package
  -y, --yes                       Forwarded to local apply hooks, ignored by Stow
  -h, --help                      Show this help message

Any other options are passed through to stow.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            usage
            exit 0
            ;;
    esac
done

# Parse arguments to detect dry-run mode
DRY_RUN=false
ARGS=("$@")  # Pass through all arguments
LOCAL_APPLY_RAN=false

for arg in "$@"; do
    case $arg in
        --no-act|--no|--simulate|-n)
            DRY_RUN=true
            ;;
    esac
done

run_local_apply() {
    if ! $LOCAL_APPLY_RAN && [ -x "$HOME/dotfiles-local/apply.sh" ]; then
        echo "🔗 Found dotfiles-local, applying..."
        "$HOME/dotfiles-local/apply.sh" "${ARGS[@]}"
        LOCAL_APPLY_RAN=true
    fi
}

install_stow() {
    echo "Installing stow..."

    case "$(uname)" in
        Darwin)
            if command -v brew >/dev/null; then
                brew install stow
            else
                echo "error: Homebrew is not installed; install stow first, then rerun apply.sh" >&2
                return 1
            fi
            ;;
        Linux)
            if ! command -v apt-get >/dev/null; then
                echo "error: stow is not installed; install it with your package manager, then rerun apply.sh" >&2
                return 1
            fi

            if [ "$(id -u)" -eq 0 ]; then
                apt-get update
                apt-get install -y stow
            elif command -v sudo >/dev/null && sudo -n true 2>/dev/null; then
                sudo apt-get update
                sudo apt-get install -y stow
            elif [ -t 0 ]; then
                sudo apt-get update
                sudo apt-get install stow
            else
                echo "error: stow is not installed and sudo is not available non-interactively" >&2
                echo "       Install stow first, then rerun apply.sh" >&2
                return 1
            fi
            ;;
        *)
            echo "error: stow is not installed; install it with your package manager, then rerun apply.sh" >&2
            return 1
            ;;
    esac
}

# Install stow if needed
if ! command -v stow >/dev/null; then
    if $DRY_RUN; then
        echo "[DRY RUN] Would install stow"
        echo "[DRY RUN] stow is required to preview package changes; skipping stow packages"
        run_local_apply
        echo "✅ Dry run completed - no changes were made"
        exit 0
    else
        install_stow
    fi
fi

if ! command -v stow >/dev/null; then
    echo "error: stow is not installed and could not be installed automatically" >&2
    exit 1
fi

# Go to script directory
cd "$(dirname "$0")"

stow_package() {
    local pkg="$1"
    shift
    [ -d "$pkg" ] || return 0
    echo "📦 Installing $pkg package"

    # Pre-create directories safely (never remove or replace existing paths)
    if [ -d "$pkg" ]; then
        echo "  Ensuring directories exist for $pkg..."
        find "$pkg" -mindepth 1 -type d | sort | while read -r dir; do
            rel_path="${dir#"$pkg"/}"
            target_path="$HOME/$rel_path"

            # If anything already exists at the target path (dir, file, or symlink),
            # do nothing.
            if [ -e "$target_path" ] || [ -L "$target_path" ]; then
                continue
            fi

            if $DRY_RUN; then
                echo "  [DRY RUN] Would create directory $target_path"
            else
                mkdir -p -- "$target_path"
            fi
        done
    fi

    # Filter out -y/--yes from stow arguments
    local STOW_ARGS=()
    for arg in "${ARGS[@]}"; do
        if [[ "$arg" != "-y" ]] && [[ "$arg" != "--yes" ]]; then
            STOW_ARGS+=("$arg")
        fi
    done

    # Use restow to handle any conflicts or missing symlinks
    stow --target="$HOME" --verbose=1 "${STOW_ARGS[@]}" "$pkg"

    if $DRY_RUN; then
        echo "  [DRY RUN] Skipping verification"
        return 0
    fi

    # Check only the directories that this package actually affects
    # Skip problematic directories like Library which can have massive cache data
    if [ -d "$pkg" ]; then
        echo "🔍 Checking stowed files for $pkg package..."
        for item in "$pkg"/*; do
            if [ -e "$item" ]; then
                item_name=$(basename "$item")
                target_path="$HOME/$item_name"
                
                # Skip Library and other problematic directories
                case "$item_name" in
                    Library|Caches|Cache|.cache)
                        echo "  Skipping $item_name (too large/problematic)"
                        continue
                        ;;
                esac
                
                if [ -e "$target_path" ]; then
                    echo "  Checking $target_path..."
                    # Only run chkstow on directories, files are handled by the directory check
                    if [ -d "$target_path" ]; then
                        # Broken symlinks
                        chkstow --badlinks -t "$target_path" 2>/dev/null || true
                        # Non-symlink "alien" files (things Stow doesn't manage) in the target
                        chkstow --aliens -t "$target_path" 2>/dev/null | head -20 || true
                        # What package owns each link
                        chkstow --list -t "$target_path" 2>/dev/null | head -10 || true
                    fi
                fi
            fi
        done
    fi
}

# Stow common package (always)
stow_package common

# Stow platform-specific packages
case "$(uname)" in
    Darwin)
        echo "🍎 macOS detected"
        stow_package mac
        ;;
    Linux)
        echo "🐧 Linux detected"
        # Linux uses common package for VS Code (already stowed above)
        ;;
    MINGW*|MSYS*|CYGWIN*)
        echo "🪟 Windows detected"
        stow_package windows
        ;;
    *)
        echo "ℹ️ Unknown platform - common package only"
        ;;
esac

run_local_apply

if $DRY_RUN; then
    echo "✅ Dry run completed - no changes were made"
else
    echo "✅ Stow operation completed"
fi
