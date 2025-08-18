return {
  {
    "lmburns/lf.nvim",
    dependencies = { "nvim-lua/plenary.nvim", "akinsho/toggleterm.nvim" },
    keys = {
      { "<leader>e", mode = { "n", "v" }, "<cmd>Lf %:p:h<cr>", desc = "lf at current file" },
      { "<leader>E", "<cmd>Lf<cr>", desc = "lf at CWD" },
    },
    config = function()
      require("lf").setup({})
    end,
    init = function()
      -- vim.g.lf_netrw = 1 -- Uncomment to replace netrw
    end,
  },
}
