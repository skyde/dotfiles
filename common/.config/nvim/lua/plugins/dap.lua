return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      {
        "rcarriga/nvim-dap-ui",
        config = function() end,
      },
      {
        "theHamsta/nvim-dap-virtual-text",
        config = function() end,
      },
      {
        "jay-babu/mason-nvim-dap.nvim",
        -- nvim-dap owns the single setup call below. Without this no-op,
        -- lazy.nvim also auto-configures the dependency from its opts.
        config = function() end,
      },
      "nvim-neotest/nvim-nio",
    },
    keys = function()
      local disabled_breakpoints = {}

      local function call(module, method)
        return function(...)
          return require(module)[method](...)
        end
      end

      local function conditional_breakpoint()
        local dap = require("dap")
        vim.ui.input({ prompt = "Breakpoint condition: " }, function(condition)
          if condition and condition ~= "" then
            dap.set_breakpoint(condition)
          end
        end)
      end

      local function log_point()
        local dap = require("dap")
        vim.ui.input({ prompt = "Log point message: " }, function(message)
          if message and message ~= "" then
            dap.set_breakpoint(nil, nil, message)
          end
        end)
      end

      local function disable_all_breakpoints()
        local breakpoints = require("dap.breakpoints")
        disabled_breakpoints = vim.deepcopy(breakpoints.get())
        if vim.tbl_isempty(disabled_breakpoints) then
          return vim.notify("No breakpoints to disable", vim.log.levels.INFO)
        end
        require("dap").clear_breakpoints()
        vim.notify("Breakpoints disabled", vim.log.levels.INFO)
      end

      local function enable_all_breakpoints()
        if vim.tbl_isempty(disabled_breakpoints) then
          return vim.notify("No disabled breakpoints", vim.log.levels.INFO)
        end

        local breakpoints = require("dap.breakpoints")
        for bufnr, entries in pairs(disabled_breakpoints) do
          for _, breakpoint in ipairs(entries) do
            breakpoints.set({
              condition = breakpoint.condition,
              hit_condition = breakpoint.hitCondition,
              log_message = breakpoint.logMessage,
            }, bufnr, breakpoint.line)
          end
        end
        disabled_breakpoints = {}

        local dap = require("dap")
        local session = dap.session()
        if session then
          session:set_breakpoints(breakpoints.get())
        end
        vim.notify("Breakpoints enabled", vim.log.levels.INFO)
      end

      local function clear_all_breakpoints()
        disabled_breakpoints = {}
        require("dap").clear_breakpoints()
      end

      local function frame_edge(first)
        local dap = require("dap")
        local session = dap.session()
        local thread = session and session.stopped_thread_id and session.threads[session.stopped_thread_id]
        local frames = thread and thread.frames
        if not frames or not session.current_frame then
          return vim.notify("No stopped stack frame", vim.log.levels.INFO)
        end

        local current = 1
        for index, frame in ipairs(frames) do
          if frame.id == session.current_frame.id then
            current = index
            break
          end
        end

        local target = first and 1 or #frames
        local move = target < current and dap.down or dap.up
        for _ = 1, math.abs(target - current) do
          move()
        end
      end

      local function expression()
        return require("dapui.util").get_current_expr()
      end

      return {
        { "<leader>db", call("dap", "toggle_breakpoint"), desc = "DAP Toggle Breakpoint" },
        { "<leader>dBc", conditional_breakpoint, desc = "DAP Conditional Breakpoint" },
        { "<leader>dBd", disable_all_breakpoints, desc = "DAP Disable All Breakpoints" },
        { "<leader>dBe", enable_all_breakpoints, desc = "DAP Enable All Breakpoints" },
        { "<leader>dBr", clear_all_breakpoints, desc = "DAP Remove All Breakpoints" },
        { "<leader>dL", log_point, desc = "DAP Log Point" },
        { "<leader>dc", call("dap", "continue"), desc = "DAP Continue" },
        { "<leader>dp", call("dap", "pause"), desc = "DAP Pause" },
        { "<leader>dS", call("dap", "terminate"), desc = "DAP Stop" },
        { "<leader>dR", call("dap", "restart"), desc = "DAP Restart" },
        { "<leader>dg", call("dap", "goto_"), desc = "DAP Set Next Statement" },
        { "<leader>dC", call("dap", "run_to_cursor"), desc = "DAP Run to Cursor" },
        { "<leader>tn", call("dap", "step_over"), desc = "DAP Step Over" },
        { "<leader>ti", call("dap", "step_into"), desc = "DAP Step Into" },
        {
          "<leader>tI",
          function()
            require("dap").step_into({ askForTargets = true })
          end,
          desc = "DAP Step Into Target",
        },
        { "<leader>to", call("dap", "step_out"), desc = "DAP Step Out" },
        { "<leader>tu", call("dap", "up"), desc = "DAP Stack Up" },
        { "<leader>td", call("dap", "down"), desc = "DAP Stack Down" },
        {
          "<leader>tU",
          function()
            frame_edge(true)
          end,
          desc = "DAP Stack Top",
        },
        {
          "<leader>tD",
          function()
            frame_edge(false)
          end,
          desc = "DAP Stack Bottom",
        },
        {
          "<leader>dr",
          function()
            require("dap").repl.open()
          end,
          desc = "DAP REPL",
        },
        { "<leader>dl", call("dap", "run_last"), desc = "DAP Run Last" },
        { "<leader>du", call("dapui", "toggle"), desc = "DAP UI Toggle" },
        { "<leader>de", call("dapui", "eval"), mode = { "n", "x" }, desc = "DAP Evaluate" },
        {
          "<leader>dw",
          function()
            require("dapui").elements.watches.add(expression())
          end,
          mode = { "n", "x" },
          desc = "DAP Add Watch",
        },
        {
          "<leader>dx",
          function()
            local dap = require("dap")
            dap.repl.open()
            dap.repl.execute(expression())
          end,
          mode = { "n", "x" },
          desc = "DAP Evaluate in REPL",
        },
        {
          "<leader>tl",
          function()
            require("dapui").float_element("scopes", { enter = true })
          end,
          desc = "DAP Locals",
        },
        {
          "<leader>tw",
          function()
            require("dapui").float_element("watches", { enter = true })
          end,
          desc = "DAP Watches",
        },
        {
          "<leader>th",
          function()
            require("dapui").float_element("repl", { enter = true })
          end,
          desc = "DAP REPL View",
        },
        {
          "<leader>tb",
          function()
            require("dapui").float_element("breakpoints", { enter = true })
          end,
          desc = "DAP Breakpoints",
        },
        {
          "<leader>tc",
          function()
            require("dapui").float_element("stacks", { enter = true })
          end,
          desc = "DAP Call Stack",
        },
        {
          "<leader><backspace>",
          function()
            require("dap.ui.widgets").hover()
          end,
          mode = { "n", "x" },
          desc = "DAP Eval Hover",
        },
      }
    end,
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")
      require("config.dap").setup()

      vim.fn.sign_define("DapBreakpoint", { text = "", texthl = "DiagnosticSignError" })
      vim.fn.sign_define("DapBreakpointCondition", { text = "", texthl = "DiagnosticSignWarn" })
      vim.fn.sign_define("DapLogPoint", { text = "◆", texthl = "DiagnosticSignInfo" })
      vim.fn.sign_define(
        "DapStopped",
        { text = "", texthl = "DiagnosticSignInfo", linehl = "DiagnosticUnderlineInfo" }
      )

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

      local mason_opts = LazyVim.opts("mason-nvim-dap.nvim")
      -- Global Mason owns adapter installation, including debugpy and
      -- codelldb. This integration only registers installed adapters, so
      -- opening DAP in two fresh Neovim processes cannot race installers.
      mason_opts.ensure_installed = {}
      mason_opts.automatic_installation = false
      mason_opts.handlers = mason_opts.handlers or {}
      require("mason-nvim-dap").setup(mason_opts)

      -- mason-nvim-dap normally registers codelldb. Keep a direct fallback for
      -- minimal/offline installations where its handler was not available.
      local ok_mason, mason_registry = pcall(require, "mason-registry")
      if ok_mason and not dap.adapters.codelldb then
        local ok_pkg, codelldb = pcall(function()
          return mason_registry.get_package("codelldb")
        end)
        if ok_pkg and codelldb:is_installed() then
          -- Mason 2.0 removed Package:get_install_path(). Resolve the package
          -- through its public install-location object so this works with both
          -- the pinned Mason version and newer releases.
          local install = require("mason-core.installer.InstallLocation").global():package("codelldb")
          local system = vim.uv.os_uname().sysname
          local adapter, library = require("config.dap").codelldb_paths(install, system)
          dap.adapters.codelldb = {
            type = "server",
            port = "${port}",
            executable = {
              command = adapter,
              args = { "--liblldb", library, "--port", "${port}" },
            },
          }
        end
      end

      local function get_args()
        local args = vim.trim(vim.fn.input("Args: "))
        return args == "" and {} or vim.split(vim.fn.expand(args), "%s+", { trimempty = true })
      end

      dap.configurations.cpp = dap.configurations.cpp
        or {
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
      dap.configurations.c = dap.configurations.c or dap.configurations.cpp
      dap.configurations.rust = dap.configurations.rust or dap.configurations.cpp

      require("nvim-dap-virtual-text").setup({ commented = true })
    end,
  },
}
