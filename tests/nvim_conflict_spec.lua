-- Run with: nvim --headless -u NONE -i NONE -l tests/nvim_conflict_spec.lua
--
-- Exercises common/.config/nvim/lua/util/conflict.lua. Conflict handling is
-- marker-based rather than git-based, so these cases are the whole contract:
-- if a shape parses wrong here, the wrong side gets committed.

local source = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(repo .. "/common/.config/nvim")

local conflict = require("util.conflict")

local passed, failed = 0, 0
local failures = {}

local function check(name, ok, detail)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    table.insert(failures, name .. (detail and ("\n    " .. detail) or ""))
    print("FAIL " .. name .. (detail and ("  -- " .. detail) or ""))
  end
end

local function eq(name, expected, actual)
  check(
    name,
    vim.deep_equal(expected, actual),
    string.format("expected %s, got %s", vim.inspect(expected), vim.inspect(actual))
  )
end

---Load `lines` into the current buffer and put the cursor on `row`.
local function load(lines, row)
  vim.cmd("enew!")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { row or 1, 0 })
end

local function buffer()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

--------------------------------------------------------------------------
-- shapes
--------------------------------------------------------------------------

-- zdiff3, which is what common/.config/git/config configures.
local zdiff3 = {
  "top",
  "<<<<<<< HEAD",
  "ours a",
  "ours b",
  "||||||| 1234567",
  "base a",
  "=======",
  "theirs a",
  ">>>>>>> other-branch",
  "bottom",
}

-- Plain `merge` conflictstyle: no base section at all.
local plain = {
  "top",
  "<<<<<<< HEAD",
  "ours a",
  "=======",
  "theirs a",
  ">>>>>>> other-branch",
  "bottom",
}

do
  load(zdiff3)
  local list = conflict.list(0)
  eq("zdiff3: one conflict found", 1, #list)
  eq("zdiff3: start line", 2, list[1].start)
  eq("zdiff3: base marker line", 5, list[1].base_start)
  eq("zdiff3: separator line", 7, list[1].mid)
  eq("zdiff3: end line", 9, list[1].finish)

  load(plain)
  local p = conflict.list(0)
  eq("plain: one conflict found", 1, #p)
  eq("plain: no base section", nil, p[1].base_start)
  eq("plain: separator line", 4, p[1].mid)
  eq("plain: end line", 6, p[1].finish)
end

--------------------------------------------------------------------------
-- resolution, every choice, both shapes
--------------------------------------------------------------------------

for _, case in ipairs({
  { "zdiff3", zdiff3, 3 },
  { "plain", plain, 3 },
}) do
  local label, lines, cursor = case[1], case[2], case[3]
  local expected = {
    ours = { "top", "ours a", (label == "zdiff3") and "ours b" or nil, "theirs a", "bottom" },
    theirs = { "top", "theirs a", "bottom" },
    none = { "top", "bottom" },
  }

  load(lines, cursor)
  conflict.choose("ours")
  eq(
    label .. ": ours keeps only our side",
    label == "zdiff3" and { "top", "ours a", "ours b", "bottom" } or { "top", "ours a", "bottom" },
    buffer()
  )
  eq(label .. ": ours leaves no markers", 0, #conflict.list(0))

  load(lines, cursor)
  conflict.choose("theirs")
  eq(label .. ": theirs keeps only their side", expected.theirs, buffer())

  load(lines, cursor)
  conflict.choose("none")
  eq(label .. ": none drops both sides", expected.none, buffer())

  load(lines, cursor)
  conflict.choose("both")
  eq(
    label .. ": both concatenates ours then theirs",
    label == "zdiff3" and { "top", "ours a", "ours b", "theirs a", "bottom" }
      or { "top", "ours a", "theirs a", "bottom" },
    buffer()
  )
end

do
  load(zdiff3, 3)
  conflict.choose("base")
  eq("zdiff3: base restores the common ancestor", { "top", "base a", "bottom" }, buffer())

  -- With no base section there is nothing to restore; dropping the hunk is the
  -- only honest answer, and it must not raise.
  load(plain, 3)
  local ok = pcall(conflict.choose, "base")
  check("plain: base does not raise without a base section", ok)
  eq("plain: base with no base section empties the hunk", { "top", "bottom" }, buffer())
end

--------------------------------------------------------------------------
-- cursor placement
--------------------------------------------------------------------------

do
  load(zdiff3, 1) -- above the conflict
  local before = buffer()
  conflict.choose("ours")
  eq("cursor outside a conflict changes nothing", before, buffer())

  load(zdiff3, 10) -- below the conflict
  before = buffer()
  conflict.choose("theirs")
  eq("cursor below a conflict changes nothing", before, buffer())

  for _, row in ipairs({ 2, 5, 7, 9 }) do
    load(zdiff3, row)
    conflict.choose("theirs")
    eq("cursor on marker line " .. row .. " still resolves", { "top", "theirs a", "bottom" }, buffer())
  end
end

--------------------------------------------------------------------------
-- multiple conflicts
--------------------------------------------------------------------------

local multi = {
  "alpha",
  "<<<<<<< HEAD",
  "one-ours",
  "=======",
  "one-theirs",
  ">>>>>>> b",
  "beta",
  "<<<<<<< HEAD",
  "two-ours",
  "=======",
  "two-theirs",
  ">>>>>>> b",
  "gamma",
  "<<<<<<< HEAD",
  "three-ours",
  "=======",
  "three-theirs",
  ">>>>>>> b",
}

do
  load(multi)
  eq("multi: all three found", 3, #conflict.list(0))

  load(multi, 3)
  conflict.choose("ours")
  eq("multi: resolving the first leaves two", 2, #conflict.list(0))
  -- The first conflict collapsed from 5 lines to 1, so the second one's ours
  -- side now sits at line 5 with its markers still intact.
  eq("multi: later conflicts keep their markers", "<<<<<<< HEAD", buffer()[4])
  eq("multi: later conflicts are untouched", "two-ours", buffer()[5])

  -- choose_all works back to front precisely so earlier positions stay valid.
  load(multi)
  conflict.choose_all("theirs")
  eq("multi: choose_all resolves everything", 0, #conflict.list(0))
  eq(
    "multi: choose_all keeps their side of each",
    { "alpha", "one-theirs", "beta", "two-theirs", "gamma", "three-theirs" },
    buffer()
  )

  load(multi)
  conflict.choose_all("ours")
  eq(
    "multi: choose_all ours keeps our side of each",
    { "alpha", "one-ours", "beta", "two-ours", "gamma", "three-ours" },
    buffer()
  )
end

--------------------------------------------------------------------------
-- navigation
--------------------------------------------------------------------------

do
  load(multi, 1)
  conflict.goto_conflict(1)
  eq("goto: forward from the top lands on the first", 2, vim.api.nvim_win_get_cursor(0)[1])
  conflict.goto_conflict(1)
  eq("goto: forward again lands on the second", 8, vim.api.nvim_win_get_cursor(0)[1])
  conflict.goto_conflict(1)
  eq("goto: forward again lands on the third", 14, vim.api.nvim_win_get_cursor(0)[1])
  conflict.goto_conflict(1)
  eq("goto: forward wraps to the first", 2, vim.api.nvim_win_get_cursor(0)[1])

  conflict.goto_conflict(-1)
  eq("goto: backward wraps to the last", 14, vim.api.nvim_win_get_cursor(0)[1])
  conflict.goto_conflict(-1)
  eq("goto: backward lands on the second", 8, vim.api.nvim_win_get_cursor(0)[1])

  load({ "no markers here", "at all" }, 1)
  local ok = pcall(conflict.goto_conflict, 1)
  check("goto: no conflicts does not raise", ok)
  eq("goto: no conflicts leaves the cursor alone", 1, vim.api.nvim_win_get_cursor(0)[1])
end

--------------------------------------------------------------------------
-- malformed and adversarial input
--------------------------------------------------------------------------

do
  load({ "top", "<<<<<<< HEAD", "ours", "bottom" })
  eq("unterminated conflict is not reported", 0, #conflict.list(0))

  load({ "top", "=======", "bottom" })
  eq("a bare separator is not a conflict", 0, #conflict.list(0))

  load({ "top", ">>>>>>> b", "bottom" })
  eq("a bare end marker is not a conflict", 0, #conflict.list(0))

  load({ "<<<<<<< HEAD", "ours", "=======", "theirs", ">>>>>>> b" })
  eq("conflict spanning the whole buffer parses", 1, #conflict.list(0))
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  conflict.choose("ours")
  eq("conflict spanning the whole buffer resolves", { "ours" }, buffer())

  -- A conflict where one side is empty, which is what a delete/modify looks like.
  load({ "<<<<<<< HEAD", "=======", "theirs", ">>>>>>> b" }, 1)
  conflict.choose("ours")
  eq("empty ours side resolves to nothing", { "" }, buffer())

  -- Markers with no label after them, which some tools emit.
  load({ "<<<<<<<", "ours", "=======", "theirs", ">>>>>>>" })
  eq("unlabelled markers parse", 1, #conflict.list(0))

  -- Text that merely starts with angle brackets must not look like a marker.
  load({ "<<<< not a marker", "==== not either", ">>>> nope" })
  eq("near-miss marker text is ignored", 0, #conflict.list(0))

  -- A separator with trailing whitespace is still a separator.
  load({ "<<<<<<< HEAD", "ours", "=======   ", "theirs", ">>>>>>> b" })
  eq("separator with trailing whitespace parses", 1, #conflict.list(0))

  -- Conflict markers inside what is otherwise a normal file full of angle
  -- brackets, e.g. C++ templates.
  load({
    "std::map<std::string, std::vector<int>> m;",
    "<<<<<<< HEAD",
    "  m[a] = b;",
    "=======",
    "  m[a] = c;",
    ">>>>>>> b",
    "return m;",
  }, 3)
  eq("C++ angle brackets do not confuse the parser", 1, #conflict.list(0))
  conflict.choose("theirs")
  eq(
    "C++ file resolves correctly",
    { "std::map<std::string, std::vector<int>> m;", "  m[a] = c;", "return m;" },
    buffer()
  )
end

--------------------------------------------------------------------------
-- has_conflicts / merge view reconstruction
--------------------------------------------------------------------------

do
  load(multi)
  check("has_conflicts is true when markers are present", conflict.has_conflicts(0))
  conflict.choose_all("ours")
  check("has_conflicts is false once resolved", not conflict.has_conflicts(0))

  -- merge_view builds ours/theirs panes by replaying the file with every
  -- conflict resolved one way; check the panes it produces.
  load(multi)
  conflict.merge_view()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  eq("merge view opens three panes", 3, #wins)
  local contents = {}
  for _, w in ipairs(wins) do
    table.insert(contents, vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false))
  end
  eq(
    "merge view left pane is the file with our side taken",
    { "alpha", "one-ours", "beta", "two-ours", "gamma", "three-ours" },
    contents[1]
  )
  eq("merge view middle pane still has the markers", 18, #contents[2])
  eq(
    "merge view right pane is the file with their side taken",
    { "alpha", "one-theirs", "beta", "two-theirs", "gamma", "three-theirs" },
    contents[3]
  )
  local in_diff = 0
  for _, w in ipairs(wins) do
    if vim.wo[w].diff then
      in_diff = in_diff + 1
    end
  end
  eq("merge view puts all three panes in diff mode", 3, in_diff)
  vim.cmd("tabclose")
end

--------------------------------------------------------------------------
-- finish()
--------------------------------------------------------------------------

do
  local path = vim.fn.tempname()
  vim.fn.writefile(multi, path)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  eq("finish: file loads with conflicts", 3, #conflict.list(0))
  conflict.finish()
  eq("finish: refuses to write while markers remain", 3, #conflict.list(0))
  check("finish: buffer not written while unresolved", vim.deep_equal(multi, vim.fn.readfile(path)))

  conflict.choose_all("theirs")
  conflict.finish()
  check(
    "finish: writes once resolved",
    vim.deep_equal({ "alpha", "one-theirs", "beta", "two-theirs", "gamma", "three-theirs" }, vim.fn.readfile(path))
  )
  vim.fn.delete(path)
end

--------------------------------------------------------------------------
-- highlighting
--------------------------------------------------------------------------

do
  load(zdiff3, 3)
  local buf = vim.api.nvim_get_current_buf()
  conflict.highlight(buf)
  local ns = vim.api.nvim_get_namespaces()["vcs_conflict"]
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  check("highlight: marks the conflict region", #marks > 0, tostring(#marks))
  local groups = {}
  for _, m in ipairs(marks) do
    groups[m[4].line_hl_group] = (groups[m[4].line_hl_group] or 0) + 1
  end
  check("highlight: ours uses DiffAdd", (groups.DiffAdd or 0) > 0)
  check("highlight: base uses DiffChange", (groups.DiffChange or 0) > 0)
  check("highlight: theirs uses DiffText", (groups.DiffText or 0) > 0)

  conflict.choose("theirs")
  conflict.highlight(buf)
  eq("highlight: cleared once resolved", 0, #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}))
end

--------------------------------------------------------------------------

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  error("\n" .. table.concat(failures, "\n"))
end
