-- Run with: nvim --headless -u NONE -i NONE -l tests/nvim_vcs_ui_spec.lua
--
-- Exercises the diff UI in common/.config/nvim/lua/util/vcs_ui.lua: window
-- layout, which buffer ends up in which pane, scrubbing the file list, the
-- inline/side-by-side toggle, and the lifecycle of the diff tab.
--
-- Deliberately plugin-free. vcs_ui only reaches for snacks inside M.tui(), so
-- everything else can be driven with a bare Neovim.

local source = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(repo .. "/common/.config/nvim")

-- A realistic terminal, so the layout assertions mean something.
vim.o.columns = 200
vim.o.lines = 50

local vcs = require("util.vcs")
local ui = require("util.vcs_ui")

local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")

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
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local fd = assert(io.open(path, "wb"))
  fd:write(text)
  fd:close()
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

---Feed keys and let the debounced diff render land before asserting.
local function scrub(keys)
  feed(keys)
  vim.wait(400, function()
    return false
  end)
end

---Panel window plus the diff windows, left to right.
local function layout()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  table.sort(wins, function(a, b)
    return vim.api.nvim_win_get_position(a)[2] < vim.api.nvim_win_get_position(b)[2]
  end)
  return wins
end

local function win_lines(w)
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false)
end

local function win_name(w)
  return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w))
end

local function panel_lines()
  return win_lines(layout()[1])
end

--------------------------------------------------------------------------
-- fixture
--------------------------------------------------------------------------

local root = temp .. "/repo"
vim.fn.mkdir(root, "p")
root = vim.fn.resolve(root)
git(root, "init", "-q", "-b", "main")
write(root .. "/a_modified.txt", "one\ntwo\nthree\n")
write(root .. "/b_deleted.txt", "gone soon\n")
write(root .. "/c_untouched.txt", "stable\n")
write(root .. "/committed_on_branch.txt", "before\n")
git(root, "add", "-A")
git(root, "commit", "-qm", "initial")
git(root, "update-ref", "refs/remotes/origin/main", "HEAD")
git(root, "checkout", "-qb", "feature")
write(root .. "/committed_on_branch.txt", "after\n")
git(root, "add", "-A")
git(root, "commit", "-qm", "branch work")
write(root .. "/a_modified.txt", "one\nTWO\nthree\nfour\n")
vim.fn.delete(root .. "/b_deleted.txt")
write(root .. "/d_untracked.txt", "brand new\n")

vim.cmd("cd " .. vim.fn.fnameescape(root))

--------------------------------------------------------------------------
-- opening
--------------------------------------------------------------------------

local function unnamed_buffers()
  local n = 0
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_name(b) == "" and vim.bo[b].buftype == "" then
      n = n + 1
    end
  end
  return n
end

do
  local tabs_before = #vim.api.nvim_list_tabpages()
  local unnamed_before = unnamed_buffers()
  ui.open({ scope = "working" })
  eq("open: creates one new tab", tabs_before + 1, #vim.api.nvim_list_tabpages())

  local wins = layout()
  eq("open: panel plus two diff panes", 3, #wins)
  eq("open: panel is leftmost", "vcs://changes", win_name(wins[1]))
  eq("open: panel is pinned to its width", 42, vim.api.nvim_win_get_width(wins[1]))

  local w2, w3 = vim.api.nvim_win_get_width(wins[2]), vim.api.nvim_win_get_width(wins[3])
  check("open: diff panes are balanced", math.abs(w2 - w3) <= 1, string.format("%d vs %d", w2, w3))

  check("open: both diff panes are in diff mode", vim.wo[wins[2]].diff and vim.wo[wins[3]].diff)
  check("open: diff panes show line numbers", vim.wo[wins[2]].number and vim.wo[wins[3]].number)

  local lines = panel_lines()
  check("open: header names the backend and scope", lines[1]:find("git") and lines[1]:find("uncommitted"), lines[1])
  check("open: header counts the files", lines[2]:find("3 files"), lines[2])

  local listed = {}
  for i = 4, #lines do
    table.insert(listed, lines[i])
  end
  eq("open: lists every changed file, sorted, with status icons", {
    " ~  a_modified.txt",
    " -  b_deleted.txt",
    " ?  d_untracked.txt",
  }, listed)

  eq("open: cursor starts on the first file", 4, vim.api.nvim_win_get_cursor(wins[1])[1])
  check("open: focus stays in the panel", vim.api.nvim_get_current_win() == wins[1])

  -- The first entry is a plain modification: base on the left, real file right.
  eq("open: left pane holds the committed version", { "one", "two", "three" }, win_lines(wins[2]))
  eq("open: right pane holds the working copy", { "one", "TWO", "three", "four" }, win_lines(wins[3]))
  eq("open: right pane is the real file", root .. "/a_modified.txt", win_name(wins[3]))
  eq("open: right pane is editable", "", vim.bo[vim.api.nvim_win_get_buf(wins[3])].buftype)
  eq("open: left pane is a scratch buffer", "nofile", vim.bo[vim.api.nvim_win_get_buf(wins[2])].buftype)
  check("open: left pane is read-only", not vim.bo[vim.api.nvim_win_get_buf(wins[2])].modifiable)
  eq("open: left pane inherits the filetype", "text", vim.bo[vim.api.nvim_win_get_buf(wins[2])].filetype)

  -- `tabnew` leaves an unnamed buffer behind; it should not survive, or it
  -- shows up in the bufferline as "[No Name]".
  eq("open: leaves no new [No Name] buffer", unnamed_before, unnamed_buffers())
end

--------------------------------------------------------------------------
-- scrubbing the list
--------------------------------------------------------------------------

do
  scrub("j")
  local wins = layout()
  eq("j: cursor moves to the deleted file", 5, vim.api.nvim_win_get_cursor(wins[1])[1])
  check("j: focus stays in the panel", vim.api.nvim_get_current_win() == wins[1])
  eq("deleted file: left pane holds the old content", { "gone soon" }, win_lines(wins[2]))
  eq("deleted file: right pane is empty", { "" }, win_lines(wins[3]))
  eq(
    "deleted file: right pane is a scratch, not a missing file",
    "nofile",
    vim.bo[vim.api.nvim_win_get_buf(wins[3])].buftype
  )

  scrub("j")
  wins = layout()
  eq("j: cursor moves to the untracked file", 6, vim.api.nvim_win_get_cursor(wins[1])[1])
  eq("untracked file: left pane is empty", { "" }, win_lines(wins[2]))
  eq("untracked file: right pane holds the new content", { "brand new" }, win_lines(wins[3]))

  scrub("j")
  eq("j: stops at the last file", 6, vim.api.nvim_win_get_cursor(layout()[1])[1])

  scrub("kkk")
  eq("k: stops at the first file", 4, vim.api.nvim_win_get_cursor(layout()[1])[1])
  eq("k: re-renders the first file's diff", { "one", "two", "three" }, win_lines(layout()[2]))

  -- The panel must never be left showing a header line as the "current file".
  vim.api.nvim_win_set_cursor(layout()[1], { 1, 0 })
  scrub("j")
  check("j from a header line lands on a file", vim.api.nvim_win_get_cursor(layout()[1])[1] >= 4)
end

--------------------------------------------------------------------------
-- scrubbing is debounced and base content is cached
--------------------------------------------------------------------------

do
  local panel = layout()[1]
  vim.api.nvim_win_set_cursor(panel, { 4, 0 })
  scrub("")

  -- Holding j must move the cursor immediately without rendering each step;
  -- otherwise a large changelist blocks the UI for a subprocess per keystroke.
  feed("jj")
  eq("scrub: cursor keeps up with the keys", 6, vim.api.nvim_win_get_cursor(panel)[1])
  local rendered_immediately = win_lines(layout()[3])
  vim.wait(400, function()
    return false
  end)
  local rendered_after = win_lines(layout()[3])
  check(
    "scrub: the diff catches up once the keys stop",
    vim.deep_equal(rendered_after, { "brand new" }),
    vim.inspect(rendered_after)
  )
  _ = rendered_immediately

  -- <CR> must pre-empt a pending debounce rather than race it.
  vim.api.nvim_win_set_cursor(panel, { 4, 0 })
  feed("j")
  feed("\r")
  eq("scrub: <CR> renders the selected file at once", { "gone soon" }, win_lines(layout()[2]))

  -- Revisiting a file must not re-shell for content already fetched.
  vim.api.nvim_set_current_win(panel)
  vim.api.nvim_win_set_cursor(panel, { 4, 0 })
  scrub("")
  local t0 = vim.uv.hrtime()
  vim.api.nvim_win_set_cursor(panel, { 5, 0 })
  scrub("")
  vim.api.nvim_win_set_cursor(panel, { 4, 0 })
  scrub("")
  local elapsed = (vim.uv.hrtime() - t0) / 1e6
  check("scrub: cached revisits stay responsive", elapsed < 2000, string.format("%.0f ms", elapsed))
  eq("scrub: cached content is still correct", { "one", "two", "three" }, win_lines(layout()[2]))

  -- A render that lands after focus has moved on must not drag it back.
  vim.api.nvim_win_set_cursor(panel, { 4, 0 })
  feed("j")
  vim.api.nvim_set_current_win(layout()[3])
  local focused = vim.api.nvim_get_current_win()
  vim.wait(400, function()
    return false
  end)
  eq("scrub: a late render does not steal focus", focused, vim.api.nvim_get_current_win())
end

--------------------------------------------------------------------------
-- focusing, switching sides, scope cycling
--------------------------------------------------------------------------

do
  local panel = layout()[1]
  vim.api.nvim_win_set_cursor(panel, { 4, 0 })
  feed("\r")
  check("<CR>: moves focus into the diff", vim.api.nvim_get_current_win() ~= panel)
  eq("<CR>: focus lands on the working copy", root .. "/a_modified.txt", vim.api.nvim_buf_get_name(0))

  local before = vim.api.nvim_get_current_win()
  ui.switch_side()
  check("switch_side: moves to the other diff pane", vim.api.nvim_get_current_win() ~= before)
  check("switch_side: the other pane is also a diff", vim.wo.diff)
  ui.switch_side()
  eq("switch_side: comes back", before, vim.api.nvim_get_current_win())

  vim.api.nvim_set_current_win(panel)
  scrub("s")
  local lines = panel_lines()
  check("s: scope cycles to the fork point", lines[1]:find("since fork point"), lines[1])
  check("s: the branch commit now appears", vim.tbl_contains(lines, " ~  committed_on_branch.txt"), vim.inspect(lines))
  check("s: header counts four files", lines[2]:find("4 files"), lines[2])

  scrub("s")
  check("s: cycles on to the last commit", panel_lines()[1]:find("last commit"), panel_lines()[1])
  scrub("s")
  check("s: cycles back to uncommitted", panel_lines()[1]:find("uncommitted"), panel_lines()[1])
end

--------------------------------------------------------------------------
-- inline rendering
--------------------------------------------------------------------------

do
  vim.api.nvim_set_current_win(layout()[1])
  vim.api.nvim_win_set_cursor(layout()[1], { 4, 0 })
  scrub("i")
  local wins = layout()
  eq("inline: collapses to panel plus one pane", 2, #wins)
  eq("inline: panel keeps its width", 42, vim.api.nvim_win_get_width(wins[1]))
  check("inline: the pane is not in diff mode", not vim.wo[wins[2]].diff)

  scrub("i")
  eq("inline: toggling back restores two diff panes", 3, #layout())
  check("inline: back in diff mode", vim.wo[layout()[2]].diff)
end

--------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------

do
  local tabs = #vim.api.nvim_list_tabpages()
  ui.open({ scope = "working" })
  eq("open twice: reuses the existing tab", tabs, #vim.api.nvim_list_tabpages())

  vim.api.nvim_set_current_win(layout()[1])
  feed("q")
  eq("q: closes the diff tab", tabs - 1, #vim.api.nvim_list_tabpages())

  -- Reopening after a close has to rebuild state rather than reuse a dead tab.
  ui.open({ scope = "working" })
  eq("reopen: builds a fresh tab", tabs, #vim.api.nvim_list_tabpages())
  eq("reopen: panel is populated again", 3, #layout())

  -- Closing the tab out from under the UI must not wedge it.
  vim.cmd("tabclose")
  local ok = pcall(ui.open, { scope = "working" })
  check("open after an external tabclose recovers", ok)
  eq("open after an external tabclose rebuilds the panel", 3, #layout())
end

--------------------------------------------------------------------------
-- goto_file
--------------------------------------------------------------------------

do
  vim.api.nvim_win_set_cursor(layout()[1], { 4, 0 })
  feed("\r")
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  local tabs = #vim.api.nvim_list_tabpages()
  ui.goto_file()
  eq("goto_file: closes the diff tab", tabs - 1, #vim.api.nvim_list_tabpages())
  eq("goto_file: opens the real file", root .. "/a_modified.txt", vim.api.nvim_buf_get_name(0))
  eq("goto_file: keeps the line", 3, vim.api.nvim_win_get_cursor(0)[1])
  eq("goto_file: leaves a single window", 1, #vim.api.nvim_tabpage_list_wins(0))

  -- From the base side too, where the buffer name is a vcs:// URI.
  ui.open({ scope = "working" })
  vim.api.nvim_win_set_cursor(layout()[1], { 4, 0 })
  vim.api.nvim_set_current_win(layout()[2])
  ui.goto_file()
  eq("goto_file: works from the base pane too", root .. "/a_modified.txt", vim.api.nvim_buf_get_name(0))
end

--------------------------------------------------------------------------
-- file_diff, patch, copy_patch
--------------------------------------------------------------------------

do
  vim.cmd("edit " .. vim.fn.fnameescape(root .. "/a_modified.txt"))
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  local tabs = #vim.api.nvim_list_tabpages()
  ui.file_diff("working")
  eq("file_diff: opens a new tab", tabs + 1, #vim.api.nvim_list_tabpages())
  local wins = layout()
  eq("file_diff: two panes", 2, #wins)
  eq("file_diff: base on the left", { "one", "two", "three" }, win_lines(wins[1]))
  eq("file_diff: working copy on the right", { "one", "TWO", "three", "four" }, win_lines(wins[2]))
  check("file_diff: both in diff mode", vim.wo[wins[1]].diff and vim.wo[wins[2]].diff)
  eq("file_diff: focus is on the working copy", root .. "/a_modified.txt", vim.api.nvim_buf_get_name(0))
  eq("file_diff: cursor line preserved", 2, vim.api.nvim_win_get_cursor(0)[1])
  vim.cmd("tabclose")

  vim.fn.setreg("+", "")
  ui.copy_patch("branch")
  local copied = vim.fn.getreg("+")
  check("copy_patch: puts a unified diff on the clipboard", copied:find("diff --git", 1, true), copied:sub(1, 80))
  check("copy_patch: includes the branch commit", copied:find("committed_on_branch", 1, true))
end

--------------------------------------------------------------------------
-- history
--------------------------------------------------------------------------

do
  -- vim.ui.select would block without a UI; pick the oldest entry instead.
  local original = vim.ui.select
  local offered
  vim.ui.select = function(items, _, on_choice)
    offered = items
    on_choice(items[#items])
  end
  vim.cmd("edit " .. vim.fn.fnameescape(root .. "/committed_on_branch.txt"))
  local tabs = #vim.api.nvim_list_tabpages()
  ui.history()
  eq("history: offers every revision touching the file", 2, offered and #offered)
  eq("history: opens a diff tab", tabs + 1, #vim.api.nvim_list_tabpages())
  eq("history: base pane holds the chosen revision", { "before" }, win_lines(layout()[1]))
  eq("history: right pane holds the working copy", { "after" }, win_lines(layout()[2]))
  vim.cmd("tabclose")
  vim.ui.select = original
end

--------------------------------------------------------------------------
-- degenerate cases
--------------------------------------------------------------------------

do
  local clean = temp .. "/clean"
  vim.fn.mkdir(clean, "p")
  clean = vim.fn.resolve(clean)
  git(clean, "init", "-q", "-b", "main")
  write(clean .. "/only.txt", "content\n")
  git(clean, "add", "-A")
  git(clean, "commit", "-qm", "initial")
  vim.cmd("cd " .. vim.fn.fnameescape(clean))
  vim.cmd("edit " .. vim.fn.fnameescape(clean .. "/only.txt"))

  local tabs = #vim.api.nvim_list_tabpages()
  local ok = pcall(ui.open, { scope = "working" })
  check("no changes: does not raise", ok)
  eq("no changes: still opens a tab", tabs + 1, #vim.api.nvim_list_tabpages())
  check("no changes: panel says so", vim.tbl_contains(panel_lines(), " (no changes)"), vim.inspect(panel_lines()))
  local ok_move = pcall(scrub, "jjkk")
  check("no changes: moving in an empty list does not raise", ok_move)
  vim.cmd("tabclose")

  -- Outside any repository nothing should be opened at all.
  local bare = temp .. "/bare"
  vim.fn.mkdir(bare, "p")
  vim.cmd("cd " .. vim.fn.fnameescape(bare))
  vim.cmd("enew!")
  vcs.clear_cache()
  tabs = #vim.api.nvim_list_tabpages()
  local notified
  local original_notify = vim.notify
  vim.notify = function(msg)
    notified = msg
  end
  local ok_bare = pcall(ui.open, { scope = "working" })
  vim.notify = original_notify
  check("no repo: does not raise", ok_bare)
  eq("no repo: opens no tab", tabs, #vim.api.nvim_list_tabpages())
  check("no repo: says why", notified and notified:find("No version control"), tostring(notified))
end

--------------------------------------------------------------------------

vim.fn.delete(temp, "rf")

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  error("\n" .. table.concat(failures, "\n"))
end
