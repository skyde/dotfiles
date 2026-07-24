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
      local vscode = require("config.vscode")
      vscode.setup_overseer()

      local function preload()
        overseer.preload_task_cache({ dir = LazyVim.root.get({ normalize = true }) })
      end

      local group = vim.api.nvim_create_augroup("dotfiles_overseer_preload", { clear = true })
      vim.api.nvim_create_autocmd({ "VimEnter", "DirChanged" }, {
        group = group,
        callback = preload,
      })
      vim.api.nvim_create_autocmd("BufWritePost", {
        group = group,
        pattern = { "*/.vscode/settings.json", "*/.vscode/tasks.json" },
        callback = function()
          vscode.clear_cache()
          overseer.clear_task_cache()
          preload()
        end,
      })
      vim.schedule(preload)
    end,
    keys = function()
      local function overseer()
        return require("overseer")
      end

      local function recent_task()
        return overseer().list_tasks({ recent_first = true })[1]
      end

      local function ensure_launch_loaded()
        return require("config.dap").load_launch()
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
        if not ensure_launch_loaded() then
          return
        end
        require("dap").continue()
      end

      local function debug_select_and_start()
        if not ensure_launch_loaded() then
          return
        end
        local dap = require("dap")
        local configurations = require("config.dap").configurations()
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

      local pending_break_here_cleanup

      local function break_here()
        if not ensure_launch_loaded() then
          return
        end
        local dap = require("dap")
        if dap.session() then
          return dap.run_to_cursor()
        end

        local target_buf = vim.api.nvim_get_current_buf()
        local target_line = vim.api.nvim_win_get_cursor(0)[1]
        local listener = "dotfiles_break_here_once"
        local marker = "__dotfiles_break_here_token"

        -- nvim-dap cannot run_to_cursor until a session is already stopped.
        -- For a fresh launch, select the configuration first, then temporarily
        -- replace breakpoints with the cursor location. Cancellation never
        -- invokes `before`, and every exit path restores the user's snapshot.
        local launch_options = {}
        launch_options.before = function(configuration)
          -- nvim-dap retains the options table for run_last(). Make this
          -- launch-only hook one-shot so rerunning uses the selected config
          -- without resurrecting an old cursor or breakpoint snapshot.
          launch_options.before = nil

          if pending_break_here_cleanup then
            pending_break_here_cleanup()
          end

          local breakpoints = require("dap.breakpoints")
          local snapshot = vim.deepcopy(breakpoints.get())
          local token = ("%d:%d"):format(vim.uv.hrtime(), target_buf)
          local expected_session
          local restored = false
          local on_stopped
          local on_terminated
          local on_exited
          local on_session

          local function remove_listeners()
            if dap.listeners.after.event_stopped[listener] == on_stopped then
              dap.listeners.after.event_stopped[listener] = nil
            end
            if dap.listeners.before.event_terminated[listener] == on_terminated then
              dap.listeners.before.event_terminated[listener] = nil
            end
            if dap.listeners.before.event_exited[listener] == on_exited then
              dap.listeners.before.event_exited[listener] = nil
            end
            if dap.listeners.on_session[listener] == on_session then
              dap.listeners.on_session[listener] = nil
            end
          end

          local function restore(sync_session)
            if restored then
              return
            end
            restored = true
            remove_listeners()
            breakpoints.clear()
            for bufnr, entries in pairs(snapshot) do
              for _, breakpoint in ipairs(entries) do
                breakpoints.set({
                  condition = breakpoint.condition,
                  hit_condition = breakpoint.hitCondition,
                  log_message = breakpoint.logMessage,
                }, bufnr, breakpoint.line)
              end
            end
            if sync_session and not sync_session.closed then
              sync_session:set_breakpoints(breakpoints.get())
            end
            if pending_break_here_cleanup == restore then
              pending_break_here_cleanup = nil
            end
          end

          on_stopped = function(session)
            if session == expected_session then
              restore(session)
            end
          end
          on_terminated = function(session)
            if session == expected_session then
              restore()
            end
          end
          on_exited = on_terminated
          on_session = function(old_session, new_session)
            if new_session and new_session.config and new_session.config[marker] == token then
              expected_session = new_session
              new_session.config[marker] = nil
            elseif expected_session and old_session == expected_session and new_session ~= expected_session then
              restore()
            elseif new_session and not expected_session then
              -- A failed adapter must not leave the temporary breakpoint
              -- armed for a later, unrelated debug launch.
              restore(new_session)
            end
          end

          dap.listeners.after.event_stopped[listener] = on_stopped
          dap.listeners.before.event_terminated[listener] = on_terminated
          dap.listeners.before.event_exited[listener] = on_exited
          dap.listeners.on_session[listener] = on_session
          pending_break_here_cleanup = restore

          breakpoints.clear()
          breakpoints.set({}, target_buf, target_line)
          vim.defer_fn(function()
            if not expected_session then
              restore()
            end
          end, 30000)

          local prepared = vim.deepcopy(configuration)
          local metatable = getmetatable(configuration)
          if metatable and type(metatable.__call) == "function" then
            local original_call = metatable.__call
            metatable = vim.deepcopy(metatable)
            metatable.__call = function(_, ...)
              local resolved = original_call(configuration, ...)
              resolved[marker] = token
              return resolved
            end
            return setmetatable(prepared, metatable)
          end
          prepared[marker] = token
          return prepared
        end
        dap.continue(launch_options)
      end

      return {
        { "<leader>mb", run_build_default, desc = "Tasks: Run Build (default)" },
        { "<leader>mB", pick_build_task, desc = "Tasks: Pick Build" },
        { "<leader>mT", "<cmd>OverseerRun<CR>", desc = "Tasks: Run Task" },
        { "<leader>mt", rerun_last, desc = "Tasks: Re-run Last" },
        { "<leader>mc", stop_last, desc = "Tasks: Terminate Last" },
        { "<leader>mr", debug_start_default, desc = "Debug: Start (VS Code)" },
        { "<leader>mR", debug_select_and_start, desc = "Debug: Select and Start" },
        {
          "<leader>ms",
          function()
            require("dap").terminate()
          end,
          desc = "Debug: Stop",
        },
        { "<leader>mp", break_here, desc = "Debug: Break at cursor" },
      }
    end,
  },
}
