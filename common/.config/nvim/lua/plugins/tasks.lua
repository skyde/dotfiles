return {
  {
    "stevearc/overseer.nvim",
    cmd = { "OverseerRun", "OverseerToggle", "OverseerRunCmd" },
    dependencies = { "mfussenegger/nvim-dap" },
    opts = {
      dap = true,
      output = {
        use_terminal = true,
        preserve_output = false,
      },
    },
    config = function(_, opts)
      local overseer = require("overseer")
      overseer.setup(opts)

      local function preload()
        overseer.preload_task_cache({ dir = LazyVim.root.get({ normalize = true }) })
      end

      local group = vim.api.nvim_create_augroup("dotfiles_overseer_preload", { clear = true })
      vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, {
        group = group,
        callback = preload,
      })
      vim.schedule(preload)
    end,
    keys = function()
      local dap = require("dap")
      local vscode = require("dap.ext.vscode")

      local function overseer()
        return require("overseer")
      end

      local function recent_task()
        return overseer().list_tasks({ recent_first = true })[1]
      end

      local function ensure_adapters()
        if dap.adapters and dap.adapters.codelldb and not dap.adapters.lldb then
          dap.adapters.lldb = dap.adapters.codelldb
        end
      end

      local function normalize_attach_pids()
        for _, language in ipairs({ "c", "cpp", "rust", "objc", "objcpp" }) do
          for _, config in ipairs(dap.configurations[language] or {}) do
            if config.request == "attach" then
              local pick = require("dap.utils").pick_process
              if type(config.processId) == "string" and config.processId:find("%${command:pickProcess}") then
                config.pid = pick
                config.processId = nil
              end
              if type(config.pid) == "string" and config.pid:find("%${command:pickProcess}") then
                config.pid = pick
              end
            end
          end
        end
      end

      local function ensure_launch_loaded()
        ensure_adapters()
        local vscode_dir = vim.fs.find(".vscode", {
          path = vim.fn.getcwd(),
          upward = true,
          type = "directory",
        })[1]
        local launch = vscode_dir and vim.fs.joinpath(vscode_dir, "launch.json")
        if launch and vim.uv.fs_stat(launch) then
          local ok, err = pcall(vscode.load_launchjs, launch, {
            lldb = { "c", "cpp", "rust" },
            codelldb = { "c", "cpp", "rust" },
          })
          if not ok then
            vim.notify("Unable to load " .. launch .. ": " .. tostring(err), vim.log.levels.WARN)
          end
          normalize_attach_pids()
        end
      end

      local function run_build_default()
        local instance = overseer()
        instance.run_template({ tags = { instance.TAG.BUILD } })
      end

      local function pick_build_task()
        local instance = overseer()
        instance.run_template({ tags = { instance.TAG.BUILD }, prompt = "always" })
      end

      local function rerun_last()
        local task = recent_task()
        if task then
          task:restart(true)
        else
          vim.notify("No task to rerun", vim.log.levels.INFO)
        end
      end

      local function stop_last()
        for _, task in ipairs(overseer().list_tasks({ recent_first = true })) do
          if task:is_running() then
            task:stop()
            return
          end
        end
        vim.notify("No task is running", vim.log.levels.INFO)
      end

      local function debug_start_default()
        ensure_launch_loaded()
        dap.continue()
      end

      local function debug_select_and_start()
        ensure_launch_loaded()
        local filetype = vim.bo.filetype ~= "" and vim.bo.filetype or "cpp"
        local configurations = dap.configurations[filetype] or dap.configurations.cpp or {}
        if #configurations == 0 then
          return vim.notify("No DAP configurations found", vim.log.levels.WARN)
        end
        vim.ui.select(configurations, {
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

      local function break_here()
        ensure_launch_loaded()
        if dap.session() then
          return dap.run_to_cursor()
        end

        local listener = "dotfiles_break_here_once"
        dap.listeners.after.event_initialized[listener] = function()
          dap.listeners.after.event_initialized[listener] = nil
          vim.schedule(dap.run_to_cursor)
        end
        dap.continue()
      end

      return {
        { "<leader>mb", run_build_default, desc = "Tasks: Run Build (default)" },
        { "<leader>mB", pick_build_task, desc = "Tasks: Pick Build" },
        { "<leader>mT", "<cmd>OverseerRun<CR>", desc = "Tasks: Run Task" },
        { "<leader>mt", rerun_last, desc = "Tasks: Re-run Last" },
        { "<leader>mc", stop_last, desc = "Tasks: Terminate Last" },
        { "<leader>mr", debug_start_default, desc = "Debug: Start (VS Code)" },
        { "<leader>mR", debug_select_and_start, desc = "Debug: Select and Start" },
        { "<leader>ms", dap.terminate, desc = "Debug: Stop" },
        { "<leader>mp", break_here, desc = "Debug: Break at cursor" },
      }
    end,
  },
}
