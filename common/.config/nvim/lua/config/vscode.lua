local M = {}

local settings_cache = {}
local overseer_patched = false
local warned = {}

local function context_dir(directory, bufnr)
  if directory and directory ~= "" then
    return vim.fs.normalize(directory)
  end

  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name ~= "" then
    name = vim.uv.fs_realpath(name) or vim.fs.normalize(name)
    return vim.fs.dirname(name)
  end
  return vim.fn.getcwd()
end

function M.workspace(directory, bufnr)
  local vscode_dir = vim.fs.find(".vscode", {
    path = context_dir(directory, bufnr),
    upward = true,
    type = "directory",
  })[1]
  if not vscode_dir then
    return nil
  end
  local root = vim.fs.dirname(vscode_dir)
  return vim.uv.fs_realpath(root) or vim.fs.normalize(root), vscode_dir
end

function M.clear_cache()
  settings_cache = {}
end

function M.settings(root)
  local settings_path = vim.fs.joinpath(root, ".vscode", "settings.json")
  local stat = vim.uv.fs_stat(settings_path)
  if not stat then
    return {}
  end

  local signature = table.concat({
    stat.size or 0,
    stat.mtime and stat.mtime.sec or 0,
    stat.mtime and stat.mtime.nsec or 0,
  }, ":")
  local cached = settings_cache[settings_path]
  if cached and cached.signature == signature then
    return cached.settings
  end

  local ok_read, lines = pcall(vim.fn.readfile, settings_path)
  if not ok_read then
    return nil, ("Unable to read %s: %s"):format(settings_path, lines)
  end
  local ok_decode, settings = pcall(require("overseer.json").decode, table.concat(lines, "\n"))
  if not ok_decode then
    return nil, ("Unable to parse %s: %s"):format(settings_path, settings)
  end
  if type(settings) ~= "table" then
    return nil, ("%s must contain a JSON object"):format(settings_path)
  end

  settings_cache[settings_path] = {
    signature = signature,
    settings = settings,
  }
  return settings
end

local function expand_string(value, settings, stack)
  local first_error
  local expanded = value:gsub("%${config:([^}]+)}", function(key)
    if stack[key] then
      first_error = first_error or ("Cyclic VS Code setting reference: %s"):format(key)
      return "${config:" .. key .. "}"
    end

    local replacement = settings[key]
    if replacement == nil then
      first_error = first_error or ("VS Code setting is not defined: %s"):format(key)
      return "${config:" .. key .. "}"
    end
    if type(replacement) ~= "string" and type(replacement) ~= "number" and type(replacement) ~= "boolean" then
      first_error = first_error or ("VS Code setting must be scalar when interpolated: %s"):format(key)
      return "${config:" .. key .. "}"
    end

    stack[key] = true
    local resolved, err = expand_string(tostring(replacement), settings, stack)
    stack[key] = nil
    first_error = first_error or err
    return resolved
  end)
  return expanded, first_error
end

function M.expand_config(value, settings)
  if type(value) == "table" then
    local expanded = {}
    local first_error
    for key, item in pairs(value) do
      local resolved, err = M.expand_config(item, settings)
      expanded[key] = resolved
      first_error = first_error or err
    end
    return expanded, first_error
  end
  if type(value) ~= "string" then
    return value
  end
  return expand_string(value, settings, {})
end

local function active_workspace_vars(original)
  local vars = original()
  local root = M.workspace()
  if not root then
    return vars
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(bufnr)
  file = file ~= "" and (vim.uv.fs_realpath(file) or vim.fs.normalize(file)) or ""
  local relative_file = file ~= "" and vim.fs.relpath(root, file) or nil
  vars.workspaceFolder = root
  vars.workspaceRoot = root
  vars.workspaceFolderBasename = vim.fs.basename(root)
  vars.fileWorkspaceFolder = root
  if relative_file then
    vars.relativeFile = relative_file
    vars.relativeFileDirname = vim.fs.dirname(relative_file) or "."
  end
  return vars
end

function M.setup_overseer()
  if overseer_patched then
    return
  end

  local variables = require("overseer.vscode.variables")
  local original_precalculate = variables.precalculate_vars
  local original_replace = variables.replace_vars

  variables.precalculate_vars = function()
    return active_workspace_vars(original_precalculate)
  end
  variables.replace_vars = function(value, params, precalculated_vars)
    local root = precalculated_vars and precalculated_vars.workspaceFolder or M.workspace()
    if root then
      local settings, settings_err = M.settings(root)
      if settings then
        local expanded, expand_err = M.expand_config(value, settings)
        value = expanded
        settings_err = expand_err
      end
      if settings_err and not warned[settings_err] then
        warned[settings_err] = true
        vim.notify(settings_err, vim.log.levels.WARN)
      end
    end
    return original_replace(value, params, precalculated_vars)
  end

  overseer_patched = true
end

return M
