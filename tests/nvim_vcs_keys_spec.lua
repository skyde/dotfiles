-- Run with: nvim --headless -u NONE -i NONE -l tests/nvim_vcs_keys_spec.lua
--
-- config/vcs.lua is the layer between the keys a hand actually presses and
-- util.vcs_ui / util.conflict. Its whole job is deciding *which* of them to
-- call from where — `]c` means diff hunk here, conflict marker there, gitsigns
-- hunk somewhere else — and none of that is exercised by testing the modules
-- underneath. tests/check-nvim-keymaps.sh invokes every binding once, but from
-- an ordinary buffer, which is the one context where these branches are all
-- false.
--
-- Plugin-free like the rest: config/vcs.lua reaches for which-key and gitsigns
-- through pcall, and for nothing else.

local source = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fn.fnamemodify(source, ":p:h:h")
local cfg = repo .. "/common/.config/nvim"
vim.opt.runtimepath:prepend(cfg)

-- LazyVim sets these before any keymap is declared; without them <leader>
-- would still be the default backslash and every binding below would land on
-- a key nobody presses.
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

vim.o.columns = 200
vim.o.lines = 50
-- See nvim_vcs_ui_spec.lua: headless Neovim draws the tabline into a grid
-- still sized 80x24, and this spec opens tabs.
vim.o.showtabline = 0

local ui = require("util.vcs_ui")
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

-- Collect notifications instead of printing them, so a spec run stays readable
-- and "it told the user something" can be asserted.
local notes = {}
vim.notify = function(msg, level)
  notes[#notes + 1] = { msg = tostring(msg), level = level }
end
local function last_note()
  return notes[#notes] and notes[#notes].msg or nil
end
local function clear_notes()
  notes = {}
end

local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")
local root = temp .. "/repo"
vim.fn.mkdir(root, "p")

local function run(cmd)
  local res = vim.system(cmd, { cwd = root, text = true }):wait()
  if res.code ~= 0 then
    error(table.concat(cmd, " ") .. ": " .. (res.stderr or ""))
  end
end
local function git(...)
  local cmd = { "git", "-c", "user.email=t@example.com", "-c", "user.name=Test", "-c", "commit.gpgsign=false" }
  vim.list_extend(cmd, { ... })
  run(cmd)
end
local function write(path, text)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local fd = assert(io.open(path, "wb"))
  fd:write(text)
  fd:close()
end

---Open `path` fresh from disk. `:edit!` on a file that already has a buffer
---switches to that buffer rather than re-reading it, so a spec that rewrites a
---file between sections would otherwise keep asserting against the old,
---modified copy.
local function reload(path)
  local existing = vim.fn.bufnr(path)
  if existing ~= -1 then
    pcall(vim.cmd, "bwipeout! " .. existing)
  end
  vim.cmd("edit " .. vim.fn.fnameescape(path))
end

git("init", "-q", "-b", "main")
write(root .. "/tracked.txt", "one\ntwo\nthree\nfour\nfive\n")
git("add", "-A")
git("commit", "-qm", "initial")
write(root .. "/tracked.txt", "one\nTWO\nthree\nFOUR\nfive\n")
write(root .. "/conflicted.txt", table.concat({
  "before",
  "<<<<<<< HEAD",
  "ours line",
  "=======",
  "theirs line",
  ">>>>>>> other",
  "middle",
  "<<<<<<< HEAD",
  "second ours",
  "=======",
  "second theirs",
  ">>>>>>> other",
  "after",
}, "\n") .. "\n")
vim.cmd("cd " .. vim.fn.fnameescape(root))

-- Loading the module is what registers the keymaps and the :Vcs* commands.
dofile(cfg .. "/lua/config/vcs.lua")

---The callback behind a normal-mode mapping, by its lhs as nvim reports it
---(leader is <space>).
local function mapping(lhs, mode)
  for _, m in ipairs(vim.api.nvim_get_keymap(mode or "n")) do
    if m.lhs == lhs then
      return m.callback
    end
  end
  return nil
end

local function press(lhs, mode)
  local fn = mapping(lhs, mode)
  if not fn then
    error("not mapped: " .. lhs)
  end
  return fn()
end

--------------------------------------------------------------------------
-- the commands exist and take the scopes they advertise
--------------------------------------------------------------------------

do
  local commands = vim.api.nvim_get_commands({})
  for _, name in ipairs({ "VcsChanges", "VcsDiff", "VcsPatch", "VcsHistory", "VcsInfo" }) do
    check("commands: :" .. name .. " is defined", commands[name] ~= nil)
  end
  for _, name in ipairs({ "VcsChanges", "VcsDiff", "VcsPatch" }) do
    local cmd = commands[name]
    eq("commands: :" .. name .. " takes an optional argument", "?", cmd and cmd.nargs)
  end

  clear_notes()
  vim.cmd("VcsInfo")
  local said = last_note() or ""
  check("commands: :VcsInfo names the backend", said:find("git", 1, true) ~= nil, said)
  check("commands: :VcsInfo reports both bases", said:find("branch base", 1, true) ~= nil, said)
end

--------------------------------------------------------------------------
-- <leader>cv: revert this change, wherever the cursor is
--------------------------------------------------------------------------

do
  -- In a side-by-side diff, the left pane is the base version as a read-only
  -- scratch. `do` there raises E21 instead of reverting; the change only
  -- exists in the working copy, so that is where the revert has to happen.
  reload(root .. "/tracked.txt")
  ui.file_diff("working")
  vim.cmd("wincmd h")
  check("cv: the base pane is read-only", not vim.bo.modifiable)
  check("cv: and it is half of a diff", vim.wo.diff)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  clear_notes()
  local ok, err = pcall(press, " cv")
  check("cv: does not raise on the read-only side", ok, tostring(err))
  -- It reverts the hunk under *this* cursor, in the working copy, without
  -- moving the focus off the side the reader was reading.
  check("cv: focus stays on the base side", not vim.bo.modifiable, vim.api.nvim_buf_get_name(0))
  vim.cmd("wincmd l")
  eq(
    "cv: and the hunk under the cursor is reverted in the working copy",
    { "one", "two", "three", "FOUR", "five" },
    vim.api.nvim_buf_get_lines(0, 0, -1, false)
  )
  vim.cmd("tabclose")
  reload(root .. "/tracked.txt")

  -- Two read-only sides: nothing to revert into, and it has to say so rather
  -- than throw.
  vim.cmd("tabnew")
  local a = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(a, 0, -1, false, { "x" })
  vim.bo[a].modifiable = false
  vim.api.nvim_win_set_buf(0, a)
  vim.cmd("diffthis")
  vim.cmd("vertical split")
  local b = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(b, 0, -1, false, { "y" })
  vim.bo[b].modifiable = false
  vim.api.nvim_win_set_buf(0, b)
  vim.cmd("diffthis")
  clear_notes()
  ok, err = pcall(press, " cv")
  check("cv: two read-only sides does not raise", ok, tostring(err))
  check("cv: and says why", (last_note() or ""):find("editable", 1, true) ~= nil, tostring(last_note()))
  vim.cmd("tabclose")
end

--------------------------------------------------------------------------
-- <leader>cV: revert the selected range
--------------------------------------------------------------------------

do
  reload(root .. "/tracked.txt")
  write(root .. "/tracked.txt", "one\nTWO\nthree\nFOUR\nfive\n")
  reload(root .. "/tracked.txt")
  ui.file_diff("working")
  vim.cmd("wincmd h")
  clear_notes()
  local ok, err = pcall(press, " cV")
  check("cV: does not raise on the read-only side", ok, tostring(err))
  check("cV: and says which key to press first", (last_note() or ""):find("read%-only") ~= nil, tostring(last_note()))

  -- On the working side it reverts exactly the cursor line.
  vim.cmd("wincmd l")
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  ok, err = pcall(press, " cV")
  check("cV: works on the editable side", ok, tostring(err))
  eq(
    "cV: and reverts just that line",
    { "one", "two", "three", "FOUR", "five" },
    vim.api.nvim_buf_get_lines(0, 0, -1, false)
  )
  vim.cmd("tabclose")
end

--------------------------------------------------------------------------
-- ]c / [c mean "next change" for every kind of change
--------------------------------------------------------------------------

do
  -- In a conflicted buffer they walk the markers.
  reload(root .. "/conflicted.txt")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  press("]c")
  eq("]c: lands on the first conflict", 2, vim.api.nvim_win_get_cursor(0)[1])
  press("]c")
  eq("]c: then the second", 8, vim.api.nvim_win_get_cursor(0)[1])
  press("]c")
  eq("]c: and wraps", 2, vim.api.nvim_win_get_cursor(0)[1])
  press("[c")
  eq("[c: goes back the other way", 8, vim.api.nvim_win_get_cursor(0)[1])
  -- <leader>cn / <leader>cp are the same action on other keys.
  press(" cn")
  eq("<leader>cn: is ]c", 2, vim.api.nvim_win_get_cursor(0)[1])
  press(" cp")
  eq("<leader>cp: is [c", 8, vim.api.nvim_win_get_cursor(0)[1])

  -- ]x / [x are conflicts specifically, from anywhere.
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  press("]x")
  eq("]x: first conflict", 2, vim.api.nvim_win_get_cursor(0)[1])
  press("[x")
  eq("[x: wraps to the last", 8, vim.api.nvim_win_get_cursor(0)[1])

  -- In a diff they walk diff hunks instead.
  write(root .. "/tracked.txt", "one\nTWO\nthree\nFOUR\nfive\n")
  reload(root .. "/tracked.txt")
  ui.file_diff("working")
  vim.cmd("normal! gg")
  press("]c")
  eq("]c: in a diff, the first hunk", 2, vim.api.nvim_win_get_cursor(0)[1])
  press("]c")
  eq("]c: in a diff, the second hunk", 4, vim.api.nvim_win_get_cursor(0)[1])
  vim.cmd("tabclose")

  -- And in an ordinary buffer with neither, nothing raises.
  vim.cmd("enew!")
  local ok, err = pcall(press, "]c")
  check("]c: harmless in a plain buffer", ok, tostring(err))
end

--------------------------------------------------------------------------
-- <leader>cd: diagnostics outside a diff, switch side inside one
--------------------------------------------------------------------------

do
  reload(root .. "/tracked.txt")
  local ok, err = pcall(press, " cd")
  check("cd: opens diagnostics outside a diff without raising", ok, tostring(err))

  ui.file_diff("working")
  local before = vim.api.nvim_get_current_win()
  press(" cd")
  check("cd: switches side inside a diff", vim.api.nvim_get_current_win() ~= before)
  before = vim.api.nvim_get_current_win()
  press(" cc")
  check("cc: switches side too", vim.api.nvim_get_current_win() ~= before)
  vim.cmd("tabclose")
end

--------------------------------------------------------------------------
-- the conflict keys operate on the conflict under the cursor
--------------------------------------------------------------------------

do
  local function reset()
    reload(root .. "/conflicted.txt")
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
  end

  reset()
  press(" co")
  eq("co: takes ours here", "ours line", vim.api.nvim_buf_get_lines(0, 1, 2, false)[1])
  check("co: leaves the other conflict alone", conflict.has_conflicts(0))

  reset()
  press(" ct")
  eq("ct: takes theirs here", "theirs line", vim.api.nvim_buf_get_lines(0, 1, 2, false)[1])

  reset()
  press(" cb")
  eq("cb: takes both here", { "ours line", "theirs line" }, vim.api.nvim_buf_get_lines(0, 1, 3, false))

  reset()
  press(" c0")
  eq("c0: takes neither", "middle", vim.api.nvim_buf_get_lines(0, 1, 2, false)[1])

  reset()
  press(" cO")
  check("cO: takes ours everywhere", not conflict.has_conflicts(0))
  reset()
  press(" cT")
  check("cT: takes theirs everywhere", not conflict.has_conflicts(0))
  reset()
  press(" cB")
  check("cB: takes both everywhere", not conflict.has_conflicts(0))

  -- Away from any conflict it says so rather than guessing.
  reset()
  vim.cmd("normal! G")
  clear_notes()
  local ok, err = pcall(press, " co")
  check("co: outside a conflict does not raise", ok, tostring(err))
  check("co: and says so", (last_note() or ""):find("not inside a conflict") ~= nil, tostring(last_note()))

  -- <leader>cq refuses to finish while markers remain.
  reset()
  clear_notes()
  ok, err = pcall(press, " cq")
  check("cq: does not raise with conflicts left", ok, tostring(err))
  check("cq: and refuses", (last_note() or ""):find("unresolved") ~= nil, tostring(last_note()))
end

--------------------------------------------------------------------------
-- the merge view, and finishing it
--------------------------------------------------------------------------

do
  reload(root .. "/conflicted.txt")
  local tabs = #vim.api.nvim_list_tabpages()
  press(" cm")
  eq("cm: the merge view opens in its own tab", tabs + 1, #vim.api.nvim_list_tabpages())
  eq("cm: three panes", 3, #vim.api.nvim_tabpage_list_wins(0))
  press(" cO")
  check("cm: resolving in the middle pane works", not conflict.has_conflicts(0))
  press(" cq")
  eq("cq: closes the merge view once it is clean", tabs, #vim.api.nvim_list_tabpages())
  eq(
    "cq: and the file on disk is resolved",
    { "before", "ours line", "middle", "second ours", "after" },
    vim.fn.readfile(root .. "/conflicted.txt")
  )
end

--------------------------------------------------------------------------
-- the rendering toggles reach the diff wherever it is
--------------------------------------------------------------------------

do
  write(root .. "/tracked.txt", "one\nTWO\nthree\nFOUR\nfive\n")
  reload(root .. "/tracked.txt")
  ui.file_diff("working")
  local wins = vim.api.nvim_tabpage_list_wins(0)
  local levels = {}
  for _, w in ipairs(wins) do
    levels[#levels + 1] = vim.wo[w].foldlevel
  end
  press(" cz")
  local flipped = false
  for i, w in ipairs(wins) do
    if vim.wo[w].foldlevel ~= levels[i] then
      flipped = true
    end
  end
  check("cz: re-levels the diff windows in place", flipped, vim.inspect(levels))
  press(" cz")
  vim.cmd("tabclose")

  -- <leader>ci outside the view flips the split orientation of an ad-hoc diff.
  reload(root .. "/tracked.txt")
  ui.file_diff("working")
  local ok, err = pcall(press, " ci")
  check("ci: harmless on an ad-hoc diff", ok, tostring(err))
  while #vim.api.nvim_list_tabpages() > 1 do
    vim.cmd("tabclose")
  end
end

--------------------------------------------------------------------------

vim.fn.delete(temp, "rf")

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  error("\n" .. table.concat(failures, "\n"))
end
