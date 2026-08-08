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
    -- lazy.nvim evaluates `keys` specs during startup to register the trigger
    -- mappings, so a require at the top of a keys function loads the plugin --
    -- and with it the whole DAP/mason chain -- on every launch. The requires
    -- have to stay inside the callbacks for the lazy-loading to mean anything.
    keys = {
      {
        "<leader>db",
        function()
          require("dap").toggle_breakpoint()
        end,
        desc = "DAP Toggle Breakpoint",
      },
      {
        "<leader>dB",
        function()
          vim.ui.input({ prompt = "Breakpoint condition: " }, function(cond)
            if cond and #cond > 0 then
              require("dap").set_breakpoint(cond)
            end
          end)
        end,
        desc = "DAP Conditional Breakpoint",
      },
      {
        "<leader>dc",
        function()
          require("dap").continue()
        end,
        desc = "DAP Continue",
      },
      -- Stepping is deliberately absent here. config/parity.lua owns the whole
      -- <leader>t cluster (step over/into/out, up/down the call stack, the
      -- dapui views) to keep it together and matching the VS Code layout, and
      -- it loads on VeryLazy — after lazy.nvim has registered these triggers,
      -- so declaring them in both places left three dead entries that looked
      -- authoritative and were silently replaced. Nothing is lost by dropping
      -- them: parity.lua reaches dap through `require`, which lazy.nvim's
      -- loader answers by loading the plugin, exactly as a `keys` trigger does.
      {
        "<leader>dr",
        function()
          require("dap").repl.open()
        end,
        desc = "DAP REPL",
      },
      {
        "<leader>dl",
        function()
          require("dap").run_last()
        end,
        desc = "DAP Run Last",
      },
      {
        "<leader>du",
        function()
          require("dapui").toggle()
        end,
        desc = "DAP UI Toggle",
      },
      {
        "<leader><backspace>",
        function()
          require("dap.ui.widgets").hover()
        end,
        mode = { "n", "v" },
        desc = "DAP Eval (hover)",
      },
    },
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
        local ok_pkg, codelldb = pcall(mason_registry.get_package, mason_registry, "codelldb")
        if ok_pkg and codelldb:is_installed() then
          local ext = codelldb:get_install_path()
          local codelldb_path = ext .. "/extension/adapter/codelldb"
          local sysname = vim.uv.os_uname().sysname
          local liblldb_ext = "so"
          if sysname:find("Windows") then
            codelldb_path = codelldb_path .. ".exe"
            liblldb_ext = "dll"
          elseif sysname == "Darwin" then
            liblldb_ext = "dylib"
          end
          local liblldb_path = ext .. "/extension/lldb/lib/liblldb." .. liblldb_ext
          dap.adapters.codelldb = function(cb, _)
            local stdout = assert(vim.uv.new_pipe(false))
            local stderr = assert(vim.uv.new_pipe(false))
            local handle, spawn_err
            -- Port 0 asks the OS for a free one; codelldb prints which it got,
            -- and that line is what completes the adapter below.
            handle, spawn_err = vim.uv.spawn(codelldb_path, {
              stdio = { nil, stdout, stderr },
              args = { "--liblldb", liblldb_path, "--port", "0" },
            }, function()
              -- Every handle this adapter opened, closed exactly once — the
              -- exit callback is the only place that can know the process is
              -- done with them.
              if not stdout:is_closing() then
                stdout:close()
              end
              if not stderr:is_closing() then
                stderr:close()
              end
              if handle and not handle:is_closing() then
                handle:close()
              end
            end)
            if not handle then
              -- Without this the pipes would sit open and `cb` would never be
              -- called, so the session hangs on "Starting debug adapter" with
              -- nothing said about why.
              stdout:close()
              stderr:close()
              vim.notify(
                ("codelldb failed to start (%s): %s"):format(codelldb_path, spawn_err or "unknown error"),
                vim.log.levels.ERROR
              )
              return
            end
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

      -- Split on runs of whitespace and drop the empties: splitting a blank
      -- answer on a single space yields { "" }, which launches the program with
      -- one empty argument rather than none.
      local function get_args()
        local args_str = vim.fn.input("Args: ")
        return vim.split(vim.fn.expand(args_str), "%s+", { trimempty = true })
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
