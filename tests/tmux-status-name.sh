#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$root/common/.local/bin/tmux-status-name.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/home" "$tmp/plain"
git_root="$tmp/repo"
mkdir -p "$git_root/sub/dir"
git -C "$git_root" init -q
monorepo_root="$tmp/monorepo"
mkdir -p "$monorepo_root/apps/api/src"
git -C "$monorepo_root" init -q
touch "$monorepo_root/apps/api/package.json"
jj_root="$tmp/jj repo"
mkdir -p "$jj_root/.jj" "$jj_root/sub/dir"
vscode_root="$tmp/vscode repo"
mkdir -p "$vscode_root/.vscode" "$vscode_root/sub/dir"
node_root="$tmp/node app"
mkdir -p "$node_root/packages/api/src"
touch "$node_root/package.json"
nested_vscode_node_root="$tmp/nested vscode node"
mkdir -p "$nested_vscode_node_root/app/.vscode" "$nested_vscode_node_root/app/src"
touch "$nested_vscode_node_root/package.json"
python_root="$tmp/python app"
mkdir -p "$python_root/src/app"
touch "$python_root/pyproject.toml"
requirements_root="$tmp/requirements app"
mkdir -p "$requirements_root/scripts/tools"
touch "$requirements_root/requirements.txt"
turbo_root="$tmp/turbo app"
mkdir -p "$turbo_root/apps/web/src"
touch "$turbo_root/turbo.json"
nx_root="$tmp/nx app"
mkdir -p "$nx_root/apps/web/src"
touch "$nx_root/nx.json"
angular_root="$tmp/angular app"
mkdir -p "$angular_root/projects/web/src"
touch "$angular_root/angular.json"
lerna_root="$tmp/lerna app"
mkdir -p "$lerna_root/packages/web/src"
touch "$lerna_root/lerna.json"
rush_root="$tmp/rush app"
mkdir -p "$rush_root/apps/web/src"
touch "$rush_root/rush.json"
tsconfig_root="$tmp/tsconfig app"
mkdir -p "$tsconfig_root/src/components"
touch "$tsconfig_root/tsconfig.json"
poetry_root="$tmp/poetry app"
mkdir -p "$poetry_root/src/app"
touch "$poetry_root/poetry.lock"
pixi_root="$tmp/pixi app"
mkdir -p "$pixi_root/src/app"
touch "$pixi_root/pixi.toml"
compose_root="$tmp/compose app"
mkdir -p "$compose_root/services/api"
touch "$compose_root/compose.yaml"
just_root="$tmp/just app"
mkdir -p "$just_root/tools/scripts"
touch "$just_root/Justfile"
taskfile_root="$tmp/task app"
mkdir -p "$taskfile_root/services/api"
touch "$taskfile_root/Taskfile.yml"
bazel_root="$tmp/bazel app"
mkdir -p "$bazel_root/pkg/lib"
touch "$bazel_root/MODULE.bazel"
swift_root="$tmp/swift app"
mkdir -p "$swift_root/Sources/App"
touch "$swift_root/Package.swift"
go_work_root="$tmp/go workspace"
mkdir -p "$go_work_root/services/api"
touch "$go_work_root/go.work"
stack_root="$tmp/stack workspace"
mkdir -p "$stack_root/app/src"
touch "$stack_root/stack.yaml"
rebar_root="$tmp/rebar workspace"
mkdir -p "$rebar_root/apps/api/src"
touch "$rebar_root/rebar.config"
dune_root="$tmp/dune workspace"
mkdir -p "$dune_root/lib/src"
touch "$dune_root/dune-project"
devcontainer_root="$tmp/devcontainer app"
mkdir -p "$devcontainer_root/.devcontainer" "$devcontainer_root/app/src"
canonical_root="$tmp/canonical status root"
canonical_link="$tmp/canonical status link"
mkdir -p "$canonical_root/src"
touch "$canonical_root/package.json"

assert_name() {
  local name="$1"
  local path="$2"
  local command="$3"
  local expected="$4"
  local actual

  actual="$(HOME="$tmp/home" "$helper" "$path" "$command")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'not ok - %s\n' "$name" >&2
    printf 'expected: %s\nactual: %s\n' "$expected" "$actual" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

assert_eq() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$actual" != "$expected" ]]; then
    printf 'not ok - %s\n' "$name" >&2
    printf 'expected: %s\nactual: %s\n' "$expected" "$actual" >&2
    return 1
  fi

  printf 'ok - %s\n' "$name"
}

assert_name "home shell uses tilde" "$tmp/home" zsh "~"
assert_name "home program shows command" "$tmp/home" nvim "~:nvim"
assert_name "git workspace uses repo name" "$git_root/sub/dir" bash "$(basename "$git_root")"
assert_name "nested marker beats outer git root" "$monorepo_root/apps/api/src" bash api
assert_name "jj workspace uses repo name" "$jj_root/sub/dir" bash "$(basename "$jj_root")"
assert_name "vscode workspace uses repo name" "$vscode_root/sub/dir" bash "$(basename "$vscode_root")"
assert_name "package marker workspace uses repo name" "$node_root/packages/api/src" bash "$(basename "$node_root")"
assert_name \
  "nested vscode falls back behind package marker" \
  "$nested_vscode_node_root/app/src" \
  bash \
  "$(basename "$nested_vscode_node_root")"
assert_name "pyproject workspace uses repo name" "$python_root/src/app" bash "$(basename "$python_root")"
assert_name "requirements workspace uses repo name" "$requirements_root/scripts/tools" bash "$(basename "$requirements_root")"
assert_name "turbo workspace uses repo name" "$turbo_root/apps/web/src" bash "$(basename "$turbo_root")"
assert_name "nx workspace uses repo name" "$nx_root/apps/web/src" bash "$(basename "$nx_root")"
assert_name "angular workspace uses repo name" "$angular_root/projects/web/src" bash "$(basename "$angular_root")"
assert_name "lerna workspace uses repo name" "$lerna_root/packages/web/src" bash "$(basename "$lerna_root")"
assert_name "rush workspace uses repo name" "$rush_root/apps/web/src" bash "$(basename "$rush_root")"
assert_name "tsconfig workspace uses repo name" "$tsconfig_root/src/components" bash "$(basename "$tsconfig_root")"
assert_name "poetry workspace uses repo name" "$poetry_root/src/app" bash "$(basename "$poetry_root")"
assert_name "pixi workspace uses repo name" "$pixi_root/src/app" bash "$(basename "$pixi_root")"
assert_name "compose workspace uses repo name" "$compose_root/services/api" bash "$(basename "$compose_root")"
assert_name "justfile workspace uses repo name" "$just_root/tools/scripts" bash "$(basename "$just_root")"
assert_name "taskfile workspace uses repo name" "$taskfile_root/services/api" bash "$(basename "$taskfile_root")"
assert_name "bazel module workspace uses repo name" "$bazel_root/pkg/lib" bash "$(basename "$bazel_root")"
assert_name "swift package workspace uses repo name" "$swift_root/Sources/App" bash "$(basename "$swift_root")"
assert_name "go workspace uses repo name" "$go_work_root/services/api" bash "$(basename "$go_work_root")"
assert_name "stack workspace uses repo name" "$stack_root/app/src" bash "$(basename "$stack_root")"
assert_name "rebar workspace uses repo name" "$rebar_root/apps/api/src" bash "$(basename "$rebar_root")"
assert_name "dune workspace uses repo name" "$dune_root/lib/src" bash "$(basename "$dune_root")"
assert_name "devcontainer workspace uses repo name" "$devcontainer_root/app/src" bash "$(basename "$devcontainer_root")"
assert_name \
  "parent traversal status uses canonical marker root" \
  "$canonical_root/src/../src" \
  bash \
  "$(basename "$canonical_root")"
if ln -s "$canonical_root" "$canonical_link" 2>/dev/null; then
  assert_name \
    "symlinked status path uses real project name" \
    "$canonical_link/src" \
    bash \
    "$(basename "$canonical_root")"
fi
assert_name "full command path uses basename" "$git_root/sub/dir" /opt/homebrew/bin/nvim "$(basename "$git_root"):nvim"
assert_name "Windows command suffix is normalized" "$git_root/sub/dir" nvim.exe "$(basename "$git_root"):nvim"
assert_name "Windows command path uses basename" "$git_root/sub/dir" 'C:\tools\ssh.exe' "$(basename "$git_root"):ssh"
assert_name "Windows drive current path uses basename" 'C:\Users\sky\Project App' bash "Project App"
assert_name "Windows UNC current path uses basename" '\\server\share\Project App' bash "Project App"
assert_name "Windows UNC current path with command uses basename" '\\server\share\Project App' nvim.exe "Project App:nvim"
assert_name "Windows slash UNC current path uses basename" '//server/share/Project App' bash "Project App"
assert_name "Windows slash UNC current path with command uses basename" '//server/share/Project App' nvim.exe "Project App:nvim"
assert_name "login shell is suppressed" "$tmp/plain" -zsh plain
assert_name "Windows login shell suffix is suppressed" "$tmp/plain" -zsh.exe plain
assert_name "plain directory fallback" "$tmp/plain" fish plain
assert_name "modern shell is suppressed" "$tmp/plain" /opt/homebrew/bin/nu plain
assert_name "powershell is suppressed" "$tmp/plain" pwsh plain
assert_name "Windows powershell path is suppressed" "$tmp/plain" 'C:\tools\pwsh.exe' plain
assert_name "Windows cmd shell is suppressed" "$tmp/plain" cmd plain
assert_name "Windows cmd.exe path is suppressed" "$tmp/plain" 'C:\Windows\System32\cmd.exe' plain
assert_name "google cloud path uses workspace segment" /google/src/cloud/user/workspace/project bash workspace
assert_name "empty path fallback" "" "" tmux

no_git_bin="$tmp/no-git-bin"
no_git_stderr="$tmp/no-git.stderr"
mkdir -p "$no_git_bin"
ln -s "$(command -v bash)" "$no_git_bin/bash"
no_git_status="$(
  HOME="$tmp/home" \
    PATH="$no_git_bin" \
    "$helper" "$tmp/plain" bash 2>"$no_git_stderr"
)"
assert_eq "missing git falls back to directory name" plain "$no_git_status"
assert_eq "missing git is quiet" "" "$(<"$no_git_stderr")"
