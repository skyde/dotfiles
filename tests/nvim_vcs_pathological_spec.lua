-- Run with: nvim --headless -u NONE -i NONE -l tests/nvim_vcs_pathological_spec.lua
--
-- The diff UI against the files a real checkout is actually full of, rather than
-- the tidy three-line text files the other specs use: binaries, generated files
-- with quarter-megabyte lines, CRLF from a Windows branch, a file with no
-- trailing newline, one deleted from disk, an empty one, and paths with spaces
-- and non-ASCII characters in them.
--
-- None of these is exotic in a Chromium tree, and every one of them reaches a
-- different corner of the render path — extmark placement, the stats pass, the
-- base fetch, filetype detection. The bar here is deliberately low and absolute:
-- rendering must not raise, and the panel must still describe the listing
-- correctly afterwards. A diff of a .png is not meaningful; a stack trace in the
-- middle of a review is a great deal worse.
--
-- Plugin-free, like the other specs.

local source = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(repo .. "/common/.config/nvim")

-- A realistic terminal, so the layout code runs for real.
vim.o.columns = 200
vim.o.lines = 50
-- What config/options.lua sets, since CRLF handling depends on it.
vim.opt.fileformats = { "unix", "dos" }

local vcs = require("util.vcs")
local ui = require("util.vcs_ui")
local inline_diff = require("util.inline_diff")

local passed, failed = 0, 0
local failures = {}

local function check(name, ok, detail)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    table.insert(failures, name)
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

---Write raw bytes, so CRLF and NUL survive.
local function write_bytes(path, bytes)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local fd = assert(io.open(path, "wb"))
  fd:write(bytes)
  fd:close()
end

--------------------------------------------------------------------------
-- the repository
--------------------------------------------------------------------------

local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")
local root = vim.fn.resolve(temp .. "/patho")
vim.fn.mkdir(root, "p")
git(root, "init", "-q", "-b", "main")

-- A quarter-megabyte single line: what a generated or minified file looks like,
-- and far past the intraline-diff guard in util.inline_diff.
local LONG = string.rep("x", 250000)
-- Past STATS_MAX_LINES (20000), so the panel's +n -n pass has to bail out.
local MANY = {}
for i = 1, 25000 do
  MANY[i] = "line " .. i
end

write_bytes(root .. "/crlf.txt", "alpha\r\nbeta\r\ngamma\r\n")
write_bytes(root .. "/nonl.txt", "no trailing newline")
write_bytes(root .. "/blob.png", "\137PNG\r\n\26\n\0\1binary\0data\n")
write_bytes(root .. "/long.txt", LONG .. "\n")
write_bytes(root .. "/many.txt", table.concat(MANY, "\n") .. "\n")
write_bytes(root .. "/empty.txt", "")
write_bytes(root .. "/deleted.txt", "here for now\n")
write_bytes(root .. "/a file with spaces ünïcode.txt", "one\ntwo\n")
git(root, "add", "-A")
git(root, "commit", "-qm", "initial")

-- Now change every one of them, each in the way that stresses its own corner.
write_bytes(root .. "/crlf.txt", "alpha\r\nBETA\r\ngamma\r\n")
write_bytes(root .. "/nonl.txt", "no trailing newline, edited")
write_bytes(root .. "/blob.png", "\137PNG\r\n\26\n\0\1BINARY\0data\n")
write_bytes(root .. "/long.txt", LONG:gsub("^xxxx", "yyyy") .. "\n")
MANY[12345] = "line 12345 edited"
write_bytes(root .. "/many.txt", table.concat(MANY, "\n") .. "\n")
write_bytes(root .. "/empty.txt", "no longer empty\n")
assert(os.remove(root .. "/deleted.txt"))
write_bytes(root .. "/a file with spaces ünïcode.txt", "one\nTWO\n")
-- And one file that never existed at the base revision.
write_bytes(root .. "/untracked binary.bin", "\0\1\2\3\255\254\n")

vim.cmd("cd " .. vim.fn.fnameescape(root))
vcs.clear_cache()

local function settle()
  vim.wait(8000, function()
    return not ui.busy()
  end)
end

local function panel_win()
  return vim.api.nvim_tabpage_list_wins(0)[1]
end

-- Rendering happens on a coroutine behind vcs.async, and every path there wraps
-- itself in pcall and reports a failure through vim.notify rather than letting
-- it escape — which is right for a UI and useless for a test: a pcall around
-- the walk below can never see a broken render. Watch the notifications
-- instead, which is the only place the failure actually surfaces.
local notified_errors = {}
local real_notify = vim.notify
vim.notify = function(msg, level, opts)
  if level == vim.log.levels.ERROR then
    table.insert(notified_errors, tostring(msg))
  end
  return real_notify(msg, level, opts)
end

---Errors notified since the last call, and reset.
local function drain_errors()
  local seen = table.concat(notified_errors, " | ")
  notified_errors = {}
  return seen
end

local function panel_lines()
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(panel_win()), 0, -1, false)
end

--------------------------------------------------------------------------
-- the listing
--------------------------------------------------------------------------

local EXPECTED = {
  "a file with spaces ünïcode.txt",
  "blob.png",
  "crlf.txt",
  "deleted.txt",
  "empty.txt",
  "long.txt",
  "many.txt",
  "nonl.txt",
  "untracked binary.bin",
}

do
  local backend, detected = vcs.detect(root)
  eq("detected as git", "git", backend and backend.name)
  local listed = {}
  for _, f in ipairs(backend.changed(detected, backend.rev(detected, "working"))) do
    table.insert(listed, f.path)
  end
  table.sort(listed)
  eq("every pathological file is listed", EXPECTED, listed)
end

do
  local ok, err = pcall(ui.open, { scope = "working" })
  check("open: does not raise on a listing full of them", ok, tostring(err))
  settle()
  local lines = panel_lines()
  check("open: the panel header counts them all", lines[2] and lines[2]:find("of 9", 1, true) ~= nil, lines[2])
end

--------------------------------------------------------------------------
-- rendering each of them, in both renderings
--------------------------------------------------------------------------

---Panel line numbers of the file rows, so the walk does not depend on how the
---tree happens to be laid out.
local function file_rows()
  local rows = {}
  for i, line in ipairs(panel_lines()) do
    -- " M  name", " D  name", " ?  name" — a status letter in the left column.
    if line:match("^ [MAD?RC]  %S") then
      table.insert(rows, i)
    end
  end
  return rows
end

for _, inline in ipairs({ true, false }) do
  local label = inline and "inline" or "side-by-side"
  ui.close()
  vcs.clear_cache()
  ui.open({ scope = "working" })
  settle()
  if not inline then
    ui.toggle_inline()
    settle()
  end

  local rows = file_rows()
  eq(("%s: all nine files have a row"):format(label), 9, #rows)

  local rendered = 0
  for _, row in ipairs(rows) do
    local pw = panel_win()
    vim.api.nvim_set_current_win(pw)
    vim.api.nvim_win_set_cursor(pw, { row, 0 })
    -- [MAD?RC], not %a: `?` is a status code and is not a letter, so a
    -- letters-only pattern leaves it stuck to the front of the filename.
    local name = vim.trim((panel_lines()[row] or ""):gsub("^ [MAD?RC]  ", ""))
    -- Drive it the way the cursor does, so the debounce and the async base
    -- fetch run exactly as they would for a person holding `j`.
    drain_errors()
    local ok, err = pcall(function()
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = vim.api.nvim_win_get_buf(pw) })
      vim.wait(300)
      settle()
    end)
    local reported = drain_errors()

    -- Two independent checks, on purpose. Watching vim.notify catches a render
    -- that threw — but only while something is still reporting it, and a change
    -- that quietly stopped reporting would make every assertion here vacuous.
    -- So also assert the render actually landed: some pane in the tab must be
    -- showing *this* file, by name, whether that is the real buffer or the
    -- vcs:// scratch a deleted file gets.
    -- "Shows the file" is not enough on its own: render_inline puts the buffer
    -- in the window before it attaches the overlay, so a pane can carry the
    -- right file with the diff half-built. Assert the rendering itself — the
    -- overlay attached inline, two diffed panes side-by-side.
    local showing, dressed = false, false
    local diffed = 0
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if w ~= panel_win() then
        local buf = vim.api.nvim_win_get_buf(w)
        local pane = vim.api.nvim_buf_get_name(buf)
        if pane:find(name, 1, true) then
          showing = true
          if not inline then
            dressed = vim.wo[w].diff
          elseif pane:find("vcs://deleted/", 1, true) then
            -- Nothing on disk to overlay: the inline rendering of a deleted
            -- file is its old content, struck through. Correct when the pane
            -- actually holds that content rather than an empty scratch.
            dressed = #vim.api.nvim_buf_get_lines(buf, 0, -1, false) > 0
              and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] ~= ""
          else
            dressed = inline_diff.has(buf)
          end
        end
        if vim.wo[w].diff then
          diffed = diffed + 1
        end
      end
    end
    if not inline then
      -- Both halves, not just the one holding the file.
      dressed = dressed and diffed == 2
    end

    check(("%s: renders %s"):format(label, name), ok and reported == "", ok and reported or tostring(err))
    check(("%s: a pane actually shows %s"):format(label, name), showing, "panes did not name it")
    check(
      ("%s: %s is really diffed, not just displayed"):format(label, name),
      dressed,
      inline and "no inline overlay attached" or ("diffed panes: " .. diffed)
    )
    if ok and reported == "" and showing and dressed then
      rendered = rendered + 1
    end
    check(
      ("%s: the view survives %s"):format(label, name),
      #vim.api.nvim_tabpage_list_wins(0) >= 2,
      "windows: " .. #vim.api.nvim_tabpage_list_wins(0)
    )
  end
  eq(("%s: rendered every file"):format(label), 9, rendered)
end

--------------------------------------------------------------------------
-- what the panel says about the awkward ones
--------------------------------------------------------------------------

do
  ui.close()
  vcs.clear_cache()
  ui.open({ scope = "working" })
  settle()
  -- The prefetch fills stats for everything it can; a file past
  -- STATS_MAX_LINES is deliberately given zeros rather than left nil, so it is
  -- not re-judged on every sweep.
  local text = table.concat(panel_lines(), "\n")
  check("panel: still readable after the stats pass", text:find("many.txt", 1, true) ~= nil, text)
  check("panel: names the file with spaces and non-ASCII", text:find("ünïcode.txt", 1, true) ~= nil, text)
  check("panel: the deleted file is marked D", text:find(" D  deleted.txt", 1, true) ~= nil, text)
  check("panel: the untracked binary is marked ?", text:find(" ?  untracked binary.bin", 1, true) ~= nil, text)
end

--------------------------------------------------------------------------
-- CRLF must not read as "every line changed"
--------------------------------------------------------------------------

do
  -- Three different reads of the same file feed the diff: `git show` for the
  -- base, readfile() for the stats of an unopened file, and the buffer itself.
  -- If any one of them keeps the carriage returns the other two drop, a file
  -- from a Windows branch diffs as wholly rewritten.
  local backend, detected = vcs.detect(root)
  local base = backend.show(detected, backend.rev(detected, "working"), "crlf.txt")
  eq("crlf: git show strips the carriage returns", { "alpha", "beta", "gamma" }, base)
  eq("crlf: readfile agrees with it", { "alpha", "BETA", "gamma" }, vim.fn.readfile(root .. "/crlf.txt"))
  vim.cmd("edit " .. vim.fn.fnameescape(root .. "/crlf.txt"))
  eq("crlf: the buffer agrees too", "dos", vim.bo.fileformat)
  eq("crlf: and holds the same lines", { "alpha", "BETA", "gamma" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
end

--------------------------------------------------------------------------

ui.close()
check("nothing was reported as an error along the way", drain_errors() == "", drain_errors())
vim.notify = real_notify
vim.fn.delete(temp, "rf")

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  error("\n" .. table.concat(failures, "\n"))
end
