-- Tokyo Night (night). Palette reference: docs/tokyonight.md
return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "night",

      -- Push the theme's own palette out to the terminal's 16 ANSI slots, so a
      -- :terminal buffer matches kitty/wezterm instead of inheriting whatever
      -- the parent shell had.
      terminal_colors = true,

      styles = {
        comments = { italic = true },
        keywords = { italic = true },
        functions = {},
        variables = {},
        -- Floats and sidebars get the darker background, which reads as depth
        -- against the editor body rather than as a second, competing surface.
        floats = "dark",
        sidebars = "dark",
      },

      -- Dim windows that do not have focus. With splits open this is the
      -- cheapest possible "where am I" cue.
      dim_inactive = true,

      on_highlights = function(hl, c)
        -- The shared #ff5000 cursor, matching kitty, wezterm and the fzf
        -- pointer. options.lua points every guicursor mode at this one group.
        hl.Cursor = { fg = "#000000", bg = "#ff5000" }

        -- signcolumn is off and cursorline is disabled (see config/options.lua),
        -- so the only remaining "current position" cue is the line number.
        -- Give it the cursor orange instead of the theme's muted grey.
        hl.CursorLineNr = { fg = "#ff9e64", bold = true }

        -- Floating windows: a visible border in the accent blue. The default
        -- borrows fg_border, which on the dark float background nearly vanishes.
        hl.FloatBorder = { fg = c.blue, bg = c.bg_float }
        hl.NormalFloat = { fg = c.fg_float, bg = c.bg_float }

        -- Make the split separator readable; the default is close to bg.
        hl.WinSeparator = { fg = c.bg_highlight, bold = true }
      end,
    },
    config = function(_, opts)
      require("tokyonight").setup(opts)
      vim.cmd.colorscheme("tokyonight")
      -- diff highlighting intentionally left at the colorscheme defaults
    end,
  },
}
