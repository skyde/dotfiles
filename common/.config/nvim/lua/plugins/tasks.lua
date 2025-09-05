return {
  {
    "stevearc/overseer.nvim",
    cmd = { "OverseerRun", "OverseerToggle", "OverseerQuickAction", "OverseerRunCmd" },
    dependencies = { "mfussenegger/nvim-dap" },
  opts = function()
      local ok, overseer = pcall(require, "overseer")
      if not ok then
        return {}
      end
      overseer.setup({
        -- Use a simple terminal buffer for portability; toggleterm is optional
        strategy = "terminal",
    templates = { "builtin" },
    dap = true, -- enable preLaunchTask/postDebugTask with nvim-dap
      })

      -- Preload VS Code tasks for the current workspace to reduce first-run delay
      local function preload()
        local cwd = vim.fn.getcwd()
        overseer.preload_task_cache({ dir = cwd })
      end
      vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, {
        callback = preload,
      })

      return {}
    end,
    keys = function()
      local overseer = require("overseer")
      local TAG = overseer.TAG
      local dap = require("dap")
      local vscode = require("dap.ext.vscode")

      local function ensure_adapters()
        -- If only codelldb is installed, alias VS Code's "lldb" to it
        if dap.adapters and dap.adapters.codelldb and not dap.adapters.lldb then
          dap.adapters.lldb = dap.adapters.codelldb
        end
      end

      local function normalize_attach_pids()
        local langs = { "c", "cpp", "rust", "objc", "objcpp" }
        for _, lang in ipairs(langs) do
          local cfgs = dap.configurations[lang]
          if type(cfgs) == "table" then
            for _, cfg in ipairs(cfgs) do
              if cfg and cfg.request == "attach" then
                -- VS Code commonly uses processId with ${command:pickProcess}
                local pick = require("dap.utils").pick_process
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

      local function ensure_launch_loaded()
        ensure_adapters()
        local roots = vim.fs.find(".vscode", { upward = true, type = "directory" })
        if roots and roots[1] then
          local f = roots[1] .. "/launch.json"
          if vim.uv.fs_stat(f) then
            pcall(vscode.load_launchjs, f, { lldb = { "c", "cpp", "rust" }, codelldb = { "c", "cpp", "rust" } })
            normalize_attach_pids()
          end
        end
      end

      local function run_build_default()
        overseer.run_template({ tags = { TAG.BUILD } })
      end
      local function pick_build_task()
        overseer.run_template({ tags = { TAG.BUILD }, prompt = "always" })
      end
      local function run_task_picker()
        vim.cmd("OverseerRun")
      end
      local function rerun_last()
        vim.cmd("OverseerQuickAction restart")
      end
      local function stop_last()
        vim.cmd("OverseerQuickAction stop")
      end

      local function debug_start_default()
        ensure_launch_loaded()
        -- Let Overseer handle preLaunchTask; dap.continue uses last/default config
        dap.continue()
      end

      local function debug_select_and_start()
        ensure_launch_loaded()
        local ft = vim.bo.filetype ~= "" and vim.bo.filetype or "cpp"
        local cfgs = (dap.configurations[ft] or {})
        if #cfgs == 0 then
          -- fall back to cpp configs if current ft has none
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

      -- Break at cursor: prefer run_to_cursor, which sets a temporary bp
      -- If no session, start default config and run_to_cursor on init
      local function break_here()
        ensure_launch_loaded()
        local function rtc()
          pcall(dap.run_to_cursor)
        end
        local s = dap.session()
        if s then
          rtc()
        else
          local key = "break_here_once"
          dap.listeners.after.event_initialized[key] = function()
            dap.listeners.after.event_initialized[key] = nil
            vim.schedule(rtc)
          end
          dap.continue()
        end
      end

      return {
        -- Match VS Code-style task keys from your settings.json
        { "<leader>mb", run_build_default, desc = "Tasks: Run Build (default)" },
        { "<leader>mB", pick_build_task, desc = "Tasks: Pick Build" },
        { "<leader>mT", run_task_picker, desc = "Tasks: Run Task" },
        { "<leader>mt", rerun_last, desc = "Tasks: Re-run Last" },
        { "<leader>mc", stop_last, desc = "Tasks: Terminate Last" },
        -- Debug: start / select-and-start (preLaunchTask handled by Overseer)
        { "<leader>mr", debug_start_default, desc = "Debug: Start (VS Code)" },
        { "<leader>mR", debug_select_and_start, desc = "Debug: Select and Start" },
        { "<leader>mp", break_here, desc = "Debug: Break at cursor" },
      }
    end,
  },
}
