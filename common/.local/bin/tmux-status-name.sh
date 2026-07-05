#!/usr/bin/env bash
set -euo pipefail

# Get the current path and command from arguments
current_path="${1:-}"
current_command="${2:-}"

workspace=""
workspace_markers=(
  ".git"
  ".jj"
  ".devcontainer"
  "CMakeLists.txt"
  "Makefile"
  "Justfile"
  "justfile"
  "Taskfile.yml"
  "Taskfile.yaml"
  "taskfile.yml"
  "taskfile.yaml"
  "package.json"
  "pnpm-workspace.yaml"
  "package-lock.json"
  "pnpm-lock.yaml"
  "yarn.lock"
  "bun.lock"
  "bun.lockb"
  "bunfig.toml"
  "tsconfig.json"
  "jsconfig.json"
  "vite.config.js"
  "vite.config.ts"
  "next.config.js"
  "next.config.ts"
  "eslint.config.js"
  "eslint.config.mjs"
  "eslint.config.ts"
  "turbo.json"
  "nx.json"
  "angular.json"
  "lerna.json"
  "rush.json"
  "biome.json"
  "biome.jsonc"
  "pyproject.toml"
  "poetry.lock"
  "pdm.lock"
  "pixi.toml"
  "pixi.lock"
  "uv.lock"
  "requirements.txt"
  "pyrightconfig.json"
  "ruff.toml"
  "mypy.ini"
  "setup.py"
  "setup.cfg"
  "tox.ini"
  "pytest.ini"
  "Pipfile"
  "Cargo.toml"
  "stack.yaml"
  "cabal.project"
  "package.yaml"
  "Package.swift"
  "go.mod"
  "go.work"
  "WORKSPACE"
  "WORKSPACE.bazel"
  "MODULE.bazel"
  "deno.json"
  "deno.jsonc"
  "deno.lock"
  "flake.nix"
  ".tool-versions"
  ".mise.toml"
  "mise.toml"
  "meson.build"
  "build.gradle"
  "build.gradle.kts"
  "settings.gradle"
  "settings.gradle.kts"
  "pom.xml"
  "composer.json"
  "Gemfile"
  "Rakefile"
  "gradlew"
  "compose.yaml"
  "compose.yml"
  "docker-compose.yaml"
  "docker-compose.yml"
  "mix.exs"
  "rebar.config"
  "gleam.toml"
  "dune-project"
  "dune-workspace"
)
fallback_workspace_markers=(
  ".vscode"
)

is_windows_absolute_path() {
  [[ "$1" =~ ^[A-Za-z]:[\\/] || "$1" == \\\\* || "$1" == //* ]]
}

normalize_windows_absolute_path() {
  local path="$1"

  if is_windows_absolute_path "$path"; then
    path="${path//\\//}"
  fi

  printf '%s\n' "$path"
}

canonical_path() {
  local path="$1"
  local resolved dir base

  path="$(normalize_windows_absolute_path "$path")"
  if [[ "$path" =~ ^[A-Za-z]:/ || "$path" == //* ]]; then
    printf '%s\n' "$path"
    return
  fi

  if [[ "$path" == "/" ]]; then
    printf '/\n'
    return
  fi

  if command -v realpath >/dev/null 2>&1 && resolved="$(realpath "$path" 2>/dev/null)"; then
    printf '%s\n' "$resolved"
    return
  fi

  if command -v grealpath >/dev/null 2>&1 && resolved="$(grealpath -m "$path" 2>/dev/null)"; then
    printf '%s\n' "$resolved"
    return
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$path"
    return
  fi

  dir="$(parent_dir "$path")"
  base="$(base_name "$path")"
  if [[ -d "$dir" ]]; then
    (cd -- "$dir" && printf '%s/%s\n' "$PWD" "$base")
  else
    printf '%s\n' "$path"
  fi
}

base_name() {
  local path="${1%/}"

  path="${path##*/}"
  printf '%s\n' "${path:-/}"
}

parent_dir() {
  local path="${1%/}"

  if [[ -z "$path" || "$path" == "/" ]]; then
    printf '/\n'
    return
  fi
  if [[ "$path" =~ ^[A-Za-z]:$ || ( "$path" != */* && "$path" != *\\* ) ]]; then
    printf '/\n'
    return
  fi

  path="${path%/*}"
  printf '%s\n' "${path:-/}"
}

command_name() {
  local command="$1"

  command="${command##*/}"
  command="${command##*\\}"
  command="${command#-}"
  case "$command" in
    *.[eE][xX][eE] | *.[cC][mM][dD] | *.[bB][aA][tT])
      command="${command%.*}"
      ;;
  esac

  printf '%s\n' "$command"
}

if [[ -n "$current_path" ]]; then
  current_path="$(canonical_path "$current_path")"
fi
home_path="${HOME:-}"
if [[ -n "$home_path" ]]; then
  home_path="$(canonical_path "$home_path")"
fi

find_marker_root() {
  local current="$1"
  local marker="$2"
  local next

  found_marker_root=""

  [[ -n "$current" ]] || return 1
  while [[ "$current" != "/" && -n "$current" ]]; do
    if [[ -e "$current/$marker" ]]; then
      found_marker_root="$current"
      return 0
    fi

    next="${current%/}"
    next="${next%/*}"
    [[ "$next" != "$current" ]] || break
    current="${next:-/}"
  done

  return 1
}

find_workspace_root() {
  local marker marker_dir best_dir=""

  found_workspace_root=""
  for marker in "$@"; do
    if find_marker_root "$current_path" "$marker"; then
      marker_dir="$found_marker_root"
    else
      marker_dir=""
    fi
    if [[ -n "$marker_dir" && ${#marker_dir} -gt ${#best_dir} ]]; then
      best_dir="$marker_dir"
    fi
  done

  [[ -n "$best_dir" ]] || return 1
  found_workspace_root="$best_dir"
}

if [[ -n "$home_path" && "$current_path" == "$home_path" ]]; then
  workspace="~"
elif [[ "$current_path" =~ ^/google/src/cloud/[^/]+/([^/]+) ]]; then
  workspace="${BASH_REMATCH[1]}"
fi

# 2. Detect marker-based workspaces. This intentionally runs before the Git
# fallback so nested projects in monorepos can use their nearest marker.
if [[ -z "$workspace" && -n "$current_path" ]]; then
  if find_workspace_root "${workspace_markers[@]}"; then
    marker_dir="$found_workspace_root"
  else
    marker_dir=""
  fi
  if [[ -z "$marker_dir" ]]; then
    if find_workspace_root "${fallback_workspace_markers[@]}"; then
      marker_dir="$found_workspace_root"
    else
      marker_dir=""
    fi
  fi
  if [[ -n "$marker_dir" ]]; then
    workspace="$(base_name "$marker_dir")"
  fi
fi

# 2b. Fall back to Git's repository root for unusual worktree layouts where a
# marker file is not visible in the path tmux reports.
if [[ -z "$workspace" && -n "$current_path" ]]; then
  if command -v git >/dev/null 2>&1; then
    git_dir="$(git -C "$current_path" rev-parse --show-toplevel 2>/dev/null || true)"
  else
    git_dir=""
  fi
  if [[ -n "$git_dir" ]]; then
    workspace="$(base_name "$git_dir")"
  fi
fi

# 3. Fallback to current directory name
if [[ -z "$workspace" && -n "$current_path" ]]; then
  workspace="$(base_name "$current_path")"
fi
if [[ -z "$workspace" ]]; then
  workspace="tmux"
fi

# Process command. tmux normally reports the command basename, but normalize
# defensively so login shells or full paths still collapse to the workspace.
cmd="$(command_name "$current_command")"
# Ignore common shells
if [[ "$cmd" =~ ^(bash|zsh|fish|sh|dash|ksh|nu|nushell|pwsh|powershell|cmd|xonsh)$ ]]; then
  cmd=""
fi

# Output the result
if [[ -n "$cmd" ]]; then
  printf '%s:%s\n' "$workspace" "$cmd"
else
  printf '%s\n' "$workspace"
fi
