-- Code colours matched to VS Code.
--
-- The editor chrome stays Tokyo Night (see tokyonight.lua); only the colours of
-- the code itself are replaced, so a buffer in Neovim reads the same as the same
-- file in VS Code.
--
-- The reference is the exact pair the VS Code config uses:
--   * theme      "Visual Studio Dark - C++"  (ms-vscode.cpptools-themes)
--   * overrides  editor.tokenColorCustomizations in
--                common/.config/Code/User/settings.json
-- Every hex below is the colour VS Code actually resolves for that construct,
-- read out of the theme + those overrides rather than eyeballed. See
-- docs/vscode-syntax-parity.md for how the values were derived and verified.

-- Colour roles, named after what they mean in the VS Code theme rather than
-- after the hue, so the mapping below reads as a translation table.
local c = {
  comment = "#7A987A", -- comment
  string = "#DFA67C", -- string.quoted
  string_punct = "#E8C9BB", -- punctuation.definition.string (the quotes)
  escape = "#D7BA7D", -- constant.character.escape
  number = "#5796BE", -- constant.numeric
  language = "#569CD6", -- constant.language, storage.modifier, py logical ops
  operator = "#DFDFBE", -- keyword.operator
  punctuation = "#DFDDB9", -- punctuation
  arguments = "#F89500", -- punctuation.section.arguments (call parens)
  control = "#ECBC6F", -- keyword.control
  keyword_other = "#86C9EF", -- the bare `keyword` rule: typedef, = default
  storage = "#ECB763", -- storage.type, support.type, keyword.operator.cast
  type = "#4EC9B0", -- entity.name.type
  enum_member = "#4FC1FF", -- variable.other.enummember
  fn = "#DCDCAA", -- entity.name.function
  variable = "#9CDCFE", -- variable
  parameter = "#9A9A9A", -- variable.parameter, keyword.control.directive
  namespace = "#C8C8C8", -- entity.name.namespace, entity.name.scope-resolution
  macro = "#C255C5", -- entity.name.function.preprocessor
  property = "#DADADA", -- variable.other.property
  object = "#DD9DC2", -- variable.other.object
  reference = "#B4B4B4", -- storage.modifier.reference / .pointer
  text = "#D4D4D4", -- the `source` rule: unclassified code
}

-- Groups shared by every language.
local shared = {
  ["@comment"] = c.comment,
  ["@comment.documentation"] = c.comment,
  ["@string"] = c.string,
  ["@string.documentation"] = c.string,
  ["@string.regexp"] = c.string,
  ["@string.special"] = c.string,
  ["@string.special.path"] = c.string,
  ["@string.special.url"] = c.string,
  ["@string.delimiter"] = c.string_punct,
  ["@string.escape"] = c.escape,
  ["@character"] = c.string,
  ["@character.special"] = c.escape,
  ["@number"] = c.number,
  ["@number.float"] = c.number,
  ["@boolean"] = c.language,
  ["@constant.builtin"] = c.language,
  ["@operator"] = c.operator,
  ["@punctuation.delimiter"] = c.punctuation,
  ["@punctuation.bracket"] = c.punctuation,
  ["@punctuation.arguments"] = c.arguments,
  ["@keyword"] = c.language,
  ["@keyword.return"] = c.control,
  ["@keyword.conditional"] = c.control,
  ["@keyword.repeat"] = c.control,
  ["@keyword.exception"] = c.control,
  ["@keyword.coroutine"] = c.control,
  ["@keyword.conditional.ternary"] = c.operator,
  ["@keyword.type"] = c.storage,
  ["@keyword.function"] = c.storage,
  ["@keyword.modifier"] = c.language,
  ["@keyword.operator"] = c.language,
  ["@keyword.other"] = c.keyword_other,
  ["@keyword.directive"] = c.parameter,
  ["@keyword.directive.define"] = c.parameter,
  ["@keyword.import"] = c.control,
  ["@punctuation.special"] = c.punctuation,
  ["@operator.reference"] = c.reference,
  ["@variable.magic"] = c.variable,
  ["@type"] = c.type,
  ["@type.definition"] = c.type,
  ["@type.builtin"] = c.storage,
  ["@type.qualifier"] = c.language,
  ["@function"] = c.fn,
  ["@function.call"] = c.fn,
  ["@function.method"] = c.fn,
  ["@function.method.call"] = c.fn,
  ["@function.builtin"] = c.fn,
  ["@function.macro"] = c.macro,
  ["@constructor"] = c.fn,
  ["@attribute"] = c.fn,
  ["@attribute.builtin"] = c.storage,
  ["@variable"] = c.variable,
  ["@variable.parameter"] = c.parameter,
  ["@variable.parameter.builtin"] = c.parameter,
  ["@variable.member"] = c.variable,
  ["@variable.builtin"] = c.language,
  ["@variable.object"] = c.object,
  ["@property"] = c.property,
  ["@constant"] = c.enum_member,
  ["@constant.macro"] = c.macro,
  ["@module"] = c.namespace,
  ["@module.builtin"] = c.variable,
  ["@label"] = c.namespace,
  ["@tag"] = c.type,
}

-- Per-language overrides. Neovim resolves `@capture.<lang>` before `@capture`,
-- so these only affect the language they are listed under.
local by_lang = {
  -- The C++ grammar in VS Code is `jeff-hykin.better-cpp-syntax`, which is what
  -- produces the scopes the user's overrides target (call parens, object
  -- access, preprocessor names).
  cpp = {
    ["@keyword.import"] = c.parameter, -- #include / #define directive word
    ["@keyword.directive"] = c.parameter,
    ["@keyword.directive.define"] = c.parameter,
    ["@constant"] = c.enum_member,
    ["@variable"] = c.variable,
    ["@variable.member"] = c.variable,
    ["@property"] = c.property,
    ["@module"] = c.namespace,
    ["@type.qualifier"] = c.language,
    ["@operator.reference"] = c.reference, -- & and * as declarator modifiers
  },

  -- MagicPython leaves most identifiers unclassified, so plain Python code is
  -- the `source` colour rather than the variable blue that C++ gets.
  python = {
    ["@variable"] = c.text,
    ["@variable.member"] = c.text,
    ["@constant"] = c.text,
    ["@module"] = c.text,
    ["@module.builtin"] = c.variable,
    ["@type"] = c.text, -- annotations are plain text in VS Code
    ["@type.definition"] = c.type, -- but `class Foo(Base)` names are not
    ["@keyword"] = c.control, -- with / as / assert / yield / del
    ["@keyword.import"] = c.control,
    ["@keyword.function"] = c.storage, -- def, lambda, async def
    ["@keyword.type"] = c.storage, -- class
    ["@keyword.directive"] = c.comment, -- the shebang line is a comment
    ["@function.builtin"] = c.fn,
    ["@type.builtin"] = c.storage,
    ["@attribute"] = c.fn,
    ["@punctuation.special"] = c.language, -- f-string { }
    ["@function.macro"] = c.storage, -- f-string !r / !s conversion
    ["@variable.magic"] = c.variable, -- __name__, __slots__, ...
    -- MagicPython leaves an ordinary call uncoloured; only the built-in name
    -- lists and `def` names keep a colour.
    ["@function.call"] = c.text,
    ["@function.method.call"] = c.text,
  },

  -- Format specifiers inside a printf-style string are injected as their own
  -- language; VS Code calls them constant.other.placeholder.
  printf = {
    ["@character"] = c.variable,
  },
}
by_lang.c = by_lang.cpp

local function apply()
  local set = function(group, fg)
    vim.api.nvim_set_hl(0, group, { fg = fg })
  end
  for group, fg in pairs(shared) do
    set(group, fg)
  end
  for lang, groups in pairs(by_lang) do
    for group, fg in pairs(groups) do
      set(group .. "." .. lang, fg)
    end
  end

  -- LSP semantic tokens sit above treesitter, so point them at the same colours
  -- VS Code resolves for the equivalent semantic token type. Without this a
  -- buffer would change colour the moment clangd or pyright attaches.
  local semantic_types = {
    namespace = c.namespace,
    class = c.type,
    struct = c.type,
    enum = c.type,
    interface = "#B8D7A3",
    type = c.type,
    typeParameter = c.type,
    concept = c.type,
    ["function"] = c.fn,
    method = c.fn,
    decorator = c.fn,
    macro = c.macro,
    variable = c.variable,
    parameter = c.parameter,
    property = c.property,
    enumMember = c.enum_member,
    event = c.variable,
    keyword = c.control,
    comment = c.comment,
    string = "#8FAFDF", -- the bare `string` rule, not string.quoted
    number = c.number,
    operator = c.operator,
    regexp = "#646695",
  }

  -- The only type+modifier pairs VS Code resolves differently from the plain
  -- type; every other combination just keeps the type's colour.
  local typemod = {
    ["variable.readonly"] = c.namespace,
    ["property.readonly"] = c.namespace,
    ["property.defaultLibrary"] = c.variable,
    ["type.defaultLibrary"] = c.storage,
    ["interface.defaultLibrary"] = c.type,
  }

  -- Neovim paints one mark per modifier the server reports, all at the same
  -- priority, so with several modifiers on one token the winner comes down to
  -- iteration order. It also ships default links for some of these groups (for
  -- instance class.defaultLibrary -> @type.builtin). Clearing every combination
  -- that VS Code has no opinion about makes the outcome deterministic: only the
  -- type colour, or the one meaningful override, ever paints.
  local modifiers = {
    "abstract", "async", "declaration", "defaultLibrary", "definition",
    "deprecated", "documentation", "modification", "readonly", "static",
    -- clangd's non-standard modifiers
    "classScope", "constructorOrDestructor", "dependentName", "fileScope",
    "functionScope", "globalScope", "usedAsMutablePointer",
    "usedAsMutableReference", "virtual",
  }
  for type_name, fg in pairs(semantic_types) do
    set("@lsp.type." .. type_name, fg)
    for _, mod in ipairs(modifiers) do
      local override = typemod[type_name .. "." .. mod]
      if override then
        set("@lsp.typemod." .. type_name .. "." .. mod, override)
      else
        vim.api.nvim_set_hl(0, "@lsp.typemod." .. type_name .. "." .. mod, {})
      end
    end
  end

  -- Neovim also paints one `@lsp.mod.<modifier>` group per modifier the server
  -- reports, at the same priority as the type group, so whichever happens to be
  -- applied last wins. VS Code has no such concept -- a modifier only matters in
  -- combination with a type. Clearing these leaves the type and typemod groups
  -- above as the only things that paint.
  for _, mod in ipairs({
    "abstract", "async", "declaration", "defaultLibrary", "definition",
    "deprecated", "documentation", "modification", "readonly", "static",
    -- clangd's non-standard modifiers
    "classScope", "constructorOrDestructor", "dependentName", "fileScope",
    "functionScope", "globalScope", "usedAsMutablePointer",
    "usedAsMutableReference", "virtual",
  }) do
    vim.api.nvim_set_hl(0, "@lsp.mod." .. mod, {})
  end

  -- MagicPython leaves ordinary Python names uncoloured, so a Python language
  -- server attaching must not repaint them blue.
  vim.api.nvim_set_hl(0, "@lsp.type.variable.python", { fg = c.text })
  vim.api.nvim_set_hl(0, "@lsp.type.property.python", { fg = c.text })
  vim.api.nvim_set_hl(0, "@lsp.type.function.python", { fg = c.text })
  vim.api.nvim_set_hl(0, "@lsp.type.method.python", { fg = c.text })
  vim.api.nvim_set_hl(0, "@lsp.type.class.python", { fg = c.text })
end

return {
  {
    "folke/tokyonight.nvim",
    optional = true,
    -- `init` runs before tokyonight's own config calls :colorscheme, so the
    -- autocmd is in place for that first switch as well as any later one --
    -- :colorscheme clears every highlight, so these have to be re-applied.
    init = function()
      local group = vim.api.nvim_create_augroup("vscode_syntax", { clear = true })
      vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = apply })
      -- lazy.nvim gives no ordering guarantee between this and tokyonight's own
      -- config, so the colorscheme may already be in place (no ColorScheme event
      -- left to catch) or may still be coming. Applying now and once more when
      -- startup has settled covers both.
      apply()
      vim.api.nvim_create_autocmd("VimEnter", { group = group, once = true, callback = apply })
    end,
  },
}
