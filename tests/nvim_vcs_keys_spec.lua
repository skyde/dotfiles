-- Run with: nvim --headless -u NONE -i NONE -l tests/nvim_vcs_keys_spec.lua
--
-- The revert keys in config/vcs.lua, from inside a real diff.
-- tests/check-nvim-keymaps.sh presses every binding once from an ordinary
-- buffer, which is the one context where these branches are all false — so
-- nothing noticed that `<leader>cv` threw E21 on the read-only base pane.
--
-- Plugin-free like the rest: config/vcs.lua reaches for which-key and
-- gitsigns through pcall, and for nothing else.

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

vim.fn.delete(temp, "rf")

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  error("\n" .. table.concat(failures, "\n"))
end
