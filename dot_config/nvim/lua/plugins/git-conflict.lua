return {
  {
    "akinsho/git-conflict.nvim",
    version = "*",
    config = function()
      require("git-conflict").setup({
        default_mappings = false,
        -- use diff colors from the colorscheme
        highlights = {
          current = "DiffText",
          incoming = "DiffAdd",
          ancestor = "DiffChange",
        },
      })
      local map = vim.keymap.set
      map("n", "<leader>co", "<Plug>(git-conflict-ours)", { desc = "Choose ours" })
      map("n", "<leader>ct", "<Plug>(git-conflict-theirs)", { desc = "Choose theirs" })
      map("n", "<leader>cb", "<Plug>(git-conflict-both)", { desc = "Choose both" })
      map("n", "<leader>c0", "<Plug>(git-conflict-none)", { desc = "Choose none" })
      map("n", "]x", "<Plug>(git-conflict-next-conflict)", { desc = "Next conflict" })
      map("n", "[x", "<Plug>(git-conflict-prev-conflict)", { desc = "Prev conflict" })
    end,
  },
}
