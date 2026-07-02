#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lua_file="$(mktemp)"
trap 'rm -f "$lua_file"' EXIT

cat >"$lua_file" <<'LUA'
local root = assert(os.getenv("DOTFILES_ROOT"))

vim.g.mapleader = " "
package.path = root
  .. "/common/.config/nvim/lua/?.lua;"
  .. root
  .. "/common/.config/nvim/lua/?/init.lua;"
  .. package.path

dofile(root .. "/common/.config/nvim/lua/config/options.lua")
assert(vim.o.signcolumn == "auto:1")

require("config.keymaps")

local uv = vim.uv or vim.loop
local project_config = require("config.project")

;(function()
  local debug_config = require("config.debug")

  local function assert_args(label, actual, expected)
    assert(#actual == #expected, label .. " arg count " .. vim.inspect(actual))
    for index, expected_value in ipairs(expected) do
      assert(actual[index] == expected_value, label .. " arg " .. index .. " " .. vim.inspect(actual))
    end
  end

  assert_args("plain debug args", debug_config.parse_args("alpha beta", { expand = false }), { "alpha", "beta" })
  assert_args(
    "quoted debug args",
    debug_config.parse_args([["two words" bare]], { expand = false }),
    { "two words", "bare" }
  )
  assert_args("escaped debug space", debug_config.parse_args([[one\ two]], { expand = false }), { "one two" })
  assert_args("empty debug arg", debug_config.parse_args([[--name "" tail]], { expand = false }), { "--name", "", "tail" })

  vim.env.DOTFILES_ARG_TEST = "expanded"
  assert_args(
    "expanded debug args",
    debug_config.parse_args([[$DOTFILES_ARG_TEST '$DOTFILES_ARG_TEST' "\$DOTFILES_ARG_TEST"]]),
    { "expanded", "$DOTFILES_ARG_TEST", "$DOTFILES_ARG_TEST" }
  )
  assert_args(
    "braced expanded debug args",
    debug_config.parse_args([[${DOTFILES_ARG_TEST}/bin '${DOTFILES_ARG_TEST}' \${DOTFILES_ARG_TEST}]]),
    { "expanded/bin", "${DOTFILES_ARG_TEST}", "${DOTFILES_ARG_TEST}" }
  )
  vim.env.DOTFILES_ARG_TEST = nil
end)()

local function has_marker(value)
  for _, marker in ipairs(project_config.markers) do
    if marker == value then
      return true
    end
  end
  return false
end

assert(has_marker(".jj"), "project markers missing .jj")
assert(has_marker(".devcontainer"), "project markers missing .devcontainer")
assert(has_marker(".vscode"), "project markers missing .vscode")
assert(has_marker("go.mod"), "project markers missing go.mod")
assert(has_marker("Justfile"), "project markers missing Justfile")
assert(has_marker("Taskfile.yml"), "project markers missing Taskfile.yml")
assert(has_marker("MODULE.bazel"), "project markers missing MODULE.bazel")
assert(has_marker("Package.swift"), "project markers missing Package.swift")
assert(has_marker("go.work"), "project markers missing go.work")
assert(has_marker("pom.xml"), "project markers missing pom.xml")
assert(has_marker("Gemfile"), "project markers missing Gemfile")
assert(has_marker(".mise.toml"), "project markers missing .mise.toml")
assert(has_marker("requirements.txt"), "project markers missing requirements.txt")
assert(has_marker("turbo.json"), "project markers missing turbo.json")
assert(has_marker("nx.json"), "project markers missing nx.json")
assert(has_marker("angular.json"), "project markers missing angular.json")
assert(has_marker("lerna.json"), "project markers missing lerna.json")
assert(has_marker("rush.json"), "project markers missing rush.json")
assert(has_marker("biome.json"), "project markers missing biome.json")
assert(has_marker("biome.jsonc"), "project markers missing biome.jsonc")
assert(has_marker("bun.lock"), "project markers missing bun.lock")
assert(has_marker("bunfig.toml"), "project markers missing bunfig.toml")
assert(has_marker("tsconfig.json"), "project markers missing tsconfig.json")
assert(has_marker("poetry.lock"), "project markers missing poetry.lock")
assert(has_marker("pixi.toml"), "project markers missing pixi.toml")
assert(has_marker("pixi.lock"), "project markers missing pixi.lock")
assert(has_marker("pyrightconfig.json"), "project markers missing pyrightconfig.json")
assert(has_marker("compose.yaml"), "project markers missing compose.yaml")
assert(has_marker("Rakefile"), "project markers missing Rakefile")

local function has_primary_marker(value)
  for _, marker in ipairs(project_config.primary_markers) do
    if marker == value then
      return true
    end
  end
  return false
end

assert(not has_primary_marker(".vscode"), ".vscode should be a fallback marker")
assert(has_primary_marker(".devcontainer"), ".devcontainer should be a primary marker")
assert(has_primary_marker("package.json"), "package.json should be a primary marker")
assert(has_primary_marker("requirements.txt"), "requirements.txt should be a primary marker")
assert(has_primary_marker("turbo.json"), "turbo.json should be a primary marker")
assert(has_primary_marker("nx.json"), "nx.json should be a primary marker")
assert(has_primary_marker("angular.json"), "angular.json should be a primary marker")
assert(has_primary_marker("lerna.json"), "lerna.json should be a primary marker")
assert(has_primary_marker("rush.json"), "rush.json should be a primary marker")
assert(has_primary_marker("tsconfig.json"), "tsconfig.json should be a primary marker")
assert(has_primary_marker("poetry.lock"), "poetry.lock should be a primary marker")
assert(has_primary_marker("pixi.toml"), "pixi.toml should be a primary marker")
assert(has_primary_marker("pixi.lock"), "pixi.lock should be a primary marker")
assert(has_primary_marker("stack.yaml"), "stack.yaml should be a primary marker")
assert(has_primary_marker("rebar.config"), "rebar.config should be a primary marker")
assert(has_primary_marker("dune-project"), "dune-project should be a primary marker")

local directory_root_fixture = vim.fn.tempname()
vim.fn.delete(directory_root_fixture, "rf")
vim.fn.mkdir(directory_root_fixture .. "/src", "p")
vim.fn.writefile({ "{}" }, directory_root_fixture .. "/package.json")
local expected_directory_root = uv.fs_realpath(directory_root_fixture) or directory_root_fixture
local actual_directory_root = project_config.root_for_path(directory_root_fixture)
actual_directory_root = uv.fs_realpath(actual_directory_root) or actual_directory_root
assert(actual_directory_root == expected_directory_root, "directory project root " .. tostring(actual_directory_root))
local actual_trailing_directory_root = project_config.root_for_path(directory_root_fixture .. "/src/")
actual_trailing_directory_root = uv.fs_realpath(actual_trailing_directory_root) or actual_trailing_directory_root
assert(
  actual_trailing_directory_root == expected_directory_root,
  "trailing directory project root " .. tostring(actual_trailing_directory_root)
)
local actual_parent_directory_root = project_config.root_for_path(directory_root_fixture .. "/src/../src")
assert(
  actual_parent_directory_root == expected_directory_root,
  "parent traversal directory project root " .. tostring(actual_parent_directory_root)
)

;(function()
  assert(
    project_config.normalize_path([[C:\Users\sky\Project App\src\main.lua]])
      == "C:/Users/sky/Project App/src/main.lua",
    "Windows drive path should stay absolute"
  )
  assert(
    project_config.normalize_path([[\\server\share\Project App\src\main.lua]])
      == "//server/share/Project App/src/main.lua",
    "Windows UNC path should stay absolute"
  )
  assert(
    project_config.root_for_path([[C:\Users\sky\Project App\src\main.lua]])
      == "C:/Users/sky/Project App/src",
    "Windows drive root should not be prefixed by cwd"
  )
  assert(
    project_config.root_for_path([[\\server\share\Project App\src\main.lua]])
      == "//server/share/Project App/src",
    "Windows UNC root should not be prefixed by cwd"
  )
  assert(
    project_config.relative_path(
      [[C:\Users\sky\Project App\src\main.lua]],
      [[C:\Users\sky\Project App]]
    ) == "src/main.lua",
    "Windows drive relative path"
  )
  assert(
    project_config.relative_path(
      [[\\server\share\Project App\src\main.lua]],
      [[\\server\share\Project App]]
    ) == "src/main.lua",
    "Windows UNC relative path"
  )
end)()

;(function()
  local nx_root_fixture = vim.fn.tempname()
  vim.fn.delete(nx_root_fixture, "rf")
  vim.fn.mkdir(nx_root_fixture .. "/apps/web/src", "p")
  vim.fn.writefile({ "{}" }, nx_root_fixture .. "/nx.json")
  local expected_nx_root = uv.fs_realpath(nx_root_fixture) or nx_root_fixture
  local actual_nx_root = project_config.root_for_path(nx_root_fixture .. "/apps/web/src/app.ts")
  actual_nx_root = uv.fs_realpath(actual_nx_root) or actual_nx_root
  assert(actual_nx_root == expected_nx_root, "nx project root " .. tostring(actual_nx_root))
  vim.fn.delete(nx_root_fixture, "rf")
end)()
local directory_root_link = directory_root_fixture .. "-link"
pcall(uv.fs_unlink, directory_root_link)
local symlink_ok = pcall(uv.fs_symlink, directory_root_fixture, directory_root_link, { dir = true })
if symlink_ok and uv.fs_stat(directory_root_link .. "/src") then
  local actual_symlink_directory_root = project_config.root_for_path(directory_root_link .. "/src")
  assert(
    actual_symlink_directory_root == expected_directory_root,
    "symlink directory project root " .. tostring(actual_symlink_directory_root)
  )
end
pcall(uv.fs_unlink, directory_root_link)
local original_directory_root_cwd = vim.fn.getcwd()
vim.cmd("cd " .. vim.fn.fnameescape(directory_root_fixture))
local actual_relative_new_file_root = project_config.root_for_path("src/new-file.lua")
actual_relative_new_file_root = uv.fs_realpath(actual_relative_new_file_root) or actual_relative_new_file_root
assert(
  actual_relative_new_file_root == expected_directory_root,
  "relative new file project root " .. tostring(actual_relative_new_file_root)
)
vim.cmd("cd " .. vim.fn.fnameescape(original_directory_root_cwd))
vim.fn.delete(directory_root_fixture, "rf")

;(function()
  local cwd_fixture = vim.fn.tempname()
  local file_fixture = vim.fn.tempname()
  vim.fn.delete(cwd_fixture, "rf")
  vim.fn.delete(file_fixture, "rf")
  vim.fn.mkdir(cwd_fixture, "p")
  vim.fn.mkdir(file_fixture .. "/standalone", "p")
  local markerless_file = file_fixture .. "/standalone/scratch.txt"
  vim.fn.writefile({ "scratch" }, markerless_file)
  local expected_root = uv.fs_realpath(file_fixture .. "/standalone") or (file_fixture .. "/standalone")
  local original_cwd = vim.fn.getcwd()
  vim.cmd("cd " .. vim.fn.fnameescape(cwd_fixture))
  local actual_root = project_config.root_for_path(markerless_file)
  actual_root = uv.fs_realpath(actual_root) or actual_root
  assert(actual_root == expected_root, "markerless file project root " .. tostring(actual_root))
  vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
  vim.fn.delete(cwd_fixture, "rf")
  vim.fn.delete(file_fixture, "rf")
end)()

;(function()
  local cwd_fixture = vim.fn.tempname()
  vim.fn.delete(cwd_fixture, "rf")
  vim.fn.mkdir(cwd_fixture, "p")
  local expected_cwd = uv.fs_realpath(cwd_fixture) or cwd_fixture
  local original_cwd = vim.fn.getcwd()
  vim.cmd("cd " .. vim.fn.fnameescape(cwd_fixture))

  vim.cmd("enew!")
  vim.bo.buftype = "nofile"
  vim.api.nvim_buf_set_name(0, "/tmp/not-a-real-project/scratch.txt")
  local actual_nofile_root = project_config.root_for_buffer(0)
  actual_nofile_root = uv.fs_realpath(actual_nofile_root) or actual_nofile_root
  assert(actual_nofile_root == expected_cwd, "nofile buffer project root " .. tostring(actual_nofile_root))
  local actual_nofile_dir = project_config.file_dir_for_buffer(0)
  actual_nofile_dir = uv.fs_realpath(actual_nofile_dir) or actual_nofile_dir
  assert(actual_nofile_dir == expected_cwd, "nofile buffer file dir " .. tostring(actual_nofile_dir))

  vim.bo.buftype = ""
  vim.cmd("enew!")
  vim.api.nvim_buf_set_name(0, "oil:///tmp/not-a-real-project")
  local actual_uri_root = project_config.root_for_buffer(0)
  actual_uri_root = uv.fs_realpath(actual_uri_root) or actual_uri_root
  assert(actual_uri_root == expected_cwd, "uri buffer project root " .. tostring(actual_uri_root))
  local actual_uri_dir = project_config.file_dir_for_buffer(0)
  actual_uri_dir = uv.fs_realpath(actual_uri_dir) or actual_uri_dir
  assert(actual_uri_dir == expected_cwd, "uri buffer file dir " .. tostring(actual_uri_dir))

  vim.cmd("bwipeout!")
  vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
  vim.fn.delete(cwd_fixture, "rf")
end)()

local project_helper_fixture = vim.fn.tempname()
vim.fn.delete(project_helper_fixture, "rf")
vim.fn.mkdir(project_helper_fixture .. "/.jj", "p")
vim.fn.mkdir(project_helper_fixture .. "/pkg/lib", "p")
local project_helper_file = project_helper_fixture .. "/pkg/lib/helper.lua"
vim.fn.writefile({ "return true" }, project_helper_file)
local expected_helper_project = uv.fs_realpath(project_helper_fixture) or project_helper_fixture
local actual_helper_project = project_config.root_for_path(project_helper_file)
actual_helper_project = uv.fs_realpath(actual_helper_project) or actual_helper_project
assert(actual_helper_project == expected_helper_project, "helper project root " .. tostring(actual_helper_project))
assert(project_config.relative_path(project_helper_file, project_helper_fixture) == "pkg/lib/helper.lua")
vim.fn.mkdir(project_helper_fixture .. "/.vscode", "p")
local project_helper_tasks = project_helper_fixture .. "/.vscode/tasks.json"
vim.fn.writefile({ "{}" }, project_helper_tasks)
local actual_vscode_file, actual_vscode_workspace = project_config.vscode_file(
  "tasks.json",
  project_helper_fixture .. "/pkg/lib"
)
actual_vscode_file = actual_vscode_file and (uv.fs_realpath(actual_vscode_file) or actual_vscode_file)
actual_vscode_workspace = actual_vscode_workspace and (uv.fs_realpath(actual_vscode_workspace) or actual_vscode_workspace)
assert(actual_vscode_file == (uv.fs_realpath(project_helper_tasks) or project_helper_tasks))
assert(actual_vscode_workspace == expected_helper_project)
local actual_file_start_vscode_file, actual_file_start_vscode_workspace =
  project_config.vscode_file("tasks.json", project_helper_file)
actual_file_start_vscode_file = actual_file_start_vscode_file
  and (uv.fs_realpath(actual_file_start_vscode_file) or actual_file_start_vscode_file)
actual_file_start_vscode_workspace = actual_file_start_vscode_workspace
  and (uv.fs_realpath(actual_file_start_vscode_workspace) or actual_file_start_vscode_workspace)
assert(actual_file_start_vscode_file == (uv.fs_realpath(project_helper_tasks) or project_helper_tasks))
assert(actual_file_start_vscode_workspace == expected_helper_project)
vim.fn.delete(project_helper_fixture, "rf")

local nested_vscode_project = vim.fn.tempname()
vim.fn.delete(nested_vscode_project, "rf")
vim.fn.mkdir(nested_vscode_project .. "/.vscode", "p")
vim.fn.mkdir(nested_vscode_project .. "/app/.vscode", "p")
vim.fn.mkdir(nested_vscode_project .. "/app/src", "p")
local nested_vscode_tasks = nested_vscode_project .. "/.vscode/tasks.json"
vim.fn.writefile({ "{}" }, nested_vscode_tasks)
vim.fn.writefile({ "{}" }, nested_vscode_project .. "/app/.vscode/settings.json")
local expected_nested_vscode_project = uv.fs_realpath(nested_vscode_project) or nested_vscode_project
local actual_nested_vscode_file, actual_nested_vscode_workspace = project_config.vscode_file(
  "tasks.json",
  nested_vscode_project .. "/app/src"
)
actual_nested_vscode_file = actual_nested_vscode_file and (uv.fs_realpath(actual_nested_vscode_file) or actual_nested_vscode_file)
actual_nested_vscode_workspace = actual_nested_vscode_workspace
  and (uv.fs_realpath(actual_nested_vscode_workspace) or actual_nested_vscode_workspace)
assert(actual_nested_vscode_file == (uv.fs_realpath(nested_vscode_tasks) or nested_vscode_tasks))
assert(
  actual_nested_vscode_workspace == expected_nested_vscode_project,
  "nested vscode workspace " .. tostring(actual_nested_vscode_workspace)
)
vim.fn.delete(nested_vscode_project, "rf")

local vscode_only_project = vim.fn.tempname()
vim.fn.delete(vscode_only_project, "rf")
vim.fn.mkdir(vscode_only_project .. "/.vscode", "p")
vim.fn.mkdir(vscode_only_project .. "/app", "p")
local vscode_only_file = vscode_only_project .. "/app/main.txt"
vim.fn.writefile({ "vscode workspace" }, vscode_only_file)
local expected_vscode_only_project = uv.fs_realpath(vscode_only_project) or vscode_only_project
local actual_vscode_only_project = project_config.root_for_path(vscode_only_file)
actual_vscode_only_project = uv.fs_realpath(actual_vscode_only_project) or actual_vscode_only_project
assert(
  actual_vscode_only_project == expected_vscode_only_project,
  "vscode-only project root " .. tostring(actual_vscode_only_project)
)
vim.fn.delete(vscode_only_project, "rf")

local nested_vscode_marker_project = vim.fn.tempname()
vim.fn.delete(nested_vscode_marker_project, "rf")
vim.fn.mkdir(nested_vscode_marker_project .. "/app/.vscode", "p")
vim.fn.mkdir(nested_vscode_marker_project .. "/app/src", "p")
vim.fn.writefile({ "{}" }, nested_vscode_marker_project .. "/package.json")
local nested_vscode_marker_file = nested_vscode_marker_project .. "/app/src/main.ts"
vim.fn.writefile({ "export {}" }, nested_vscode_marker_file)
local expected_nested_vscode_marker_project = uv.fs_realpath(nested_vscode_marker_project)
  or nested_vscode_marker_project
local actual_nested_vscode_marker_project = project_config.root_for_path(nested_vscode_marker_file)
actual_nested_vscode_marker_project = uv.fs_realpath(actual_nested_vscode_marker_project)
  or actual_nested_vscode_marker_project
assert(
  actual_nested_vscode_marker_project == expected_nested_vscode_marker_project,
  "nested vscode marker project root " .. tostring(actual_nested_vscode_marker_project)
)
vim.fn.delete(nested_vscode_marker_project, "rf")

local taskfile_project = vim.fn.tempname()
vim.fn.delete(taskfile_project, "rf")
vim.fn.mkdir(taskfile_project .. "/service/internal", "p")
vim.fn.writefile({ "version: '3'" }, taskfile_project .. "/Taskfile.yml")
local taskfile_project_file = taskfile_project .. "/service/internal/main.go"
vim.fn.writefile({ "package main" }, taskfile_project_file)
local expected_taskfile_project = uv.fs_realpath(taskfile_project) or taskfile_project
local actual_taskfile_project = project_config.root_for_path(taskfile_project_file)
actual_taskfile_project = uv.fs_realpath(actual_taskfile_project) or actual_taskfile_project
assert(
  actual_taskfile_project == expected_taskfile_project,
  "taskfile project root " .. tostring(actual_taskfile_project)
)
vim.fn.delete(taskfile_project, "rf")

local go_workspace_project = vim.fn.tempname()
vim.fn.delete(go_workspace_project, "rf")
vim.fn.mkdir(go_workspace_project .. "/services/api", "p")
vim.fn.writefile({ "go 1.22" }, go_workspace_project .. "/go.work")
local go_workspace_project_file = go_workspace_project .. "/services/api/main.go"
vim.fn.writefile({ "package main" }, go_workspace_project_file)
local expected_go_workspace_project = uv.fs_realpath(go_workspace_project) or go_workspace_project
local actual_go_workspace_project = project_config.root_for_path(go_workspace_project_file)
actual_go_workspace_project = uv.fs_realpath(actual_go_workspace_project) or actual_go_workspace_project
assert(
  actual_go_workspace_project == expected_go_workspace_project,
  "go workspace project root " .. tostring(actual_go_workspace_project)
)
vim.fn.delete(go_workspace_project, "rf")

;(function()
  local requirements_project = vim.fn.tempname()
  vim.fn.delete(requirements_project, "rf")
  vim.fn.mkdir(requirements_project .. "/scripts/tools", "p")
  vim.fn.writefile({ "pytest" }, requirements_project .. "/requirements.txt")
  local requirements_project_file = requirements_project .. "/scripts/tools/check.py"
  vim.fn.writefile({ "print('ok')" }, requirements_project_file)
  local expected_requirements_project = uv.fs_realpath(requirements_project) or requirements_project
  local actual_requirements_project = project_config.root_for_path(requirements_project_file)
  actual_requirements_project = uv.fs_realpath(actual_requirements_project) or actual_requirements_project
  assert(
    actual_requirements_project == expected_requirements_project,
    "requirements project root " .. tostring(actual_requirements_project)
  )
  vim.fn.delete(requirements_project, "rf")
end)()

;(function()
  local turbo_project = vim.fn.tempname()
  vim.fn.delete(turbo_project, "rf")
  vim.fn.mkdir(turbo_project .. "/apps/web/src", "p")
  vim.fn.writefile({ "{}" }, turbo_project .. "/turbo.json")
  local turbo_project_file = turbo_project .. "/apps/web/src/app.ts"
  vim.fn.writefile({ "export {}" }, turbo_project_file)
  local expected_turbo_project = uv.fs_realpath(turbo_project) or turbo_project
  local actual_turbo_project = project_config.root_for_path(turbo_project_file)
  actual_turbo_project = uv.fs_realpath(actual_turbo_project) or actual_turbo_project
  assert(actual_turbo_project == expected_turbo_project, "turbo project root " .. tostring(actual_turbo_project))
  vim.fn.delete(turbo_project, "rf")
end)()

;(function()
  local ts_project = vim.fn.tempname()
  vim.fn.delete(ts_project, "rf")
  vim.fn.mkdir(ts_project .. "/src/components", "p")
  vim.fn.writefile({ "{}" }, ts_project .. "/tsconfig.json")
  local ts_project_file = ts_project .. "/src/components/app.tsx"
  vim.fn.writefile({ "export {}" }, ts_project_file)
  local expected_ts_project = uv.fs_realpath(ts_project) or ts_project
  local actual_ts_project = project_config.root_for_path(ts_project_file)
  actual_ts_project = uv.fs_realpath(actual_ts_project) or actual_ts_project
  assert(actual_ts_project == expected_ts_project, "tsconfig project root " .. tostring(actual_ts_project))
  vim.fn.delete(ts_project, "rf")
end)()

;(function()
  local poetry_project = vim.fn.tempname()
  vim.fn.delete(poetry_project, "rf")
  vim.fn.mkdir(poetry_project .. "/src/app", "p")
  vim.fn.writefile({ "# lock" }, poetry_project .. "/poetry.lock")
  local poetry_project_file = poetry_project .. "/src/app/main.py"
  vim.fn.writefile({ "print('ok')" }, poetry_project_file)
  local expected_poetry_project = uv.fs_realpath(poetry_project) or poetry_project
  local actual_poetry_project = project_config.root_for_path(poetry_project_file)
  actual_poetry_project = uv.fs_realpath(actual_poetry_project) or actual_poetry_project
  assert(actual_poetry_project == expected_poetry_project, "poetry project root " .. tostring(actual_poetry_project))
  vim.fn.delete(poetry_project, "rf")
end)()

;(function()
  local pixi_project = vim.fn.tempname()
  vim.fn.delete(pixi_project, "rf")
  vim.fn.mkdir(pixi_project .. "/src/app", "p")
  vim.fn.writefile({ "[workspace]" }, pixi_project .. "/pixi.toml")
  local pixi_project_file = pixi_project .. "/src/app/main.py"
  vim.fn.writefile({ "print('ok')" }, pixi_project_file)
  local expected_pixi_project = uv.fs_realpath(pixi_project) or pixi_project
  local actual_pixi_project = project_config.root_for_path(pixi_project_file)
  actual_pixi_project = uv.fs_realpath(actual_pixi_project) or actual_pixi_project
  assert(actual_pixi_project == expected_pixi_project, "pixi project root " .. tostring(actual_pixi_project))
  vim.fn.delete(pixi_project, "rf")
end)()

;(function()
  local compose_project = vim.fn.tempname()
  vim.fn.delete(compose_project, "rf")
  vim.fn.mkdir(compose_project .. "/services/api", "p")
  vim.fn.writefile({ "services: {}" }, compose_project .. "/compose.yaml")
  local compose_project_file = compose_project .. "/services/api/Dockerfile"
  vim.fn.writefile({ "FROM scratch" }, compose_project_file)
  local expected_compose_project = uv.fs_realpath(compose_project) or compose_project
  local actual_compose_project = project_config.root_for_path(compose_project_file)
  actual_compose_project = uv.fs_realpath(actual_compose_project) or actual_compose_project
  assert(actual_compose_project == expected_compose_project, "compose project root " .. tostring(actual_compose_project))
  vim.fn.delete(compose_project, "rf")
end)()

;(function()
  local devcontainer_project = vim.fn.tempname()
  vim.fn.delete(devcontainer_project, "rf")
  vim.fn.mkdir(devcontainer_project .. "/.devcontainer", "p")
  vim.fn.mkdir(devcontainer_project .. "/app/src", "p")
  local devcontainer_project_file = devcontainer_project .. "/app/src/main.ts"
  vim.fn.writefile({ "export {}" }, devcontainer_project_file)
  local expected_devcontainer_project = uv.fs_realpath(devcontainer_project) or devcontainer_project
  local actual_devcontainer_project = project_config.root_for_path(devcontainer_project_file)
  actual_devcontainer_project = uv.fs_realpath(actual_devcontainer_project) or actual_devcontainer_project
  assert(
    actual_devcontainer_project == expected_devcontainer_project,
    "devcontainer project root " .. tostring(actual_devcontainer_project)
  )
  vim.fn.delete(devcontainer_project, "rf")
end)()

;(function()
  local stack_project = vim.fn.tempname()
  vim.fn.delete(stack_project, "rf")
  vim.fn.mkdir(stack_project .. "/app/src", "p")
  vim.fn.writefile({ "resolver: lts" }, stack_project .. "/stack.yaml")
  local stack_project_file = stack_project .. "/app/src/Main.hs"
  vim.fn.writefile({ "main = pure ()" }, stack_project_file)
  local expected_stack_project = uv.fs_realpath(stack_project) or stack_project
  local actual_stack_project = project_config.root_for_path(stack_project_file)
  actual_stack_project = uv.fs_realpath(actual_stack_project) or actual_stack_project
  assert(actual_stack_project == expected_stack_project, "stack project root " .. tostring(actual_stack_project))
  vim.fn.delete(stack_project, "rf")
end)()

;(function()
  local rebar_project = vim.fn.tempname()
  vim.fn.delete(rebar_project, "rf")
  vim.fn.mkdir(rebar_project .. "/apps/api/src", "p")
  vim.fn.writefile({ "{}." }, rebar_project .. "/rebar.config")
  local rebar_project_file = rebar_project .. "/apps/api/src/api.erl"
  vim.fn.writefile({ "-module(api)." }, rebar_project_file)
  local expected_rebar_project = uv.fs_realpath(rebar_project) or rebar_project
  local actual_rebar_project = project_config.root_for_path(rebar_project_file)
  actual_rebar_project = uv.fs_realpath(actual_rebar_project) or actual_rebar_project
  assert(actual_rebar_project == expected_rebar_project, "rebar project root " .. tostring(actual_rebar_project))
  vim.fn.delete(rebar_project, "rf")
end)()

;(function()
  local dune_project = vim.fn.tempname()
  vim.fn.delete(dune_project, "rf")
  vim.fn.mkdir(dune_project .. "/lib/src", "p")
  vim.fn.writefile({ "(lang dune 3.0)" }, dune_project .. "/dune-project")
  local dune_project_file = dune_project .. "/lib/src/main.ml"
  vim.fn.writefile({ "let () = ()" }, dune_project_file)
  local expected_dune_project = uv.fs_realpath(dune_project) or dune_project
  local actual_dune_project = project_config.root_for_path(dune_project_file)
  actual_dune_project = uv.fs_realpath(actual_dune_project) or actual_dune_project
  assert(actual_dune_project == expected_dune_project, "dune project root " .. tostring(actual_dune_project))
  vim.fn.delete(dune_project, "rf")
end)()

local function callback_for(lhs, mode)
  local mapping = vim.fn.maparg(lhs, mode or "n", false, true)
  assert(type(mapping.callback) == "function", lhs .. " should be a callback mapping")
  return mapping.callback
end

local function rhs_for(lhs, mode)
  local mapping = vim.fn.maparg(lhs, mode or "n", false, true)
  assert(type(mapping.rhs) == "string" and mapping.rhs ~= "", lhs .. " should have an rhs mapping")
  return mapping.rhs
end

assert(rhs_for("<S-F1>") == "<cmd>bprevious<CR>")
assert(rhs_for("<F13>") == "<cmd>bprevious<CR>")
assert(rhs_for("<S-F1>", "i") == "<cmd>bprevious<CR>")
assert(rhs_for("<F13>", "i") == "<cmd>bprevious<CR>")
assert(rhs_for("<S-F4>") == "16k")
assert(rhs_for("<F16>") == "16k")
assert(rhs_for("<S-F4>", "i") == "<C-o>16k")
assert(rhs_for("<F16>", "i") == "<C-o>16k")
assert(rhs_for("<S-F5>") == "<cmd>w<CR>")
assert(rhs_for("<F17>") == "<cmd>w<CR>")
assert(rhs_for("<S-F5>", "i") == "<cmd>w<CR>")
assert(rhs_for("<F17>", "i") == "<cmd>w<CR>")
assert(rhs_for("<S-F6>") == "16j")
assert(rhs_for("<F18>") == "16j")
assert(rhs_for("<S-F6>", "i") == "<C-o>16j")
assert(rhs_for("<F18>", "i") == "<C-o>16j")
assert(type(vim.fn.maparg("<S-F9>", "n", false, true).callback) == "function")
assert(type(vim.fn.maparg("<F21>", "n", false, true).callback) == "function")
assert(type(vim.fn.maparg("<S-F9>", "i", false, true).callback) == "function")
assert(type(vim.fn.maparg("<F21>", "i", false, true).callback) == "function")
assert(rhs_for("<S-F11>") == "gcc")
assert(rhs_for("<F23>") == "gcc")
assert(rhs_for("<S-F11>", "i") == "<C-o>gcc")
assert(rhs_for("<F23>", "i") == "<C-o>gcc")
assert(rhs_for("<S-F11>", "x") == "gc")
assert(rhs_for("<F23>", "x") == "gc")
assert(rhs_for("<S-F12>") == "<cmd>bnext<CR>")
assert(rhs_for("<F24>") == "<cmd>bnext<CR>")
assert(rhs_for("<S-F12>", "i") == "<cmd>bnext<CR>")
assert(rhs_for("<F24>", "i") == "<cmd>bnext<CR>")

;(function()
  local build_fixture = vim.fn.tempname()
  local build_other = vim.fn.tempname()
  vim.fn.delete(build_fixture, "rf")
  vim.fn.delete(build_other, "rf")
  vim.fn.mkdir(build_fixture .. "/.vscode", "p")
  vim.fn.mkdir(build_fixture .. "/src", "p")
  vim.fn.mkdir(build_other, "p")
  local build_file = build_fixture .. "/src/main.cpp"
  vim.fn.writefile({ "{}" }, build_fixture .. "/.vscode/tasks.json")
  vim.fn.writefile({ "int main() { return 0; }" }, build_file)
  local expected_build_project = uv.fs_realpath(build_fixture) or build_fixture
  local original_build_cwd = vim.fn.getcwd()
  local captured_build_opts
  package.loaded["lazy"] = {
    load = function() end,
  }
  package.loaded["overseer"] = {
    TAG = { BUILD = "BUILD" },
    run_task = function(opts)
      captured_build_opts = opts
    end,
  }
  vim.cmd("cd " .. vim.fn.fnameescape(build_other))
  vim.cmd("edit " .. vim.fn.fnameescape(build_file))
  vim.bo.filetype = "cpp"
  assert(pcall(callback_for("<S-F2>")))
  assert(captured_build_opts, "Shift-F2 build did not call overseer")
  assert(captured_build_opts.cwd == expected_build_project, "build cwd " .. tostring(captured_build_opts.cwd))
  assert(captured_build_opts.search_params.dir == expected_build_project)
  assert(captured_build_opts.search_params.filetype == "cpp")
  assert(captured_build_opts.tags[1] == "BUILD")
  package.loaded["overseer"] = nil
  package.loaded["lazy"] = nil
  vim.cmd("bwipeout!")
  vim.cmd("cd " .. vim.fn.fnameescape(original_build_cwd))
  vim.fn.delete(build_fixture, "rf")
  vim.fn.delete(build_other, "rf")
end)()

;(function()
  local old_notify = vim.notify
  local notices = {}
  vim.notify = function(message, level)
    table.insert(notices, { message = tostring(message), level = level })
  end

  local function has_warning(prefix)
    for _, notice in ipairs(notices) do
      if notice.level == vim.log.levels.WARN and notice.message:sub(1, #prefix) == prefix then
        return true
      end
    end
    return false
  end

  local source_failure_file = vim.fn.tempname() .. ".vim"
  vim.fn.writefile({ "ThisCommandDoesNotExistForDotfilesSmoke" }, source_failure_file)
  vim.cmd("edit " .. vim.fn.fnameescape(source_failure_file))
  vim.bo.filetype = "vim"
  assert(pcall(callback_for("zl")))
  assert(has_warning("Unable to source current file:"), vim.inspect(notices))
  vim.cmd("bwipeout!")
  vim.fn.delete(source_failure_file)

  local reload_failure_file = vim.fn.tempname() .. ".vim"
  local old_myvimrc = vim.env.MYVIMRC
  vim.fn.writefile({ "ThisReloadCommandDoesNotExistForDotfilesSmoke" }, reload_failure_file)
  vim.env.MYVIMRC = reload_failure_file
  assert(pcall(callback_for(" rr")))
  assert(has_warning("Unable to reload config:"), vim.inspect(notices))
  vim.env.MYVIMRC = old_myvimrc
  vim.fn.delete(reload_failure_file)

  package.loaded["lazy"] = nil
  package.loaded["overseer"] = {
    TAG = { BUILD = "BUILD" },
    run_task = function()
      error("forced keymap run_task failure")
    end,
    list_tasks = function()
      error("forced keymap list_tasks failure")
    end,
  }
  assert(pcall(callback_for("<S-F2>")))
  assert(has_warning("Unable to run task:"), vim.inspect(notices))
  assert(pcall(callback_for("<S-F7>")))
  assert(has_warning("Unable to list running tasks:"), vim.inspect(notices))

  package.loaded["overseer"] = {
    TAG = { BUILD = "BUILD" },
    run_task = function() end,
    list_tasks = function()
      return { { name = "running" } }
    end,
    run_action = function()
      error("forced keymap stop failure")
    end,
  }
  assert(pcall(callback_for("<S-F7>")))
  assert(has_warning("Unable to stop task:"), vim.inspect(notices))

  package.loaded["telescope.builtin"] = {
    lsp_workspace_symbols = function()
      error("forced keymap symbol failure")
    end,
  }
  assert(pcall(callback_for("<S-F3>")))
  assert(has_warning("Unable to find type symbols:"), vim.inspect(notices))

  package.loaded["lazy"] = nil
  package.loaded["overseer"] = nil
  package.loaded["telescope.builtin"] = nil

  pcall(vim.api.nvim_del_user_command, "CMakeBuild")
  vim.api.nvim_create_user_command("CMakeBuild", function()
    error("forced CMakeBuild failure")
  end, {})
  assert(pcall(callback_for("<S-F2>")))
  assert(has_warning("Unable to run CMakeBuild:"), vim.inspect(notices))
  pcall(vim.api.nvim_del_user_command, "CMakeBuild")

  pcall(vim.api.nvim_del_user_command, "Telescope")
  vim.api.nvim_create_user_command("Telescope", function()
    error("forced Telescope failure")
  end, { nargs = "*" })
  assert(pcall(callback_for("<S-F3>")))
  assert(has_warning("Unable to run Telescope:"), vim.inspect(notices))
  pcall(vim.api.nvim_del_user_command, "Telescope")

  pcall(vim.api.nvim_del_user_command, "CMakeStop")
  pcall(vim.api.nvim_del_user_command, "OverseerTaskAction")
  vim.api.nvim_create_user_command("CMakeStop", function()
    error("forced CMakeStop failure")
  end, {})
  assert(pcall(callback_for("<S-F7>")))
  assert(has_warning("Unable to run CMakeStop:"), vim.inspect(notices))
  pcall(vim.api.nvim_del_user_command, "CMakeStop")

  vim.api.nvim_create_user_command("OverseerTaskAction", function()
    error("forced OverseerTaskAction failure")
  end, {})
  assert(pcall(callback_for("<S-F7>")))
  assert(has_warning("Unable to run OverseerTaskAction:"), vim.inspect(notices))
  pcall(vim.api.nvim_del_user_command, "OverseerTaskAction")

  vim.notify = old_notify
end)()

local qnext = callback_for("]q")
local qprev = callback_for("[q")
local lnext = callback_for("]l")
local lprev = callback_for("[l")
local diagnostic_next = callback_for("]d")
local diagnostic_prev = callback_for("[d")
local diagnostic_error = callback_for("]e")
local diagnostic_prev_error = callback_for("[e")
local diagnostic_warn = callback_for("]w")
local diagnostic_prev_warn = callback_for("[w")
local line_diagnostics = callback_for(" cd")
local diagnostics_to_qf = callback_for(" cq")
local diagnostics_to_loc = callback_for(" cl")
local qopen = callback_for(" co")
local lopen = callback_for(" cO")
local definition = callback_for("<S-F8>")
local definition_alt = callback_for("<F20>")
local source_header = callback_for("<A-o>")
local source_current_file = callback_for("zl")
local reload_config = callback_for(" rr")
local path_copy = callback_for(" fl")
local path_line_copy = callback_for(" fL")
local relative_path_copy = callback_for(" fr")
local relative_path_line_copy = callback_for(" fR")
local project_path_copy = callback_for(" fP")
local project_path_line_copy = callback_for(" fY")
local project_terminal = callback_for(" ft")
local file_terminal = callback_for(" fT")
local hide_terminal = callback_for(" fX")
local project_cwd = callback_for(" fc")
local file_cwd = callback_for(" fC")
local tmux_project_session = callback_for(" ws")
local tmux_project_resume = callback_for(" wr")
local tmux_project_ai = callback_for(" wa")
local tmux_project_terminal = callback_for(" wt")

assert(pcall(qnext))
assert(pcall(qprev))
assert(pcall(lnext))
assert(pcall(lprev))
assert(pcall(diagnostic_next))
assert(pcall(diagnostic_prev))
assert(pcall(diagnostic_error))
assert(pcall(diagnostic_prev_error))
assert(pcall(diagnostic_warn))
assert(pcall(diagnostic_prev_warn))
assert(pcall(line_diagnostics))
assert(pcall(diagnostics_to_qf))
assert(pcall(diagnostics_to_loc))
assert(pcall(qopen))
assert(pcall(lopen))
assert(pcall(definition))
assert(pcall(definition_alt))
vim.o.hlsearch = true
assert(pcall(callback_for("<S-F9>")))
assert(vim.o.hlsearch == false)
assert(pcall(callback_for("<F21>")))
assert(vim.o.hlsearch == true)
assert(pcall(callback_for("<S-F9>", "i")))
assert(vim.o.hlsearch == false)
assert(pcall(callback_for("<F21>", "i")))
assert(vim.o.hlsearch == true)
assert(pcall(source_header))

local fixture = root .. "/AGENTS.md"
vim.fn.setqflist({
  { filename = fixture, lnum = 1, col = 1, text = "one" },
  { filename = fixture, lnum = 2, col = 1, text = "two" },
}, "r")
assert(pcall(qnext))
assert(vim.fn.getqflist({ idx = 0 }).idx == 2)
assert(pcall(qprev))
assert(vim.fn.getqflist({ idx = 0 }).idx == 1)
assert(pcall(qopen))
vim.cmd("cclose")

local source_win = vim.api.nvim_get_current_win()
vim.fn.setloclist(source_win, {
  { filename = fixture, lnum = 1, col = 1, text = "one" },
  { filename = fixture, lnum = 2, col = 1, text = "two" },
}, "r")
assert(pcall(lnext))
assert(vim.fn.getloclist(source_win, { idx = 0 }).idx == 2)
assert(pcall(lprev))
assert(vim.fn.getloclist(source_win, { idx = 0 }).idx == 1)
assert(pcall(lopen))
vim.cmd("lclose")

assert(vim.fn.maparg(" ft", "n") ~= "")
assert(vim.fn.maparg(" fT", "n") ~= "")
assert(vim.fn.maparg(" fX", "n") ~= "")
assert(vim.fn.maparg(" e", "n") ~= "")
assert(vim.fn.maparg(" fc", "n") ~= "")
assert(vim.fn.maparg(" fC", "n") ~= "")
assert(vim.fn.maparg(" fl", "n") ~= "")
assert(vim.fn.maparg(" fL", "n") ~= "")
assert(vim.fn.maparg(" fr", "n") ~= "")
assert(vim.fn.maparg(" fR", "n") ~= "")
assert(vim.fn.maparg(" fP", "n") ~= "")
assert(vim.fn.maparg(" fY", "n") ~= "")
assert(vim.fn.maparg(" ws", "n") ~= "")
assert(vim.fn.maparg(" wr", "n") ~= "")
assert(vim.fn.maparg(" wa", "n") ~= "")
assert(vim.fn.maparg(" wt", "n") ~= "")

;(function()
  local file_manager = callback_for(" e")
  local file_manager_fixture = vim.fn.tempname()
  local file_manager_other = vim.fn.tempname()
  vim.fn.delete(file_manager_fixture, "rf")
  vim.fn.delete(file_manager_other, "rf")
  vim.fn.mkdir(file_manager_fixture .. "/.git", "p")
  vim.fn.mkdir(file_manager_fixture .. "/app/src", "p")
  vim.fn.mkdir(file_manager_other, "p")
  local file_manager_file = file_manager_fixture .. "/app/src/file.txt"
  vim.fn.writefile({ "file manager target" }, file_manager_file)
  local expected_file_manager_project = uv.fs_realpath(file_manager_fixture) or file_manager_fixture
  local original_file_manager_cwd = vim.fn.getcwd()
  local captured_yazi
  package.loaded["yazi"] = {
    yazi = function(config, input_path, args)
      captured_yazi = { config = config, input_path = input_path, args = args }
    end,
  }
  vim.cmd("cd " .. vim.fn.fnameescape(file_manager_other))
  vim.cmd("edit " .. vim.fn.fnameescape(file_manager_file))
  assert(pcall(file_manager))
  assert(captured_yazi, "file manager did not call yazi")
  assert(captured_yazi.config == nil)
  assert(captured_yazi.input_path == expected_file_manager_project)
  assert(captured_yazi.args and captured_yazi.args.reveal_path == file_manager_file)
  package.loaded["yazi"] = nil
  vim.cmd("bwipeout!")
  vim.cmd("cd " .. vim.fn.fnameescape(original_file_manager_cwd))
  vim.fn.delete(file_manager_fixture, "rf")
  vim.fn.delete(file_manager_other, "rf")
end)()

;(function()
  local file_manager = callback_for(" e")
  local lf_fixture = vim.fn.tempname() .. " root"
  local lf_other = vim.fn.tempname()
  vim.fn.delete(lf_fixture, "rf")
  vim.fn.delete(lf_other, "rf")
  vim.fn.mkdir(lf_fixture .. "/.git", "p")
  vim.fn.mkdir(lf_fixture .. "/app/src", "p")
  vim.fn.mkdir(lf_other, "p")
  local lf_file = lf_fixture .. "/app/src/file.txt"
  vim.fn.writefile({ "lf target" }, lf_file)
  local expected_lf_project = uv.fs_realpath(lf_fixture) or lf_fixture
  local original_lf_cwd = vim.fn.getcwd()
  local captured_lf_dir
  package.loaded["yazi"] = nil
  package.loaded["fm-nvim"] = {
    Lf = function(dir)
      captured_lf_dir = dir
    end,
  }
  vim.cmd("cd " .. vim.fn.fnameescape(lf_other))
  vim.cmd("edit " .. vim.fn.fnameescape(lf_file))
  assert(pcall(file_manager))
  assert(captured_lf_dir == vim.fn.shellescape(expected_lf_project), "LF dir " .. tostring(captured_lf_dir))
  package.loaded["fm-nvim"] = nil
  vim.cmd("bwipeout!")
  vim.cmd("cd " .. vim.fn.fnameescape(original_lf_cwd))
  vim.fn.delete(lf_fixture, "rf")
  vim.fn.delete(lf_other, "rf")
end)()

;(function()
  local file_manager = callback_for(" e")
  local yazi_fail_fixture = vim.fn.tempname() .. " yazi fail root"
  local yazi_fail_other = vim.fn.tempname()
  vim.fn.delete(yazi_fail_fixture, "rf")
  vim.fn.delete(yazi_fail_other, "rf")
  vim.fn.mkdir(yazi_fail_fixture .. "/.git", "p")
  vim.fn.mkdir(yazi_fail_fixture .. "/app/src", "p")
  vim.fn.mkdir(yazi_fail_other, "p")
  local yazi_fail_file = yazi_fail_fixture .. "/app/src/file.txt"
  vim.fn.writefile({ "yazi failure target" }, yazi_fail_file)
  local expected_yazi_fail_project = uv.fs_realpath(yazi_fail_fixture) or yazi_fail_fixture
  local original_yazi_fail_cwd = vim.fn.getcwd()
  local old_notify = vim.notify
  local yazi_fail_notices = {}
  local captured_lf_after_yazi_failure
  package.loaded["yazi"] = {
    yazi = function()
      error("forced yazi failure")
    end,
  }
  package.loaded["fm-nvim"] = {
    Lf = function(dir)
      captured_lf_after_yazi_failure = dir
    end,
  }
  package.loaded["mini.files"] = nil
  pcall(vim.api.nvim_del_user_command, "NvimTreeToggle")
  vim.notify = function(message, level)
    table.insert(yazi_fail_notices, { message = tostring(message), level = level })
  end
  vim.cmd("cd " .. vim.fn.fnameescape(yazi_fail_other))
  vim.cmd("edit " .. vim.fn.fnameescape(yazi_fail_file))
  assert(pcall(file_manager))
  assert(
    captured_lf_after_yazi_failure == vim.fn.shellescape(expected_yazi_fail_project),
    "LF dir after Yazi failure " .. tostring(captured_lf_after_yazi_failure)
  )
  assert(
    yazi_fail_notices[1] and yazi_fail_notices[1].message:find("Unable to open Yazi:", 1, true),
    vim.inspect(yazi_fail_notices)
  )
  vim.notify = old_notify
  package.loaded["yazi"] = nil
  package.loaded["fm-nvim"] = nil
  vim.cmd("bwipeout!")
  vim.cmd("cd " .. vim.fn.fnameescape(original_yazi_fail_cwd))
  vim.fn.delete(yazi_fail_fixture, "rf")
  vim.fn.delete(yazi_fail_other, "rf")
end)()

;(function()
  local file_manager = callback_for(" e")
  local mini_fixture = vim.fn.tempname() .. " mini root"
  local mini_other = vim.fn.tempname()
  vim.fn.delete(mini_fixture, "rf")
  vim.fn.delete(mini_other, "rf")
  vim.fn.mkdir(mini_fixture .. "/.git", "p")
  vim.fn.mkdir(mini_fixture .. "/app/src", "p")
  vim.fn.mkdir(mini_other, "p")
  local mini_file = mini_fixture .. "/app/src/file.txt"
  vim.fn.writefile({ "mini files target" }, mini_file)
  local expected_mini_project = uv.fs_realpath(mini_fixture) or mini_fixture
  local original_mini_cwd = vim.fn.getcwd()
  local captured_mini_dir
  package.loaded["yazi"] = nil
  package.loaded["fm-nvim"] = nil
  package.loaded["mini.files"] = {
    open = function(dir)
      captured_mini_dir = dir
    end,
  }
  pcall(vim.api.nvim_del_user_command, "NvimTreeToggle")
  vim.cmd("cd " .. vim.fn.fnameescape(mini_other))
  vim.cmd("edit " .. vim.fn.fnameescape(mini_file))
  assert(pcall(file_manager))
  assert(captured_mini_dir == expected_mini_project, "mini.files dir " .. tostring(captured_mini_dir))
  package.loaded["mini.files"] = nil
  vim.cmd("bwipeout!")
  vim.cmd("cd " .. vim.fn.fnameescape(original_mini_cwd))
  vim.fn.delete(mini_fixture, "rf")
  vim.fn.delete(mini_other, "rf")
end)()

;(function()
  local file_manager = callback_for(" e")
  local lf_fail_fixture = vim.fn.tempname() .. " lf fail root"
  local lf_fail_other = vim.fn.tempname()
  vim.fn.delete(lf_fail_fixture, "rf")
  vim.fn.delete(lf_fail_other, "rf")
  vim.fn.mkdir(lf_fail_fixture .. "/.git", "p")
  vim.fn.mkdir(lf_fail_fixture .. "/app/src", "p")
  vim.fn.mkdir(lf_fail_other, "p")
  local lf_fail_file = lf_fail_fixture .. "/app/src/file.txt"
  vim.fn.writefile({ "lf failure target" }, lf_fail_file)
  local expected_lf_fail_project = uv.fs_realpath(lf_fail_fixture) or lf_fail_fixture
  local original_lf_fail_cwd = vim.fn.getcwd()
  local old_notify = vim.notify
  local lf_fail_notices = {}
  local captured_mini_after_lf_failure
  package.loaded["yazi"] = nil
  package.loaded["fm-nvim"] = {
    Lf = function()
      error("forced fm-nvim LF failure")
    end,
  }
  package.loaded["mini.files"] = {
    open = function(dir)
      captured_mini_after_lf_failure = dir
    end,
  }
  pcall(vim.api.nvim_del_user_command, "NvimTreeToggle")
  vim.notify = function(message, level)
    table.insert(lf_fail_notices, { message = tostring(message), level = level })
  end
  vim.cmd("cd " .. vim.fn.fnameescape(lf_fail_other))
  vim.cmd("edit " .. vim.fn.fnameescape(lf_fail_file))
  assert(pcall(file_manager))
  assert(
    captured_mini_after_lf_failure == expected_lf_fail_project,
    "mini.files dir after LF failure " .. tostring(captured_mini_after_lf_failure)
  )
  assert(
    lf_fail_notices[1] and lf_fail_notices[1].message:find("Unable to open LF:", 1, true),
    vim.inspect(lf_fail_notices)
  )
  vim.notify = old_notify
  package.loaded["fm-nvim"] = nil
  package.loaded["mini.files"] = nil
  vim.cmd("bwipeout!")
  vim.cmd("cd " .. vim.fn.fnameescape(original_lf_fail_cwd))
  vim.fn.delete(lf_fail_fixture, "rf")
  vim.fn.delete(lf_fail_other, "rf")
end)()

;(function()
  local file_manager = callback_for(" e")
  local tree_fixture = vim.fn.tempname() .. " tree root"
  local tree_other = vim.fn.tempname()
  vim.fn.delete(tree_fixture, "rf")
  vim.fn.delete(tree_other, "rf")
  vim.fn.mkdir(tree_fixture .. "/.git", "p")
  vim.fn.mkdir(tree_fixture .. "/app/src", "p")
  vim.fn.mkdir(tree_other, "p")
  local tree_file = tree_fixture .. "/app/src/file.txt"
  vim.fn.writefile({ "nvim tree target" }, tree_file)
  local expected_tree_project = uv.fs_realpath(tree_fixture) or tree_fixture
  local original_tree_cwd = vim.fn.getcwd()
  local captured_tree_dir
  package.loaded["yazi"] = nil
  package.loaded["fm-nvim"] = nil
  package.loaded["mini.files"] = nil
  pcall(vim.api.nvim_del_user_command, "NvimTreeToggle")
  vim.api.nvim_create_user_command("NvimTreeToggle", function(opts)
    captured_tree_dir = opts.fargs[1]
  end, { nargs = "*" })
  vim.cmd("cd " .. vim.fn.fnameescape(tree_other))
  vim.cmd("edit " .. vim.fn.fnameescape(tree_file))
  assert(pcall(file_manager))
  assert(captured_tree_dir == expected_tree_project, "NvimTree dir " .. tostring(captured_tree_dir))
  pcall(vim.api.nvim_del_user_command, "NvimTreeToggle")
  vim.cmd("bwipeout!")
  vim.cmd("cd " .. vim.fn.fnameescape(original_tree_cwd))
  vim.fn.delete(tree_fixture, "rf")
  vim.fn.delete(tree_other, "rf")
end)()

;(function()
  local file_manager = callback_for(" e")
  local mini_fail_fixture = vim.fn.tempname() .. " mini fail root"
  local mini_fail_other = vim.fn.tempname()
  vim.fn.delete(mini_fail_fixture, "rf")
  vim.fn.delete(mini_fail_other, "rf")
  vim.fn.mkdir(mini_fail_fixture .. "/.git", "p")
  vim.fn.mkdir(mini_fail_fixture .. "/app/src", "p")
  vim.fn.mkdir(mini_fail_other, "p")
  local mini_fail_file = mini_fail_fixture .. "/app/src/file.txt"
  vim.fn.writefile({ "mini failure target" }, mini_fail_file)
  local expected_mini_fail_project = uv.fs_realpath(mini_fail_fixture) or mini_fail_fixture
  local original_mini_fail_cwd = vim.fn.getcwd()
  local old_notify = vim.notify
  local mini_fail_notices = {}
  local captured_tree_after_mini_failure
  package.loaded["yazi"] = nil
  package.loaded["fm-nvim"] = nil
  package.loaded["mini.files"] = {
    open = function()
      error("forced mini.files failure")
    end,
  }
  pcall(vim.api.nvim_del_user_command, "NvimTreeToggle")
  vim.api.nvim_create_user_command("NvimTreeToggle", function(opts)
    captured_tree_after_mini_failure = opts.fargs[1]
  end, { nargs = "*" })
  vim.notify = function(message, level)
    table.insert(mini_fail_notices, { message = tostring(message), level = level })
  end
  vim.cmd("cd " .. vim.fn.fnameescape(mini_fail_other))
  vim.cmd("edit " .. vim.fn.fnameescape(mini_fail_file))
  assert(pcall(file_manager))
  assert(
    captured_tree_after_mini_failure == expected_mini_fail_project,
    "NvimTree dir after mini.files failure " .. tostring(captured_tree_after_mini_failure)
  )
  assert(
    mini_fail_notices[1] and mini_fail_notices[1].message:find("Unable to open mini.files:", 1, true),
    vim.inspect(mini_fail_notices)
  )
  vim.notify = old_notify
  package.loaded["mini.files"] = nil
  pcall(vim.api.nvim_del_user_command, "NvimTreeToggle")
  vim.cmd("bwipeout!")
  vim.cmd("cd " .. vim.fn.fnameescape(original_mini_fail_cwd))
  vim.fn.delete(mini_fail_fixture, "rf")
  vim.fn.delete(mini_fail_other, "rf")
end)()

;(function()
  local file_manager = callback_for(" e")
  local missing_fixture = vim.fn.tempname() .. " missing root"
  local missing_other = vim.fn.tempname()
  vim.fn.delete(missing_fixture, "rf")
  vim.fn.delete(missing_other, "rf")
  vim.fn.mkdir(missing_fixture .. "/.git", "p")
  vim.fn.mkdir(missing_fixture .. "/app/src", "p")
  vim.fn.mkdir(missing_other, "p")
  local missing_file = missing_fixture .. "/app/src/file.txt"
  vim.fn.writefile({ "missing manager target" }, missing_file)
  local original_missing_cwd = vim.fn.getcwd()
  local old_notify = vim.notify
  local missing_notice
  package.loaded["yazi"] = nil
  package.loaded["fm-nvim"] = nil
  package.loaded["mini.files"] = nil
  pcall(vim.api.nvim_del_user_command, "NvimTreeToggle")
  vim.notify = function(message, level)
    missing_notice = { message = tostring(message), level = level }
  end
  vim.cmd("cd " .. vim.fn.fnameescape(missing_other))
  vim.cmd("edit " .. vim.fn.fnameescape(missing_file))
  assert(pcall(file_manager))
  assert(missing_notice, "missing file manager notification was not emitted")
  assert(missing_notice.message == "No file manager is available", missing_notice.message)
  assert(missing_notice.level == vim.log.levels.WARN)
  vim.notify = old_notify
  vim.cmd("bwipeout!")
  vim.cmd("cd " .. vim.fn.fnameescape(original_missing_cwd))
  vim.fn.delete(missing_fixture, "rf")
  vim.fn.delete(missing_other, "rf")
end)()

local terminal_fixture = vim.fn.tempname()
vim.fn.delete(terminal_fixture, "rf")
vim.fn.mkdir(terminal_fixture .. "/.git", "p")
vim.fn.mkdir(terminal_fixture .. "/sub", "p")
vim.fn.writefile({ "terminal target" }, terminal_fixture .. "/sub/file.txt")

local original_terminal_cwd = vim.fn.getcwd()
local original_shell = vim.o.shell
vim.g.dotfiles_smoke_original_lines = vim.o.lines
vim.g.dotfiles_smoke_original_cmdheight = vim.o.cmdheight
if vim.fn.executable("/bin/sh") == 1 then
  vim.o.shell = "/bin/sh"
end
vim.o.cmdheight = 1
vim.cmd("cd " .. vim.fn.fnameescape(root))
vim.cmd("edit " .. vim.fn.fnameescape(terminal_fixture .. "/sub/file.txt"))
local source_terminal_win = vim.api.nvim_get_current_win()
local expected_terminal_project = uv.fs_realpath(terminal_fixture) or terminal_fixture
local expected_terminal_file_dir = uv.fs_realpath(terminal_fixture .. "/sub") or terminal_fixture .. "/sub"
local terminal_buffers = {}

function _G.dotfiles_smoke_expected_terminal_height(lines)
  local preferred = math.max(8, math.min(15, math.floor(lines * 0.30)))
  local available = math.max(1, lines - vim.o.cmdheight - 6)
  return math.max(1, math.min(preferred, available))
end

local function stop_terminal_job(bufnr)
  local ok, job_id = pcall(vim.api.nvim_buf_get_var, bufnr, "terminal_job_id")
  assert(ok and type(job_id) == "number", "terminal job id missing")
  vim.fn.jobstop(job_id)
  local stopped = vim.wait(1000, function()
    local wait_ok, status = pcall(vim.fn.jobwait, { job_id }, 0)
    return wait_ok and status[1] ~= -1
  end)
  assert(stopped, "terminal job did not stop")
end

vim.o.lines = 20
assert(pcall(project_terminal))
local project_terminal_buf = vim.api.nvim_get_current_buf()
table.insert(terminal_buffers, project_terminal_buf)
local project_terminal_win = vim.api.nvim_get_current_win()
assert(vim.bo[project_terminal_buf].buftype == "terminal", "project terminal buffer not opened")
assert(
  vim.api.nvim_win_get_height(project_terminal_win) == _G.dotfiles_smoke_expected_terminal_height(20),
  "short UI terminal height " .. tostring(vim.api.nvim_win_get_height(project_terminal_win))
)
local actual_terminal_project = vim.fn.getcwd()
actual_terminal_project = uv.fs_realpath(actual_terminal_project) or actual_terminal_project
assert(actual_terminal_project == expected_terminal_project, "project terminal cwd " .. actual_terminal_project)
assert(pcall(hide_terminal))
assert(not vim.api.nvim_win_is_valid(project_terminal_win), "project terminal window should hide")

assert(vim.api.nvim_win_is_valid(source_terminal_win), "source window should remain")
vim.api.nvim_set_current_win(source_terminal_win)
assert(pcall(project_terminal))
assert(vim.api.nvim_get_current_buf() == project_terminal_buf, "project terminal buffer should be reused")
project_terminal_win = vim.api.nvim_get_current_win()
assert(pcall(hide_terminal))
assert(not vim.api.nvim_win_is_valid(project_terminal_win), "reused project terminal window should hide")

vim.api.nvim_set_current_win(source_terminal_win)
assert(pcall(project_terminal))
local stopped_project_terminal_buf = vim.api.nvim_get_current_buf()
local stopped_project_terminal_win = vim.api.nvim_get_current_win()
assert(stopped_project_terminal_buf == project_terminal_buf, "live project terminal should still be reused")
stop_terminal_job(stopped_project_terminal_buf)
assert(pcall(hide_terminal))
assert(not vim.api.nvim_win_is_valid(stopped_project_terminal_win), "stopped project terminal window should hide")

vim.api.nvim_set_current_win(source_terminal_win)
assert(pcall(project_terminal))
local restarted_project_terminal_buf = vim.api.nvim_get_current_buf()
table.insert(terminal_buffers, restarted_project_terminal_buf)
local restarted_project_terminal_win = vim.api.nvim_get_current_win()
assert(restarted_project_terminal_buf ~= project_terminal_buf, "stopped project terminal should not be reused")
assert(pcall(hide_terminal))
assert(not vim.api.nvim_win_is_valid(restarted_project_terminal_win), "restarted project terminal window should hide")

vim.api.nvim_set_current_win(source_terminal_win)
vim.o.lines = 80
assert(pcall(file_terminal))
local file_terminal_buf = vim.api.nvim_get_current_buf()
table.insert(terminal_buffers, file_terminal_buf)
local file_terminal_win = vim.api.nvim_get_current_win()
assert(vim.bo[file_terminal_buf].buftype == "terminal", "file terminal buffer not opened")
assert(file_terminal_buf ~= project_terminal_buf, "file terminal should use a directory-specific buffer")
assert(
  vim.api.nvim_win_get_height(file_terminal_win) == _G.dotfiles_smoke_expected_terminal_height(80),
  "tall UI terminal height " .. tostring(vim.api.nvim_win_get_height(file_terminal_win))
)
local actual_terminal_file_dir = vim.fn.getcwd()
actual_terminal_file_dir = uv.fs_realpath(actual_terminal_file_dir) or actual_terminal_file_dir
assert(actual_terminal_file_dir == expected_terminal_file_dir, "file terminal cwd " .. actual_terminal_file_dir)
assert(pcall(hide_terminal))
assert(not vim.api.nvim_win_is_valid(file_terminal_win), "file terminal window should hide")

;(function()
  local old_jobwait = vim.fn.jobwait
  local ok, err = pcall(function()
    vim.fn.jobwait = function()
      return "not-a-list"
    end
    if vim.api.nvim_win_is_valid(source_terminal_win) then
      vim.api.nvim_set_current_win(source_terminal_win)
    end
    assert(pcall(project_terminal))
  end)
  vim.fn.jobwait = old_jobwait
  assert(ok, err)
  local odd_jobwait_terminal_buf = vim.api.nvim_get_current_buf()
  table.insert(terminal_buffers, odd_jobwait_terminal_buf)
  local odd_jobwait_terminal_win = vim.api.nvim_get_current_win()
  assert(vim.bo[odd_jobwait_terminal_buf].buftype == "terminal", "odd jobwait terminal buffer not opened")
  assert(odd_jobwait_terminal_buf ~= restarted_project_terminal_buf, "odd jobwait terminal should not be reused")
  assert(pcall(hide_terminal))
  assert(not vim.api.nvim_win_is_valid(odd_jobwait_terminal_win), "odd jobwait terminal window should hide")
end)()

;(function()
  local old_cmd = vim.cmd
  local old_notify = vim.notify
  local notices = {}
  vim.notify = function(message, level)
    table.insert(notices, { message = tostring(message), level = level })
  end
  local ok, err = pcall(function()
    vim.cmd = function(command)
      if tostring(command):match("^botright%s+") then
        error("forced terminal split failure")
      end
      return old_cmd(command)
    end
    if vim.api.nvim_win_is_valid(source_terminal_win) then
      vim.api.nvim_set_current_win(source_terminal_win)
    end
    assert(pcall(project_terminal))
  end)
  vim.cmd = old_cmd
  vim.notify = old_notify
  assert(ok, err)
  assert(notices[1] and notices[1].level == vim.log.levels.WARN, vim.inspect(notices))
  assert(notices[1].message:find("Unable to open terminal split:", 1, true), notices[1].message)
end)()

local function assert_terminal_setup_failure_closes_split(label, should_fail, expected_message)
  local old_cmd = vim.cmd
  local old_notify = vim.notify
  local notices = {}
  local failure_fixture = vim.fn.tempname()
  local failure_file = failure_fixture .. "/sub/file.txt"
  local original_file = terminal_fixture .. "/sub/file.txt"
  vim.fn.delete(failure_fixture, "rf")
  vim.fn.mkdir(failure_fixture .. "/.git", "p")
  vim.fn.mkdir(failure_fixture .. "/sub", "p")
  vim.fn.writefile({ label }, failure_file)
  vim.notify = function(message, level)
    table.insert(notices, { message = tostring(message), level = level })
  end
  local ok, err = pcall(function()
    vim.cmd = function(command)
      command = tostring(command)
      if should_fail(command) then
        error("forced " .. label .. " failure")
      end
      return old_cmd(command)
    end
    if vim.api.nvim_win_is_valid(source_terminal_win) then
      vim.api.nvim_set_current_win(source_terminal_win)
    end
    vim.cmd("edit " .. vim.fn.fnameescape(failure_file))
    local window_count = #vim.api.nvim_tabpage_list_wins(0)
    assert(pcall(project_terminal))
    assert(
      #vim.api.nvim_tabpage_list_wins(0) == window_count,
      label .. " failure left a terminal split behind"
    )
  end)
  vim.cmd = old_cmd
  vim.notify = old_notify
  if vim.api.nvim_win_is_valid(source_terminal_win) then
    vim.api.nvim_set_current_win(source_terminal_win)
    vim.cmd("edit " .. vim.fn.fnameescape(original_file))
  end
  local failure_bufnr = vim.fn.bufnr(failure_file)
  if failure_bufnr > 0 and vim.api.nvim_buf_is_valid(failure_bufnr) then
    vim.api.nvim_buf_delete(failure_bufnr, { force = true })
  end
  vim.fn.delete(failure_fixture, "rf")
  assert(ok, err)
  assert(vim.api.nvim_win_is_valid(source_terminal_win), label .. " failure invalidated source window")
  vim.api.nvim_set_current_win(source_terminal_win)
  assert(notices[1] and notices[1].level == vim.log.levels.WARN, vim.inspect(notices))
  assert(notices[1].message:find(expected_message, 1, true), notices[1].message)
end

assert_terminal_setup_failure_closes_split("terminal lcd", function(command)
  return command:match("^lcd%s+") ~= nil
end, "Unable to set terminal directory:")

assert_terminal_setup_failure_closes_split("terminal command", function(command)
  return command == "terminal"
end, "Unable to open terminal:")

for _, bufnr in ipairs(terminal_buffers) do
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end
if vim.api.nvim_win_is_valid(source_terminal_win) then
  vim.api.nvim_set_current_win(source_terminal_win)
  vim.cmd("bwipeout!")
end
vim.o.shell = original_shell
vim.o.lines = vim.g.dotfiles_smoke_original_lines
vim.o.cmdheight = vim.g.dotfiles_smoke_original_cmdheight
vim.g.dotfiles_smoke_original_lines = nil
vim.g.dotfiles_smoke_original_cmdheight = nil
_G.dotfiles_smoke_expected_terminal_height = nil
vim.cmd("cd " .. vim.fn.fnameescape(original_terminal_cwd))
vim.fn.delete(terminal_fixture, "rf")

local cwd_fixture = vim.fn.tempname()
local cwd_other = vim.fn.tempname()
vim.fn.delete(cwd_fixture, "rf")
vim.fn.delete(cwd_other, "rf")
vim.fn.mkdir(cwd_fixture .. "/.git", "p")
vim.fn.mkdir(cwd_fixture .. "/app/src", "p")
vim.fn.mkdir(cwd_other, "p")
vim.fn.writefile({ "cwd target" }, cwd_fixture .. "/app/src/file.txt")
local expected_cwd_project = uv.fs_realpath(cwd_fixture) or cwd_fixture
local expected_cwd_file_dir = uv.fs_realpath(cwd_fixture .. "/app/src") or cwd_fixture .. "/app/src"
local original_cwd_mapping_cwd = vim.fn.getcwd()
vim.cmd("cd " .. vim.fn.fnameescape(cwd_other))
vim.cmd("edit " .. vim.fn.fnameescape(cwd_fixture .. "/app/src/file.txt"))
assert(pcall(project_cwd))
local actual_project_cwd = vim.fn.getcwd()
actual_project_cwd = uv.fs_realpath(actual_project_cwd) or actual_project_cwd
assert(actual_project_cwd == expected_cwd_project, "project cwd mapping " .. tostring(actual_project_cwd))
assert(pcall(file_cwd))
local actual_file_cwd = vim.fn.getcwd()
actual_file_cwd = uv.fs_realpath(actual_file_cwd) or actual_file_cwd
assert(actual_file_cwd == expected_cwd_file_dir, "file cwd mapping " .. tostring(actual_file_cwd))

;(function()
  local old_cmd = vim.cmd
  local old_notify = vim.notify
  local notices = {}
  vim.notify = function(message, level)
    table.insert(notices, { message = tostring(message), level = level })
  end
  local ok, err = pcall(function()
    vim.cmd = function(command)
      if tostring(command):match("^lcd%s+") then
        error("forced cwd failure")
      end
      return old_cmd(command)
    end
    assert(pcall(project_cwd))
  end)
  vim.cmd = old_cmd
  vim.notify = old_notify
  assert(ok, err)
  assert(notices[1] and notices[1].level == vim.log.levels.WARN, vim.inspect(notices))
  assert(notices[1].message:find("Unable to set Project cwd:", 1, true), notices[1].message)
end)()

vim.cmd("bwipeout!")
vim.cmd("cd " .. vim.fn.fnameescape(original_cwd_mapping_cwd))
vim.fn.delete(cwd_fixture, "rf")
vim.fn.delete(cwd_other, "rf")

local tmux_handoff_fixture = vim.fn.tempname()
vim.fn.delete(tmux_handoff_fixture, "rf")
vim.fn.mkdir(tmux_handoff_fixture .. "/.git", "p")
vim.fn.mkdir(tmux_handoff_fixture .. "/app/src", "p")
vim.fn.writefile({ "tmux handoff" }, tmux_handoff_fixture .. "/app/src/file.txt")

local tmux_fake_bin = vim.fn.tempname()
vim.fn.delete(tmux_fake_bin, "rf")
vim.fn.mkdir(tmux_fake_bin, "p")
local tmux_fake_log = tmux_fake_bin .. "/args.log"
local tmux_fake_notify_command = tmux_fake_bin .. "/tmux-session-notify"
local tmux_fake_session_command = tmux_fake_bin .. "/tmux-session"

vim.fn.writefile({
  "#!/bin/sh",
  'if [ "$1" = "display-message" ] && [ "$2" = "-p" ]; then',
  '  if [ "${TMUX_CLIENT_TEST_FAIL:-}" = "1" ]; then',
  "    exit 1",
  "  fi",
  '  printf "%s\\n" "%1"',
  "  exit 0",
  "fi",
  'echo "unexpected tmux command: $*" >&2',
  "exit 2",
}, tmux_fake_bin .. "/tmux")
vim.fn.setfperm(tmux_fake_bin .. "/tmux", "rwxr-xr-x")

local function write_fake_tmux_session_command(path, label)
  vim.fn.writefile({
    "#!/bin/sh",
    'if [ "${TMUX_SESSION_TEST_FAIL:-}" = "1" ]; then',
    '  echo "forced tmux-session failure" >&2',
    "  exit 42",
    "fi",
    'printf "%s\\n" "helper=' .. label .. '" >> "$TMUX_SESSION_TEST_LOG"',
    'printf "%s\\n" "$@" >> "$TMUX_SESSION_TEST_LOG"',
    'printf "%s\\n" "---" >> "$TMUX_SESSION_TEST_LOG"',
  }, path)
  vim.fn.setfperm(path, "rwxr-xr-x")
end

write_fake_tmux_session_command(tmux_fake_notify_command, "notify")
write_fake_tmux_session_command(tmux_fake_session_command, "session")

local old_tmux_env = vim.env.TMUX
local old_path_env = vim.env.PATH
vim.g.dotfiles_smoke_old_home_env = vim.env.HOME
local original_tmux_handoff_cwd = vim.fn.getcwd()
tmux_fake_home = vim.fn.tempname()
vim.fn.delete(tmux_fake_home, "rf")
vim.fn.mkdir(tmux_fake_home, "p")
vim.env.TMUX = "/tmp/tmux-test-socket"
vim.env.PATH = tmux_fake_bin .. ":/usr/bin:/bin:/usr/sbin:/sbin"
vim.env.HOME = tmux_fake_home
vim.env.TMUX_SESSION_TEST_LOG = tmux_fake_log
vim.cmd("cd " .. vim.fn.fnameescape(root))
vim.cmd("edit " .. vim.fn.fnameescape(tmux_handoff_fixture .. "/app/src/file.txt"))
local expected_tmux_handoff_project = uv.fs_realpath(tmux_handoff_fixture) or tmux_handoff_fixture
local old_notify = vim.notify
local notify_messages = {}
vim.notify = function(message, level)
  table.insert(notify_messages, { message = tostring(message), level = level })
end

local function assert_tmux_handoff_args(name, callback, expected_args, expected_notice)
  vim.fn.delete(tmux_fake_log)
  local start_notify_count = #notify_messages
  assert(pcall(callback), name)
  assert(
    vim.wait(1000, function()
      if vim.fn.filereadable(tmux_fake_log) ~= 1 then
        return false
      end
      local lines = vim.fn.readfile(tmux_fake_log)
      return lines[#lines] == "---"
    end, 10),
    name .. " did not invoke tmux session helper"
  )

  local actual_args = vim.fn.readfile(tmux_fake_log)
  assert(vim.deep_equal(actual_args, expected_args), name .. " args " .. vim.inspect(actual_args))
  if expected_notice then
    assert(
      vim.wait(1000, function()
        for i = start_notify_count + 1, #notify_messages do
          if notify_messages[i].message == expected_notice then
            return true
          end
        end
        return false
      end, 10),
      name .. " did not notify " .. expected_notice
    )
  end
end

assert_tmux_handoff_args("tmux project session", tmux_project_session, {
  "helper=notify",
  "--start-dir",
  expected_tmux_handoff_project,
  "---",
}, "Tmux project session: " .. expected_tmux_handoff_project)
assert_tmux_handoff_args("tmux project resume", tmux_project_resume, {
  "helper=notify",
  "--window",
  "resume",
  "--start-dir",
  expected_tmux_handoff_project,
  "---",
}, "Tmux project resume window: " .. expected_tmux_handoff_project)
assert_tmux_handoff_args("tmux project AI", tmux_project_ai, {
  "helper=notify",
  "--window",
  "agent",
  "--start-dir",
  expected_tmux_handoff_project,
  "---",
}, "Tmux project AI window: " .. expected_tmux_handoff_project)
assert_tmux_handoff_args("tmux project terminal", tmux_project_terminal, {
  "helper=notify",
  "--window",
  "terminal",
  "--start-dir",
  expected_tmux_handoff_project,
  "---",
}, "Tmux project terminal window: " .. expected_tmux_handoff_project)

local old_jobstart = vim.fn.jobstart
local function assert_tmux_jobstart_guard(name, fake_jobstart, expected_prefix)
  vim.fn.delete(tmux_fake_log)
  local start_notify_count = #notify_messages
  local ok, err = pcall(function()
    vim.fn.jobstart = fake_jobstart
    assert(pcall(tmux_project_session), name)
  end)
  vim.fn.jobstart = old_jobstart
  assert(ok, err)
  assert(vim.fn.filereadable(tmux_fake_log) == 0, name .. " should not invoke helper")
  assert(
    vim.wait(1000, function()
      for i = start_notify_count + 1, #notify_messages do
        if notify_messages[i].message:sub(1, #expected_prefix) == expected_prefix then
          return true
        end
      end
      return false
    end, 10),
    name .. " notification missing: " .. vim.inspect(notify_messages)
  )
end

assert_tmux_jobstart_guard("tmux project session jobstart exception", function()
  error("forced jobstart failure")
end, "Unable to start tmux-session:")

assert_tmux_jobstart_guard("tmux project session invalid job id", function()
  return "not-a-job-id"
end, "Unable to start tmux-session")

vim.fn.mkdir(tmux_fake_home .. "/.local/bin", "p")
local tmux_home_local_notify = tmux_fake_home .. "/.local/bin/tmux-session-notify"
write_fake_tmux_session_command(tmux_home_local_notify, "home-local-notify")
assert_tmux_handoff_args("tmux project session home local precedes PATH", tmux_project_session, {
  "helper=home-local-notify",
  "--start-dir",
  expected_tmux_handoff_project,
  "---",
}, "Tmux project session: " .. expected_tmux_handoff_project)
vim.fn.delete(tmux_home_local_notify)

vim.fn.mkdir(tmux_fake_home .. "/dotfiles/common/.local/bin", "p")
local tmux_home_dotfiles_precedence_notify = tmux_fake_home .. "/dotfiles/common/.local/bin/tmux-session-notify"
write_fake_tmux_session_command(tmux_home_dotfiles_precedence_notify, "home-dotfiles-precedence-notify")
assert_tmux_handoff_args("tmux project session home dotfiles precedes PATH", tmux_project_session, {
  "helper=home-dotfiles-precedence-notify",
  "--start-dir",
  expected_tmux_handoff_project,
  "---",
}, "Tmux project session: " .. expected_tmux_handoff_project)
vim.fn.delete(tmux_home_dotfiles_precedence_notify)

vim.fn.delete(tmux_fake_notify_command)
assert_tmux_handoff_args("tmux project session fallback", tmux_project_session, {
  "helper=session",
  "--start-dir",
  expected_tmux_handoff_project,
  "---",
}, "Tmux project session: " .. expected_tmux_handoff_project)

vim.fn.mkdir(tmux_fake_home .. "/dotfiles/common/.local/bin", "p")
tmux_home_dotfiles_notify = tmux_fake_home .. "/dotfiles/common/.local/bin/tmux-session-notify"
write_fake_tmux_session_command(tmux_home_dotfiles_notify, "home-dotfiles-notify")
vim.fn.delete(tmux_fake_session_command)
vim.env.HOME = tmux_fake_home
vim.env.PATH = tmux_fake_bin .. ":/usr/bin:/bin:/usr/sbin:/sbin"
assert_tmux_handoff_args("tmux project session home dotfiles fallback", tmux_project_session, {
  "helper=home-dotfiles-notify",
  "--start-dir",
  expected_tmux_handoff_project,
  "---",
}, "Tmux project session: " .. expected_tmux_handoff_project)
vim.fn.delete(tmux_home_dotfiles_notify)

vim.fn.delete(tmux_fake_log)
local unavailable_notify_start = #notify_messages
assert(pcall(tmux_project_session))
assert(vim.fn.filereadable(tmux_fake_log) == 0, "missing tmux session helpers should not invoke a helper")
assert(
  vim.wait(1000, function()
    for i = unavailable_notify_start + 1, #notify_messages do
      if notify_messages[i].message == "tmux-session is unavailable" then
        return true
      end
    end
    return false
  end, 10),
  "tmux session unavailable notification missing: " .. vim.inspect(notify_messages)
)

;(function()
  local old_executable = vim.fn.executable
  local old_exepath = vim.fn.exepath
  vim.fn.delete(tmux_fake_log)
  local lookup_failure_notify_start = #notify_messages
  local lookup_failure_ok, lookup_failure_err = pcall(function()
    vim.fn.executable = function(command)
      if command == "tmux" then
        return old_executable(command)
      end
      error("forced executable failure")
    end
    vim.fn.exepath = function()
      error("forced exepath failure")
    end
    assert(pcall(tmux_project_session))
  end)
  vim.fn.executable = old_executable
  vim.fn.exepath = old_exepath
  assert(lookup_failure_ok, lookup_failure_err)
  assert(vim.fn.filereadable(tmux_fake_log) == 0, "tmux session lookup failure should not invoke helper")
  assert(
    vim.wait(1000, function()
      for i = lookup_failure_notify_start + 1, #notify_messages do
        if notify_messages[i].message == "tmux-session is unavailable" then
          return true
        end
      end
      return false
    end, 10),
    "tmux session lookup failure notification missing: " .. vim.inspect(notify_messages)
  )

  vim.fn.delete(tmux_fake_log)
  local tmux_executable_failure_notify_start = #notify_messages
  local tmux_executable_failure_ok, tmux_executable_failure_err = pcall(function()
    vim.fn.executable = function(command)
      if command == "tmux" then
        error("forced tmux executable failure")
      end
      return old_executable(command)
    end
    assert(pcall(tmux_project_session))
  end)
  vim.fn.executable = old_executable
  assert(tmux_executable_failure_ok, tmux_executable_failure_err)
  assert(vim.fn.filereadable(tmux_fake_log) == 0, "tmux executable failure should not invoke helper")
  assert(
    vim.wait(1000, function()
      for i = tmux_executable_failure_notify_start + 1, #notify_messages do
        if notify_messages[i].message == "Not inside tmux" then
          return true
        end
      end
      return false
    end, 10),
    "tmux executable failure notification missing: " .. vim.inspect(notify_messages)
  )
end)()

vim.env.HOME = vim.g.dotfiles_smoke_old_home_env
vim.env.PATH = tmux_fake_bin .. ":/usr/bin:/bin:/usr/sbin:/sbin"
write_fake_tmux_session_command(tmux_fake_session_command, "session")
write_fake_tmux_session_command(tmux_fake_notify_command, "notify")

vim.fn.delete(tmux_fake_log)
vim.g.dotfiles_smoke_stale_notify_start = #notify_messages
vim.env.TMUX_CLIENT_TEST_FAIL = "1"
assert(pcall(tmux_project_session))
assert(vim.fn.filereadable(tmux_fake_log) == 0, "stale tmux client should not invoke helper")
assert(
  vim.wait(1000, function()
    for i = vim.g.dotfiles_smoke_stale_notify_start + 1, #notify_messages do
      if notify_messages[i].message == "Not inside tmux" then
        return true
      end
    end
    return false
  end, 10),
  "stale tmux client notification missing: " .. vim.inspect(notify_messages)
)
vim.env.TMUX_CLIENT_TEST_FAIL = nil

vim.fn.delete(tmux_fake_log)
local old_system = vim.fn.system
local system_failure_notify_start = #notify_messages
local system_failure_ok, system_failure_err = pcall(function()
  vim.fn.system = function()
    error("forced tmux probe failure")
  end
  assert(pcall(tmux_project_session))
end)
vim.fn.system = old_system
assert(system_failure_ok, system_failure_err)
assert(vim.fn.filereadable(tmux_fake_log) == 0, "tmux probe failure should not invoke helper")
assert(
  vim.wait(1000, function()
    for i = system_failure_notify_start + 1, #notify_messages do
      if notify_messages[i].message == "Not inside tmux" then
        return true
      end
    end
    return false
  end, 10),
  "tmux probe failure notification missing: " .. vim.inspect(notify_messages)
)

vim.env.HOME = tmux_fake_home
vim.env.TMUX_SESSION_TEST_FAIL = "1"
assert(pcall(tmux_project_session))
local failure_notification
assert(
  vim.wait(1000, function()
    for _, item in ipairs(notify_messages) do
      if item.message:find("forced tmux%-session failure") then
        failure_notification = item
        return true
      end
    end
    return false
  end, 10),
  "tmux project session failure notification missing: " .. vim.inspect(notify_messages)
)
assert(failure_notification.level == vim.log.levels.WARN)
vim.env.TMUX_SESSION_TEST_FAIL = nil
vim.notify = old_notify

vim.env.TMUX = old_tmux_env
vim.env.PATH = old_path_env
vim.env.HOME = vim.g.dotfiles_smoke_old_home_env
vim.env.TMUX_SESSION_TEST_LOG = nil
vim.g.dotfiles_smoke_stale_notify_start = nil
vim.cmd("bwipeout!")
vim.cmd("cd " .. vim.fn.fnameescape(original_tmux_handoff_cwd))
vim.fn.delete(tmux_handoff_fixture, "rf")
vim.fn.delete(tmux_fake_bin, "rf")
vim.fn.delete(tmux_fake_home, "rf")

local path_copy_fixture = vim.fn.tempname() .. ".txt"
vim.fn.writefile({ "first", "second", "third" }, path_copy_fixture)
local original_path_copy_cwd = vim.fn.getcwd()
vim.cmd("cd " .. vim.fn.fnameescape(vim.fs.dirname(path_copy_fixture)))
vim.cmd("edit " .. vim.fn.fnameescape(path_copy_fixture))
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local expected_path = vim.fn.expand("%:p")
local expected_relative_path = vim.fn.fnamemodify(path_copy_fixture, ":t")
assert(pcall(path_copy))
assert(vim.fn.getreg("+") == expected_path or vim.fn.getreg('"') == expected_path)
assert(pcall(path_line_copy))
local expected_path_line = expected_path .. ":2"
assert(vim.fn.getreg("+") == expected_path_line or vim.fn.getreg('"') == expected_path_line)
assert(pcall(relative_path_copy))
assert(vim.fn.getreg("+") == expected_relative_path or vim.fn.getreg('"') == expected_relative_path)
assert(pcall(relative_path_line_copy))
local expected_relative_path_line = expected_relative_path .. ":2"
assert(vim.fn.getreg("+") == expected_relative_path_line or vim.fn.getreg('"') == expected_relative_path_line)
vim.cmd("bwipeout!")
vim.cmd("cd " .. vim.fn.fnameescape(original_path_copy_cwd))
vim.fn.delete(path_copy_fixture)

local project_path_fixture = vim.fn.tempname()
vim.fn.delete(project_path_fixture, "rf")
vim.fn.mkdir(project_path_fixture .. "/.git", "p")
vim.fn.mkdir(project_path_fixture .. "/src", "p")
vim.fn.writefile({ "alpha", "beta", "gamma" }, project_path_fixture .. "/src/main.lua")
local original_project_path_cwd = vim.fn.getcwd()
vim.cmd("cd " .. vim.fn.fnameescape(project_path_fixture .. "/src"))
vim.cmd("edit " .. vim.fn.fnameescape(project_path_fixture .. "/src/main.lua"))
vim.api.nvim_win_set_cursor(0, { 2, 0 })
assert(pcall(project_path_copy))
assert(vim.fn.getreg("+") == "src/main.lua" or vim.fn.getreg('"') == "src/main.lua")
assert(pcall(project_path_line_copy))
assert(vim.fn.getreg("+") == "src/main.lua:2" or vim.fn.getreg('"') == "src/main.lua:2")
vim.cmd("bwipeout!")
vim.cmd("cd " .. vim.fn.fnameescape(original_project_path_cwd))
vim.fn.delete(project_path_fixture, "rf")

local jj_project_fixture = vim.fn.tempname()
vim.fn.delete(jj_project_fixture, "rf")
vim.fn.mkdir(jj_project_fixture .. "/.jj", "p")
vim.fn.mkdir(jj_project_fixture .. "/pkg/lib", "p")
vim.fn.writefile({ "one", "two" }, jj_project_fixture .. "/pkg/lib/mod.lua")
local original_jj_project_cwd = vim.fn.getcwd()
vim.cmd("cd " .. vim.fn.fnameescape(jj_project_fixture .. "/pkg"))
vim.cmd("edit " .. vim.fn.fnameescape(jj_project_fixture .. "/pkg/lib/mod.lua"))
vim.api.nvim_win_set_cursor(0, { 2, 0 })
assert(pcall(project_path_copy))
assert(vim.fn.getreg("+") == "pkg/lib/mod.lua" or vim.fn.getreg('"') == "pkg/lib/mod.lua")
assert(pcall(project_path_line_copy))
assert(vim.fn.getreg("+") == "pkg/lib/mod.lua:2" or vim.fn.getreg('"') == "pkg/lib/mod.lua:2")
vim.cmd("bwipeout!")
vim.cmd("cd " .. vim.fn.fnameescape(original_jj_project_cwd))
vim.fn.delete(jj_project_fixture, "rf")

vim.cmd("enew!")
vim.fn.setreg('"', "keep-me")
assert(pcall(project_path_copy))
assert(vim.fn.getreg('"') == "keep-me")

;(function()
  local plus_ok = pcall(vim.fn.setreg, "+", "keep-plus")
  vim.cmd("enew!")
  vim.bo.buftype = "nofile"
  vim.api.nvim_buf_set_name(0, "/tmp/not-a-real-file.txt")
  vim.fn.setreg('"', "keep-quote")
  assert(pcall(path_copy))
  assert(vim.fn.getreg('"') == "keep-quote")
  if plus_ok then
    assert(vim.fn.getreg("+") == "keep-plus")
  end
  vim.cmd("bwipeout!")
end)()

;(function()
  local fallback_fixture = vim.fn.tempname() .. ".txt"
  vim.fn.writefile({ "fallback" }, fallback_fixture)
  vim.cmd("edit " .. vim.fn.fnameescape(fallback_fixture))
  local expected = vim.fn.expand("%:p")
  local old_setreg = vim.fn.setreg
  local ok, err = pcall(function()
    vim.fn.setreg = function(register, value)
      if register == "+" then
        error("forced plus register failure")
      end
      return old_setreg(register, value)
    end
    assert(pcall(path_copy))
    assert(vim.fn.getreg('"') == expected)
  end)
  vim.fn.setreg = old_setreg
  vim.cmd("bwipeout!")
  vim.fn.delete(fallback_fixture)
  assert(ok, err)
end)()

;(function()
  local failure_fixture = vim.fn.tempname() .. ".txt"
  vim.fn.writefile({ "failure" }, failure_fixture)
  vim.cmd("edit " .. vim.fn.fnameescape(failure_fixture))
  local old_setreg = vim.fn.setreg
  local old_notify = vim.notify
  local notices = {}
  local ok, err = pcall(function()
    vim.fn.setreg = function()
      error("forced register failure")
    end
    vim.notify = function(message, level)
      table.insert(notices, { message = tostring(message), level = level })
    end
    assert(pcall(path_copy))
    assert(notices[1] and notices[1].level == vim.log.levels.WARN, vim.inspect(notices))
    assert(notices[1].message:find("Unable to copy path:", 1, true), notices[1].message)
  end)
  vim.fn.setreg = old_setreg
  vim.notify = old_notify
  vim.cmd("bwipeout!")
  vim.fn.delete(failure_fixture)
  assert(ok, err)
end)()

local telescope_spec = dofile(root .. "/common/.config/nvim/lua/plugins/telescope-ignore.lua")
local telescope = telescope_spec[2]
local opts = {}
telescope.opts(nil, opts)

local function has(list, value)
  for _, item in ipairs(list) do
    if item == value then
      return true
    end
  end
  return false
end

local live_args = opts.pickers.live_grep.additional_args()
local live_args_again = opts.pickers.live_grep.additional_args()
local file_args = opts.pickers.find_files.additional_args()
live_args[1] = "mutated"
assert(live_args_again[1] == "--hidden")
assert(has(live_args_again, "--glob=!.cache/**"))
assert(has(live_args_again, "--glob=!.tox/**"))
assert(has(live_args_again, "--glob=!vendor/**"))
assert(has(live_args_again, "--glob=!build/**"))
assert(has(live_args_again, "--glob=!.next/**"))
assert(has(live_args_again, "--glob=!.terraform/**"))
assert(has(live_args_again, "--glob=!.gradle/**"))
assert(has(live_args_again, "--glob=!android/.gradle/**"))
assert(has(live_args_again, "--glob=!target/**"))
assert(has(live_args_again, "--glob=!.zig-cache/**"))
assert(has(live_args_again, "--glob=!coverage/**"))
assert(has(file_args, "--exclude=build"))
assert(has(file_args, "--exclude=vendor"))
assert(has(file_args, "--exclude=.next"))
assert(has(file_args, "--exclude=.terraform"))
assert(has(file_args, "--exclude=.gradle"))
assert(has(file_args, "--exclude=target"))
assert(has(file_args, "--exclude=.zig-cache"))
assert(has(file_args, "--exclude=CMakeCache.txt"))
assert(has(file_args, "--exclude=compile_commands.json"))
assert(has(file_args, "--exclude=docs/_build"))
assert(not has(file_args, "--glob=!build/**"))
assert(has(opts.defaults.file_ignore_patterns, "^%.git/"))
assert(has(opts.defaults.file_ignore_patterns, "^%.next/"))
assert(has(opts.defaults.file_ignore_patterns, "^%.terraform/"))
assert(has(opts.defaults.file_ignore_patterns, "^%.zig%-cache/"))
assert(not has(opts.defaults.file_ignore_patterns, "^.git/"))
assert(not has(opts.defaults.file_ignore_patterns, "^.next/"))
assert(not has(opts.defaults.file_ignore_patterns, "^.vscode/"))
assert(opts.defaults.hidden == true)
assert(opts.pickers.find_files.hidden == true)
local telescope_keys = telescope.keys()
assert(#telescope_keys == 3)

local function spec_callback(keys, lhs)
  for _, key in ipairs(keys) do
    if key[1] == lhs then
      assert(type(key[2]) == "function", lhs .. " should be a callback key")
      return key[2]
    end
  end
  error("missing key: " .. lhs)
end

local loaded_telescope_extension
local captured_live_grep
package.loaded["telescope"] = {
  extensions = {
    live_grep_args = {
      live_grep_args = function(opts)
        captured_live_grep = opts
      end,
    },
  },
  load_extension = function(name)
    loaded_telescope_extension = name
  end,
}

spec_callback(telescope_keys, "<leader>se")()
assert(loaded_telescope_extension == "live_grep_args")
local cpp_python_args = captured_live_grep.additional_args()
assert(has(cpp_python_args, "--type=cpp"))
assert(has(cpp_python_args, "--type=py"))
assert(has(cpp_python_args, "--glob=!blob/**"))
cpp_python_args[1] = "mutated"
assert(captured_live_grep.additional_args()[1] == "--type=cpp")

spec_callback(telescope_keys, "<leader>sA")()
local grep_args = captured_live_grep.additional_args()
assert(grep_args[1] == "--hidden")
assert(has(grep_args, "--glob=!build/**"))
grep_args[1] = "mutated"
assert(captured_live_grep.additional_args()[1] == "--hidden")

vim.cmd("enew!")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "needle value" })
vim.api.nvim_win_set_cursor(0, { 1, 1 })
vim.bo.filetype = "cpp"
vim.bo.modified = false
spec_callback(telescope_keys, "<leader>st")()
assert(captured_live_grep.default_text == "needle")
local current_type_args = captured_live_grep.additional_args()
assert(current_type_args[1] == "--type=cpp")
assert(has(current_type_args, "--glob=!*.blob.*"))
vim.bo.filetype = "objcpp"
spec_callback(telescope_keys, "<leader>st")()
local objcpp_type_args = captured_live_grep.additional_args()
assert(objcpp_type_args[1] == "--type=objcpp")
vim.bo.filetype = ""
vim.api.nvim_buf_set_name(0, "schema/example.proto")
spec_callback(telescope_keys, "<leader>st")()
local extension_type_args = captured_live_grep.additional_args()
assert(extension_type_args[1] == "--glob=*.proto")
assert(has(extension_type_args, "--glob=!blob/**"))

;(function()
  local yazi_spec = dofile(root .. "/common/.config/nvim/lua/plugins/yazi.lua")
  assert(yazi_spec[1].cmd == "Yazi", "yazi should register a lazy command")
  assert(yazi_spec[1].event == nil, "yazi should not load eagerly")

  local lf_spec = dofile(root .. "/common/.config/nvim/lua/plugins/lf.lua")
  assert(lf_spec[1].cmd == "Lf", "lf should register a lazy command")
  local has_lf_key = false
  local lf_project_callback
  for _, key in ipairs(lf_spec[1].keys) do
    if key[1] == "<leader>E" and key.desc == "LF at project root" and type(key[2]) == "function" then
      has_lf_key = true
      lf_project_callback = key[2]
    end
  end
  assert(has_lf_key, "lf missing <leader>E mapping")

  local lf_key_fixture = vim.fn.tempname() .. " key root"
  local lf_key_other = vim.fn.tempname()
  vim.fn.delete(lf_key_fixture, "rf")
  vim.fn.delete(lf_key_other, "rf")
  vim.fn.mkdir(lf_key_fixture .. "/.git", "p")
  vim.fn.mkdir(lf_key_fixture .. "/pkg", "p")
  vim.fn.mkdir(lf_key_other, "p")
  local lf_key_file = lf_key_fixture .. "/pkg/file.txt"
  vim.fn.writefile({ "lf key target" }, lf_key_file)
  local expected_lf_key_project = uv.fs_realpath(lf_key_fixture) or lf_key_fixture
  local original_lf_key_cwd = vim.fn.getcwd()
  local captured_lf_key_dir
  package.loaded["fm-nvim"] = {
    Lf = function(dir)
      captured_lf_key_dir = dir
    end,
  }
  vim.cmd("cd " .. vim.fn.fnameescape(lf_key_other))
  vim.cmd("edit " .. vim.fn.fnameescape(lf_key_file))
  assert(pcall(lf_project_callback))
  assert(
    captured_lf_key_dir == vim.fn.shellescape(expected_lf_key_project),
    "LF key dir " .. tostring(captured_lf_key_dir)
  )
  package.loaded["fm-nvim"] = nil

  local captured_lf_command_dir
  pcall(vim.api.nvim_del_user_command, "Lf")
  vim.api.nvim_create_user_command("Lf", function(opts)
    captured_lf_command_dir = opts.fargs[1]
  end, { nargs = "*" })
  assert(pcall(lf_project_callback))
  assert(captured_lf_command_dir == expected_lf_key_project, "LF command dir " .. tostring(captured_lf_command_dir))
  pcall(vim.api.nvim_del_user_command, "Lf")

  local old_notify = vim.notify
  local lf_notices = {}
  vim.notify = function(message, level)
    table.insert(lf_notices, { message = tostring(message), level = level })
  end
  local function has_lf_warning(prefix)
    for _, notice in ipairs(lf_notices) do
      if notice.level == vim.log.levels.WARN and notice.message:sub(1, #prefix) == prefix then
        return true
      end
    end
    return false
  end

  vim.api.nvim_create_user_command("Lf", function()
    error("forced LF failure")
  end, { nargs = "*" })
  assert(pcall(lf_project_callback))
  assert(has_lf_warning("Unable to open LF:"), vim.inspect(lf_notices))
  pcall(vim.api.nvim_del_user_command, "Lf")

  assert(pcall(lf_project_callback))
  assert(has_lf_warning("LF is unavailable"), vim.inspect(lf_notices))
  vim.notify = old_notify

  vim.cmd("bwipeout!")
  vim.cmd("cd " .. vim.fn.fnameescape(original_lf_key_cwd))
  vim.fn.delete(lf_key_fixture, "rf")
  vim.fn.delete(lf_key_other, "rf")
end)()

local tasks_spec = dofile(root .. "/common/.config/nvim/lua/plugins/tasks.lua")
local task_keys = tasks_spec[1].keys()
assert(#task_keys == 9)

local overseer_setup_opts
local preloaded_task_dirs = {}
local run_task_opts = {}
package.loaded["overseer"] = {
  TAG = { BUILD = "BUILD" },
  setup = function(opts)
    overseer_setup_opts = opts
  end,
  preload_task_cache = function(opts)
    table.insert(preloaded_task_dirs, opts.dir)
  end,
  run_task = function(opts)
    table.insert(run_task_opts, opts)
  end,
}

tasks_spec[1].config(nil, { sentinel = true })
assert(overseer_setup_opts.sentinel == true)

local tasks_project = vim.fn.tempname()
local tasks_other_cwd = vim.fn.tempname()
vim.fn.delete(tasks_project, "rf")
vim.fn.delete(tasks_other_cwd, "rf")
vim.fn.mkdir(tasks_project .. "/.vscode", "p")
vim.fn.mkdir(tasks_project .. "/src", "p")
vim.fn.mkdir(tasks_other_cwd, "p")
vim.fn.writefile({ "{}" }, tasks_project .. "/.vscode/tasks.json")
vim.fn.writefile({ "int task_main() { return 0; }" }, tasks_project .. "/src/task.cpp")

local original_task_cwd = vim.fn.getcwd()
local expected_tasks_project = uv.fs_realpath(tasks_project) or tasks_project
vim.cmd("cd " .. vim.fn.fnameescape(tasks_other_cwd))
vim.cmd("edit " .. vim.fn.fnameescape(tasks_project .. "/src/task.cpp"))
vim.cmd("doautocmd BufEnter")
local actual_tasks_project = preloaded_task_dirs[#preloaded_task_dirs]
actual_tasks_project = actual_tasks_project and (uv.fs_realpath(actual_tasks_project) or actual_tasks_project)
assert(
  actual_tasks_project == expected_tasks_project,
  "preloaded task dir " .. tostring(preloaded_task_dirs[#preloaded_task_dirs])
)
local preload_count = #preloaded_task_dirs
vim.cmd("doautocmd BufEnter")
assert(#preloaded_task_dirs == preload_count, "task dir should only preload once")

local marker_tasks_project = vim.fn.tempname()
vim.fn.delete(marker_tasks_project, "rf")
vim.fn.mkdir(marker_tasks_project .. "/.git", "p")
vim.fn.mkdir(marker_tasks_project .. "/src", "p")
vim.fn.writefile({ "print('task')" }, marker_tasks_project .. "/src/task.lua")
vim.cmd("cd " .. vim.fn.fnameescape(tasks_other_cwd))
vim.cmd("edit " .. vim.fn.fnameescape(marker_tasks_project .. "/src/task.lua"))
vim.cmd("doautocmd BufEnter")
local actual_marker_tasks_project = preloaded_task_dirs[#preloaded_task_dirs]
actual_marker_tasks_project = actual_marker_tasks_project
  and (uv.fs_realpath(actual_marker_tasks_project) or actual_marker_tasks_project)
local expected_marker_tasks_project = uv.fs_realpath(marker_tasks_project) or marker_tasks_project
assert(
  actual_marker_tasks_project == expected_marker_tasks_project,
  "marker fallback task dir " .. tostring(preloaded_task_dirs[#preloaded_task_dirs])
)
vim.fn.delete(marker_tasks_project, "rf")

vim.cmd("edit " .. vim.fn.fnameescape(tasks_project .. "/src/task.cpp"))
vim.bo.filetype = "cpp"
assert(pcall(spec_callback(task_keys, "<leader>mb")))
local build_task_opts = run_task_opts[#run_task_opts]
assert(build_task_opts.cwd == expected_tasks_project, "build task cwd " .. tostring(build_task_opts.cwd))
assert(build_task_opts.search_params.dir == expected_tasks_project)
assert(build_task_opts.search_params.filetype == "cpp")
assert(build_task_opts.tags[1] == "BUILD")
assert(build_task_opts.first == nil)

assert(pcall(spec_callback(task_keys, "<leader>mB")))
local pick_build_task_opts = run_task_opts[#run_task_opts]
assert(pick_build_task_opts.cwd == expected_tasks_project, "pick build cwd " .. tostring(pick_build_task_opts.cwd))
assert(pick_build_task_opts.search_params.dir == expected_tasks_project)
assert(pick_build_task_opts.tags[1] == "BUILD")
assert(pick_build_task_opts.first == false)

assert(pcall(spec_callback(task_keys, "<leader>mT")))
local pick_task_opts = run_task_opts[#run_task_opts]
assert(pick_task_opts.cwd == expected_tasks_project, "task picker cwd " .. tostring(pick_task_opts.cwd))
assert(pick_task_opts.search_params.dir == expected_tasks_project)
assert(pick_task_opts.first == false)
assert(pick_task_opts.tags == nil)

;(function()
  local old_notify = vim.notify
  local task_notices = {}
  vim.notify = function(message, level)
    table.insert(task_notices, { message = tostring(message), level = level })
  end

  local function saw_task_warning(prefix)
    for _, notice in ipairs(task_notices) do
      if notice.level == vim.log.levels.WARN and notice.message:find(prefix, 1, true) then
        return true
      end
    end
    return false
  end

  local action_task = { name = "compile" }
  local list_task_opts = {}
  local task_actions = {}
  package.loaded["overseer"].list_tasks = function(opts)
    table.insert(list_task_opts, opts)
    return { action_task }
  end
  package.loaded["overseer"].run_action = function(task, action)
    table.insert(task_actions, { task = task, action = action })
  end

  assert(pcall(spec_callback(task_keys, "<leader>mt")))
  assert(task_actions[#task_actions].task == action_task)
  assert(task_actions[#task_actions].action == "restart")
  assert(list_task_opts[#list_task_opts].unique == true)
  assert(list_task_opts[#list_task_opts].status == nil)

  assert(pcall(spec_callback(task_keys, "<leader>mc")))
  assert(task_actions[#task_actions].task == action_task)
  assert(task_actions[#task_actions].action == "stop")
  assert(list_task_opts[#list_task_opts].unique == true)
  assert(list_task_opts[#list_task_opts].status == "RUNNING")

  package.loaded["overseer"].run_task = function()
    error("forced run_task failure")
  end
  assert(pcall(spec_callback(task_keys, "<leader>mb")))
  assert(saw_task_warning("Unable to run task:"), vim.inspect(task_notices))

  package.loaded["overseer"].list_tasks = function()
    error("forced list_tasks failure")
  end
  assert(pcall(spec_callback(task_keys, "<leader>mt")))
  assert(saw_task_warning("Unable to list tasks:"), vim.inspect(task_notices))
  assert(pcall(spec_callback(task_keys, "<leader>mc")))
  assert(saw_task_warning("Unable to list running tasks:"), vim.inspect(task_notices))

  package.loaded["overseer"].list_tasks = function()
    return { action_task }
  end
  package.loaded["overseer"].run_action = function(_, action)
    error("forced " .. action .. " failure")
  end
  assert(pcall(spec_callback(task_keys, "<leader>mt")))
  assert(saw_task_warning("Unable to restart task:"), vim.inspect(task_notices))
  assert(pcall(spec_callback(task_keys, "<leader>mc")))
  assert(saw_task_warning("Unable to stop task:"), vim.inspect(task_notices))

  pcall(vim.api.nvim_del_user_command, "OverseerToggle")
  vim.api.nvim_create_user_command("OverseerToggle", function()
    error("forced OverseerToggle failure")
  end, {})
  assert(pcall(spec_callback(task_keys, "<leader>mo")))
  assert(saw_task_warning("Unable to toggle Overseer:"), vim.inspect(task_notices))
  pcall(vim.api.nvim_del_user_command, "OverseerToggle")
  vim.notify = old_notify
end)()

vim.cmd("cd " .. vim.fn.fnameescape(original_task_cwd))

;(function()
  local loaded_launchjs
  local loaded_launchjs_types
  local continued = false
  local pick_process = function() end
  local attach_cfg = { request = "attach", processId = "${command:pickProcess}" }
  local remote_attach_cfg = { request = "attach", processId = " ${command:pickRemoteProcess} " }
  local extension_attach_cfg = { request = "attach", pid = "${command:extension.pickProcess}" }
  local extension_remote_attach_cfg = { request = "attach", pid = "${command:codelldb.pickRemoteProcess}" }
  local literal_attach_cfg = { request = "attach", pid = "12345" }
  local launch_with_process_id_cfg = { request = "launch", processId = "${command:pickProcess}" }
  local dap_stub = {
    adapters = { codelldb = { type = "server" } },
    configurations = {
      cpp = {
        attach_cfg,
        remote_attach_cfg,
        extension_attach_cfg,
        extension_remote_attach_cfg,
        literal_attach_cfg,
        launch_with_process_id_cfg,
      },
    },
    continue = function()
      continued = true
    end,
  }

  package.loaded["dap"] = dap_stub
  package.loaded["dap.utils"] = { pick_process = pick_process }
  package.loaded["dap.ext.vscode"] = {
    load_launchjs = function(path, types)
      loaded_launchjs = path
      loaded_launchjs_types = types
    end,
  }

  local project = vim.fn.tempname()
  local other_cwd = vim.fn.tempname()
  vim.fn.mkdir(project .. "/.vscode", "p")
  vim.fn.mkdir(project .. "/src", "p")
  vim.fn.mkdir(other_cwd, "p")
  vim.fn.writefile({ "{}" }, project .. "/.vscode/launch.json")
  vim.fn.writefile({ "int main() { return 0; }" }, project .. "/src/main.cpp")

  local original_cwd = vim.fn.getcwd()
  vim.cmd("cd " .. vim.fn.fnameescape(other_cwd))
  vim.cmd("edit " .. vim.fn.fnameescape(project .. "/src/main.cpp"))
  local debug_ok, debug_err = pcall(spec_callback(task_keys, "<leader>mr"))
  assert(debug_ok, tostring(debug_err))
  local expected_launchjs = uv.fs_realpath(project .. "/.vscode/launch.json") or project .. "/.vscode/launch.json"
  local actual_launchjs = loaded_launchjs and (uv.fs_realpath(loaded_launchjs) or loaded_launchjs)
  assert(
    actual_launchjs == expected_launchjs,
    "loaded launch.json from " .. tostring(loaded_launchjs)
  )
  assert(continued, "dap.continue was not called")
  assert(dap_stub.adapters.lldb == dap_stub.adapters.codelldb, "lldb adapter was not aliased")
  assert(attach_cfg.pid == pick_process, "attach processId was not normalized")
  assert(attach_cfg.processId == nil, "attach processId should be cleared")
  assert(remote_attach_cfg.pid == pick_process, "remote attach processId was not normalized")
  assert(remote_attach_cfg.processId == nil, "remote attach processId should be cleared")
  assert(extension_attach_cfg.pid == pick_process, "extension attach pid was not normalized")
  assert(extension_remote_attach_cfg.pid == pick_process, "extension remote attach pid was not normalized")
  assert(literal_attach_cfg.pid == "12345", "literal attach pid should remain unchanged")
  assert(
    launch_with_process_id_cfg.processId == "${command:pickProcess}",
    "launch processId should remain unchanged"
  )
  assert(has(loaded_launchjs_types.lldb, "objc"), "lldb launch mapping missing objc")
  assert(has(loaded_launchjs_types.lldb, "objcpp"), "lldb launch mapping missing objcpp")
  assert(has(loaded_launchjs_types.codelldb, "objc"), "codelldb launch mapping missing objc")
  assert(has(loaded_launchjs_types.codelldb, "objcpp"), "codelldb launch mapping missing objcpp")
  vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
  vim.cmd("bwipeout!")
  vim.fn.delete(project, "rf")
  vim.fn.delete(other_cwd, "rf")
end)()

;(function()
  local old_notify = vim.notify
  local old_ui_select = vim.ui.select
  local task_debug_notices = {}
  vim.notify = function(message, level)
    table.insert(task_debug_notices, { message = tostring(message), level = level })
  end

  local function saw_task_debug_warning(prefix)
    for _, notice in ipairs(task_debug_notices) do
      if notice.level == vim.log.levels.WARN and notice.message:find(prefix, 1, true) then
        return true
      end
    end
    return false
  end

  local original_dap = package.loaded["dap"]
  local original_dap_utils = package.loaded["dap.utils"]
  local original_dap_vscode = package.loaded["dap.ext.vscode"]
  package.loaded["dap.utils"] = { pick_process = function() end }

  local debug_failure_project = vim.fn.tempname()
  local debug_failure_other = vim.fn.tempname()
  vim.fn.delete(debug_failure_project, "rf")
  vim.fn.delete(debug_failure_other, "rf")
  vim.fn.mkdir(debug_failure_project .. "/.vscode", "p")
  vim.fn.mkdir(debug_failure_project .. "/src", "p")
  vim.fn.mkdir(debug_failure_other, "p")
  vim.fn.writefile({ "{}" }, debug_failure_project .. "/.vscode/launch.json")
  vim.fn.writefile({ "int main() { return 0; }" }, debug_failure_project .. "/src/main.cpp")

  local original_cwd = vim.fn.getcwd()
  vim.cmd("cd " .. vim.fn.fnameescape(debug_failure_other))
  vim.cmd("edit " .. vim.fn.fnameescape(debug_failure_project .. "/src/main.cpp"))

  local continued_after_launch_failure = false
  package.loaded["dap"] = {
    adapters = {},
    configurations = { cpp = {} },
    continue = function()
      continued_after_launch_failure = true
    end,
  }
  package.loaded["dap.ext.vscode"] = {
    load_launchjs = function()
      error("forced launch load failure")
    end,
  }
  assert(pcall(spec_callback(task_keys, "<leader>mr")))
  assert(saw_task_debug_warning("Unable to load launch.json:"), vim.inspect(task_debug_notices))
  assert(continued_after_launch_failure, "debug start did not continue after launch.json warning")

  package.loaded["dap.ext.vscode"] = {
    load_launchjs = function() end,
  }
  package.loaded["dap"] = {
    adapters = {},
    configurations = { cpp = {} },
    continue = function()
      error("forced debug continue failure")
    end,
  }
  assert(pcall(spec_callback(task_keys, "<leader>mr")))
  assert(saw_task_debug_warning("Unable to start debug session:"), vim.inspect(task_debug_notices))

  package.loaded["dap"] = {
    adapters = {},
    configurations = {},
  }
  assert(pcall(spec_callback(task_keys, "<leader>mR")))
  assert(saw_task_debug_warning("No DAP configurations found"), vim.inspect(task_debug_notices))

  package.loaded["dap"] = {
    adapters = {},
    configurations = { cpp = { { name = "Launch" } } },
  }
  vim.ui.select = function()
    error("forced select failure")
  end
  assert(pcall(spec_callback(task_keys, "<leader>mR")))
  assert(saw_task_debug_warning("Unable to show debug configuration picker:"), vim.inspect(task_debug_notices))

  package.loaded["dap"] = {
    adapters = {},
    configurations = { cpp = { { name = "Launch" } } },
    run = function()
      error("forced dap run failure")
    end,
  }
  vim.ui.select = function(items, _, callback)
    callback(items[1])
  end
  assert(pcall(spec_callback(task_keys, "<leader>mR")))
  assert(saw_task_debug_warning("Unable to run debug configuration:"), vim.inspect(task_debug_notices))

  package.loaded["dap"] = {
    adapters = {},
    configurations = {},
    session = function()
      error("forced session failure")
    end,
    run_to_cursor = function() end,
  }
  assert(pcall(spec_callback(task_keys, "<leader>mp")))
  assert(saw_task_debug_warning("Unable to inspect DAP session:"), vim.inspect(task_debug_notices))

  package.loaded["dap"] = {
    adapters = {},
    configurations = {},
    session = function()
      return {}
    end,
    run_to_cursor = function()
      error("forced run_to_cursor failure")
    end,
  }
  assert(pcall(spec_callback(task_keys, "<leader>mp")))
  assert(saw_task_debug_warning("Unable to run to cursor:"), vim.inspect(task_debug_notices))

  package.loaded["dap"] = {
    adapters = {},
    configurations = {},
    session = function()
      return nil
    end,
    run_to_cursor = function() end,
  }
  assert(pcall(spec_callback(task_keys, "<leader>mp")))
  assert(saw_task_debug_warning("Unable to install break-at-cursor hook:"), vim.inspect(task_debug_notices))

  package.loaded["dap"] = {
    adapters = {},
    configurations = {},
    listeners = { after = { event_initialized = {} } },
    session = function()
      return nil
    end,
    run_to_cursor = function() end,
    continue = function()
      error("forced break continue failure")
    end,
  }
  assert(pcall(spec_callback(task_keys, "<leader>mp")))
  assert(saw_task_debug_warning("Unable to start debug session:"), vim.inspect(task_debug_notices))

  local break_continue_called = false
  local run_to_cursor_called = false
  local break_dap = {
    adapters = {},
    configurations = {},
    listeners = { after = { event_initialized = {} } },
    session = function()
      return nil
    end,
    run_to_cursor = function()
      run_to_cursor_called = true
    end,
    continue = function()
      break_continue_called = true
    end,
  }
  package.loaded["dap"] = break_dap
  assert(pcall(spec_callback(task_keys, "<leader>mp")))
  assert(break_continue_called, "break-at-cursor did not start a debug session")
  assert(type(break_dap.listeners.after.event_initialized.break_here_once) == "function")
  break_dap.listeners.after.event_initialized.break_here_once()
  vim.wait(100, function()
    return run_to_cursor_called
  end)
  assert(run_to_cursor_called, "break-at-cursor listener did not run to cursor")

  vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
  vim.cmd("bwipeout!")
  vim.fn.delete(debug_failure_project, "rf")
  vim.fn.delete(debug_failure_other, "rf")
  package.loaded["dap"] = original_dap
  package.loaded["dap.utils"] = original_dap_utils
  package.loaded["dap.ext.vscode"] = original_dap_vscode
  vim.ui.select = old_ui_select
  vim.notify = old_notify
end)()

package.loaded["dap"] = nil
local dap_configured = {
  adapters = {},
  configurations = {},
  listeners = {
    after = { event_initialized = {} },
    before = { event_terminated = {}, event_exited = {} },
  },
  toggle_breakpoint = function() end,
  set_breakpoint = function() end,
  clear_breakpoints = function() end,
  continue = function() end,
  disconnect = function() end,
  terminate = function() end,
  step_over = function() end,
  step_into = function() end,
  step_out = function() end,
  repl = { open = function() end },
  run_last = function() end,
}
local dapui_setup
local dapui_toggled = false
local virtual_text_setup
local mason_dap_setup
package.loaded["dap"] = dap_configured
package.loaded["dapui"] = {
  setup = function(opts)
    dapui_setup = opts
  end,
  open = function() end,
  close = function() end,
  toggle = function()
    dapui_toggled = true
  end,
}
package.loaded["mason-nvim-dap"] = {
  setup = function(opts)
    mason_dap_setup = opts
  end,
}
package.loaded["nvim-dap-virtual-text"] = {
  setup = function(opts)
    virtual_text_setup = opts
  end,
}

local dap_spec = dofile(root .. "/common/.config/nvim/lua/plugins/dap.lua")
local dap_keys = dap_spec[1].keys()
assert(#dap_keys == 14)
spec_callback(dap_keys, "<leader>du")()
assert(dapui_toggled, "dapui toggle key did not call dapui.toggle")

;(function()
  local old_notify = vim.notify
  local dap_notices = {}
  vim.notify = function(message, level)
    table.insert(dap_notices, { message = tostring(message), level = level })
  end

  local function saw_dap_warning(prefix)
    for _, notice in ipairs(dap_notices) do
      if notice.level == vim.log.levels.WARN and notice.message:find(prefix, 1, true) then
        return true
      end
    end
    return false
  end

  local original_dap = package.loaded["dap"]
  local original_dapui = package.loaded["dapui"]
  local original_widgets = package.loaded["dap.ui.widgets"]
  package.loaded["dap"] = {
    toggle_breakpoint = function() end,
    set_breakpoint = function()
      error("forced breakpoint failure")
    end,
    clear_breakpoints = function() end,
    continue = function()
      error("forced continue failure")
    end,
    disconnect = function() end,
    terminate = function() end,
    step_over = function() end,
    step_into = function() end,
    step_out = function() end,
    repl = {
      open = function()
        error("forced repl failure")
      end,
    },
    run_last = function() end,
  }
  package.loaded["dapui"] = {
    toggle = function()
      error("forced dapui toggle failure")
    end,
  }
  package.loaded["dap.ui.widgets"] = {
    hover = function()
      error("forced hover failure")
    end,
  }

  local failing_dap_keys = dap_spec[1].keys()
  assert(pcall(spec_callback(failing_dap_keys, "<leader>dc")))
  assert(saw_dap_warning("Unable to continue DAP session:"), vim.inspect(dap_notices))
  assert(pcall(spec_callback(failing_dap_keys, "<leader>dr")))
  assert(saw_dap_warning("Unable to open DAP REPL:"), vim.inspect(dap_notices))
  assert(pcall(spec_callback(failing_dap_keys, "<leader>du")))
  assert(saw_dap_warning("Unable to toggle DAP UI:"), vim.inspect(dap_notices))
  assert(pcall(spec_callback(failing_dap_keys, "<leader>de")))
  assert(saw_dap_warning("Unable to show DAP hover:"), vim.inspect(dap_notices))

  local old_ui_input = vim.ui.input
  vim.ui.input = function(_, callback)
    callback("x > 1")
  end
  assert(pcall(spec_callback(failing_dap_keys, "<leader>dB")))
  assert(saw_dap_warning("Unable to set conditional breakpoint:"), vim.inspect(dap_notices))
  vim.ui.input = old_ui_input

  package.loaded["dap"] = original_dap
  package.loaded["dapui"] = original_dapui
  package.loaded["dap.ui.widgets"] = original_widgets
  vim.notify = old_notify
end)()

dap_spec[1].config()
assert(dapui_setup.controls.element == "repl")
assert(mason_dap_setup.ensure_installed[1] == "codelldb")
assert(virtual_text_setup.commented == true)
assert(type(dap_configured.listeners.after.event_initialized.dapui_config) == "function")
assert(type(dap_configured.listeners.before.event_terminated.dapui_config) == "function")
assert(type(dap_configured.configurations.cpp[1].args) == "function")
assert(type(dap_configured.configurations.cpp[1].cwd) == "function")
assert(type(dap_configured.configurations.cpp[2].cwd) == "function")
assert(dap_configured.configurations.c == dap_configured.configurations.cpp)
assert(dap_configured.configurations.rust == dap_configured.configurations.cpp)
assert(dap_configured.configurations.objc == dap_configured.configurations.cpp)
assert(dap_configured.configurations.objcpp == dap_configured.configurations.cpp)

assert(
  vim.deep_equal(require("config.debug").parse_args([['single\slash' "C:\tmp\app.exe" "quote\"ok" escaped\ space]], { expand = false }), {
    [[single\slash]],
    [[C:\tmp\app.exe]],
    [[quote"ok]],
    "escaped space",
  }),
  "debug args parser did not preserve shell quoting edge cases"
)

local dap_project = vim.fn.tempname()
local dap_other_cwd = vim.fn.tempname()
vim.fn.delete(dap_project, "rf")
vim.fn.delete(dap_other_cwd, "rf")
vim.fn.mkdir(dap_project .. "/.jj", "p")
vim.fn.mkdir(dap_project .. "/src", "p")
vim.fn.mkdir(dap_other_cwd, "p")
vim.fn.writefile({ "int dap_main() { return 0; }" }, dap_project .. "/src/main.cpp")

local original_dap_cwd = vim.fn.getcwd()
vim.cmd("cd " .. vim.fn.fnameescape(dap_other_cwd))
vim.cmd("edit " .. vim.fn.fnameescape(dap_project .. "/src/main.cpp"))
local expected_dap_project = uv.fs_realpath(dap_project) or dap_project
local actual_launch_cwd = dap_configured.configurations.cpp[1].cwd()
local actual_attach_cwd = dap_configured.configurations.cpp[2].cwd()
actual_launch_cwd = uv.fs_realpath(actual_launch_cwd) or actual_launch_cwd
actual_attach_cwd = uv.fs_realpath(actual_attach_cwd) or actual_attach_cwd
assert(actual_launch_cwd == expected_dap_project, "launch cwd " .. tostring(actual_launch_cwd))
assert(actual_attach_cwd == expected_dap_project, "attach cwd " .. tostring(actual_attach_cwd))
local original_input = vim.fn.input
local captured_program_default
vim.fn.input = function(_, default)
  captured_program_default = default
  return default
end
assert(dap_configured.configurations.cpp[1].program() == expected_dap_project .. "/")
vim.fn.input = original_input
assert(captured_program_default == expected_dap_project .. "/", "program default " .. tostring(captured_program_default))
vim.fn.input = function()
  return [[--flag "two words" escaped\ space 'single quoted']]
end
assert(
  vim.deep_equal(dap_configured.configurations.cpp[1].args(), { "--flag", "two words", "escaped space", "single quoted" }),
  "debug args parser did not preserve quoting"
)
vim.fn.input = original_input
vim.cmd("bwipeout!")
vim.cmd("cd " .. vim.fn.fnameescape(original_dap_cwd))
vim.fn.delete(dap_project, "rf")
vim.fn.delete(dap_other_cwd, "rf")

local tmux_nav_spec = dofile(root .. "/common/.config/nvim/lua/plugins/tmux-navigator.lua")
assert(#tmux_nav_spec[1].keys == 10)
local tmux_nav_keys = tmux_nav_spec[1].keys
local terminal_left
for _, key in ipairs(tmux_nav_keys) do
  if key[1] == "<C-h>" and key.mode == "t" then
    terminal_left = key[2]
  end
end
assert(type(terminal_left) == "function", "missing terminal tmux left mapping")

for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name:match("^term://~/repo//") then
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end
end

local function set_terminal_name(name)
  local current = vim.api.nvim_get_current_buf()
  local conflict = vim.fn.bufnr(name)
  if conflict > 0 and conflict ~= current then
    pcall(vim.api.nvim_buf_delete, conflict, { force = true })
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if bufnr ~= current and vim.api.nvim_buf_get_name(bufnr) == name then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end

  local ok, err = pcall(vim.api.nvim_buf_set_name, 0, name)
  if not ok and tostring(err):find("E95:", 1, true) then
    conflict = vim.fn.bufnr(name)
    if conflict > 0 and conflict ~= current then
      pcall(vim.api.nvim_buf_delete, conflict, { force = true })
      ok, err = pcall(vim.api.nvim_buf_set_name, 0, name)
    end
  end
  assert(ok, tostring(err))
end

vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.bo.filetype = "fzf"
assert(terminal_left() == "<C-h>")
vim.bo.filetype = "fzf-lua"
assert(terminal_left() == "<C-h>")
vim.bo.filetype = "lazygit"
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//123:/opt/homebrew/bin/lazygit")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//123:/opt/homebrew/bin/gitui")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//123:/usr/local/bin/tig")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//123:/opt/homebrew/bin/lazydocker")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//123:/opt/homebrew/bin/k9s")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//123:/opt/homebrew/bin/btop")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//123:/usr/bin/htop")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//124:/usr/bin/fzf --multi")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//125:/usr/bin/sk --ansi")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//126:/opt/homebrew/bin/yazi")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//127:/usr/local/bin/lf")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//128:/usr/bin/ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name([[term://~/repo//128:C:\tools\ssh.exe devbox]])
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name([[term://~/repo//128:C:\tools\SSH.EXE devbox]])
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name([[term://~/repo//128://server/share/ssh.exe devbox]])
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name([[term://~/repo//128://server/share/SSH.EXE devbox]])
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name([[term://~/repo//128:C:\tools\ssh.exe -N -L 8080:localhost:80 devbox]])
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name([[term://~/repo//128://server/share/ssh.exe -N -L 8080:localhost:80 devbox]])
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//129:/opt/homebrew/bin/mosh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//129:/opt/homebrew/bin/mosh-client")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//129:/usr/local/bin/autossh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//129:/opt/homebrew/bin/sshpass -e ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//129:/opt/homebrew/bin/sshpass -p secret ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//129:/usr/bin/ssh -N -L 8080:localhost:80 devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//129:/usr/bin/ssh -T devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//129:/usr/bin/ssh -O check devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//129:/opt/homebrew/bin/sshpass -p secret ssh -N -L 8080:localhost:80 devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//129:/usr/bin/arch -x86_64 nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//129:/usr/bin/arch -arm64 ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//129:/usr/bin/arch -x86_64 echo nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//129:/usr/local/bin/autossh -M 0 -N -L 8080:localhost:80 devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//129:/opt/homebrew/bin/sshpass -p secret echo ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//129:/opt/homebrew/bin/kitten ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//129:/Applications/kitty.app/Contents/MacOS/kitty +kitten ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//129:/opt/homebrew/bin/kitten icat image.png")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//130:/opt/homebrew/bin/nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//130:/opt/homebrew/bin/nvim.exe README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name([[term://~/repo//130:C:\tools\nvim.exe README.md]])
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name([[term://~/repo//130:C:\tools\NVIM.EXE README.md]])
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name([[term://~/repo//130://server/share/nvim.exe README.md]])
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name([[term://~/repo//130://server/share/NVIM.EXE README.md]])
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//130:/usr/bin/vi README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//130:/usr/bin/vim.basic README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//130:/opt/homebrew/bin/hx src/main.rs")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//130:/opt/homebrew/bin/helix src/main.rs")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//130:/usr/bin/less README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//130:/usr/bin/man tmux")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//131:/usr/bin/vimdiff left right")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//131:/opt/homebrew/bin/tmux attach")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/screen -x")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/zellij attach main")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/codex")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/opencode")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/gemini")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/Users/skydebreuil/.local/bin/claude")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/aider")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/ipython")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/python3")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/python3 -i app.py")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/python3 -m pdb app.py")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/python3 -m IPython")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/python3 -mIPython")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/python3 -mhttp.server")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
vim.api.nvim_buf_set_name(0, "term://~/repo//132:/usr/bin/python3 -ic 'print(\"nvim\")'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/python3 app.py")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/python3 -m http.server")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
vim.api.nvim_buf_set_name(0, "term://~/repo//132:/usr/bin/python3 -c 'print(\"nvim\")'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
vim.api.nvim_buf_set_name(0, "term://~/repo//132:/usr/bin/python3 -cprint(\"nvim\")")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/python3-config --includes")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/node")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/node -i app.js")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/node -r ts-node/register")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/node inspect app.js")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/nodejs --interactive")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/node -rinteractive")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
vim.api.nvim_buf_set_name(0, "term://~/repo//132:/usr/local/bin/node -ie 'console.log(\"nvim\")'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/node app.js")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
vim.api.nvim_buf_set_name(0, "term://~/repo//132:/usr/local/bin/node -e 'console.log(\"nvim\")'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/node -p 'process.version'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
vim.api.nvim_buf_set_name(0, "term://~/repo//132:/usr/local/bin/node -econsole.info(\"nvim\")")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/node -pprocess.version")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/node -rinteractive app.js")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/node --test")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/node --inspect-brk app.js")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/deno")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/deno repl")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/deno --config deno.json repl")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/deno run app.ts")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/deno --config deno.json run app.ts")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/deno eval 'console.log(1)'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/deno --version")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/bun repl")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/bun")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/bun run app.ts")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/php -a")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/php --interactive")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/php -d memory_limit=-1 -a")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/php -c php.ini --interactive")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/php -r 'echo 1;'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/php -d memory_limit=-1 -r 'echo 1;'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/php app.php")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/php -c php.ini app.php")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/phpdbg -qrr app.php")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/irb")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/pry")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/rdbg app.rb")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/rails console")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/rails dbconsole")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/rails runner 'puts 1'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/rails console --help")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/bundle exec pry")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/bundler _2.5.0_ exec -- irb")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/bundle exec rails console")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/bundle exec echo pry")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/ruby -S irb")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/ruby -I lib -S rails console")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/ruby bin/rails console")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/ruby app.rb")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/ruby -e 'puts 1'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/ruby bin/rails runner 'puts 1'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/gdb ./app")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/lldb ./app")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/rr replay")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/ghci Main.hs")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/iex -S mix")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/erl")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/utop")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/jshell")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/radian")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/psql postgres")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/psql postgres -c 'select 1'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/psql postgres -cselect")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/psql -f schema.sql")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/psql -fschema.sql")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/mysql app")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/mysql app -e 'select 1'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/mysql app -eselect")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/mariadb app")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/mariadb --execute='select 1' app")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/sqlite3 app.db")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/sqlite3 app.db 'select 1'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/duckdb analytics.duckdb")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/duckdb -c 'select 1'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/duckdb -cselect")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/redis-cli -h localhost -p 6379")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/redis-cli -h localhost ping")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/redis-cli --help")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/lua")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/lua -i app.lua")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/lua -l socket")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/lua app.lua")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/lua -e 'print(1)'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/lua -eprint(1)")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/luajit -l ffi")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/luajit app.lua")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/bin/luajit -eprint(1)")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/julia --project=.")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/julia -i app.jl")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/julia app.jl")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/julia -e 'println(1)'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/opt/homebrew/bin/julia -eprintln(1)")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/R --vanilla")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/R -e 'print(1)'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/R -eprint(1)")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/usr/local/bin/R CMD BATCH app.R")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name([[term://~/repo//132:C:\tools\R.EXE --vanilla]])
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//132:/bin/zsh")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//133:/usr/bin/env TERM=xterm-256color ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//134:/usr/bin/env -u TERM -- mosh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//135:/usr/bin/command lazygit")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//136:/bin/exec nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//137:/usr/bin/env -u TERM VAR")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//138:/usr/bin/env --chdir=/tmp ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//139:/usr/bin/env --chdir /tmp mosh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//140:/usr/bin/sudo -u root ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//140:/usr/bin/sudo -iu root ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//140:/usr/bin/sudo -uroot ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//141:/usr/bin/sudo --user=root mosh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//142:/usr/bin/nice -n 5 htop")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//143:/usr/bin/nice -10 btop")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//143:/usr/bin/stdbuf -oL nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//143:/usr/bin/stdbuf -o L ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//143:/usr/bin/unbuffer ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//143:/usr/bin/rlwrap -f completions.txt nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//143:/usr/bin/setsid -w nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//143:/usr/bin/winpty nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//143:/usr/bin/winpty.exe nvim.exe README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//143:/usr/bin/script -q -c 'ssh devbox' /dev/null")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//143:/usr/bin/script -q /dev/null nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//144:/usr/bin/sudo -u root zsh")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//144:/usr/bin/sudo -iu root echo ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//144:/usr/bin/sudo -ut ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//145:/usr/bin/env GREETING='hello world' ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//146:/usr/bin/env GREETING=escaped\\ value mosh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//147:/usr/bin/env -S 'ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//147:/usr/bin/env -S 'echo ssh' ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
vim.api.nvim_buf_set_name(0, 'term://~/repo//148:/usr/bin/env --split-string="mosh devbox"')
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//149:/usr/bin/env -S 'zsh -l'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
vim.api.nvim_buf_set_name(0, 'term://~/repo//150:/usr/bin/sudo --prompt="password please" --user=root mosh devbox')
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//150:/usr/bin/doas -u root ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//150:/usr/bin/doas -C /tmp/doas.conf mosh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//150:/usr/bin/doas -u root echo ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//150:/usr/bin/stdbuf -oL echo nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//150:/usr/bin/unbuffer echo ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//150:/usr/bin/rlwrap echo ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//150:/usr/bin/setsid echo nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//150:/usr/bin/winpty echo nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//150:/usr/bin/winpty.exe echo nvim.exe README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//150:/usr/bin/script -q -c 'echo ssh devbox' /dev/null")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//150:/usr/bin/script -q /dev/null echo ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
vim.api.nvim_buf_set_name(0, 'term://~/repo//151:/usr/bin/nice --adjustment="5" htop')
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//151:/usr/bin/time -p nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//151:/opt/homebrew/bin/gtime -f '%E' -o timing.log mosh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//151:/usr/bin/time -p echo nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//152:/bin/bash -lc 'ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//152:/bin/bash -lc 'time ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//152:/bin/bash -lc 'time echo ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//152:/bin/dash -c 'ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//152:/usr/local/bin/pwsh -NoProfile -Command 'ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//152:/usr/local/bin/pwsh -NoProfile -Command 'echo ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//152:/usr/local/bin/pwsh -configurationName ssh")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//152:/bin/bash -lc 'tmux attach'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//152:/bin/bash -lc 'screen -x'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//152:/bin/bash -lc 'zellij attach main'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//153:/bin/zsh -ic 'nvim README.md'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//154:/bin/sh -c 'mosh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//155:/opt/homebrew/bin/fish --command='yazi .'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//156:/usr/bin/env FOO='two words' bash -lc 'ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//156:/usr/bin/env TERM=xterm-kitty kitten ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/poetry run ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/poetry run -- ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/poetry -C ./app run nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/poetry --project=./app run ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/pipenv run ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/pipenv --python 3.12 run nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/pipx run --spec neovim nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/hatch run test:nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/hatch run +py=3.12 -version=9000 ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/hatch env run -e test nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/uv run -- nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/uv run --with ruff --env-file .env -- nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/uv run --with=ruff --python 3.12 ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/uv --project ./app run --with-requirements requirements.txt nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/uvx --from neovim nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/uvx --python 3.12 ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/uvx --managed-python --no-build nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/uv tool run --from neovim nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/uv run -m http.server")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/pixi run nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/pixi run -- ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/pixi run -e cuda ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/pixi --manifest-path ./pixi.toml run nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/npx --yes nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/npx.cmd --yes nvim.exe README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/NPX.CMD --yes NVIM.EXE README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/npm exec -- ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/npm exec -c 'ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/npm x --package=neovim -- nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/pnpm exec nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/pnpm --dir ./app exec ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/pnpm exec -c 'nvim README.md'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/pnpm dlx --package lazygit lazygit")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/pnx --package neovim nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/pnpx --package openssh ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/yarn dlx --package=neovim nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/yarn exec 'ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/yarn exec nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/yarnpkg dlx --package=neovim nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/bunx --bun nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/bun x --package lazygit lazygit")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/corepack yarn dlx --package=neovim nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/corepack yarn@4.1.0 exec 'ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/corepack pnpm exec ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/corepack npx --yes nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/corepack pnx --package lazygit lazygit")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/direnv exec . mosh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/direnv exec . -- nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/asdf exec nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/asdf exec ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/mise exec -- ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/mise x -- nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/rtx exec -- ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/rtx x -- nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/nix/var/nix/profiles/default/bin/nix develop -c ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/nix/var/nix/profiles/default/bin/nix shell .#openssh -c mosh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/nix/var/nix/profiles/default/bin/nix run .#openssh -- ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/devcontainer exec --workspace-folder . nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/devcontainer exec --workspace-folder . --remote-env TERM=xterm-256color bash -lc 'nvim README.md'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker exec -it app nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker exec --user root app bash -lc 'nvim README.md'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker --context prod exec app nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker attach app")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker container attach app")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker attach --no-stdin=false app")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker start -ai app")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker container start --attach --interactive app")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker run --rm -it -e TERM=xterm-256color ubuntu nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker --host=unix:///tmp/docker.sock run --rm -it ubuntu ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker run --rm --workdir /src ubuntu bash -lc 'nvim README.md'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker run --rm --entrypoint nvim ubuntu README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker run --rm --entrypoint sh ubuntu -lc 'nvim README.md'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/podman container exec -it app ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/podman attach app")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/podman start -ai app")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/podman --connection prod container exec app ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/podman run --rm -it fedora ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/podman --remote run --rm -it fedora ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/podman run --rm --entrypoint nvim fedora README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl exec -it deploy/app -c api -- nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl exec -it deploy/app -c api nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl exec -n dev pod/app --container api nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl -n dev exec pod/app -- nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl --context=prod -n dev exec pod/app -- sh -c 'ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl -v 6 exec pod/app -- nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl --v 6 exec pod/app -- ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl --client-certificate cert.pem --client-key key.pem exec pod/app -- nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl --username alice --password example exec pod/app -- ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl --log-flush-frequency 5s --vmodule kubelet=6 exec pod/app -- nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl attach -it pod/app -c api")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl attach -it pod/app -capi")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl -n dev attach --stdin pod/app -c api")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/oc exec pod/app -- sh -c 'mosh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/oc --namespace dev exec pod/app -- mosh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/oc attach -it pod/app -c api")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/poetry run echo ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/poetry -C ./app run echo ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/pipenv run echo ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/pipx run --spec cowsay echo nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/hatch run test:echo nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/hatch env run -e test echo ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/uv run --with ruff echo nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/uvx --from cowsay echo nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/uvx --help nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/pixi run echo nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/pixi run --dry-run nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/pixi --version run nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/npx --yes echo nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/npm exec -c 'echo ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/pnpm exec echo nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/pnpm exec -c 'echo ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/pnpx --package cowsay echo ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/yarn dlx echo nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/yarn exec 'echo ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/yarnpkg dlx echo nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/bunx echo nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/bun x --package cowsay echo ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/corepack use pnpm@10 nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/corepack yarn dlx echo nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/corepack pnpm exec -c 'echo ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/direnv exec . echo ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/asdf exec echo nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/mise exec echo ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/rtx exec echo ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/nix/var/nix/profiles/default/bin/nix develop -c echo ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/devcontainer exec --workspace-folder . bash -lc 'echo nvim README.md'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/devcontainer up --workspace-folder . nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker exec app bash -lc 'echo nvim README.md'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker run --rm ubuntu bash -lc 'echo nvim README.md'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker run --rm --entrypoint echo ubuntu ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker run --rm -it ubuntu")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker --context prod ps nvim")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker --help exec app nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker attach --no-stdin app")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker start -a app")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker start --attach=false --interactive app")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker compose exec app bash -lc 'echo nvim README.md'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker compose run app bash -lc 'echo nvim README.md'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/usr/local/bin/docker compose run app")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/podman run --rm --entrypoint echo fedora ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/podman --version run fedora ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/podman attach --no-stdin app")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl exec pod/app -- echo ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl exec pod/app echo ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl -n dev get pods nvim")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl -v 6 get pods nvim")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl --client-certificate cert.pem get pods nvim")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl --help exec pod/app -- nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl attach pod/app -c api")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl attach pod/app -capi")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl attach -nprod pod/app -capi")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/opt/homebrew/bin/kubectl attach --stdin=false pod/app -c api")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//157:/bin/bash -lc 'echo hi'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//158:/bin/zsh -l")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//159:/bin/bash -lc 'cd /tmp && ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//160:/bin/zsh -ic 'source ~/.zshrc; nvim README.md'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//160:/bin/bash -lc 'clear; nvim README.md'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
vim.api.nvim_buf_set_name(0, "term://~/repo//160:/bin/bash -lc 'printf \"opening\\n\"; ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//160:/bin/bash -lc 'echo opening; mosh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
vim.api.nvim_buf_set_name(0, "term://~/repo//160:/bin/bash -lc 'trap \"printf cleanup\" EXIT; ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//161:/bin/sh -c 'FOO=bar mosh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//161:/bin/sh -c 'kitten ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//162:FOO=bar ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name([[term://~/repo//162:C:\Windows\System32\cmd.exe /c ssh devbox]])
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name([[term://~/repo//162:C:\Windows\System32\CMD.EXE /C SSH.EXE devbox]])
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name([[term://~/repo//162:\\server\share\ssh.exe devbox]])
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name([[term://~/repo//162:\\server\share\NVIM.EXE README.md]])
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name([[term://~/repo//162://server/share/ssh.exe devbox]])
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name([[term://~/repo//162://server/share/NVIM.EXE README.md]])
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name([[term://~/repo//162:C:\Windows\System32\cmd.exe /s /c "nvim README.md"]])
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name([[term://~/repo//162:C:\Windows\System32\cmd.exe /k "echo ssh devbox"]])
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name([[term://~/repo//162:C:\Windows\System32\cmd.exe]])
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//163:/bin/bash -lc 'cd /tmp && echo hi'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//164:/bin/bash -lc 'echo ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//164:/bin/bash -lc 'printf ssh; echo done'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
vim.api.nvim_buf_set_name(0, "term://~/repo//164:/bin/bash -lc 'trap \"ssh devbox\" EXIT; echo done'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//165:/bin/bash -lc 'cd /tmp || exit; ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//166:/bin/zsh -ic 'source ~/.zshrc || return; nvim README.md'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//167:/bin/bash -lc 'cd /tmp || ssh fallback'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//168:/bin/bash -lc 'cd /tmp || echo ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//169:/bin/bash -lc 'cd /tmp 2>&1 && ssh devbox'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//170:/bin/zsh -ic 'source ~/.zshrc >&2; nvim README.md'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//170:/usr/local/bin/docker compose exec -it app nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//170:/usr/local/bin/docker --context prod compose exec app nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//170:/usr/local/bin/docker compose -f compose.dev.yml --project-name demo exec app bash -lc 'nvim README.md'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//170:/usr/local/bin/docker compose run --rm --service-ports app nvim README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//170:/usr/local/bin/docker compose --profile dev run -e TERM=xterm-256color app bash -lc 'nvim README.md'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//170:/usr/local/bin/docker compose run --entrypoint=nvim app README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//170:/usr/local/bin/docker compose run --entrypoint sh app -lc 'nvim README.md'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//170:/usr/local/bin/docker compose run --entrypoint echo app ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//170:/usr/local/bin/docker-compose exec app ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//170:/usr/local/bin/docker-compose run --rm app ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//170:/usr/local/bin/podman compose exec app mosh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//170:/usr/local/bin/podman --url ssh://devbox compose exec app mosh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//170:/usr/local/bin/podman compose run --rm app mosh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//170:/usr/local/bin/podman compose run --entrypoint nvim app README.md")
vim.bo.filetype = ""
assert(terminal_left() == "<C-h>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//170:/usr/local/bin/podman compose run --entrypoint echo app ssh devbox")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")
vim.cmd("enew!")
set_terminal_name("term://~/repo//171:/bin/bash -lc 'echo hi >&2'")
vim.bo.filetype = ""
assert(terminal_left() == "<C-\\><C-n><cmd>TmuxNavigateLeft<cr>")

local which_key_spec = dofile(root .. "/common/.config/nvim/lua/plugins/which-key.lua")
local which_key_opts = { spec = {} }
which_key_spec[1].opts(nil, which_key_opts)

local function has_group(prefix, group)
  for _, item in ipairs(which_key_opts.spec) do
    if item[1] == prefix and item.group == group then
      return true
    end
  end
  return false
end

assert(has_group("<leader>b", "buffers/tabs"), "which-key missing buffer/tab group")
assert(has_group("<leader>w", "workspace/tmux"), "which-key missing workspace/tmux group")

local debug_config = require("config.debug")

local function assert_args(input, expected)
  local actual = debug_config.parse_args(input, { expand = false, notify = false })
  assert(vim.deep_equal(actual, expected), input .. " parsed as " .. vim.inspect(actual))
end

assert_args("", {})
assert_args("alpha beta", { "alpha", "beta" })
assert_args([[--name "two words" 'three words']], { "--name", "two words", "three words" })
assert_args([[--path src/my\ file.lua]], { "--path", "src/my file.lua" })
assert_args([[--literal trailing\]], { "--literal", [[trailing\]] })
assert_args([[--empty "" '']], { "--empty", "", "" })
assert_args([["unterminated value]], { "unterminated value" })

vim.env.DOTFILES_DEBUG_PARSE_ARGS_TEST = "expanded-value"
local expanded_debug_args = debug_config.parse_args(
  [[$DOTFILES_DEBUG_PARSE_ARGS_TEST "$DOTFILES_DEBUG_PARSE_ARGS_TEST" ${DOTFILES_DEBUG_PARSE_ARGS_TEST}/bin '$DOTFILES_DEBUG_PARSE_ARGS_TEST' \${DOTFILES_DEBUG_PARSE_ARGS_TEST}]],
  { notify = false }
)
assert(
  vim.deep_equal(expanded_debug_args, {
    "expanded-value",
    "expanded-value",
    "expanded-value/bin",
    "$DOTFILES_DEBUG_PARSE_ARGS_TEST",
    "${DOTFILES_DEBUG_PARSE_ARGS_TEST}",
  }),
  "debug args parser expanded literal shell values as " .. vim.inspect(expanded_debug_args)
)
vim.env.DOTFILES_DEBUG_PARSE_ARGS_TEST = nil

;(function()
  local original_home = vim.env.HOME
  local original_cwd = vim.fn.getcwd()
  local debug_fixture = vim.fn.tempname()
  vim.fn.delete(debug_fixture, "rf")
  vim.fn.mkdir(debug_fixture, "p")
  vim.fn.writefile({ "first" }, debug_fixture .. "/first.txt")
  vim.fn.writefile({ "second" }, debug_fixture .. "/second.txt")
  vim.env.HOME = debug_fixture
  vim.cmd("cd " .. vim.fn.fnameescape(debug_fixture))
  vim.cmd("enew!")
  vim.api.nvim_buf_set_name(0, debug_fixture .. "/current-file.txt")
  vim.env.DOTFILES_DEBUG_PARSE_ARGS_TEST = "expanded-value"

  local expanded = debug_config.parse_args(
    [[~ ~/bin $DOTFILES_DEBUG_PARSE_ARGS_TEST ${DOTFILES_DEBUG_PARSE_ARGS_TEST}/bin '$DOTFILES_DEBUG_PARSE_ARGS_TEST' \${DOTFILES_DEBUG_PARSE_ARGS_TEST} * % #]],
    { notify = false }
  )
  assert(
    vim.deep_equal(expanded, {
      debug_fixture,
      debug_fixture .. "/bin",
      "expanded-value",
      "expanded-value/bin",
      "$DOTFILES_DEBUG_PARSE_ARGS_TEST",
      "${DOTFILES_DEBUG_PARSE_ARGS_TEST}",
      "*",
      "%",
      "#",
    }),
    "debug args parser expanded unintended values as " .. vim.inspect(expanded)
  )

  vim.env.DOTFILES_DEBUG_PARSE_ARGS_TEST = nil
  vim.env.HOME = original_home
  vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
  vim.fn.delete(debug_fixture, "rf")
end)()

print("nvim-config-smoke-ok")
LUA

DOTFILES_ROOT="$root" nvim --headless -n -i NONE -u NONE -l "$lua_file"
printf '\n'
