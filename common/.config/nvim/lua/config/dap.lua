local M = {}

function M.codelldb_paths(install, system)
  local windows = system:find("Windows") ~= nil
  local adapter = install .. "/extension/adapter/codelldb" .. (windows and ".exe" or "")
  local library_extension = windows and "dll" or (system == "Darwin" and "dylib" or "so")
  local library_directory = windows and "bin" or "lib"
  local library = install .. "/extension/lldb/" .. library_directory .. "/liblldb." .. library_extension
  return adapter, library
end

local function ensure_adapters()
  local dap = require("dap")
  if dap.adapters and dap.adapters.codelldb and not dap.adapters.lldb then
    dap.adapters.lldb = dap.adapters.codelldb
  end
end

local function context_dir(directory, bufnr)
  if directory and directory ~= "" then
    return vim.fs.normalize(directory)
  end

  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].buftype == "" then
    local path = vim.api.nvim_buf_get_name(bufnr)
    if path ~= "" then
      path = vim.uv.fs_realpath(path) or vim.fs.normalize(path)
      return vim.fs.dirname(path)
    end
  end
  return vim.fn.getcwd()
end

local function normalize_attach_pids(configurations)
  for _, config in ipairs(configurations) do
    local uses_pid = config.type == "codelldb" or config.type == "lldb"
    if
      config.request == "attach"
      and uses_pid
      and type(config.processId) == "string"
      and config.processId:find("%${command:pickProcess}")
    then
      -- CodeLLDB calls this field `pid`; other VS Code adapters (notably
      -- cppdbg and pwa-node) correctly keep `processId`.
      config.pid = config.processId
      config.processId = nil
    end
  end
  return configurations
end

local function launch_path(directory, bufnr)
  local vscode_dir = vim.fs.find(".vscode", {
    path = context_dir(directory, bufnr),
    upward = true,
    type = "directory",
  })[1]
  local path = vscode_dir and vim.fs.joinpath(vscode_dir, "launch.json")
  if not path or not vim.uv.fs_stat(path) then
    return nil
  end
  local root = vim.fs.dirname(vscode_dir)
  return path, vim.uv.fs_realpath(root) or vim.fs.normalize(root)
end

local function bind_workspace(value, root, bufnr, settings)
  if type(value) == "table" then
    local bound = {}
    for key, item in pairs(value) do
      bound[bind_workspace(key, root, bufnr, settings)] = bind_workspace(item, root, bufnr, settings)
    end

    local metatable = getmetatable(value)
    if metatable and type(metatable.__call) == "function" then
      metatable = vim.deepcopy(metatable)
      metatable.__call = function()
        local rebound = bind_workspace(value(), root, bufnr, settings)
        if rebound.request == "launch" and rebound.cwd == nil then
          rebound.cwd = root
        end
        return rebound
      end
    end
    return setmetatable(bound, metatable)
  end
  if type(value) ~= "string" then
    return value
  end

  local expanded, config_err = require("config.vscode").expand_config(value, settings)
  if config_err then
    error(config_err, 0)
  end

  local file = vim.api.nvim_buf_get_name(bufnr)
  local relative_file = file ~= "" and vim.fs.relpath(root, file) or nil
  local relative_dir = relative_file and vim.fs.dirname(relative_file) or nil
  return (
    expanded
      :gsub("%${workspaceFolderBasename}", function()
        return vim.fs.basename(root)
      end)
      :gsub("%${workspaceFolder}", function()
        return root
      end)
      :gsub("%${relativeFileDirname}", function()
        return relative_dir or ""
      end)
      :gsub("%${relativeFile}", function()
        return relative_file or ""
      end)
  )
end

local function launch_configurations(directory, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local path, root = launch_path(directory, bufnr)
  if not path then
    return {}
  end

  local vscode = require("dap.ext.vscode")
  vscode.json_decode = require("overseer.json").decode
  local ok, configurations = pcall(vscode.getconfigs, path)
  if not ok then
    return nil, ("Unable to load %s: %s"):format(path, configurations)
  end
  local settings, settings_err = require("config.vscode").settings(root)
  if not settings then
    return nil, settings_err
  end
  configurations = normalize_attach_pids(configurations)
  for index, configuration in ipairs(configurations) do
    local ok_bind, bound = pcall(bind_workspace, configuration, root, bufnr, settings)
    if not ok_bind then
      return nil, ("Unable to resolve %s: %s"):format(path, bound)
    end
    configurations[index] = bound
    if configurations[index].request == "launch" and configurations[index].cwd == nil then
      configurations[index].cwd = root
    end
  end
  return configurations
end

local function merged_configurations(directory, bufnr)
  local dap = require("dap")
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filetype = vim.b[bufnr]["dap-srcft"] or vim.bo[bufnr].filetype
  local result = vim.deepcopy(dap.configurations[filetype] or {})
  local launch, err = launch_configurations(directory, bufnr)
  if not launch then
    return result, err
  end

  -- A launch.json entry should replace a same-named built-in configuration,
  -- matching the behavior of the legacy load_launchjs() API.
  for _, configuration in ipairs(launch) do
    for index = #result, 1, -1 do
      local existing = result[index]
      if existing.name == configuration.name and existing.type == configuration.type then
        table.remove(result, index)
      end
    end
    table.insert(result, configuration)
  end
  return result
end

local function configure_provider()
  local dap = require("dap")
  ensure_adapters()

  -- nvim-dap's built-in provider only checks getcwd(). Resolve launch.json
  -- from the active buffer so editing a file from another workspace behaves
  -- like VS Code without changing Neovim's process cwd.
  -- Feed nvim-dap a single merged list. Its default providers concatenate
  -- globals and launch.json verbatim, which produces duplicate picker entries
  -- whenever a workspace overrides a built-in configuration by name.
  dap.providers.configs["dap.global"] = function(bufnr)
    local configurations, err = merged_configurations(nil, bufnr)
    if err then
      vim.notify(err, vim.log.levels.WARN)
    end
    return configurations
  end
  dap.providers.configs["dap.launch.json"] = function()
    return {}
  end
end

function M.setup()
  configure_provider()
end

function M.load_launch(directory)
  configure_provider()
  local configurations, err = launch_configurations(directory)
  if not configurations then
    vim.notify(err, vim.log.levels.WARN)
    return false
  end
  return true
end

function M.configurations(directory)
  configure_provider()
  local configurations, err = merged_configurations(directory)
  if err then
    vim.notify(err, vim.log.levels.WARN)
  end
  return configurations
end

return M
