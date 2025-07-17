return {
  "m4xshen/hardtime.nvim",
  event = "VeryLazy",
  opts = {},
  keys = {
    {
      "<leader>uh",
      function()
        vim.cmd("Hardtime toggle")
      end,
      desc = "Toggle Hard Mode",
    },
  },
}
