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
      -- Shared with the Shift+F hardware keys in config/keymaps.lua.
      local vscode_debug = require("config.vscode_debug")

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

      -- Break at cursor: prefer run_to_cursor, which sets a temporary bp
      -- If no session, start default config and run_to_cursor on init
      local function break_here()
        vscode_debug.load_launch_json()
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
        { "<leader>mr", vscode_debug.start, desc = "Debug: Start (VS Code)" },
        { "<leader>mR", vscode_debug.select_and_start, desc = "Debug: Select and Start" },
        { "<leader>mp", break_here, desc = "Debug: Break at cursor" },
      }
    end,
  },
}
