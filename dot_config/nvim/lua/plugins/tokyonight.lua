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
        colors.bg_float = "#0d0d0d"
        colors.bg_highlight = "#111111"
      end,
      on_highlights = function(hl, colors)
        hl.Normal = { bg = colors.bg }
        hl.NormalFloat = { bg = colors.bg_float }
        hl.FloatBorder = { bg = colors.bg_float, fg = colors.fg_dark }
        hl.Cursor = { fg = "#000000", bg = "#ff8800" }
        hl.CursorInsert = { fg = "#ff8800", bg = "NONE" }
        hl.CursorLineNr = { fg = "#569cd6" }
      end,
    },
    config = function(_, opts)
      require("tokyonight").setup(opts)
      vim.cmd.colorscheme("tokyonight")
      -- use colorscheme defaults for diff highlighting
    end,
  },
}
