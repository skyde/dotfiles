-- Talking to ripgrep about file types.
--
-- Neovim filetypes and ripgrep type names mostly agree — c, cpp, python, lua,
-- rust, go and most of the rest are spelled the same — and where they do not,
-- passing the filetype straight through is not a near miss but a hard failure:
-- `rg --type=typescriptreact` exits with "unrecognized file type" and the search
-- comes back empty rather than unfiltered.

local M = {}

-- The filetypes whose ripgrep type goes by another name. Checked against
-- `rg --type-list`; see tests/nvim_ripgrep_spec.lua, which fails if ripgrep ever
-- stops knowing one of these.
M.FT_TO_RG = {
  bash = "sh",
  dockerfile = "docker",
  javascript = "js",
  javascriptreact = "js",
  proto = "protobuf",
  ps1 = "ps",
  scss = "css",
  terraform = "tf",
  typescriptreact = "ts",
  vimdoc = "txt",
}

local cached ---@type table<string, true>|nil

---Every type name this ripgrep knows. Asked once per session and remembered:
---it costs a subprocess, and the answer only changes when ripgrep does.
---An empty table means the question could not be asked at all.
---@return table<string, true>
function M.types()
  if cached then
    return cached
  end
  cached = {}
  if vim.fn.executable("rg") ~= 1 then
    return cached
  end
  local res = vim.system({ "rg", "--type-list" }, { text = true }):wait()
  if res.code ~= 0 then
    return cached
  end
  for _, line in ipairs(vim.split(res.stdout or "", "\n", { plain = true })) do
    -- "cpp: *.[ChH], *.cc, ..." — the name is everything up to the first colon.
    local name = line:match("^([%w_+-]+):")
    if name then
      cached[name] = true
    end
  end
  return cached
end

---Forget the cached type list. For the specs, and after installing a ripgrep
---with different types.
function M.clear_cache()
  cached = nil
end

---The `--type=` argument to search only `ft`, or nil when ripgrep has no type
---for it. Nil means "search everything": an unfiltered result is a far better
---answer than the error an unrecognized type produces.
---@param ft string|nil  a Neovim filetype
---@return string|nil
function M.type_arg(ft)
  if not ft or ft == "" then
    return nil
  end
  local name = M.FT_TO_RG[ft] or ft
  local types = M.types()
  -- No type list at all (no ripgrep, or it failed) is not evidence the name is
  -- wrong, so pass it through rather than silently dropping the filter.
  if next(types) ~= nil and not types[name] then
    return nil
  end
  return "--type=" .. name
end

return M
