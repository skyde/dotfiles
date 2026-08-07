-- Assert that C++ and Python give the same colour to the same construct.
--
-- The palette itself comes from VS Code (see docs/vscode-syntax-parity.md);
-- what this guards is that the two languages stay in step, so a change to one
-- set of queries cannot quietly leave Python looking different from C++.
--
-- Writes a report to $NVIM_SYNTAX_REPORT and exits non-zero on a mismatch.

local report = {}
local function say(fmt, ...)
  report[#report + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt
end

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
    local g = (e.opts and (e.opts.hl_group_link or e.opts.hl_group)) or e.hl_group_link or e.hl_group
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

local status = 0
if #missing > 0 then
  say("SKIP: no tree-sitter highlighting for %s (parser not installed)", table.concat(missing, ", "))
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
