return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "night",
      transparent = false,
      terminal_colors = true,
      styles = {
        comments = { italic = true },
        keywords = { italic = true },
        functions = {},
        variables = {},
      },
    },
    config = function(_, opts)
      require("tokyonight").setup(opts)
      vim.cmd.colorscheme("tokyonight")
      vim.api.nvim_set_hl(0, "DiffAdd", { bg = "#203227" })
      vim.api.nvim_set_hl(0, "DiffDelete", { bg = "#37222c" })
      vim.api.nvim_set_hl(0, "DiffChange", { bg = "#1d2437" })
      vim.api.nvim_set_hl(0, "DiffText", { bg = "#1d2437", bold = true })
    end,
  },
}
