return {
  {
    "stevearc/overseer.nvim",
    cmd = { "OverseerRun", "OverseerToggle", "OverseerQuickAction", "OverseerRunCmd" },
    dependencies = { "mfussenegger/nvim-dap" },
    opts = {
      -- Use a simple terminal buffer for portability; toggleterm is optional
      strategy = "terminal",
      templates = { "builtin" },
      dap = true, -- enable preLaunchTask/postDebugTask with nvim-dap
    },
    config = function(_, opts)
      local overseer = require("overseer")
      overseer.setup(opts)

      -- Preload VS Code tasks for the current workspace to reduce first-run
      -- delay. The plugin loads on demand, after VimEnter has already fired,
      -- so the initial preload must be a direct call, not a VimEnter autocmd.
      local function preload()
        overseer.preload_task_cache({ dir = vim.fn.getcwd() })
      end
      vim.api.nvim_create_autocmd("DirChanged", { callback = preload })
      preload()
    end,
    -- lazy.nvim evaluates `keys` specs during startup, so requires stay inside
    -- the callbacks; a require at the top of a keys function would load
    -- overseer and the whole DAP chain on every launch (see dap.lua).
    keys = {
      -- Match VS Code-style task keys from your settings.json
      {
        "<leader>mb",
        function()
          local overseer = require("overseer")
          overseer.run_template({ tags = { overseer.TAG.BUILD } })
        end,
        desc = "Tasks: Run Build (default)",
      },
      {
        "<leader>mB",
        function()
          local overseer = require("overseer")
          overseer.run_template({ tags = { overseer.TAG.BUILD }, prompt = "always" })
        end,
        desc = "Tasks: Pick Build",
      },
      { "<leader>mT", "<cmd>OverseerRun<cr>", desc = "Tasks: Run Task" },
      { "<leader>mt", "<cmd>OverseerQuickAction restart<cr>", desc = "Tasks: Re-run Last" },
      { "<leader>mc", "<cmd>OverseerQuickAction stop<cr>", desc = "Tasks: Terminate Last" },
      -- Debug: start / select-and-start (preLaunchTask handled by Overseer).
      -- Shared with the Shift+F hardware keys in config/keymaps.lua.
      {
        "<leader>mr",
        function()
          require("config.vscode_debug").start()
        end,
        desc = "Debug: Start (VS Code)",
      },
      {
        "<leader>mR",
        function()
          require("config.vscode_debug").select_and_start()
        end,
        desc = "Debug: Select and Start",
      },
      {
        -- The same action Shift+F7 (the footpedal's "stop build") runs: a
        -- live debug session first, then a CMake build, then the last task.
        "<leader>ms",
        function()
          require("config.vscode_debug").stop()
        end,
        desc = "Debug: Stop (session, build or task)",
      },
      {
        "<leader>mp",
        -- Break at cursor: prefer run_to_cursor, which sets a temporary bp.
        -- If no session, start default config and run_to_cursor on init.
        function()
          require("config.vscode_debug").load_launch_json()
          local dap = require("dap")
          local function rtc()
            pcall(dap.run_to_cursor)
          end
          if dap.session() then
            rtc()
          else
            local key = "break_here_once"
            dap.listeners.after.event_initialized[key] = function()
              dap.listeners.after.event_initialized[key] = nil
              vim.schedule(rtc)
            end
            dap.continue()
          end
        end,
        desc = "Debug: Break at cursor",
      },
    },
  },
}
