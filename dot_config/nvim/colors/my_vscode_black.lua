-- my_vscode_black.lua
--
-- Emulates the VS Code “Visual Studio Dark – C++” theme with a pure-black
-- background.  Place this file into ~/.config/nvim/colors/ and run
-- :colorscheme my_vscode_black to activate it.

vim.g.colors_name = "my_vscode_black"
vim.opt.termguicolors = true

local palette = {
  fg = "#D4D4D4", -- default text
  bg = "#000000", -- black background
  cursor_fg = "#000000",
  cursor_bg = "#FF5000",
  keyword = "#86C9EF",
  control_keyword = "#ECBC6F",
  operator = "#DFDFBE",
  preproc = "#C255C5",
  string = "#8FAFDF",
  string_quoted = "#DFA67C",
  escape = "#D7BA7D",
  number = "#5796BE",
  punctuation = "#DFDDB9",
  argument_delim = "#F89500",
  tag_punct = "#808080",
  type = "#4EC9B0",
  interface = "#B8D7A3",
  enum_member = "#4FC1FF",
  func = "#DCDCAA",
  namespace = "#7BCFE6",
  builtin_type = "#ECB763",
  local_variable = "#9CDCFE",
  object_member = "#DD9DC2",
  link = "#8FAFDF",
  line_num = "#585858",
  tab_active_bg = "#301000",
  tab_inactive_bg = "#000000",
  tab_active_border = "#AA4000",
}

local function hi(group, opts)
  vim.api.nvim_set_hl(0, group, opts)
end

-- UI elements
hi("Normal", { fg = palette.fg, bg = palette.bg })
hi("Cursor", { fg = palette.cursor_fg, bg = palette.cursor_bg })
hi("LineNr", { fg = palette.line_num, bg = palette.bg })
hi("CursorLineNr", { fg = palette.fg, bg = palette.bg, bold = true })
hi("StatusLine", { fg = palette.fg, bg = palette.bg })
hi("StatusLineNC", { fg = palette.line_num, bg = palette.bg })
hi("TabLine", { fg = palette.fg, bg = palette.tab_inactive_bg })
hi("TabLineSel", { fg = palette.fg, bg = palette.tab_active_bg, bold = true })
hi("TabLineFill", { fg = palette.fg, bg = palette.bg })
hi("VertSplit", { fg = palette.tab_active_border, bg = palette.bg })
hi("Visual", { bg = "#656A48", fg = palette.fg })
hi("Pmenu", { fg = palette.fg, bg = palette.tab_inactive_bg })
hi("PmenuSel", { fg = palette.fg, bg = palette.tab_active_bg })
hi("PmenuSbar", { fg = palette.fg, bg = palette.tab_inactive_bg })
hi("PmenuThumb", { fg = palette.fg, bg = palette.line_num })

-- Standard syntax groups
hi("Comment", { fg = "#7A987A", italic = true })
hi("Constant", { fg = palette.number })
hi("String", { fg = palette.string })
hi("Character", { fg = palette.string_quoted })
hi("Number", { fg = palette.number })
hi("Boolean", { fg = palette.number })
hi("Float", { fg = palette.number })
hi("Identifier", { fg = palette.local_variable })
hi("Function", { fg = palette.func })
hi("Statement", { fg = palette.keyword })
hi("Conditional", { fg = palette.control_keyword })
hi("Repeat", { fg = palette.control_keyword })
hi("Label", { fg = palette.tag_punct })
hi("Operator", { fg = palette.operator })
hi("Keyword", { fg = palette.keyword })
hi("Exception", { fg = palette.control_keyword })
hi("PreProc", { fg = palette.preproc })
hi("Include", { fg = palette.preproc })
hi("Define", { fg = palette.preproc })
hi("Macro", { fg = palette.preproc })
hi("PreCondit", { fg = palette.preproc })
hi("Type", { fg = palette.type })
hi("StorageClass", { fg = palette.builtin_type })
hi("Structure", { fg = palette.type })
hi("Typedef", { fg = palette.builtin_type })
hi("Special", { fg = palette.punctuation })
hi("SpecialChar", { fg = palette.escape })
hi("Delimiter", { fg = palette.punctuation })
hi("SpecialComment", { fg = "#7A987A", italic = true })
hi("Debug", { fg = palette.punctuation })
hi("Underlined", { fg = palette.link, underline = true })
hi("Ignore", { fg = palette.fg })
hi("Error", { fg = "#FF5555", bg = palette.bg })
hi("Todo", { fg = "#FAD000", bg = palette.bg, bold = true })

-- Tree-sitter groups (link to above)
hi("@comment", { link = "Comment" })
hi("@punctuation.delimiter", { fg = palette.punctuation })
hi("@punctuation.bracket", { fg = palette.punctuation })
hi("@punctuation.special", { fg = palette.argument_delim })
hi("@string", { fg = palette.string })
hi("@string.escape", { fg = palette.escape })
hi("@string.regex", { fg = palette.string_quoted })
hi("@character", { fg = palette.string_quoted })
hi("@number", { fg = palette.number })
hi("@float", { fg = palette.number })
hi("@constant", { fg = palette.number })
hi("@constant.builtin", { fg = palette.builtin_type })
hi("@boolean", { fg = palette.number })
hi("@function", { fg = palette.func })
hi("@function.builtin", { fg = palette.func })
hi("@function.call", { fg = palette.func })
hi("@method", { fg = palette.func })
hi("@constructor", { fg = palette.func })
hi("@parameter", { fg = palette.local_variable })
hi("@keyword", { fg = palette.keyword })
hi("@keyword.function", { fg = palette.keyword })
hi("@keyword.operator", { fg = palette.operator })
hi("@keyword.return", { fg = palette.control_keyword })
hi("@conditional", { fg = palette.control_keyword })
hi("@repeat", { fg = palette.control_keyword })
hi("@exception", { fg = palette.control_keyword })
hi("@operator", { fg = palette.operator })
hi("@label", { fg = palette.tag_punct })
hi("@namespace", { fg = palette.namespace })
hi("@type", { fg = palette.type })
hi("@type.builtin", { fg = palette.builtin_type })
hi("@type.definition", { fg = palette.type })
hi("@type.qualifier", { fg = palette.type })
hi("@storageclass", { fg = palette.builtin_type })
hi("@attribute", { fg = palette.preproc })
hi("@field", { fg = palette.object_member })
hi("@property", { fg = palette.object_member })
hi("@variable", { fg = palette.local_variable })
hi("@variable.builtin", { fg = palette.builtin_type })
hi("@variable.member", { fg = palette.object_member })
hi("@constant.macro", { fg = palette.preproc })
hi("@module", { fg = palette.namespace })
hi("@tag", { fg = palette.tag_punct })
hi("@tag.attribute", { fg = palette.local_variable })
hi("@tag.delimiter", { fg = palette.punctuation })
hi("@text.uri", { fg = palette.link, underline = true })
hi("@markup.underline.link", { fg = palette.link, underline = true })
