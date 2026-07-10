return {
  {
    "akinsho/git-conflict.nvim",
    version = "*",
    event = "BufReadPre",
    opts = {
      default_mappings = false,
      default_commands = true,
      disable_diagnostics = false,
      highlights = {
        current = "DiffText",
        incoming = "DiffAdd",
        ancestor = "DiffChange",
      },
    },
    keys = {
      { "<leader>co", "<Plug>(git-conflict-ours)", desc = "Conflict: choose ours" },
      { "<leader>ct", "<Plug>(git-conflict-theirs)", desc = "Conflict: choose theirs" },
      { "<leader>ca", "<Plug>(git-conflict-both)", desc = "Conflict: choose both" },
      { "<leader>cb", "<Plug>(git-conflict-both)", desc = "Conflict: choose both" },
      { "<leader>c0", "<Plug>(git-conflict-none)", desc = "Conflict: choose none" },
      { "]x", "<Plug>(git-conflict-next-conflict)", desc = "Next conflict" },
      { "[x", "<Plug>(git-conflict-prev-conflict)", desc = "Previous conflict" },
    },
  },
}
