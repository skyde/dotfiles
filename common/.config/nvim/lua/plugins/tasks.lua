return {
  {
    "stevearc/overseer.nvim",
    cmd = { "OverseerRun", "OverseerToggle", "OverseerTaskAction", "OverseerShell", "OverseerOpen", "OverseerClose" },
    dependencies = { "mfussenegger/nvim-dap" },
    opts = {
      -- Use a simple terminal buffer for portability; toggleterm is optional.
      strategy = "terminal",
      templates = { "builtin" },
      dap = true, -- Enable preLaunchTask/postDebugTask with nvim-dap.
    },
    config = function(_, opts)
      local overseer = require("overseer")
      local project = require("config.project")
      overseer.setup(opts)

      local group = vim.api.nvim_create_augroup("sky_overseer_preload", { clear = true })
      local preloaded_task_dirs = {}

      local function task_preload_dir()
        local start = project.buffer_start(0)
        local _, workspace_dir = project.vscode_file("tasks.json", start)
        if workspace_dir then
          return workspace_dir
        end

        return project.root(start)
      end

      -- Preload VS Code tasks for the active buffer's workspace to reduce first-run delay.
      local function preload_tasks()
        local dir = task_preload_dir()
        if preloaded_task_dirs[dir] then
          return
        end

        local ok = pcall(overseer.preload_task_cache, { dir = dir })
        if ok then
          preloaded_task_dirs[dir] = true
        end
      end

      vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged", "BufEnter" }, {
        group = group,
        callback = preload_tasks,
      })
    end,
    keys = function()
      local loaded_launchjs = {}
      local project = require("config.project")

      local function require_or_warn(module, label)
        local ok, value = pcall(require, module)
        if ok then
          return value
        end

        vim.notify("Unable to load " .. label .. ": " .. tostring(value), vim.log.levels.WARN)
        return nil
      end

      local function task_workspace_dir()
        local start = project.buffer_start(0)
        local _, workspace_dir = project.vscode_file("tasks.json", start)
        return workspace_dir or project.root(start)
      end

      local function run_project_task(overseer, opts)
        local dir = task_workspace_dir()
        local run_opts = vim.tbl_extend("force", opts or {}, {
          cwd = dir,
          search_params = {
            dir = dir,
            filetype = vim.bo.filetype,
          },
        })
        local ok, err = pcall(overseer.run_task, run_opts)
        if not ok then
          vim.notify("Unable to run task: " .. tostring(err), vim.log.levels.WARN)
        end
      end

      local function ensure_adapters(dap)
        -- If only codelldb is installed, alias VS Code's "lldb" to it
        if dap.adapters and dap.adapters.codelldb and not dap.adapters.lldb then
          dap.adapters.lldb = dap.adapters.codelldb
        end
      end

      local function normalize_attach_pids(dap)
        local langs = { "c", "cpp", "rust", "objc", "objcpp" }
        local dap_utils = require_or_warn("dap.utils", "DAP process picker")
        if not dap_utils then
          return
        end
        local pick = dap_utils.pick_process
        if type(dap.configurations) ~= "table" then
          return
        end

        local function is_pick_process_command(value)
          if type(value) ~= "string" then
            return false
          end

          local command = vim.trim(value):match("^%${command:([%w_.-]+)}$")
          if not command then
            return false
          end

          command = command:lower()
          return command == "pickprocess"
            or command == "pickremoteprocess"
            or command:match("%.pickprocess$") ~= nil
            or command:match("%.pickremoteprocess$") ~= nil
        end

        for _, lang in ipairs(langs) do
          local cfgs = dap.configurations[lang]
          if type(cfgs) == "table" then
            for _, cfg in ipairs(cfgs) do
              if cfg and cfg.request == "attach" then
                -- VS Code attach configs often use processId placeholders that nvim-dap needs as pid callbacks.
                if is_pick_process_command(cfg.processId) then
                  cfg.pid = pick
                  cfg.processId = nil
                end
                if is_pick_process_command(cfg.pid) then
                  cfg.pid = pick
                end
              end
            end
          end
        end
      end

      local function ensure_launch_loaded(dap)
        local vscode = require_or_warn("dap.ext.vscode", "DAP VS Code support")
        if not vscode then
          return
        end

        ensure_adapters(dap)
        local f = project.vscode_file("launch.json", project.buffer_start(0))
        if f then
          if not loaded_launchjs[f] then
            local c_family = { "c", "cpp", "rust", "objc", "objcpp" }
            local ok, err = pcall(vscode.load_launchjs, f, { lldb = c_family, codelldb = c_family })
            if not ok then
              vim.notify("Unable to load launch.json: " .. tostring(err), vim.log.levels.WARN)
            end
            loaded_launchjs[f] = ok
          end
          normalize_attach_pids(dap)
        end
      end

      local function dap_continue(dap)
        if type(dap.continue) ~= "function" then
          vim.notify("Unable to start debug session: DAP continue is unavailable", vim.log.levels.WARN)
          return
        end

        local ok, err = pcall(dap.continue)
        if not ok then
          vim.notify("Unable to start debug session: " .. tostring(err), vim.log.levels.WARN)
        end
      end

      local function run_build_default()
        local overseer = require_or_warn("overseer", "Overseer")
        if not overseer then
          return
        end
        run_project_task(overseer, { tags = { overseer.TAG.BUILD } })
      end

      local function pick_build_task()
        local overseer = require_or_warn("overseer", "Overseer")
        if not overseer then
          return
        end
        run_project_task(overseer, { tags = { overseer.TAG.BUILD }, first = false })
      end

      local function run_task_picker()
        local overseer = require_or_warn("overseer", "Overseer")
        if not overseer then
          return
        end
        run_project_task(overseer, { first = false })
      end

      local function toggle_tasks()
        local ok, err = pcall(vim.cmd, "OverseerToggle")
        if not ok then
          vim.notify("Unable to toggle Overseer: " .. tostring(err), vim.log.levels.WARN)
        end
      end

      local function rerun_last()
        local overseer = require_or_warn("overseer", "Overseer")
        if not overseer then
          return
        end
        local ok, tasks = pcall(overseer.list_tasks, { unique = true })
        if not ok then
          return vim.notify("Unable to list tasks: " .. tostring(tasks), vim.log.levels.WARN)
        end

        local task = tasks[1]
        if not task then
          return vim.notify("No tasks available", vim.log.levels.WARN)
        end

        local action_ok, err = pcall(overseer.run_action, task, "restart")
        if not action_ok then
          vim.notify("Unable to restart task: " .. tostring(err), vim.log.levels.WARN)
        end
      end

      local function stop_last()
        local overseer = require_or_warn("overseer", "Overseer")
        if not overseer then
          return
        end
        local ok, tasks = pcall(overseer.list_tasks, { unique = true, status = "RUNNING" })
        if not ok then
          return vim.notify("Unable to list running tasks: " .. tostring(tasks), vim.log.levels.WARN)
        end

        local task = tasks[1]
        if not task then
          return vim.notify("No running tasks", vim.log.levels.WARN)
        end

        local action_ok, err = pcall(overseer.run_action, task, "stop")
        if not action_ok then
          vim.notify("Unable to stop task: " .. tostring(err), vim.log.levels.WARN)
        end
      end

      local function debug_start_default()
        local dap = require_or_warn("dap", "DAP")
        if not dap then
          return
        end

        ensure_launch_loaded(dap)
        -- Let Overseer handle preLaunchTask; dap.continue uses last/default config
        dap_continue(dap)
      end

      local function debug_select_and_start()
        local dap = require_or_warn("dap", "DAP")
        if not dap then
          return
        end

        ensure_launch_loaded(dap)
        local ft = vim.bo.filetype ~= "" and vim.bo.filetype or "cpp"
        local configurations = dap.configurations or {}
        local cfgs = (configurations[ft] or {})
        if #cfgs == 0 then
          -- fall back to cpp configs if current ft has none
          cfgs = configurations.cpp or {}
        end
        if #cfgs == 0 then
          return vim.notify("No DAP configurations found", vim.log.levels.WARN)
        end
        local ok, err = pcall(vim.ui.select, cfgs, {
          prompt = "Select debug configuration",
          format_item = function(item)
            return item.name or "<unnamed>"
          end,
        }, function(choice)
          if choice then
            if type(dap.run) ~= "function" then
              vim.notify("Unable to run debug configuration: DAP run is unavailable", vim.log.levels.WARN)
              return
            end

            local run_ok, run_err = pcall(dap.run, choice)
            if not run_ok then
              vim.notify("Unable to run debug configuration: " .. tostring(run_err), vim.log.levels.WARN)
            end
          end
        end)
        if not ok then
          vim.notify("Unable to show debug configuration picker: " .. tostring(err), vim.log.levels.WARN)
        end
      end

      -- Break at cursor: prefer run_to_cursor, which sets a temporary bp
      -- If no session, start default config and run_to_cursor on init
      local function break_here()
        local dap = require_or_warn("dap", "DAP")
        if not dap then
          return
        end

        ensure_launch_loaded(dap)
        local function rtc()
          if type(dap.run_to_cursor) ~= "function" then
            vim.notify("Unable to run to cursor: DAP run_to_cursor is unavailable", vim.log.levels.WARN)
            return
          end

          local ok, err = pcall(dap.run_to_cursor)
          if not ok then
            vim.notify("Unable to run to cursor: " .. tostring(err), vim.log.levels.WARN)
          end
        end
        if type(dap.session) ~= "function" then
          vim.notify("Unable to inspect DAP session: DAP session is unavailable", vim.log.levels.WARN)
          return
        end

        local session_ok, s = pcall(dap.session)
        if not session_ok then
          vim.notify("Unable to inspect DAP session: " .. tostring(s), vim.log.levels.WARN)
          return
        end
        if s then
          rtc()
        else
          if not (dap.listeners and dap.listeners.after and dap.listeners.after.event_initialized) then
            vim.notify("Unable to install break-at-cursor hook: DAP listeners are unavailable", vim.log.levels.WARN)
            return
          end
          local key = "break_here_once"
          dap.listeners.after.event_initialized[key] = function()
            dap.listeners.after.event_initialized[key] = nil
            vim.schedule(rtc)
          end
          dap_continue(dap)
        end
      end

      return {
        -- Match VS Code-style task keys from your settings.json
        { "<leader>mb", run_build_default, desc = "Tasks: Run Build (default)" },
        { "<leader>mB", pick_build_task, desc = "Tasks: Pick Build" },
        { "<leader>mT", run_task_picker, desc = "Tasks: Run Task" },
        { "<leader>mt", rerun_last, desc = "Tasks: Re-run Last" },
        { "<leader>mo", toggle_tasks, desc = "Tasks: Toggle Overseer" },
        { "<leader>mc", stop_last, desc = "Tasks: Terminate Last" },
        -- Debug: start / select-and-start (preLaunchTask handled by Overseer)
        { "<leader>mr", debug_start_default, desc = "Debug: Start (VS Code)" },
        { "<leader>mR", debug_select_and_start, desc = "Debug: Select and Start" },
        { "<leader>mp", break_here, desc = "Debug: Break at cursor" },
      }
    end,
  },
}
