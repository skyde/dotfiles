#!/usr/bin/env bash

DRY_RUN=${DRY_RUN:-0}

maybe_run() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "DRY_RUN: $*"
  else
    "$@"
  fi
}

# initialize_backup_dir
# Creates a timestamped backup directory under $HOME for this run.
initialize_backup_dir() {
  if [ -n "${backup_dir:-}" ]; then
    return 0
  fi
  local ts
  ts=$(date +%Y%m%d_%H%M%S)
  backup_dir="$HOME/.dotfiles_backup_$ts"
  mkdir -p "$backup_dir"
}

# ensure_parent "path/to/file/or/dir"
ensure_parent() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
}

# ensure_file_exists removed (unused)

# backup_conflict_into_repo_backup "absolute-target-path"
backup_conflict_into_repo_backup() {
  local target="$1"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    local rel
    if [[ "$target" == "$HOME"/* ]]; then
      rel="${target#"$HOME/"}"
      ensure_parent "$backup_dir/$rel"
      maybe_run mv "$target" "$backup_dir/$rel"
    else
      maybe_run mv "$target" "$target.bak"
    fi
  fi
}

# ensure_symlink_with_backup "src" "dest"
ensure_symlink_with_backup() {
  local src="$1"
  local dest="$2"
  ensure_parent "$dest"
  backup_conflict_into_repo_backup "$dest"
  if [ -L "$dest" ]; then
    local current
    current=$(readlink "$dest") || current=""
    if [ "$current" != "$src" ]; then
      maybe_run rm -f "$dest"
      maybe_run ln -s "$src" "$dest"
    fi
    return 0
  fi
  maybe_run ln -s "$src" "$dest"
}

# restow_package "pkg_name" [target_dir]
restow_package() {
  local pkg="$1"
  local target_dir="${2:-$HOME}"

  if [ ! -d "$pkg" ] || ! find "$pkg" -type f -print -quit | grep -q "."; then
    return 0
  fi

  while IFS= read -r -d '' path; do
    local rel_path
    rel_path=${path#"$pkg/"}
    local target="$target_dir/$rel_path"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
      local dest="$backup_dir/$rel_path"
      ensure_parent "$dest"
      maybe_run mv "$target" "$dest"
    fi
  done < <(find "$pkg" -mindepth 1 -type f -print0)

  while IFS= read -r -d '' dir; do
    local rel_path
    rel_path=${dir#"$pkg/"}
    [ -z "$rel_path" ] && continue
    local target="$target_dir/$rel_path"
    # Skip backing up top-level aggregator directories (e.g. ".config")
    # Only back up nested directories like ".config/git" so we don't
    # repeatedly move the entire ".config" directory for each package.
    if [[ "$rel_path" != */* ]]; then
      continue
    fi
    if [ -d "$target" ] && [ ! -L "$target" ]; then
      local dest="$backup_dir/$rel_path"
      if [ ! -e "$dest" ]; then
        ensure_parent "$dest"
        maybe_run mv "$target" "$dest" || true
      fi
    fi
  done < <(find "$pkg" -type d -print0)

  if [ "$DRY_RUN" = "1" ]; then
    echo "DRY_RUN: stow --restow --target=\"$target_dir\" \"$pkg\""
  else
    stow --restow --target="$target_dir" "$pkg"
  fi
}

# process_symlink_pairs pairs...
# Each argument must be "<src>::<dest>"
process_symlink_pairs() {
  local entry src dest
  for entry in "$@"; do
    src="${entry%%::*}"
    dest="${entry##*::}"
    ensure_symlink_with_backup "$src" "$dest" || true
  done
}


