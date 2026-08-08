-- Starting a debug session the way the VS Code config does: read the
-- workspace's .vscode/launch.json, fix up the bits nvim-dap spells
-- differently, then run it.
--
-- Extracted from plugins/tasks.lua so the <leader>m keys and the Shift+F
-- hardware macro keys (see config/keymaps.lua) start a session identically
-- instead of drifting apart.

local M = {}

---VS Code's launch.json says `"type": "lldb"`; on this setup only codelldb is
---installed, so point one at the other.
local function ensure_adapters(dap)
  if dap.adapters and dap.adapters.codelldb and not dap.adapters.lldb then
    dap.adapters.lldb = dap.adapters.codelldb
  end
end

---VS Code writes `${command:pickProcess}` for attach configs; nvim-dap wants a
---function on `pid`.
local function normalize_attach_pids(dap)
  -- Required only once something actually needs it. Loading dap.utils up front
  -- makes its absence look like a broken launch.json, which is a confusing way
  -- to report a missing module.
  local picker
  local function pick(...)
    picker = picker or require("dap.utils").pick_process
    return picker(...)
  end
  for _, lang in ipairs({ "c", "cpp", "rust", "objc", "objcpp" }) do
    local cfgs = dap.configurations[lang]
    if type(cfgs) == "table" then
      for _, cfg in ipairs(cfgs) do
        if cfg and cfg.request == "attach" then
          if type(cfg.processId) == "string" and cfg.processId:find("%${command:pickProcess}") then
            cfg.pid = pick
            cfg.processId = nil
          end
          -- Bound to a local first: the type checker narrows a local through
          -- `type()`, but not a field that is also assigned a function below.
          local pid = cfg.pid
          if type(pid) == "string" and pid:find("%${command:pickProcess}") then
            cfg.pid = pick
          end
        end
      end
    end
  end
end

---@return table|nil dap `nil` when nvim-dap is not installed
function M.load_launch_json()
  local ok, dap = pcall(require, "dap")
  if not ok then
    return nil
  end
  ensure_adapters(dap)
  local roots = vim.fs.find(".vscode", { upward = true, type = "directory" })
  if roots and roots[1] then
    local f = roots[1] .. "/launch.json"
    if vim.uv.fs_stat(f) then
      -- Reported, not swallowed. A trailing comma or a stray brace in
      -- launch.json makes this throw, and silently continuing means the debug
      -- key does nothing for a reason nothing on screen explains.
      local loaded, err = pcall(function()
        require("dap.ext.vscode").load_launchjs(f, {
          lldb = { "c", "cpp", "rust" },
          codelldb = { "c", "cpp", "rust" },
        })
        normalize_attach_pids(dap)
      end)
      if not loaded then
        vim.notify(("Could not read %s: %s"):format(f, err), vim.log.levels.WARN)
      end
    end
  end
  return dap
end

---VS Code's `workbench.action.debug.start`: Overseer handles any preLaunchTask,
---`continue` picks the last or default configuration.
function M.start()
  local dap = M.load_launch_json()
  if not dap then
    return vim.notify("nvim-dap is not available", vim.log.levels.WARN)
  end
  dap.continue()
end

---VS Code's "Select and Start Debugging".
function M.select_and_start()
  local dap = M.load_launch_json()
  if not dap then
    return vim.notify("nvim-dap is not available", vim.log.levels.WARN)
  end
  local ft = vim.bo.filetype ~= "" and vim.bo.filetype or "cpp"
  local cfgs = dap.configurations[ft] or {}
  if #cfgs == 0 then
    cfgs = dap.configurations.cpp or {}
  end
  if #cfgs == 0 then
    return vim.notify("No DAP configurations found", vim.log.levels.WARN)
  end
  vim.ui.select(cfgs, {
    prompt = "Select debug configuration",
    format_item = function(item)
      return item.name or "<unnamed>"
    end,
  }, function(choice)
    if choice then
      dap.run(choice)
    end
  end)
end

---VS Code's `workbench.action.debug.stop`, widened to cover the build too since
---the footpedal key is labelled "stop build".
---
---`:CMakeStop` only exists once cmake-tools has loaded, which is filetype-gated
---to C/C++, so it has to be probed rather than assumed.
function M.stop()
  local ok, dap = pcall(require, "dap")
  if ok and dap.session() then
    dap.terminate()
    return
  end

  -- A build started by <leader>mb is an Overseer task, and in a C/C++ buffer
  -- `:CMakeStop` exists whether or not cmake-tools is running anything — so
  -- probing the command first would answer the key with a no-op and leave the
  -- build running. An Overseer task that is actually RUNNING wins.
  local has_overseer, overseer = pcall(require, "overseer")
  if has_overseer then
    local listed, running = pcall(function()
      return overseer.list_tasks({ status = overseer.STATUS and overseer.STATUS.RUNNING or "RUNNING" })
    end)
    if listed and type(running) == "table" and #running > 0 then
      pcall(vim.cmd, "OverseerQuickAction stop")
      return
    end
  end

  if vim.fn.exists(":CMakeStop") == 2 then
    vim.cmd("CMakeStop")
    return
  end
  if has_overseer then
    pcall(vim.cmd, "OverseerQuickAction stop")
    return
  end
  vim.notify("Nothing to stop", vim.log.levels.INFO)
end

return M
