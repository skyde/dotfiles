return {
  "nvim-tree/nvim-tree.lua",
  keys = {
    {
      -- Matches the VS Code binding, which reveals the active file in the
      -- explorer rather than just opening it at the workspace root.
      "<leader>fe",
      "<cmd>NvimTreeFindFileToggle<CR>",
      desc = "Toggle file explorer (reveal current file)",
    },
  },
  opts = {},
}
