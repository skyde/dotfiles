-- Run with: tests/bench-nvim-vcs.sh [files]
--
-- What the changed-files view costs on a listing the size a real repository
-- produces after a rebase or a generated-code change. The config is aimed at
-- large checkouts, and nothing else here measures that.
--
-- Three numbers, because they mean different things:
--
--   first paint   how long until the list is on screen and can be read. This
--                 is the one a person feels.
--   settled       until every background pass has finished: the base prefetch
--                 that fills in each row's +n -n. The view is usable
--                 throughout — this is not blocking time.
--   scrub         forty files under a held-down `j`, base fetches and all,
--                 which is the interaction the view exists for.
--
-- Informational. A shared CI runner is far too noisy to gate on, so this
-- prints and never fails; it is here so a regression shows up in a log.

local source = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(repo .. "/common/.config/nvim")

-- A realistic terminal, so the layout and render code runs for real.
vim.o.columns = 200
vim.o.lines = 50

local vcs = require("util.vcs")
local ui = require("util.vcs_ui")

local COUNT = tonumber(vim.env.BENCH_FILES or "") or 3000
local PER_DIR = 100

local function run(cmd, cwd)
  local res = vim.system(cmd, { cwd = cwd, text = true }):wait()
  if res.code ~= 0 then
    error(table.concat(cmd, " ") .. " failed: " .. (res.stderr or ""))
  end
  return res.stdout
end

local function git(dir, ...)
  local cmd = { "git", "-c", "user.email=t@example.com", "-c", "user.name=Test", "-c", "commit.gpgsign=false" }
  vim.list_extend(cmd, { ... })
  return run(cmd, dir)
end

local function write(path, text)
  local fd = assert(io.open(path, "wb"))
  fd:write(text)
  fd:close()
end

local temp = vim.fn.tempname()
local root = temp .. "/bench"
vim.fn.mkdir(root, "p")
git(root, "init", "-q", "-b", "main")

for i = 1, COUNT do
  local dir = ("%s/src/mod%d"):format(root, math.floor((i - 1) / PER_DIR))
  vim.fn.mkdir(dir, "p")
  write(("%s/file%d.cc"):format(dir, i), "line one\nline two\nline three\n")
end
git(root, "add", "-A")
git(root, "commit", "-qm", "base")
for i = 1, COUNT do
  local dir = ("%s/src/mod%d"):format(root, math.floor((i - 1) / PER_DIR))
  write(("%s/file%d.cc"):format(dir, i), "line one\nline TWO\nline three\n")
end

vim.cmd("cd " .. vim.fn.fnameescape(root))
vcs.clear_cache()

local function ms(from, to)
  return (to - from) / 1e6
end

local function panel_lines()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  if #wins == 0 then
    return {}
  end
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(wins[1]), 0, -1, false)
end

local start = vim.uv.hrtime()
ui.open({ scope = "working" })

-- The header rows plus more file rows than a screen holds: enough to say the
-- list is really up rather than a placeholder.
local painted
vim.wait(120000, function()
  if #panel_lines() > 100 then
    painted = vim.uv.hrtime()
    return true
  end
  return false
end, 5)
local first_paint = painted and ms(start, painted) or -1

vim.wait(120000, function()
  return not ui.busy()
end)
local settled = ms(start, vim.uv.hrtime())

local lines = panel_lines()
local rows = 0
for _, line in ipairs(lines) do
  -- Any depth: the tree indents nested rows, so anything after the status
  -- column counts, not just a name flush against it.
  if line:match("^ [MAD?RC]  %s*%S") then
    rows = rows + 1
  end
end

local panel = vim.api.nvim_tabpage_list_wins(0)[1]
vim.api.nvim_set_current_win(panel)
local scrub_start = vim.uv.hrtime()
for _ = 1, 40 do
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("j", true, false, true), "x", false)
end
vim.wait(120000, function()
  return not ui.busy()
end)
local scrub = ms(scrub_start, vim.uv.hrtime())

print(("files changed: %d (panel rows: %d)"):format(COUNT, rows))
print(("first paint:   %7.0f ms"):format(first_paint))
print(("settled:       %7.0f ms"):format(settled))
print(("scrub 40:      %7.0f ms"):format(scrub))

ui.close()
vim.fn.delete(temp, "rf")
