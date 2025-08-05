require("lazy").setup({
  {
    "rebelot/kanagawa.nvim",
    lazy = false,
    priority = 1000,
  },
  {
    "echasnovski/mini.surround",
    version = "*",
    config = function()
      require("mini.surround").setup()
    end,
  },
})
