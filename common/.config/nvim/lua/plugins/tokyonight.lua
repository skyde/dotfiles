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

      -- Keep every window at the same brightness whether or not it has focus:
      -- the dim-on-blur "where am I" cue reads as the panes changing colour
      -- under you (most visibly in the vcs diff view's file list), and the
      -- cursor line number is cue enough.
      dim_inactive = false,

      on_highlights = function(hl, c)
        -- The shared #ff5000 cursor, matching kitty, wezterm and the fzf
        -- pointer. options.lua points every guicursor mode at this one group.
        hl.Cursor = { fg = "#000000", bg = "#ff5000" }

        -- ...every mode it lists, that is. Terminal mode is not in that list,
        -- so it falls back to Neovim's default `t:block-TermCursor`, and
        -- tokyonight does not define TermCursor at all — which left the cursor
        -- in a :terminal buffer as plain reverse video, the one place in the
        -- setup where it was not the orange. lCursor and CursorIM are the same
        -- story by a different route: they are the cursor under :lmap or an
        -- IME, and the theme paints them its own fg-on-bg.
        --
        -- All three are the same claim as Cursor — "you are here" — so they
        -- get the same colour. tests/check-theme.py checks the eight places
        -- that make that claim still agree.
        hl.TermCursor = { fg = "#000000", bg = "#ff5000" }
        hl.lCursor = { fg = "#000000", bg = "#ff5000" }
        hl.CursorIM = { fg = "#000000", bg = "#ff5000" }

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

        -- The selected row in the completion menu. blink.cmp is disabled, so
        -- this is Neovim's native menu — the one actually on screen — and it
        -- was the only "selected row" in the setup not wearing bg_visual: the
        -- theme blends a shade of its own for it. fzf's bg+, tmux's mode-style,
        -- zsh's completion menu, yazi's hovered row and Neovim's own Visual
        -- and WildMenu are all #283457, so this joins them.
        hl.PmenuSel = { bg = c.bg_visual }

        -- Line numbers. The theme uses fg_gutter, which is a colour meant for
        -- gutters and separators rather than for text — docs/tokyonight.md
        -- assigns line numbers to dark3, and delta already paints the line
        -- numbers in a diff #545c7e. With the sign column off and cursorline
        -- disabled this column is the whole gutter, so it may as well be
        -- readable, and match the diffs it sits next to.
        hl.LineNr = { fg = c.dark3 }

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
