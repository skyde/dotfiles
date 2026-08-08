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

      -- ...and then fix the two slots where "the theme's own palette" is not
      -- the one the terminals use. This is a fourth copy of the 16 ANSI
      -- colours -- kitty, wezterm and the VS Code integrated terminal being
      -- the other three -- and it was the only one still on upstream's
      -- values, so `:terminal` disagreed with the window it was running in.
      --
      -- Slot 8 is the deviation documented in docs/tokyonight.md: #414868 is
      -- 1.9:1 against the background, which is unreadable for the bright black
      -- that CLI tools use for de-emphasised output, and #85899c gets it to
      -- 4.9:1. Slot 0 is upstream's #15161e, which is *darker* than the
      -- background, so a program printing plain black text into a :terminal
      -- buffer wrote it invisibly; the terminals all use #1d202f for exactly
      -- that reason.
      --
      -- on_colors rather than setting vim.g.terminal_color_N after the fact:
      -- it runs inside every load, and LazyVim re-applies the colorscheme by
      -- calling `require("tokyonight").load()`, which would undo anything set
      -- from outside. Same reasoning as on_highlights below.
      on_colors = function(c)
        c.terminal.black = "#1d202f"
        c.terminal.black_bright = "#85899c"
      end,

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

      -- Keep every window at the same brightness whether or not it has focus:
      -- the dim-on-blur "where am I" cue reads as the panes changing colour
      -- under you (most visibly in the vcs diff view's file list), and the
      -- cursor line number is cue enough.
      dim_inactive = false,

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

        -- Code itself is coloured to match VS Code rather than Tokyo Night; the
        -- chrome above stays. Applied here, rather than from a ColorScheme
        -- autocmd, because LazyVim re-applies the colorscheme by calling
        -- `require("tokyonight").load()`, which fires no event -- this hook runs
        -- on every build either way. See docs/vscode-syntax-parity.md.
        require("util.vscode_syntax").apply(hl)
      end,
    },
    config = function(_, opts)
      require("tokyonight").setup(opts)
      vim.cmd.colorscheme("tokyonight")
      -- diff highlighting intentionally left at the colorscheme defaults
    end,
  },
}
