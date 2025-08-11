return {
  {
    "mikavilpas/yazi.nvim",
    version = "*",
    event = "VeryLazy",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>e", mode = { "n", "v" }, "<cmd>Yazi<cr>", desc = "Yazi at current file" },
      { "<leader>E", "<cmd>Yazi cwd<cr>", desc = "Yazi at CWD" },
    },
    -- { "<C-Up>", "<cmd>Yazi toggle<cr>", desc = "Resume last Yazi" },
    -- if you want to use a specific branch, tag, or commit, you can specify it too

    -- for development, load from local directory
    -- dir = "~/git/yazi.nvim/",
    -- (... Many more settings)
    init = function()
      -- If you replace netrw:
      -- vim.g.loaded_netrwPlugin = 1
    end,
  },
}
