return {
  "m4xshen/hardtime.nvim",
  dependencies = { "MunifTanjim/nui.nvim" },
  event = "VeryLazy",
  opts = {
    enabled = false,
  },
  keys = {
    { "<leader>uh", "<cmd>Hardtime toggle<CR>", desc = "Toggle Hardtime" },
  },
}
