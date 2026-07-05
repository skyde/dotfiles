return {
  {
    "folke/which-key.nvim",
    opts = function(_, opts)
      opts.spec = opts.spec or {}
      vim.list_extend(opts.spec, {
        { "<leader>b", group = "buffers/tabs" },
        { "<leader>c", group = "code/diagnostics" },
        { "<leader>d", group = "debug" },
        { "<leader>f", group = "file" },
        { "<leader>m", group = "tasks/debug" },
        { "<leader>r", group = "reload" },
        { "<leader>s", group = "search" },
        { "<leader>t", group = "debug step" },
        { "<leader>u", group = "ui/toggles" },
        { "<leader>w", group = "workspace/tmux" },
      })
    end,
  },
}
