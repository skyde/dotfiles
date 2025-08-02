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
      on_colors = function(colors)
        colors.bg = "#000000"
        colors.bg_dark = "#000000"
        colors.bg_float = "#000000"
        colors.bg_highlight = "#111111"
      end,
      on_highlights = function(hl, colors)
        hl.Normal = { bg = colors.bg }
        hl.NormalFloat = { bg = colors.bg }
        hl.FloatBorder = { bg = colors.bg, fg = colors.fg_dark }
      end,
    },
    config = function(_, opts)
      require("tokyonight").setup(opts)
      vim.cmd.colorscheme("tokyonight")
      -- use colorscheme defaults for diff highlighting
    end,
  },
}
