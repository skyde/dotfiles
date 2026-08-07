local wezterm = require 'wezterm'

local config = {}

-- Fonts to match kitty
config.font = wezterm.font_with_fallback({
  'JetBrainsMono Nerd Font',
  'Symbols Nerd Font',
})
config.font_size = 18.0

-- Colors mirrored from common/.config/kitty/themes/tokyonight_night.conf.
-- If you change a value here, change it there too. Palette: docs/tokyonight.md
config.colors = {
  foreground = '#c0caf5',
  background = '#1a1b26',
  cursor_bg = '#FF5000',
  cursor_fg = '#000000',
  cursor_border = '#FF5000',
  compose_cursor = '#ff9e64',
  selection_bg = '#2e3c64',
  selection_fg = '#c0caf5',
  scrollbar_thumb = '#292e42',
  split = '#292e42',
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
    -- Lightened from Tokyo Night's #414868 to match kitty's color8: the
    -- upstream value is near-unreadable for de-emphasised CLI output.
    '#85899c', -- bright black
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
      -- dark5 rather than upstream's dark3: #545c7e on this fill is 2.05:1.
      fg_color = '#737aa2',
    },
    inactive_tab_edge = '#16161e',
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
  -- Copy mode / quick select, the rough equivalents of kitty's mark colours
  copy_mode_active_highlight_bg = { Color = '#ff9e64' },
  copy_mode_active_highlight_fg = { Color = '#16161e' },
  copy_mode_inactive_highlight_bg = { Color = '#3d59a1' },
  copy_mode_inactive_highlight_fg = { Color = '#c0caf5' },
  quick_select_label_bg = { Color = '#ff5000' },
  quick_select_label_fg = { Color = '#000000' },
  quick_select_match_bg = { Color = '#3d59a1' },
  quick_select_match_fg = { Color = '#c0caf5' },
}

-- Match kitty's tab bar chrome
config.tab_bar_at_bottom = false
config.use_fancy_tab_bar = false
config.window_frame = {
  active_titlebar_bg = '#16161e',
  inactive_titlebar_bg = '#16161e',
}

-- Cursor behavior to match kitty (no blink)
config.default_cursor_style = 'SteadyBlock'

-- QoL
config.audible_bell = 'Disabled'
config.scrollback_lines = 1000000

return config
