-- Test runner on <leader>T.
--
-- LazyVim's test extra puts neotest on <leader>t, but the VS Code config uses
-- <leader>t for debugger stepping and <leader>T for tests. Keeping that split
-- matters more than matching LazyVim, so every key is re-declared here and the
-- inherited <leader>t ones are dropped.

return {
  {
    "nvim-neotest/neotest",
    optional = true,
    dependencies = { "nvim-neotest/neotest-python" },
    opts = function(_, opts)
      opts.adapters = opts.adapters or {}
      table.insert(opts.adapters, require("neotest-python"))
      return opts
    end,
    -- Replacing rather than extending: returning a fresh table discards the
    -- <leader>t bindings LazyVim declared, which would otherwise shadow the
    -- debugger stepping keys.
    keys = function()
      return {
        {
          "<leader>Tr",
          function()
            require("neotest").run.run()
          end,
          desc = "Run nearest test",
        },
        {
          "<leader>Tf",
          function()
            require("neotest").run.run(vim.fn.expand("%"))
          end,
          desc = "Run tests in file",
        },
        {
          "<leader>Ta",
          function()
            require("neotest").run.run(vim.uv.cwd())
          end,
          desc = "Run all tests",
        },
        {
          "<leader>TR",
          function()
            require("neotest").run.run_last()
          end,
          desc = "Re-run last test",
        },
        {
          "<leader>Td",
          function()
            require("neotest").run.run({ strategy = "dap" })
          end,
          desc = "Debug nearest test",
        },
        {
          "<leader>To",
          function()
            require("neotest").output.open({ enter = true, auto_close = true })
          end,
          desc = "Test output",
        },
        {
          "<leader>TO",
          function()
            require("neotest").output_panel.toggle()
          end,
          desc = "Test output panel",
        },
        {
          "<leader>Te",
          function()
            require("neotest").summary.toggle()
          end,
          desc = "Test explorer",
        },
        {
          "<leader>TS",
          function()
            require("neotest").run.stop()
          end,
          desc = "Stop test run",
        },
        {
          "<leader>Tw",
          function()
            require("neotest").watch.toggle(vim.fn.expand("%"))
          end,
          desc = "Watch file",
        },
      }
    end,
  },
}
