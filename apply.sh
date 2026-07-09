#!/bin/bash
# Stow wrapper for dotfiles management.
set -eo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ARGS=("$@")
DRY_RUN=false
DELETE_MODE=false
STOW_COMMAND="${DOTFILES_STOW_COMMAND:-stow}"
STOW_ARGS=()

for arg in "${ARGS[@]}"; do
    case "$arg" in
        --no-act)
            DRY_RUN=true
            STOW_ARGS+=(--no)
            ;;
        --no|--simulate|-n)
            DRY_RUN=true
            STOW_ARGS+=("$arg")
            ;;
        --delete|-D)
            DELETE_MODE=true
            STOW_ARGS+=("$arg")
            ;;
        -y|--yes)
            # Wrapper-only confirmation flags are never forwarded to Stow.
            ;;
        *)
            STOW_ARGS+=("$arg")
            ;;
    esac
done

install_stow() {
    if command -v "$STOW_COMMAND" >/dev/null 2>&1; then
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        echo "GNU Stow is required to preview dotfile changes; install it and retry." >&2
        return 127
    fi

    if [ "$STOW_COMMAND" != "stow" ]; then
        echo "Configured Stow command '$STOW_COMMAND' was not found." >&2
        return 127
    fi

    echo "Installing GNU Stow..."
    case "$(uname -s)" in
        Darwin)
            if ! command -v brew >/dev/null 2>&1; then
                echo "Homebrew is required to install Stow on macOS." >&2
                return 1
            fi
            brew install stow
            ;;
        Linux)
            if command -v apt-get >/dev/null 2>&1; then
                sudo apt-get install -y stow
            elif command -v apt >/dev/null 2>&1; then
                sudo apt install -y stow
            else
                echo "No supported package manager found; install GNU Stow manually." >&2
                return 1
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "Use apply.ps1 on Windows, or install GNU Stow before retrying." >&2
            return 1
            ;;
        *)
            echo "Unsupported platform; install GNU Stow manually." >&2
            return 1
            ;;
    esac

    hash -r
    if ! command -v stow >/dev/null 2>&1; then
        echo "GNU Stow installation completed, but 'stow' is still unavailable in PATH." >&2
        return 1
    fi
}

stow_package() {
    local pkg="$1"
    local dir rel_path target_path item item_name

    [ -d "$pkg" ] || return 0
    echo "📦 Applying $pkg package"

    # Keep configuration roots as real directories so unrelated files can coexist.
    # Deletion must not manufacture a directory tree in an otherwise empty HOME.
    if [ "$DELETE_MODE" = false ]; then
        while IFS= read -r -d '' dir; do
            rel_path="${dir#"$pkg"/}"
            target_path="$HOME/$rel_path"

            if [ -e "$target_path" ] || [ -L "$target_path" ]; then
                continue
            fi

            if [ "$DRY_RUN" = true ]; then
                echo "  [DRY RUN] Would create directory $target_path"
            else
                mkdir -p "$target_path"
            fi
        done < <(find "$pkg" -mindepth 1 -type d -print0)
    fi

    "$STOW_COMMAND" --target="$HOME" --verbose=1 "${STOW_ARGS[@]}" "$pkg"

    if [ "$DRY_RUN" = true ] || [ "$DELETE_MODE" = true ]; then
        return 0
    fi

    if ! command -v chkstow >/dev/null 2>&1; then
        return 0
    fi

    echo "🔍 Checking stowed directories for $pkg package..."
    for item in "$pkg"/.[!.]* "$pkg"/..?* "$pkg"/*; do
        if [ ! -e "$item" ] && [ ! -L "$item" ]; then
            continue
        fi

        item_name="$(basename "$item")"
        target_path="$HOME/$item_name"
        case "$item_name" in
            Library|Caches|Cache|.cache)
                continue
                ;;
        esac

        if [ -d "$target_path" ]; then
            chkstow --badlinks -t "$target_path" 2>/dev/null || true
            chkstow --aliens -t "$target_path" 2>/dev/null | head -20 || true
            chkstow --list -t "$target_path" 2>/dev/null | head -10 || true
        fi
    done
}

run_local_apply() {
    local local_apply="$HOME/dotfiles-local/apply.sh"
    if [ -x "$local_apply" ]; then
        echo "🔗 Found dotfiles-local, applying..."
        "$local_apply" "${ARGS[@]}"
    fi
}

install_stow
stow_package common

case "$(uname -s)" in
    Darwin)
        echo "🍎 macOS detected"
        stow_package mac
        ;;
    Linux)
        echo "🐧 Linux detected"
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

if [ "$DRY_RUN" = true ]; then
    echo "✅ Dry run completed - no changes were made"
elif [ "$DELETE_MODE" = true ]; then
    echo "✅ Dotfiles removed"
else
    echo "✅ Stow operation completed"
fi
