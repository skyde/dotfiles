local wezterm = require("wezterm")
local act = wezterm.action

local config = wezterm.config_builder and wezterm.config_builder() or {}

-- Appearance & font
config.font = wezterm.font_with_fallback({
  "JetBrainsMono Nerd Font",
  "SF Mono",
  "Menlo",
  "monospace",
})
config.font_size = 13.0
config.hide_tab_bar_if_only_one_tab = true
config.audible_bell = "Disabled"
config.scrollback_lines = 200000

-- Option-as-Alt on macOS
config.send_composed_key_when_left_alt_is_pressed = true
config.send_composed_key_when_right_alt_is_pressed = true
config.enable_kitty_keyboard = true

-- Key remaps for macOS
if wezterm.target_triple:find("darwin") then
  config.keys = config.keys or {}
  table.insert(config.keys, { key = "d", mods = "CMD", action = act.SendKey({ key = "d", mods = "CTRL" }) })
  table.insert(config.keys, { key = "u", mods = "CMD", action = act.SendKey({ key = "u", mods = "CTRL" }) })
end

-- Color scheme with builtin fallback
local scheme = "Tokyo Night Moon"
local builtins = wezterm.color.get_builtin_schemes() or {}
if builtins[scheme] then
  config.color_scheme = scheme
else
  config.colors = {
    foreground = "#c8d3f5",
    background = "#222436",
    cursor_bg  = "#c8d3f5",
    cursor_fg  = "#222436",
    selection_bg = "#2d3f76",
    selection_fg = "#c8d3f5",
    ansi = {
      "#1b1d2b","#ff757f","#c3e88d","#ffc777",
      "#82aaff","#c099ff","#86e1fc","#828bb8"
    },
    brights = {
      "#444a73","#ff757f","#c3e88d","#ffc777",
      "#82aaff","#c099ff","#86e1fc","#c8d3f5"
    },
  }
end

return config

