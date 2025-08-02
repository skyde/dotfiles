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
        colors.bg_popup = "#0d0d0d"
        colors.bg_search = "#222222"
        colors.bg_sidebar = "#000000"
        colors.bg_statusline = "#111111"
        colors.bg_visual = "#222222"
      end,
      on_highlights = function(hl, colors)
        hl.Normal = { bg = colors.bg }
        hl.NormalFloat = { bg = colors.bg_float }
        hl.FloatBorder = { bg = colors.bg_float, fg = colors.fg_dark }
        hl.Cursor = { fg = "#000000", bg = "#ff8800" }
        hl.CursorLineNr = { fg = "#569cd6" }
        hl.CursorLine = { bg = colors.bg_highlight }
        hl.Visual = { bg = colors.bg_visual }
        hl.Search = { bg = colors.bg_search, fg = colors.fg }
        hl.IncSearch = { bg = colors.bg_search, fg = colors.fg }
        hl.Pmenu = { bg = colors.bg_popup, fg = colors.fg }
        hl.PmenuSel = { bg = colors.bg_visual, fg = colors.fg }
        hl.StatusLine = { bg = colors.bg_statusline, fg = colors.fg }
        hl.StatusLineNC = { bg = colors.bg_statusline, fg = colors.fg_dark }
      end,
    },
    config = function(_, opts)
      require("tokyonight").setup(opts)
      vim.cmd.colorscheme("tokyonight")
      -- use colorscheme defaults for diff highlighting
    end,
  },
}
