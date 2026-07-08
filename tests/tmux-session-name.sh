#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$root/common/.local/bin/tmux-session-name"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/home" "$tmp/bin"

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

run_helper() {
  HOME="$tmp/home" PATH="/usr/bin:/bin:/usr/sbin:/sbin" "$helper" "$@"
}

plain_path="$tmp/plain app!"
mkdir -p "$plain_path/sub"
assert_eq "plain path basename is sanitized" "plain_app" "$(run_helper "$plain_path")"
assert_eq "home path gets stable session name" "home" "$(run_helper "$tmp/home")"
real_home="$tmp/real home"
home_link="$tmp/home link"
mkdir -p "$real_home"
if ln -s "$real_home" "$home_link" 2>/dev/null; then
  assert_eq \
    "symlinked home path gets stable session name" \
    "home" \
    "$(HOME="$home_link" PATH="/usr/bin:/bin:/usr/sbin:/sbin" "$helper" "$real_home")"
fi
assert_eq "google workspace path uses workspace segment" "workspace" "$(run_helper /google/src/cloud/user/workspace/project)"
assert_eq "Windows drive path uses basename" "Project_App" "$(run_helper 'C:\Users\sky\Project App')"
assert_eq "Windows UNC path uses basename" "Project_App" "$(run_helper '\\server\share\Project App')"
assert_eq "Windows UNC file path uses parent basename" "src" "$(run_helper '\\server\share\Project App\src\main.go')"
assert_eq "Windows slash UNC path uses basename" "Project_App" "$(run_helper '//server/share/Project App')"
assert_eq "Windows slash UNC file path uses parent basename" "src" "$(run_helper '//server/share/Project App/src/main.go')"

root_with_marker="$tmp/Client App!"
mkdir -p "$root_with_marker/services/api/src"
touch "$root_with_marker/services/api/package.json"
assert_eq "nearest package marker names session" "api" "$(run_helper "$root_with_marker/services/api/src")"

swift_root="$tmp/Swift Package"
mkdir -p "$swift_root/Sources/App"
touch "$swift_root/Package.swift"
assert_eq "swift package marker names session" "Swift_Package" "$(run_helper "$swift_root/Sources/App")"

go_workspace_root="$tmp/Go Workspace"
mkdir -p "$go_workspace_root/services/api"
touch "$go_workspace_root/go.work"
assert_eq "go workspace marker names session" "Go_Workspace" "$(run_helper "$go_workspace_root/services/api")"

stack_root="$tmp/Stack Workspace"
mkdir -p "$stack_root/app/src"
touch "$stack_root/stack.yaml"
assert_eq "stack marker names session" "Stack_Workspace" "$(run_helper "$stack_root/app/src")"

rebar_root="$tmp/Rebar Workspace"
mkdir -p "$rebar_root/apps/api/src"
touch "$rebar_root/rebar.config"
assert_eq "rebar marker names session" "Rebar_Workspace" "$(run_helper "$rebar_root/apps/api/src")"

dune_root="$tmp/Dune Workspace"
mkdir -p "$dune_root/lib/src"
touch "$dune_root/dune-project"
assert_eq "dune marker names session" "Dune_Workspace" "$(run_helper "$dune_root/lib/src")"

requirements_root="$tmp/Requirements App"
mkdir -p "$requirements_root/scripts/tools"
touch "$requirements_root/requirements.txt"
assert_eq "requirements marker names session" "Requirements_App" "$(run_helper "$requirements_root/scripts/tools")"

turbo_root="$tmp/Turbo Workspace"
mkdir -p "$turbo_root/apps/web/src"
touch "$turbo_root/turbo.json"
assert_eq "turbo marker names session" "Turbo_Workspace" "$(run_helper "$turbo_root/apps/web/src")"

nx_root="$tmp/Nx Workspace"
mkdir -p "$nx_root/apps/web/src"
touch "$nx_root/nx.json"
assert_eq "nx marker names session" "Nx_Workspace" "$(run_helper "$nx_root/apps/web/src")"

angular_root="$tmp/Angular Workspace"
mkdir -p "$angular_root/projects/web/src"
touch "$angular_root/angular.json"
assert_eq "angular marker names session" "Angular_Workspace" "$(run_helper "$angular_root/projects/web/src")"

lerna_root="$tmp/Lerna Workspace"
mkdir -p "$lerna_root/packages/web/src"
touch "$lerna_root/lerna.json"
assert_eq "lerna marker names session" "Lerna_Workspace" "$(run_helper "$lerna_root/packages/web/src")"

rush_root="$tmp/Rush Workspace"
mkdir -p "$rush_root/apps/web/src"
touch "$rush_root/rush.json"
assert_eq "rush marker names session" "Rush_Workspace" "$(run_helper "$rush_root/apps/web/src")"

tsconfig_root="$tmp/TypeScript Workspace"
mkdir -p "$tsconfig_root/src/components"
touch "$tsconfig_root/tsconfig.json"
assert_eq "tsconfig marker names session" "TypeScript_Workspace" "$(run_helper "$tsconfig_root/src/components")"

poetry_root="$tmp/Poetry Workspace"
mkdir -p "$poetry_root/src/app"
touch "$poetry_root/poetry.lock"
assert_eq "poetry lock marker names session" "Poetry_Workspace" "$(run_helper "$poetry_root/src/app")"

pixi_root="$tmp/Pixi Workspace"
mkdir -p "$pixi_root/src/app"
touch "$pixi_root/pixi.toml"
assert_eq "pixi marker names session" "Pixi_Workspace" "$(run_helper "$pixi_root/src/app")"

compose_root="$tmp/Compose Workspace"
mkdir -p "$compose_root/services/api"
touch "$compose_root/compose.yaml"
assert_eq "compose marker names session" "Compose_Workspace" "$(run_helper "$compose_root/services/api")"

devcontainer_root="$tmp/Dev Container Only"
mkdir -p "$devcontainer_root/.devcontainer" "$devcontainer_root/app/src"
assert_eq "devcontainer marker names session" "Dev_Container_Only" "$(run_helper "$devcontainer_root/app/src")"

fallback_vscode="$tmp/VS Code Only"
mkdir -p "$fallback_vscode/.vscode" "$fallback_vscode/app"
assert_eq "vscode fallback marker names session" "VS_Code_Only" "$(run_helper "$fallback_vscode/app")"

nested_vscode="$tmp/Nested VS Code"
mkdir -p "$nested_vscode/app/.vscode" "$nested_vscode/app/src"
touch "$nested_vscode/package.json"
assert_eq "primary marker beats nested vscode marker" "Nested_VS_Code" "$(run_helper "$nested_vscode/app/src")"

relative_root="$tmp/Relative Root"
mkdir -p "$relative_root/src"
touch "$relative_root/pyproject.toml"
(
  cd "$relative_root"
  assert_eq "relative new file uses cwd marker" "Relative_Root" "$(run_helper src/new-file.py)"
)

dash_root="$tmp/--Dash Workspace"
mkdir -p "$dash_root/src"
touch "$dash_root/package.json"
(
  cd "$tmp"
  assert_eq "delimiter allows dash-prefixed path" "--Dash_Workspace" "$(run_helper -- "--Dash Workspace/src")"
)

canonical_root="$tmp/Canonical Root"
canonical_link="$tmp/Canonical Link"
mkdir -p "$canonical_root/src"
touch "$canonical_root/package.json"
assert_eq \
  "parent traversal path uses canonical marker root" \
  "Canonical_Root" \
  "$(run_helper "$canonical_root/src/../src")"
if ln -s "$canonical_root" "$canonical_link" 2>/dev/null; then
  assert_eq \
    "symlinked project path uses real project name" \
    "Canonical_Root" \
    "$(run_helper "$canonical_link/src")"
fi

fake_workspace_bin="$tmp/bin"
cat >"$fake_workspace_bin/get-workspace-name" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'External Workspace!'
SH
chmod +x "$fake_workspace_bin/get-workspace-name"

implicit_start="$tmp/Implicit Start"
mkdir -p "$implicit_start"
implicit="$(
  HOME="$tmp/home" \
    PATH="$fake_workspace_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    TMUX_SESSION_START_DIR="$implicit_start" \
    "$helper"
)"
assert_eq "implicit call uses get-workspace-name when available" "External_Workspace" "$implicit"

explicit="$(
  HOME="$tmp/home" \
    PATH="$fake_workspace_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$helper" "$plain_path"
)"
assert_eq "explicit path bypasses get-workspace-name" "plain_app" "$explicit"

empty_name_bin="$tmp/empty-bin"
mkdir -p "$empty_name_bin"
cat >"$empty_name_bin/get-workspace-name" <<'SH'
#!/usr/bin/env bash
printf '\n'
SH
chmod +x "$empty_name_bin/get-workspace-name"

empty_fallback="$(
  HOME="$tmp/home" \
    PATH="$empty_name_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    TMUX_SESSION_START_DIR="$plain_path" \
    "$helper"
)"
assert_eq "empty workspace command falls back to path" "plain_app" "$empty_fallback"

no_filter_bin="$tmp/no-filter-bin"
mkdir -p "$no_filter_bin"
ln -s "$(command -v bash)" "$no_filter_bin/bash"
cat >"$no_filter_bin/git" <<'SH'
#!/usr/bin/env bash
exit 1
SH
cat >"$no_filter_bin/get-workspace-name" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'External Name!' 'Ignored Name!'
SH
chmod +x "$no_filter_bin/git" "$no_filter_bin/get-workspace-name"

no_filter_root="$tmp/No Tools!!"
mkdir -p "$no_filter_root/src"
touch "$no_filter_root/package.json"

assert_eq \
  "help works without basename" \
  "Usage: tmux-session-name [--] [path]" \
  "$(HOME="$tmp/home" PATH="$no_filter_bin" "$helper" --help 2>&1)"

assert_eq \
  "path name sanitizes without basename tr or sed" \
  "No_Tools" \
  "$(HOME="$tmp/home" PATH="$no_filter_bin" "$helper" "$no_filter_root/src")"

assert_eq \
  "implicit workspace first line sanitizes without tr or sed" \
  "External_Name" \
  "$(
    HOME="$tmp/home" \
      PATH="$no_filter_bin" \
      TMUX_SESSION_START_DIR="$no_filter_root/src" \
      "$helper"
  )"
