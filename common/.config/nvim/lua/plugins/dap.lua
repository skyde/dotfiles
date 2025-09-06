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
      return {
        { "<leader>db", dap.toggle_breakpoint, desc = "DAP Toggle Breakpoint" },
        {
          "<leader>dB",
          function()
            vim.ui.input({ prompt = "Breakpoint condition: " }, function(cond)
              if cond and #cond > 0 then
                dap.set_breakpoint(cond)
              end
            end)
          end,
          desc = "DAP Conditional Breakpoint",
        },
        { "<leader>dc", dap.continue, desc = "DAP Continue" },
        { "<leader>tn", dap.step_over, desc = "DAP Step Over" },
        { "<leader>ti", dap.step_into, desc = "DAP Step Into" },
        { "<leader>to", dap.step_out, desc = "DAP Step Out" },
        { "<leader>dr", dap.repl.open, desc = "DAP REPL" },
        { "<leader>dl", dap.run_last, desc = "DAP Run Last" },
        { "<leader>du", dapui.toggle, desc = "DAP UI Toggle" },
        {
          "<leader><backspace>",
          function()
            require("dap.ui.widgets").hover()
          end,
          mode = { "n", "v" },
          desc = "DAP Eval (hover)",
        },
      }
    end,
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")

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
        local ok_pkg, codelldb = pcall(mason_registry.get_package, "codelldb")
        if ok_pkg and codelldb:is_installed() then
          local ext = codelldb:get_install_path()
          local codelldb_path = ext .. "/extension/adapter/codelldb"
          local sysname = vim.loop.os_uname().sysname
          local liblldb_ext = "so"
          if sysname:find("Windows") then
            codelldb_path = codelldb_path .. ".exe"
            liblldb_ext = "dll"
          elseif sysname == "Darwin" then
            liblldb_ext = "dylib"
          end
          local liblldb_path = ext .. "/extension/lldb/lib/liblldb." .. liblldb_ext
          dap.adapters.codelldb = function(cb, _)
            local stdout = vim.loop.new_pipe(false)
            local stderr = vim.loop.new_pipe(false)
            local handle
            local port = 0
            handle, _ = vim.loop.spawn(codelldb_path, {
              stdio = { nil, stdout, stderr },
              args = { "--liblldb", liblldb_path, "--port", tostring(port) },
            }, function()
              stdout:close()
              stderr:close()
              handle:close()
            end)
            stdout:read_start(function(err, chunk)
              assert(not err, err)
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
        return vim.split(vim.fn.expand(args_str), " ")
      end

      dap.configurations.cpp = {
        {
          name = "Launch file",
          type = "codelldb",
          request = "launch",
          program = function()
            return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
          end,
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
          args = get_args,
          runInTerminal = false,
        },
        {
          name = "Attach to process",
          type = "codelldb",
          request = "attach",
          pid = require("dap.utils").pick_process,
          cwd = "${workspaceFolder}",
        },
      }
      dap.configurations.c = dap.configurations.cpp
      dap.configurations.rust = dap.configurations.cpp

      -- Inline virtual text for values
      require("nvim-dap-virtual-text").setup({
        commented = true,
      })
    end,
  },
}
