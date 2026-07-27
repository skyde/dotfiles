local orange = "#ff5000"
local selection = "#283457"

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
        sidebars = "dark",
        floats = "dark",
      },
      lualine_bold = true,
      on_highlights = function(hl, colors)
        -- Preserve the high-visibility cursor while keeping the rest of the UI
        -- on the canonical Tokyo Night Night palette.
        hl.Cursor = { fg = colors.bg, bg = orange }
        hl.Visual = { bg = selection }
        hl.Search = { fg = colors.bg, bg = colors.orange, bold = true }
        hl.CurSearch = { fg = "#000000", bg = orange, bold = true }
        hl.IncSearch = hl.CurSearch
        hl.MatchParen = { fg = orange, bold = true, underline = true }
        hl.FloatBorder = { fg = colors.blue, bg = colors.bg_float }
        hl.WinSeparator = { fg = colors.bg_highlight }
        hl.PmenuSel = { fg = colors.bg_dark, bg = colors.blue, bold = true }
      end,
    },
    config = function(_, opts)
      require("tokyonight").setup(opts)
      vim.cmd.colorscheme("tokyonight")
    end,
  },
}
