local wezterm = require 'wezterm'

local config = {}

-- Fonts to match kitty
config.font = wezterm.font_with_fallback({
  'JetBrainsMono Nerd Font',
  'Symbols Nerd Font',
})
config.font_size = 18.0

-- Colors mirrored from common/.config/kitty/themes/tokyonight_night.conf
config.colors = {
  foreground = '#c0caf5',
  background = '#1a1b26',
  cursor_bg = '#FF5000',
  cursor_fg = '#000000',
  cursor_border = '#FF5000',
  selection_bg = '#2e3c64',
  selection_fg = '#c0caf5',
  ansi = {
    '#1d202f', -- black
    '#f7768e', -- red
    '#9ece6a', -- green
    '#e0af68', -- yellow
    '#7aa2f7', -- blue
    '#bb9af7', -- magenta
    '#7dcfff', -- cyan
    '#a9b1d6', -- white
  },
  brights = {
    '#414868', -- bright black
    '#ff899d', -- bright red
    '#9fe044', -- bright green
    '#faba4a', -- bright yellow
    '#8db0ff', -- bright blue
    '#c7a9ff', -- bright magenta
    '#a4daff', -- bright cyan
    '#c0caf5', -- bright white
  },
  tab_bar = {
    background = '#1a1b26',
    active_tab = {
      bg_color = '#7aa2f7',
      fg_color = '#16161e',
      intensity = 'Bold',
    },
    inactive_tab = {
      bg_color = '#292e42',
      fg_color = '#545c7e',
    },
    inactive_tab_hover = {
      bg_color = '#292e42',
      fg_color = '#c0caf5',
      italic = true,
    },
    new_tab = {
      bg_color = '#1a1b26',
      fg_color = '#c0caf5',
    },
    new_tab_hover = {
      bg_color = '#7aa2f7',
      fg_color = '#16161e',
      italic = true,
    },
  },
}

-- Cursor behavior to match kitty (no blink)
config.default_cursor_style = 'SteadyBlock'

-- QoL
config.audible_bell = 'Disabled'
config.scrollback_lines = 100000

return config
