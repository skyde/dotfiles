return {
  {
    "akinsho/git-conflict.nvim",
    version = "*",
    event = "BufReadPre",
    opts = {
      -- These mappings are created only in buffers that contain conflicts, so
      -- <leader>ca remains the normal LSP code-action key everywhere else.
      default_mappings = {
        ours = "<leader>co",
        theirs = "<leader>ct",
        both = "<leader>ca",
        none = "<leader>c0",
        next = "]x",
        prev = "[x",
      },
      default_commands = true,
      disable_diagnostics = true,
      highlights = {
        current = "DiffText",
        incoming = "DiffAdd",
        ancestor = "DiffChange",
      },
    },
  },
}
