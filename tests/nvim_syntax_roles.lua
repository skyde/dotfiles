-- Assert that C++ and Python give the same colour to the same construct.
--
-- The palette itself comes from VS Code (see docs/vscode-syntax-parity.md);
-- what this guards is that the two languages stay in step, so a change to one
-- set of queries cannot quietly leave Python looking different from C++.
--
-- Writes a report to $NVIM_SYNTAX_REPORT and exits non-zero on a mismatch.
--
-- Skipping is a real outcome here -- the parsers are a separate install and a
-- developer without them should not get a red build. But a skip that exits 0
-- looks exactly like a pass, and there are three quite different ways to reach
-- one: the parsers are missing, the plugins never loaded, or this repository's
-- config is not the config Neovim started with. The third is the dangerous
-- one, because it also means the roles being compared are not the roles in
-- this checkout, and it used to be reported as "parser not installed".
--
-- So the reason is named, and $NVIM_SYNTAX_STRICT=1 turns any skip into a
-- failure -- for CI, where a silent skip is the whole risk.

local report = {}
local function say(fmt, ...)
  report[#report + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt
end

local strict = (vim.env.NVIM_SYNTAX_STRICT or "") ~= ""

local samples = {
  cpp = [[
namespace app {
struct Config { int width = 0; };
class Widget : public Base {
 public:
  bool Draw(const Config& cfg, int count) const {
    // a comment
    auto total = count * 2;
    const char* label = "text\n";
    return helper(total, cfg.width, label);
  }
 private:
  Config cfg_;
};
}
]],
  python = [[
import app


class Config:
    width: int = 0


class Widget(Base):
    def draw(self, cfg: Config, count: int) -> bool:
        # a comment
        total = count * 2
        label = "text\n"
        return helper(total, cfg.width, label)
]],
}

-- Each role names a construct and the text to find it by, per language.
local roles = {
  { "type name", cpp = "Config", python = "Config" },
  { "built-in type", cpp = "int", python = "int" },
  { "local variable", cpp = "total", python = "total" },
  { "parameter", cpp = "count", python = "count" },
  { "function definition", cpp = "Draw", python = "draw" },
  { "function call", cpp = "helper", python = "helper" },
  { "comment", cpp = "// a comment", python = "# a comment" },
  { "string", cpp = "text", python = "text" },
  { "number", cpp = "2", python = "2" },
  { "control flow", cpp = "return", python = "return" },
}

local function colour_of(buf, row, col)
  local items = vim.inspect_pos(buf, row, col)
  local best, best_pri
  for _, e in ipairs(items.treesitter or {}) do
    -- inspect_pos reports the group at the top level; older versions nest it
    -- under `opts`.
    local g = (e.opts and (e.opts.hl_group_link or e.opts.hl_group))
      or e.hl_group_link
      or e.hl_group
    local md = e.metadata or {}
    local pri = tonumber(md.priority) or 100
    if g then
      local hl = vim.api.nvim_get_hl(0, { name = g, link = false })
      if hl and next(hl) and (best_pri == nil or pri >= best_pri) then
        best, best_pri = hl.fg, pri
      end
    end
  end
  return best and string.format("#%06X", best) or nil
end

--- Colour of the first occurrence of `needle` in the buffer.
local function colour_for(buf, needle)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for row, line in ipairs(lines) do
    local s = line:find(needle, 1, true)
    if s then
      return colour_of(buf, row - 1, s - 1)
    end
  end
  return nil
end

local results, missing = {}, {}
for lang, text in pairs(samples) do
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n"))
  vim.api.nvim_set_option_value("filetype", lang == "cpp" and "cpp" or "python", { buf = buf })
  vim.api.nvim_set_current_buf(buf)
  local ok = pcall(vim.treesitter.start, buf, lang)
  if not ok or not vim.treesitter.highlighter.active[buf] then
    missing[#missing + 1] = lang
  else
    pcall(function()
      vim.treesitter.get_parser(buf, lang):parse(true)
    end)
    results[lang] = {}
    for _, role in ipairs(roles) do
      results[lang][role[1]] = colour_for(buf, role[lang])
    end
  end
end

-- Name the reason rather than blaming the parsers for all three. `@variable`
-- carrying the VS Code blue is the cheapest proof that this checkout's
-- on_highlights hook actually ran: nothing else in Neovim paints it #9CDCFE.
local function skip_reason()
  if not pcall(require, "lazy") then
    return "Neovim started with no plugin manager, so this checkout's "
      .. "config was never loaded (try: tests/check-nvim-syntax-roles.sh .)"
  end
  local hl = vim.api.nvim_get_hl(0, { name = "@variable", link = false })
  if not hl or hl.fg ~= tonumber("9CDCFE", 16) then
    return "the VS Code palette is not applied -- @variable is not #9CDCFE, "
      .. "so the colours here would not be this repository's"
  end
  return string.format("no tree-sitter highlighting for %s (parser not installed)",
    table.concat(missing, ", "))
end

local status = 0
if #missing > 0 then
  local why = skip_reason()
  if strict then
    say("FAIL: %s", why)
    say("(NVIM_SYNTAX_STRICT is set, so a skip counts as a failure)")
    status = 2
  else
    say("SKIP: %s", why)
  end
else
  local bad = 0
  say("%-22s %-10s %-10s", "role", "C++", "Python")
  say(string.rep("-", 46))
  for _, role in ipairs(roles) do
    local a, b = results.cpp[role[1]], results.python[role[1]]
    local mark = ""
    if a == nil or b == nil then
      mark = "  <-- not found"
      bad = bad + 1
    elseif a ~= b then
      mark = "  <-- DIFFERS"
      bad = bad + 1
    end
    say("%-22s %-10s %-10s%s", role[1], a or "-", b or "-", mark)
  end
  say("")
  say("%d/%d roles use the same colour in both languages", #roles - bad, #roles)
  if bad > 0 then
    status = 1
  end
end

local out = vim.env.NVIM_SYNTAX_REPORT
if out then
  local fh = io.open(out, "w")
  fh:write(table.concat(report, "\n") .. "\n")
  fh:close()
else
  print(table.concat(report, "\n"))
end

-- `:cquit N` is the only way to leave with a chosen exit code.
if status == 0 then
  vim.cmd("qa!")
else
  vim.cmd("cquit " .. status)
end
