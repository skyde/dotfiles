return {
  {
    "is0n/fm-nvim",
    keys = {
      { "<leader>e", mode = { "n", "v" }, "<cmd>Lf<cr>", desc = "LF at current file" },
      { "<leader>E", "<cmd>Lf<cr>", desc = "LF at CWD" },
    },
    config = function()
      require("fm-nvim").setup({
        cmd = "lf",
      })
    end,
  },
}
