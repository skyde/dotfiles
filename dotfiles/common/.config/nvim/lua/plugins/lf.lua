return {
  {
    "is0n/fm-nvim",
    keys = {
  -- Reserve <leader>e for Yazi; keep LF on <leader>E
  -- { "<leader>E", "<cmd>Lf<cr>", desc = "LF at CWD" },
    },
    config = function()
      require("fm-nvim").setup({
        cmd = "lf",
      })
    end,
  },
}
