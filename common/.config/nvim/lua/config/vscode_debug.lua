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
  local pick = require("dap.utils").pick_process
  for _, lang in ipairs({ "c", "cpp", "rust", "objc", "objcpp" }) do
    local cfgs = dap.configurations[lang]
    if type(cfgs) == "table" then
      for _, cfg in ipairs(cfgs) do
        if cfg and cfg.request == "attach" then
          if type(cfg.processId) == "string" and cfg.processId:find("%${command:pickProcess}") then
            cfg.pid = pick
            cfg.processId = nil
          end
          if type(cfg.pid) == "string" and cfg.pid:find("%${command:pickProcess}") then
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
      pcall(function()
        require("dap.ext.vscode").load_launchjs(f, {
          lldb = { "c", "cpp", "rust" },
          codelldb = { "c", "cpp", "rust" },
        })
        normalize_attach_pids(dap)
      end)
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
  if vim.fn.exists(":CMakeStop") == 2 then
    vim.cmd("CMakeStop")
    return
  end
  if pcall(require, "overseer") then
    pcall(vim.cmd, "OverseerQuickAction stop")
    return
  end
  vim.notify("Nothing to stop", vim.log.levels.INFO)
end

return M
