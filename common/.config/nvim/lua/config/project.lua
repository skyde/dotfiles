local M = {}

M.markers = {
  ".git",
  ".jj",
  ".devcontainer",
  ".vscode",
  "CMakeLists.txt",
  "Makefile",
  "Justfile",
  "justfile",
  "Taskfile.yml",
  "Taskfile.yaml",
  "taskfile.yml",
  "taskfile.yaml",
  "package.json",
  "pnpm-workspace.yaml",
  "package-lock.json",
  "pnpm-lock.yaml",
  "yarn.lock",
  "bun.lock",
  "bun.lockb",
  "bunfig.toml",
  "tsconfig.json",
  "jsconfig.json",
  "vite.config.js",
  "vite.config.ts",
  "next.config.js",
  "next.config.ts",
  "eslint.config.js",
  "eslint.config.mjs",
  "eslint.config.ts",
  "turbo.json",
  "nx.json",
  "angular.json",
  "lerna.json",
  "rush.json",
  "biome.json",
  "biome.jsonc",
  "pyproject.toml",
  "poetry.lock",
  "pdm.lock",
  "pixi.toml",
  "pixi.lock",
  "uv.lock",
  "requirements.txt",
  "pyrightconfig.json",
  "ruff.toml",
  "mypy.ini",
  "setup.py",
  "setup.cfg",
  "tox.ini",
  "pytest.ini",
  "Pipfile",
  "Cargo.toml",
  "stack.yaml",
  "cabal.project",
  "package.yaml",
  "Package.swift",
  "go.mod",
  "go.work",
  "WORKSPACE",
  "WORKSPACE.bazel",
  "MODULE.bazel",
  "deno.json",
  "deno.jsonc",
  "deno.lock",
  "flake.nix",
  ".tool-versions",
  ".mise.toml",
  "mise.toml",
  "meson.build",
  "build.gradle",
  "build.gradle.kts",
  "settings.gradle",
  "settings.gradle.kts",
  "pom.xml",
  "composer.json",
  "Gemfile",
  "Rakefile",
  "gradlew",
  "compose.yaml",
  "compose.yml",
  "docker-compose.yaml",
  "docker-compose.yml",
  "mix.exs",
  "rebar.config",
  "gleam.toml",
  "dune-project",
  "dune-workspace",
}

M.primary_markers = vim.tbl_filter(function(marker)
  return marker ~= ".vscode"
end, M.markers)

M.fallback_markers = {
  ".vscode",
}

local function realpath(path)
  local uv = vim.uv or vim.loop
  return (path and path ~= "" and uv.fs_realpath(path)) or path
end

local function is_windows_absolute_path(path)
  return type(path) == "string"
    and (path:match("^%a:[/\\]") ~= nil or path:match("^[\\][\\]") ~= nil or path:match("^//") ~= nil)
end

local function normalize_windows_absolute_path(path)
  if is_windows_absolute_path(path) then
    return (path:gsub("\\", "/"))
  end

  return path
end

function M.normalize_dir(dir)
  if is_windows_absolute_path(dir) then
    dir = normalize_windows_absolute_path(dir)
    return realpath(dir) or dir
  end

  local normalized = vim.fs.normalize(dir or vim.fn.getcwd())
  return realpath(normalized) or normalized
end

function M.normalize_path(path)
  if not (path and path ~= "") then
    return nil
  end

  if is_windows_absolute_path(path) then
    path = normalize_windows_absolute_path(path)
    return realpath(path) or path
  end

  local normalized = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  return realpath(normalized) or normalized
end

function M.start_for_path(path)
  local normalized = M.normalize_path(path)
  if not normalized then
    return M.normalize_dir(vim.fn.getcwd())
  end

  local uv = vim.uv or vim.loop
  local stat = uv.fs_stat(normalized)
  if (stat and stat.type == "directory") or path:sub(-1) == "/" then
    return normalized
  end

  return M.normalize_dir(vim.fs.dirname(normalized))
end

function M.root(start)
  start = M.normalize_dir(start or vim.fn.getcwd())
  local marker_root = vim.fs.root(start, M.primary_markers) or vim.fs.root(start, M.fallback_markers)

  if is_windows_absolute_path(start) and not is_windows_absolute_path(marker_root) then
    return start
  end

  return M.normalize_dir(marker_root or start)
end

function M.root_for_path(path)
  return M.root(M.start_for_path(path))
end

local function file_buffer_name(bufnr)
  bufnr = bufnr or 0
  local resolved_bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr

  if not vim.api.nvim_buf_is_valid(resolved_bufnr) then
    return nil
  end

  if vim.bo[resolved_bufnr].buftype ~= "" then
    return nil
  end

  local path = vim.api.nvim_buf_get_name(resolved_bufnr)
  if path == "" then
    return nil
  end
  if path:match("^[%a][%w+.-]*://") then
    return nil
  end

  return path, resolved_bufnr
end

function M.buffer_path(bufnr)
  local path, resolved_bufnr = file_buffer_name(bufnr)
  if not path then
    return nil
  end

  local expanded_path = vim.fn.expand("#" .. resolved_bufnr .. ":p")
  if expanded_path ~= "" then
    return expanded_path
  end

  return path
end

function M.buffer_start(bufnr)
  local path = file_buffer_name(bufnr)
  if path then
    return vim.fs.dirname(path)
  end

  return vim.fn.getcwd()
end

function M.root_for_buffer(bufnr)
  local path = file_buffer_name(bufnr)
  if path then
    return M.root_for_path(path)
  end

  return M.root()
end

function M.file_dir_for_buffer(bufnr)
  local path = file_buffer_name(bufnr)
  if path then
    return M.normalize_dir(vim.fs.dirname(path))
  end

  return M.normalize_dir(vim.fn.getcwd())
end

function M.vscode_file(name, start)
  local uv = vim.uv or vim.loop

  local roots = vim.fs.find(".vscode", {
    path = start and M.start_for_path(start) or M.buffer_start(),
    upward = true,
    type = "directory",
    limit = 100,
  })

  for _, vscode_dir in ipairs(roots or {}) do
    local file = vscode_dir .. "/" .. name
    if uv.fs_stat(file) then
      return file, M.normalize_dir(vim.fs.dirname(vscode_dir))
    end
  end

  return nil, nil
end

function M.relative_path(path, dir)
  local uv = vim.uv or vim.loop
  local normalized_dir = normalize_windows_absolute_path(dir)
  local normalized_path = normalize_windows_absolute_path(path)
  local real_dir = uv.fs_realpath(normalized_dir) or normalized_dir
  local real_path = uv.fs_realpath(normalized_path) or normalized_path

  if vim.fs.relpath then
    local rel = vim.fs.relpath(real_dir, real_path)
    if rel and rel ~= "" then
      return rel
    end
  end

  return vim.fn.fnamemodify(path, ":~:.")
end

return M
