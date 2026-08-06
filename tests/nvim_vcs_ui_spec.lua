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

---Open the view and let the background revalidation and prefetch land, so
---assertions see fresh data rather than the cached paint.
local function open_settled(opts)
  ui.open(opts)
  vim.wait(3000, function()
    return not ui.busy()
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
-- Enough identical lines that git still scores the later rename as a rename
-- once a line is added; a one-line file falls below the similarity threshold.
write(root .. "/c_untouched.txt", string.rep("stable\n", 8))
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

-- The default rendering is inline, matching `diffEditor.renderSideBySide:
-- false` in the VS Code config. The bulk of this spec drives the side-by-side
-- layout, so assert the default once and switch.
do
  ui.open({ scope = "working" })
  eq("default: the view opens inline", 2, #layout())
  check("default: the inline pane is not a diff window", not vim.wo[layout()[2]].diff)
  ui.toggle_inline()
  ui.close()
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
  check("open: header counts the files", lines[2]:find("of 3"), lines[2])

  local listed = {}
  for i = 4, #lines do
    table.insert(listed, lines[i])
  end
  eq("open: lists every changed file, sorted, with status letters", {
    " M  a_modified.txt",
    " D  b_deleted.txt",
    " ?  d_untracked.txt",
  }, listed)

  eq("open: cursor starts on the first file", 4, vim.api.nvim_win_get_cursor(wins[1])[1])
  check("open: focus stays in the panel", vim.api.nvim_get_current_win() == wins[1])

  -- The first entry is a plain modification: base on the left, real file right.
  eq("open: left pane holds the committed version", { "one", "two", "three" }, win_lines(wins[2]))
  eq("open: right pane holds the working copy", { "one", "TWO", "three", "four" }, win_lines(wins[3]))
  eq("open: right pane is the real file", root .. "/a_modified.txt", win_name(wins[3]))
  eq("open: right pane is editable", "", vim.bo[vim.api.nvim_win_get_buf(wins[3])].buftype)
  eq("open: the preview stays out of the buffer list", 0, vim.fn.buflisted(vim.api.nvim_win_get_buf(wins[3])))
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
-- panel decorations: churn stats and viewed marks
--------------------------------------------------------------------------

do
  vim.wait(3000, function()
    return not ui.busy()
  end)
  local ns_ui = vim.api.nvim_create_namespace("vcs_ui")
  local panel_buf = vim.api.nvim_win_get_buf(layout()[1])
  local right = {} ---@type table<integer, string>
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(panel_buf, ns_ui, 0, -1, { details = true })) do
    local d = m[4]
    if d.virt_text and d.virt_text_pos == "right_align" then
      local parts = {}
      for _, chunk in ipairs(d.virt_text) do
        parts[#parts + 1] = chunk[1]
      end
      right[m[2] + 1] = table.concat(parts)
    end
  end
  -- Rows: 4 a_modified, 5 b_deleted, 6 d_untracked — all three were rendered
  -- while scrubbing above, so all three carry the viewed ✓.
  eq("stats: a modified file counts both ways", "✓ +2 -1 ", right[4])
  eq("stats: a deleted file counts its deletions", "✓ -1 ", right[5])
  eq("stats: an untracked file counts its additions", "✓ +1 ", right[6])
  check("stats: the header totals the listing", panel_lines()[2]:find("+3 -2", 1, true) ~= nil, panel_lines()[2])
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
  vim.api.nvim_set_current_win(panel)
  vim.api.nvim_win_set_cursor(panel, { 4, 0 })
  feed("\r")
  check("<CR>: moves focus into the diff", vim.api.nvim_get_current_win() ~= panel)
  -- Focusing is what materialises the real, editable buffer.
  eq("<CR>: focus lands on the working copy", root .. "/a_modified.txt", vim.api.nvim_buf_get_name(0))
  eq("<CR>: the focused buffer is the real file", "", vim.bo.buftype)

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
  check("s: the branch commit now appears", vim.tbl_contains(lines, " M  committed_on_branch.txt"), vim.inspect(lines))
  check("s: header counts four files", lines[2]:find("of 4"), lines[2])

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

  local inline = require("util.inline_diff")
  local overlay_ns = vim.api.nvim_create_namespace("vcs_inline_diff")

  ---The overlay, reduced to what a reader sees: which buffer lines are
  ---highlighted as new, and which old lines are drawn as virtual text.
  local function overlay(buf)
    local virt, added = {}, {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, overlay_ns, 0, -1, { details = true })) do
      local d = m[4]
      if d.virt_lines then
        for _, vl in ipairs(d.virt_lines) do
          virt[#virt + 1] = vl[1][1]
        end
      end
      if d.line_hl_group and d.line_hl_group:find("^InlineDiffAdd") then
        added[#added + 1] = m[2] + 1
      end
    end
    table.sort(added)
    return virt, added
  end

  local buf = vim.api.nvim_win_get_buf(wins[2])
  eq("inline: the pane holds the real file", root .. "/a_modified.txt", vim.api.nvim_buf_get_name(buf))
  check("inline: the buffer is editable", vim.bo[buf].modifiable)
  check("inline: the overlay is attached", inline.has(buf))
  eq("inline: cursor sits on the first change", 2, vim.api.nvim_win_get_cursor(wins[2])[1])

  local virt, added = overlay(buf)
  eq("inline: the old line is drawn as virtual text", { "two" }, virt)
  eq("inline: the new lines are highlighted", { 2, 4 }, added)

  -- <Space> selects too; in the panel it deliberately shadows leader.
  feed(" ")
  eq("inline: <Space> focuses the file itself", root .. "/a_modified.txt", vim.api.nvim_buf_get_name(0))
  vim.api.nvim_set_current_win(layout()[1])

  -- The whole point: it is editable, and the overlay follows the edit.
  feed("\r")
  eq("inline: <CR> focuses the file itself", root .. "/a_modified.txt", vim.api.nvim_buf_get_name(0))
  buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.cmd("normal! oinserted")
  inline.render(buf)
  local _, added2 = overlay(buf)
  eq("inline: editing extends the overlay", { 2, 3, 5 }, added2)

  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  inline.goto_hunk(0, 1)
  eq("inline: next hunk from the top", 2, vim.api.nvim_win_get_cursor(0)[1])
  -- linematch pairs old "two" with "inserted" (they share characters; "TWO"
  -- shares none case-sensitively), so "TWO" and that pair are separate hunks.
  inline.goto_hunk(0, 1)
  eq("inline: next hunk again", 3, vim.api.nvim_win_get_cursor(0)[1])
  inline.goto_hunk(0, 1)
  eq("inline: last hunk", 5, vim.api.nvim_win_get_cursor(0)[1])

  check("inline: revert replaces the hunk with the base lines", inline.revert_hunk(0))
  eq(
    "inline: the reverted tail matches the base",
    { "one", "TWO", "inserted", "three" },
    vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  )
  vim.cmd("edit!")
  inline.render(buf)

  -- A deleted file has nothing on disk to edit; its content shows struck red.
  vim.api.nvim_set_current_win(layout()[1])
  vim.api.nvim_win_set_cursor(layout()[1], { 4, 0 })
  scrub("j")
  check(
    "inline: a deleted file shows the base content",
    vim.tbl_contains(win_lines(layout()[2]), "gone soon"),
    vim.inspect(win_lines(layout()[2]))
  )

  -- An untracked file is all additions, and still editable.
  scrub("j")
  local ubuf = vim.api.nvim_win_get_buf(layout()[2])
  eq("inline: an untracked file is the real file", root .. "/d_untracked.txt", vim.api.nvim_buf_get_name(ubuf))
  local uvirt, uadded = overlay(ubuf)
  eq("inline: an untracked file shows as a whole-file add", { 1 }, uadded)
  eq("inline: an untracked file has no old lines", {}, uvirt)

  -- Unsaved edits survive scrubbing away and back: the buffer is reused, not
  -- reloaded.
  vim.api.nvim_win_set_cursor(layout()[1], { 5, 0 })
  scrub("k")
  feed("\r")
  local abuf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(abuf, 0, 0, false, { "unsaved edit" })
  vim.api.nvim_set_current_win(layout()[1])
  scrub("j")
  scrub("k")
  eq(
    "inline: unsaved edits survive scrubbing away and back",
    "unsaved edit",
    vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(layout()[2]), 0, 1, false)[1]
  )
  vim.api.nvim_buf_call(abuf, function()
    vim.cmd("edit!")
  end)

  -- Scope cycling keeps the rendering mode.
  scrub("s")
  eq("inline: scope cycling stays inline", 2, #layout())
  check("inline: the pane is still not a diff", not vim.wo[layout()[2]].diff)
  scrub("s")
  scrub("s")

  -- There are no sides to switch here; it must say so without moving focus.
  local before_win = vim.api.nvim_get_current_win()
  eq("inline: switch_side reports no diff", false, ui.switch_side())
  eq("inline: switch_side does not move focus", before_win, vim.api.nvim_get_current_win())

  -- goto_file from the inline pane closes the whole view, like from a pane of
  -- the side-by-side.
  vim.api.nvim_win_set_cursor(layout()[1], { 4, 0 })
  feed("\r")
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  local tabs_before = #vim.api.nvim_list_tabpages()
  ui.goto_file()
  eq("inline: goto_file closes the view", tabs_before - 1, #vim.api.nvim_list_tabpages())
  eq("inline: goto_file lands on the real file", root .. "/a_modified.txt", vim.api.nvim_buf_get_name(0))
  eq("inline: goto_file keeps the line", 2, vim.api.nvim_win_get_cursor(0)[1])
  check("inline: goto_file leaves no overlay behind", not inline.has(0))

  -- The rendering choice is remembered for the next open, the way VS Code's
  -- renderSideBySide is a setting rather than a per-diff toggle.
  ui.open({ scope = "working" })
  eq("inline: the mode is remembered across close and reopen", 2, #layout())

  scrub("i")
  eq("inline: toggling back restores two diff panes", 3, #layout())
  check("inline: back in diff mode", vim.wo[layout()[2]].diff)
end

--------------------------------------------------------------------------
-- collapsing unchanged regions
--------------------------------------------------------------------------

do
  -- Side-by-side panes use diff mode's own folds; collapse means they start
  -- closed. (The fixture files are tiny, so nothing actually folds — what is
  -- under test is the wiring.)
  eq("collapse: side-by-side panes start with folds closed", 0, vim.wo[layout()[2]].foldlevel)

  -- The inline overlay folds through its foldexpr.
  scrub("i")
  eq("collapse: the inline pane folds via the overlay", "expr", vim.wo[layout()[2]].foldmethod)
  eq("collapse: inline folds start closed", 0, vim.wo[layout()[2]].foldlevel)

  -- z toggles it off and on; each toggle re-renders the pane.
  feed("z")
  eq("collapse: z turns the folding off", "manual", vim.wo[layout()[2]].foldmethod)
  feed("z")
  eq("collapse: z folds again", "expr", vim.wo[layout()[2]].foldmethod)

  scrub("i") -- back to side-by-side for the blocks below
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
-- renames
--------------------------------------------------------------------------

do
  git(root, "mv", "c_untouched.txt", "c_renamed.txt")
  write(root .. "/c_renamed.txt", string.rep("stable\n", 8) .. "plus a change\n")
  -- The cached listing predates the rename; the background revalidation has to
  -- land before the new name can be asserted.
  open_settled({ scope = "working" })

  local lines = panel_lines()
  local row
  for i, l in ipairs(lines) do
    if l:find("c_renamed.txt", 1, true) then
      row = i
    end
  end
  check("rename: listed under the new name", row ~= nil, vim.inspect(lines))
  check("rename: the old name is not listed separately", not vim.tbl_contains(lines, " D  c_untouched.txt"))

  vim.api.nvim_set_current_win(layout()[1])
  vim.api.nvim_win_set_cursor(layout()[1], { row, 0 })
  feed("\r")
  eq(
    "rename: base pane holds the old path's content",
    vim.split(string.rep("stable\n", 8), "\n", { trimempty = true }),
    win_lines(layout()[2])
  )
  check(
    "rename: base pane is named after the old path",
    win_name(layout()[2]):find("c_untouched.txt", 1, true),
    win_name(layout()[2])
  )
  ui.close()
end

--------------------------------------------------------------------------
-- preview buffers: scrubbing must not fill the buffer list
--------------------------------------------------------------------------

do
  for _, n in ipairs({ "a_modified.txt", "c_renamed.txt", "d_untracked.txt" }) do
    local b = vim.fn.bufnr(root .. "/" .. n)
    if b ~= -1 then
      pcall(vim.cmd, "bwipeout! " .. b)
    end
  end

  ui.open({ scope = "working" })
  local a = vim.fn.bufnr(root .. "/a_modified.txt")
  check("preview: the shown file is loaded", a ~= -1)
  eq("preview: and stays out of the buffer list", 0, vim.fn.buflisted(a))

  scrub("jjj")
  -- Close on switch: moving off an unedited preview drops it immediately.
  eq("preview: moving on drops the previous preview", -1, vim.fn.bufnr(root .. "/a_modified.txt"))
  check("preview: only the shown file is loaded", vim.fn.bufnr(root .. "/d_untracked.txt") ~= -1)

  vim.api.nvim_win_set_cursor(layout()[1], { 4, 0 })
  feed("\r")
  eq("preview: focus lands on the working copy", root .. "/a_modified.txt", vim.api.nvim_buf_get_name(0))
  eq("preview: the materialised buffer stays out of the buffer list", 0, vim.fn.buflisted(0))
  eq("preview: the diff opens at the first change", 2, vim.api.nvim_win_get_cursor(0)[1])
  vim.cmd("normal! Ox")
  -- Headless nvim delivers no BufModifiedSet, so the live relisting cannot
  -- be asserted here; the close-time guarantee can: an edited preview is
  -- kept and surfaced in the buffer list, never silently dropped.
  ui.close()
  eq("close: unedited previews are dropped", -1, vim.fn.bufnr(root .. "/d_untracked.txt"))
  local a = vim.fn.bufnr(root .. "/a_modified.txt")
  check("close: the edited buffer survives", a ~= -1)
  eq("close: and is surfaced in the buffer list", 1, vim.fn.buflisted(a))
  vim.api.nvim_buf_call(a, function()
    vim.cmd("silent! undo")
  end)
end

--------------------------------------------------------------------------
-- preview buffers: cleanup runs however the view dies, not just on q
--------------------------------------------------------------------------

do
  ui.open({ scope = "working" })
  scrub("jjj")
  feed("\r") -- focus, materialising the real preview buffer
  check("external close: focusing materialises the preview", vim.fn.bufnr(root .. "/d_untracked.txt") ~= -1)

  -- Close the tab out from under the UI, the way :tabclose or :q on its last
  -- window would; the deferred cleanup must still drop the previews.
  vim.cmd("tabclose")
  vim.wait(300, function()
    return vim.fn.bufnr(root .. "/d_untracked.txt") == -1
  end)
  eq("external close: previews are dropped anyway", -1, vim.fn.bufnr(root .. "/d_untracked.txt"))
  check("external close: the edited buffer survives", vim.fn.bufnr(root .. "/a_modified.txt") ~= -1)

  local ok = pcall(ui.open, { scope = "working" })
  check("external close: the view reopens cleanly afterwards", ok)
  ui.close()
end

--------------------------------------------------------------------------
-- sessions: nothing of the view may leak into a saved session
--------------------------------------------------------------------------

do
  -- A session saved with the view open used to bake the diff tab and its
  -- preview buffers into the session file; restoring it then resurrected
  -- them as real listed buffers plus a junk tab of dead vcs:// windows.
  ui.open({ scope = "working" })
  scrub("jjj")
  feed("\r") -- materialise one real preview buffer
  check("session: the preview exists before saving", vim.fn.bufnr(root .. "/d_untracked.txt") ~= -1)
  local tabs = #vim.api.nvim_list_tabpages()
  vim.api.nvim_exec_autocmds("User", { pattern = "PersistenceSavePre" })
  eq("session: PersistenceSavePre folds the view away", tabs - 1, #vim.api.nvim_list_tabpages())
  eq("session: the preview buffer is gone", -1, vim.fn.bufnr(root .. "/d_untracked.txt"))

  ui.open({ scope = "working" })
  tabs = #vim.api.nvim_list_tabpages()
  vim.api.nvim_exec_autocmds("VimLeavePre", {})
  eq("session: VimLeavePre folds the view away too", tabs - 1, #vim.api.nvim_list_tabpages())
end

--------------------------------------------------------------------------
-- goto_file from an ad-hoc diff tab
--------------------------------------------------------------------------

do
  vim.cmd("edit " .. vim.fn.fnameescape(root .. "/a_modified.txt"))
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.wo.relativenumber = true
  local tabs = #vim.api.nvim_list_tabpages()
  ui.file_diff("working")
  local wins = layout()
  check(
    "file_diff: relative line numbers in both panes",
    vim.wo[wins[1]].number and vim.wo[wins[2]].number and vim.wo[wins[1]].relativenumber and vim.wo[wins[2]].relativenumber
  )
  ui.goto_file()
  eq("goto_file from file_diff: closes the ad-hoc tab", tabs, #vim.api.nvim_list_tabpages())
  eq("goto_file from file_diff: lands on the real file", root .. "/a_modified.txt", vim.api.nvim_buf_get_name(0))
  check("goto_file from file_diff: no diff mode left behind", not vim.wo.diff)
  vim.wo.relativenumber = false
end

--------------------------------------------------------------------------
-- tree view: nested paths group into directories
--------------------------------------------------------------------------

do
  write(root .. "/deep/nested/dir/one.txt", "1\n")
  write(root .. "/deep/nested/dir/two.txt", "2\n")
  write(root .. "/deep/other.txt", "other\n")
  -- The first open paints the cached, pre-tree listing with the cursor on its
  -- first file; the revalidation that discovers the new files must keep the
  -- selection on that same file even though its row moved.
  open_settled({ scope = "working" })
  check(
    "tree: revalidation keeps the selection on the same file",
    panel_lines()[vim.api.nvim_win_get_cursor(layout()[1])[1]]:find("a_modified", 1, true) ~= nil,
    vim.inspect(panel_lines()) .. " cursor " .. vim.api.nvim_win_get_cursor(layout()[1])[1]
  )
  -- Reopen so the paint itself is the tree being asserted.
  ui.close()
  open_settled({ scope = "working" })

  local lines = panel_lines()
  local listed = {}
  for i = 4, #lines do
    table.insert(listed, lines[i])
  end
  eq("tree: directories group, single-child chains compact, filenames stay whole", {
    "    deep/",
    "      nested/dir/",
    " ?      one.txt",
    " ?      two.txt",
    " ?    other.txt",
    " M  a_modified.txt",
    " D  b_deleted.txt",
    " R  c_renamed.txt ← c_untouched.txt",
    " ?  d_untracked.txt",
  }, listed)

  local panel = layout()[1]
  eq("tree: cursor starts on the first file, past directory rows", 6, vim.api.nvim_win_get_cursor(panel)[1])

  scrub("j")
  eq("tree: j moves to the next file", 7, vim.api.nvim_win_get_cursor(panel)[1])
  scrub("k")
  eq("tree: k moves back", 6, vim.api.nvim_win_get_cursor(panel)[1])
  scrub("k")
  eq("tree: k stops at the first file, not a directory row", 6, vim.api.nvim_win_get_cursor(panel)[1])

  vim.api.nvim_win_set_cursor(panel, { 6, 0 })
  feed("\r")
  eq("tree: <CR> on a nested file opens it", root .. "/deep/nested/dir/one.txt", vim.api.nvim_buf_get_name(0))

  -- A directory row selects nothing; <CR> just moves into the diff already up.
  vim.api.nvim_set_current_win(panel)
  vim.api.nvim_win_set_cursor(panel, { 4, 0 })
  feed("\r")
  eq(
    "tree: <CR> on a directory row keeps the previous file",
    root .. "/deep/nested/dir/one.txt",
    vim.api.nvim_buf_get_name(0)
  )
  ui.close()
end

--------------------------------------------------------------------------
-- panel keys: l / <Right> open the diff, J/K scroll it from the list
--------------------------------------------------------------------------

do
  -- A long file so the preview has somewhere to scroll.
  write(root .. "/long.txt", string.rep("line\n", 200))
  open_settled({ scope = "working" })
  local panel = layout()[1]

  local row
  for i, l in ipairs(panel_lines()) do
    if l:find("long.txt", 1, true) then
      row = i
    end
  end
  check("panel: the long file is listed", row ~= nil, vim.inspect(panel_lines()))
  vim.api.nvim_win_set_cursor(panel, { row - 1, 0 })
  scrub("j")
  eq("panel: j lands on the long file", row, vim.api.nvim_win_get_cursor(panel)[1])

  feed("<Right>")
  eq("panel: <Right> focuses the diff", root .. "/long.txt", vim.api.nvim_buf_get_name(0))
  vim.api.nvim_set_current_win(panel)
  feed("l")
  eq("panel: l focuses the diff too", root .. "/long.txt", vim.api.nvim_buf_get_name(0))
  vim.api.nvim_set_current_win(panel)

  local right = layout()[#layout()]
  local function topline()
    return vim.api.nvim_win_call(right, function()
      return vim.fn.line("w0")
    end)
  end
  local before = topline()
  feed("J")
  local down = topline()
  check("panel: J scrolls the preview down", down > before, string.format("%d -> %d", before, down))
  feed("K")
  check("panel: K scrolls it back up", topline() < down, string.format("%d after K", topline()))
  ui.close()
end

--------------------------------------------------------------------------
-- panel: the selected file is visibly highlighted
--------------------------------------------------------------------------

do
  -- The real config sets cursorlineopt = "number" globally, and the panel has
  -- no line numbers — the panel must override it or the selection is invisible.
  local saved = vim.o.cursorlineopt
  vim.o.cursorlineopt = "number"
  open_settled({ scope = "working" })
  local panel = layout()[1]
  check("panel: cursorline is on", vim.wo[panel].cursorline)
  eq("panel: cursorline highlights the row, not just the number", "line", vim.wo[panel].cursorlineopt)
  -- The diff panes are split from the panel and would inherit that full-row
  -- highlight; on real text it must fall back to the global setting.
  for i, w in ipairs(layout()) do
    if i > 1 then
      eq(("panel: diff pane %d does not inherit the row highlight"):format(i), "number", vim.wo[w].cursorlineopt)
    end
  end
  ui.close()
  vim.o.cursorlineopt = saved
end

--------------------------------------------------------------------------
-- ]c / [c from the panel: walk the diff's changes without leaving the list
--------------------------------------------------------------------------

do
  open_settled({ scope = "working" })
  local panel = layout()[1]
  -- a_modified has two hunks; the tree's first file (untracked) has one.
  for i, l in ipairs(panel_lines()) do
    if l:find("a_modified.txt", 1, true) then
      vim.api.nvim_win_set_cursor(panel, { i - 1, 0 })
    end
  end
  scrub("j")
  local diff = layout()[#layout()]
  local before = vim.api.nvim_win_get_cursor(diff)[1]
  feed("]c")
  local after = vim.api.nvim_win_get_cursor(diff)[1]
  check("]c: moves the diff to the next change", after > before, ("%d -> %d"):format(before, after))
  eq("]c: focus stays in the panel", panel, vim.api.nvim_get_current_win())
  feed("[c")
  check("[c: moves back", vim.api.nvim_win_get_cursor(diff)[1] < after, tostring(vim.api.nvim_win_get_cursor(diff)[1]))
  ui.close()
end

--------------------------------------------------------------------------
-- caching: reopening paints from the cache, then revalidates in the background
--------------------------------------------------------------------------

do
  open_settled({ scope = "working" })
  ui.close()

  -- A change made while the view is closed is not in the cached paint, and is
  -- there once the background revalidation lands.
  write(root .. "/e_new.txt", "fresh\n")
  ui.open({ scope = "working" })
  check(
    "cache: reopening paints instantly from the cached listing",
    not vim.tbl_contains(panel_lines(), " ?  e_new.txt"),
    vim.inspect(panel_lines())
  )
  check("cache: the header says it is refreshing", panel_lines()[2]:find("refreshing", 1, true) ~= nil, panel_lines()[2])
  vim.wait(3000, function()
    return not ui.busy()
  end)
  check(
    "cache: the background refresh picks up the new file",
    vim.tbl_contains(panel_lines(), " ?  e_new.txt"),
    vim.inspect(panel_lines())
  )
  check("cache: the refresh marker clears", not panel_lines()[2]:find("refreshing", 1, true), panel_lines()[2])

  -- Base content survives close and reopen: rendering a file seen before must
  -- not shell out for it again.
  local backend = vcs.backends.git
  local real_show = backend.show
  local shows = {}
  backend.show = function(r, rv, p)
    shows[p] = (shows[p] or 0) + 1
    return real_show(r, rv, p)
  end
  ui.close()
  ui.open({ scope = "working" })
  vim.wait(3000, function()
    return not ui.busy()
  end)
  backend.show = real_show
  eq("cache: a previously fetched base is not re-fetched", nil, shows["a_modified.txt"])
  ui.close()
end

--------------------------------------------------------------------------
-- change_position: which change is the cursor on
--------------------------------------------------------------------------

do
  write(root .. "/hunky.txt", "a\nb\nc\nd\ne\nf\ng\nh\ni\nj\n")
  git(root, "add", "hunky.txt")
  git(root, "commit", "-qm", "hunky")
  write(root .. "/hunky.txt", "a\nB\nc\nd\ne\nF\ng\nh\ni\nJ\n")

  vim.cmd("edit " .. vim.fn.fnameescape(root .. "/hunky.txt"))
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  ui.file_diff("working")
  local idx, total = ui.change_position()
  eq("change_position: counts every hunk", 3, total)
  eq("change_position: 0 above the first change", 0, idx)
  vim.cmd("normal! ]c")
  eq("change_position: first change", 1, (ui.change_position()))
  vim.cmd("normal! ]c")
  eq("change_position: second change", 2, (ui.change_position()))
  vim.cmd("normal! ]c")
  eq("change_position: third change", 3, (ui.change_position()))
  ui.switch_side()
  local _, t2 = ui.change_position()
  eq("change_position: the base pane counts the same hunks", 3, t2)
  vim.cmd("tabclose")
  check("change_position: nil outside a diff", ui.change_position() == nil)
end

--------------------------------------------------------------------------
-- header: the position cue follows the selection
--------------------------------------------------------------------------

do
  open_settled({ scope = "working" })
  check("header: says file 1 of N", panel_lines()[2]:match("file 1 of %d+") ~= nil, panel_lines()[2])
  scrub("j")
  check("header: follows the cursor to file 2", panel_lines()[2]:match("file 2 of %d+") ~= nil, panel_lines()[2])
  ui.close()
end

--------------------------------------------------------------------------
-- focus: one key always goes to the view; it never closes it
--------------------------------------------------------------------------

do
  local tabs = #vim.api.nvim_list_tabpages()
  ui.focus({ scope = "working" })
  vim.wait(3000, function()
    return not ui.busy()
  end)
  eq("focus: opens the view", tabs + 1, #vim.api.nvim_list_tabpages())

  -- From the diff the same key returns to the list; it never closes.
  local panel = layout()[1]
  feed("l")
  check("focus precondition: focus sits in the diff", vim.api.nvim_get_current_win() ~= panel)
  ui.focus({ scope = "working" })
  eq("focus: from the diff it focuses the list", panel, vim.api.nvim_get_current_win())
  eq("focus: without closing the view", tabs + 1, #vim.api.nvim_list_tabpages())
  ui.focus({ scope = "working" })
  eq("focus: pressed again it still does not close", tabs + 1, #vim.api.nvim_list_tabpages())
  eq("focus: and stays on the list", panel, vim.api.nvim_get_current_win())

  -- From another tab it jumps back without resetting the selection.
  scrub("j")
  local selection = vim.api.nvim_win_get_cursor(panel)[1]
  vim.cmd("tabfirst")
  ui.focus({ scope = "working" })
  vim.wait(3000, function()
    return not ui.busy()
  end)
  eq("focus: from another tab it jumps to the view", panel, vim.api.nvim_get_current_win())
  eq("focus: keeping the selection", selection, vim.api.nvim_win_get_cursor(panel)[1])

  ui.focus({ scope = "branch" })
  vim.wait(3000, function()
    return not ui.busy()
  end)
  eq("focus: a different scope switches in place", tabs + 1, #vim.api.nvim_list_tabpages())
  check("focus: scope actually switched", panel_lines()[1]:find("fork point", 1, true) ~= nil, panel_lines()[1])
  ui.close()
end

--------------------------------------------------------------------------
-- ]f / [f: walk the changelist from inside the diff
--------------------------------------------------------------------------

do
  -- A buffer that predates the view, to prove the maps come off it on close.
  vim.cmd("edit " .. vim.fn.fnameescape(root .. "/a_modified.txt"))
  local outliving = vim.api.nvim_get_current_buf()

  open_settled({ scope = "working" })
  local panel = layout()[1]
  feed("l")
  local first = vim.api.nvim_buf_get_name(0)
  feed("]f")
  local second = vim.api.nvim_buf_get_name(0)
  check("]f: renders the next file", second ~= first and second ~= "", second)
  check("]f: keeps focus in the diff", vim.api.nvim_get_current_win() ~= panel)
  feed("[f")
  eq("[f: goes back to the previous file", first, vim.api.nvim_buf_get_name(0))

  -- Visit the pre-existing buffer through the view, then close it.
  local row
  for i, l in ipairs(panel_lines()) do
    if l:find("a_modified.txt", 1, true) then
      row = i
    end
  end
  vim.api.nvim_win_set_cursor(panel, { row, 0 })
  vim.api.nvim_set_current_win(panel)
  feed("l")
  local has_map = false
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(outliving, "n")) do
    has_map = has_map or m.lhs == "]f"
  end
  check("]f: mapped on the shown file while the view lives", has_map)
  ui.close()
  has_map = false
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(outliving, "n")) do
    has_map = has_map or m.lhs == "]f"
  end
  check("]f: removed from surviving buffers on close", not has_map)
end

--------------------------------------------------------------------------
-- q from a scratch diff pane closes the view
--------------------------------------------------------------------------

do
  open_settled({ scope = "working" })
  local panel = layout()[1]
  local row
  for i, l in ipairs(panel_lines()) do
    if l:find("b_deleted.txt", 1, true) then
      row = i
    end
  end
  vim.api.nvim_win_set_cursor(panel, { row, 0 })
  feed("l")
  check(
    "q: the deleted file's pane is a scratch buffer",
    vim.api.nvim_buf_get_name(0):find("vcs://deleted", 1, true) ~= nil,
    vim.api.nvim_buf_get_name(0)
  )
  local tabs = #vim.api.nvim_list_tabpages()
  feed("q")
  eq("q: closes the view from a scratch diff pane", tabs - 1, #vim.api.nvim_list_tabpages())
end

--------------------------------------------------------------------------
-- ?: the cheat sheet
--------------------------------------------------------------------------

do
  open_settled({ scope = "working" })
  local function floats()
    local n = 0
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_config(w).relative ~= "" then
        n = n + 1
      end
    end
    return n
  end
  eq("help: no float before ?", 0, floats())
  feed("?")
  eq("help: ? opens the cheat sheet", 1, floats())
  local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  check("help: it mentions the scroll keys", text:find("J / K", 1, true) ~= nil, text)
  feed("q")
  eq("help: q closes it again", 0, floats())
  ui.close()
end

--------------------------------------------------------------------------
-- revalidation: coming back to the tab re-asks the backend
--------------------------------------------------------------------------

do
  open_settled({ scope = "working" })
  vim.cmd("tabnew")
  write(root .. "/f_while_away.txt", "made in another tab\n")
  vim.cmd("tabclose") -- drops back into the diff tab, firing TabEnter
  vim.wait(3000, function()
    return vim.tbl_contains(panel_lines(), " ?  f_while_away.txt")
  end)
  check(
    "revalidate: returning to the tab picks up outside changes",
    vim.tbl_contains(panel_lines(), " ?  f_while_away.txt"),
    vim.inspect(panel_lines())
  )
  ui.close()
  vim.fn.delete(root .. "/f_while_away.txt")
end

--------------------------------------------------------------------------
-- a: stage / unstage
--------------------------------------------------------------------------

do
  local function staged()
    return vim.trim(git(root, "diff", "--cached", "--name-only", "--", "a_modified.txt")) ~= ""
  end
  open_settled({ scope = "working" })
  local panel = layout()[1]
  local row
  for i, l in ipairs(panel_lines()) do
    if l:find("a_modified.txt", 1, true) then
      row = i
    end
  end
  vim.api.nvim_win_set_cursor(panel, { row, 0 })
  check("stage: starts unstaged", not staged())
  feed("a")
  vim.wait(3000, staged)
  check("stage: a stages the file", staged())
  feed("a")
  vim.wait(3000, function()
    return not staged()
  end)
  check("stage: a again unstages it", not staged())
  ui.close()
end

--------------------------------------------------------------------------
-- X: revert the selected file
--------------------------------------------------------------------------

do
  write(root .. "/revert_me.txt", "keep\n")
  git(root, "add", "revert_me.txt")
  git(root, "commit", "-qm", "revert fixture")
  write(root .. "/revert_me.txt", "keep\nlocal edit\n")

  open_settled({ scope = "working" })
  local panel = layout()[1]
  local function row_of(name)
    for i, l in ipairs(panel_lines()) do
      if l:find(name, 1, true) then
        return i
      end
    end
  end
  local row = row_of("revert_me.txt")
  check("revert: fixture is listed", row ~= nil, vim.inspect(panel_lines()))
  vim.api.nvim_win_set_cursor(panel, { row, 0 })
  ui.revert_current({ force = true })
  vim.wait(3000, function()
    return not ui.busy() and row_of("revert_me.txt") == nil
  end)
  eq("revert: X restores the base content", { "keep" }, vim.fn.readfile(root .. "/revert_me.txt"))
  check("revert: the listing drops the file", row_of("revert_me.txt") == nil, vim.inspect(panel_lines()))

  -- On an untracked file, reverting means deleting it.
  row = row_of("e_new.txt")
  check("revert: untracked fixture is listed", row ~= nil, vim.inspect(panel_lines()))
  vim.api.nvim_win_set_cursor(panel, { row, 0 })
  ui.revert_current({ force = true })
  vim.wait(3000, function()
    return not ui.busy() and vim.fn.filereadable(root .. "/e_new.txt") == 0
  end)
  eq("revert: X deletes an untracked file", 0, vim.fn.filereadable(root .. "/e_new.txt"))
  ui.close()
end

--------------------------------------------------------------------------
-- closing when the view is the only tab left
--------------------------------------------------------------------------

do
  open_settled({ scope = "working" })
  vim.cmd("tabonly") -- the origin tab is gone; the view is the last tab
  local ok = pcall(ui.close)
  check("last tab: close does not raise E784", ok)
  eq("last tab: one clean tab remains", 1, #vim.api.nvim_list_tabpages())
  check(
    "last tab: the panel is gone",
    not vim.api.nvim_buf_get_name(0):find("vcs://changes", 1, true),
    vim.api.nvim_buf_get_name(0)
  )
  -- And the view is not stuck: it opens again as if nothing happened.
  open_settled({ scope = "working" })
  eq("last tab: reopening works", 2, #vim.api.nvim_list_tabpages())
  ui.close()
end

--------------------------------------------------------------------------
-- two diffs of the same file must not fight over the scratch buffer name
--------------------------------------------------------------------------

do
  vim.cmd("edit " .. vim.fn.fnameescape(root .. "/a_modified.txt"))
  ui.file_diff("working")
  local first_left = win_name(layout()[1])
  vim.cmd("tabprevious")
  ui.file_diff("working")
  local second_left = win_name(layout()[1])
  check("scratch: first base pane is named", first_left:find("vcs://", 1, true) ~= nil, first_left)
  check("scratch: second base pane is named too", second_left:find("vcs://", 1, true) ~= nil, second_left)
  check("scratch: the names differ", first_left ~= second_left, second_left)
  vim.cmd("tabclose")
  vim.cmd("tabclose")
end

--------------------------------------------------------------------------
-- m: merge view straight from the list
--------------------------------------------------------------------------

do
  write(root .. "/conflicted.txt", "<<<<<<< ours\nmine\n=======\ntheirs\n>>>>>>> theirs\n")
  open_settled({ scope = "working" })
  local panel = layout()[1]
  local row
  for i, l in ipairs(panel_lines()) do
    if l:find("conflicted.txt", 1, true) then
      row = i
    end
  end
  vim.api.nvim_win_set_cursor(panel, { row, 0 })
  local tabs = #vim.api.nvim_list_tabpages()
  feed("m")
  eq("merge: m opens the merge view in its own tab", tabs + 1, #vim.api.nvim_list_tabpages())
  eq("merge: three panes", 3, #vim.api.nvim_tabpage_list_wins(0))
  vim.cmd("tabclose")
  ui.close()
  vim.fn.delete(root .. "/conflicted.txt")
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
