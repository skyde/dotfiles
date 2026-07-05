return {
  -- Core DAP
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "rcarriga/nvim-dap-ui",
      "theHamsta/nvim-dap-virtual-text",
      "jay-babu/mason-nvim-dap.nvim",
      -- Required by nvim-dap-ui
      "nvim-neotest/nvim-nio",
    },
    keys = function()
      local dap = require("dap")
      local dapui = require("dapui")
      local unpack_fn = unpack or table.unpack

      local function safe_call(label, fn, ...)
        local args = { ... }
        return function()
          local ok, err = pcall(fn, unpack_fn(args))
          if not ok then
            vim.notify("Unable to " .. label .. ": " .. tostring(err), vim.log.levels.WARN)
          end
        end
      end

      local function eval_hover()
        local ok, widgets = pcall(require, "dap.ui.widgets")
        if not ok then
          vim.notify("Unable to load DAP widgets: " .. tostring(widgets), vim.log.levels.WARN)
          return
        end

        local hover_ok, err = pcall(widgets.hover)
        if not hover_ok then
          vim.notify("Unable to show DAP hover: " .. tostring(err), vim.log.levels.WARN)
        end
      end

      return {
        { "<leader>db", safe_call("toggle DAP breakpoint", dap.toggle_breakpoint), desc = "DAP Toggle Breakpoint" },
        {
          "<leader>dB",
          function()
            vim.ui.input({ prompt = "Breakpoint condition: " }, function(cond)
              if cond and #cond > 0 then
                local ok, err = pcall(dap.set_breakpoint, cond)
                if not ok then
                  vim.notify("Unable to set conditional breakpoint: " .. tostring(err), vim.log.levels.WARN)
                end
              end
            end)
          end,
          desc = "DAP Conditional Breakpoint",
        },
        { "<leader>dC", safe_call("clear DAP breakpoints", dap.clear_breakpoints), desc = "DAP Clear Breakpoints" },
        { "<leader>dc", safe_call("continue DAP session", dap.continue), desc = "DAP Continue" },
        { "<leader>de", eval_hover, mode = { "n", "v" }, desc = "DAP Eval (hover)" },
        { "<leader>dQ", safe_call("disconnect DAP session", dap.disconnect), desc = "DAP Disconnect" },
        { "<leader>dq", safe_call("terminate DAP session", dap.terminate), desc = "DAP Terminate" },
        { "<leader>tn", safe_call("step over", dap.step_over), desc = "DAP Step Over" },
        { "<leader>ti", safe_call("step into", dap.step_into), desc = "DAP Step Into" },
        { "<leader>to", safe_call("step out", dap.step_out), desc = "DAP Step Out" },
        { "<leader>dr", safe_call("open DAP REPL", dap.repl.open), desc = "DAP REPL" },
        { "<leader>dl", safe_call("run last DAP session", dap.run_last), desc = "DAP Run Last" },
        { "<leader>du", safe_call("toggle DAP UI", dapui.toggle), desc = "DAP UI Toggle" },
        {
          "<leader><backspace>",
          eval_hover,
          mode = { "n", "v" },
          desc = "DAP Eval (hover)",
        },
      }
    end,
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")
      local debug = require("config.debug")
      local project = require("config.project")
      local uv = vim.uv or vim.loop

      -- Nice icons for breakpoints and current line
      vim.fn.sign_define("DapBreakpoint", { text = "", texthl = "DiagnosticSignError" })
      vim.fn.sign_define(
        "DapStopped",
        { text = "", texthl = "DiagnosticSignInfo", linehl = "DiagnosticUnderlineInfo" }
      )

      -- DAP UI
      dapui.setup({
        controls = { enabled = true, element = "repl" },
        floating = { border = "rounded" },
      })
      dap.listeners.after.event_initialized["dapui_config"] = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated["dapui_config"] = function()
        dapui.close()
      end
      dap.listeners.before.event_exited["dapui_config"] = function()
        dapui.close()
      end

      -- Auto-install and set up adapters via Mason
      require("mason-nvim-dap").setup({
        ensure_installed = { "codelldb" },
        automatic_installation = true,
        handlers = {}, -- keep defaults
      })

      -- C/C++/Rust configurations using codelldb
      -- mason-nvim-dap registers the adapter if installed, but we add robust fallback
      local ok_mason, mason_registry = pcall(require, "mason-registry")
      if ok_mason and not dap.adapters.codelldb then
        local ok_pkg, codelldb = pcall(mason_registry.get_package, mason_registry, "codelldb")
        if ok_pkg and codelldb:is_installed() then
          local ext = codelldb:get_install_path()
          local codelldb_path = ext .. "/extension/adapter/codelldb"
          local sysname = uv.os_uname().sysname
          local liblldb_ext = "so"
          if sysname:find("Windows") then
            codelldb_path = codelldb_path .. ".exe"
            liblldb_ext = "dll"
          elseif sysname == "Darwin" then
            liblldb_ext = "dylib"
          end
          local liblldb_path = ext .. "/extension/lldb/lib/liblldb." .. liblldb_ext

          local function close_handle(handle)
            if handle and not handle:is_closing() then
              handle:close()
            end
          end

          dap.adapters.codelldb = function(cb, _)
            local stdout = uv.new_pipe(false)
            local stderr = uv.new_pipe(false)
            local handle, spawn_err
            local port = 0
            handle, spawn_err = uv.spawn(codelldb_path, {
              stdio = { nil, stdout, stderr },
              args = { "--liblldb", liblldb_path, "--port", tostring(port) },
            }, function()
              close_handle(stdout)
              close_handle(stderr)
              close_handle(handle)
            end)

            if not handle then
              close_handle(stdout)
              close_handle(stderr)
              vim.schedule(function()
                vim.notify("Unable to start codelldb: " .. tostring(spawn_err), vim.log.levels.ERROR)
              end)
              return
            end

            stdout:read_start(function(err, chunk)
              if err then
                vim.schedule(function()
                  vim.notify("codelldb stdout error: " .. tostring(err), vim.log.levels.ERROR)
                end)
                return
              end
              if chunk then
                local m = chunk:match("Listening on port (%d+)")
                if m then
                  cb({ type = "server", host = "127.0.0.1", port = tonumber(m) })
                end
              end
            end)
            stderr:read_start(function() end)
          end
        end
      end

      local function get_args()
        local args_str = vim.fn.input("Args: ")
        return debug.parse_args(args_str)
      end

      local function debug_cwd()
        return project.root_for_buffer(0)
      end

      dap.configurations.cpp = {
        {
          name = "Launch file",
          type = "codelldb",
          request = "launch",
          program = function()
            return vim.fn.input("Path to executable: ", debug_cwd() .. "/", "file")
          end,
          cwd = debug_cwd,
          stopOnEntry = false,
          args = get_args,
          runInTerminal = false,
        },
        {
          name = "Attach to process",
          type = "codelldb",
          request = "attach",
          pid = require("dap.utils").pick_process,
          cwd = debug_cwd,
        },
      }
      dap.configurations.c = dap.configurations.cpp
      dap.configurations.rust = dap.configurations.cpp
      dap.configurations.objc = dap.configurations.cpp
      dap.configurations.objcpp = dap.configurations.cpp

      -- Inline virtual text for values
      require("nvim-dap-virtual-text").setup({
        commented = true,
      })
    end,
  },
}
