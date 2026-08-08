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
-- Names that are pattern syntax to one backend or another: `*`, `?` and `[` are
-- glob characters in a git pathspec, a leading `:` introduces pathspec magic,
-- `(` and `)` are operators in a jj fileset, and `{` is where jj compacts a
-- rename. Every one of them is an ordinary filename that a real tree has.
write_bytes(root .. "/star*.txt", "one\ntwo\n")
write_bytes(root .. "/:colon.txt", "one\ntwo\n")
write_bytes(root .. "/report (1).txt", "one\ntwo\n")
write_bytes(root .. "/brace{x}.txt", "one\ntwo\n")
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
for _, name in ipairs({ "star*.txt", ":colon.txt", "report (1).txt", "brace{x}.txt" }) do
  write_bytes(root .. "/" .. name, "one\nTWO\n")
end
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
  ":colon.txt",
  "a file with spaces ünïcode.txt",
  "blob.png",
  "brace{x}.txt",
  "crlf.txt",
  "deleted.txt",
  "empty.txt",
  "long.txt",
  "many.txt",
  "nonl.txt",
  "report (1).txt",
  "star*.txt",
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
  check("open: the panel header counts them all", lines[2] and lines[2]:find("of 13", 1, true) ~= nil, lines[2])
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
  eq(("%s: every file has a row"):format(label), #EXPECTED, #rows)

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
  eq(("%s: rendered every file"):format(label), #EXPECTED, rendered)
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
-- browsing leaves no trace, however long you browse
--------------------------------------------------------------------------

do
  -- The view's central promise, and by the module's own account a bug it once
  -- had: scrubbing the list must not accumulate open files. One pass proves
  -- little — a leak of one buffer per cycle looks like a correct render — so
  -- run the whole loop repeatedly and require the counts to come back to
  -- exactly where they started.
  local function census()
    local listed, unlisted, scratch = 0, 0, 0
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(b) then
        local name = vim.api.nvim_buf_get_name(b)
        if name:match("^vcs://") or name:match("^merge://") then
          scratch = scratch + 1
        elseif vim.fn.buflisted(b) == 1 then
          listed = listed + 1
        else
          unlisted = unlisted + 1
        end
      end
    end
    return { listed = listed, unlisted = unlisted, scratch = scratch, tabs = #vim.api.nvim_list_tabpages() }
  end

  ui.close()
  vcs.clear_cache()
  drain_errors()
  local baseline = census()

  -- "At most one looked-at file is ever loaded", in the module's own words.
  -- Counted *during* the scrub, not after: close() cleans up every preview it
  -- tracked, so a leak that accumulates while the view is open — the one the
  -- module says it used to have — is invisible to a census taken afterwards.
  local peak_loaded = 0
  local function count_loaded()
    local loaded = 0
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_name(b):find(root, 1, true) then
        loaded = loaded + 1
      end
    end
    peak_loaded = math.max(peak_loaded, loaded)
  end

  for cycle = 1, 6 do
    ui.open({ scope = "working" })
    settle()
    local pw = panel_win()
    for _, row in ipairs(file_rows()) do
      vim.api.nvim_set_current_win(pw)
      pcall(vim.api.nvim_win_set_cursor, pw, { row, 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = vim.api.nvim_win_get_buf(pw) })
      vim.wait(120)
      count_loaded()
    end
    -- Alternate the rendering, so both paths' buffers get created and dropped.
    if cycle % 2 == 0 then
      ui.toggle_inline()
      settle()
    end
    ui.close()
    vim.wait(200)
  end
  settle()

  local after = census()
  eq("no trace: the buffer list is where it started", baseline, after)
  check(
    "no trace: never more than one looked-at file loaded at a time",
    peak_loaded <= 1,
    "peak loaded repo buffers: " .. peak_loaded
  )
  check("no trace: and nothing was reported along the way", drain_errors() == "", drain_errors())
end

--------------------------------------------------------------------------
-- the view survives being driven at random
--------------------------------------------------------------------------

do
  -- open, refresh, close, scope-switch and the two toggles all bump generation
  -- counters that orphan work already in flight, and the base cache has an
  -- epoch of its own. Interleaving them without letting the async work finish
  -- is what exercises those guards; the assertion is simply that none of it
  -- raises and the view is still usable at the end.
  ui.close()
  vcs.clear_cache()
  drain_errors()

  local raised = {}
  math.randomseed(11)
  local ops = { "open", "refresh", "close", "scrub", "inline", "collapse", "scope" }
  local scopes = { "working", "branch", "head" }
  for _ = 1, 80 do
    local op = ops[math.random(#ops)]
    local ok, err = pcall(function()
      if op == "open" then
        ui.open({ scope = "working" })
      elseif op == "refresh" then
        ui.refresh()
      elseif op == "close" then
        ui.close()
      elseif op == "inline" then
        ui.toggle_inline()
      elseif op == "collapse" then
        ui.toggle_collapse()
      elseif op == "scope" then
        ui.open({ scope = scopes[math.random(#scopes)] })
      elseif op == "scrub" then
        local pw = vim.api.nvim_tabpage_list_wins(0)[1]
        if pw and vim.api.nvim_win_is_valid(pw) then
          local b = vim.api.nvim_win_get_buf(pw)
          pcall(vim.api.nvim_win_set_cursor, pw, { math.random(vim.api.nvim_buf_line_count(b)), 0 })
          vim.api.nvim_exec_autocmds("CursorMoved", { buffer = b })
        end
      end
    end)
    if not ok then
      table.insert(raised, ("%s: %s"):format(op, tostring(err)))
    end
    -- Deliberately not settling: half-finished async work is the point.
    vim.wait(math.random(0, 20))
  end
  settle()
  check("random driving: nothing raised", #raised == 0, table.concat(raised, " | "))
  check("random driving: nothing was reported as an error", drain_errors() == "", drain_errors())

  -- And it still works afterwards.
  pcall(ui.close)
  vcs.clear_cache()
  ui.open({ scope = "working" })
  settle()
  check("random driving: the view still opens afterwards", #file_rows() == #EXPECTED, vim.inspect(panel_lines()))
  ui.close()
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
-- `y` on a name that is pattern syntax
--------------------------------------------------------------------------

-- Last, and in its own repository: it commits, which would change the working
-- set every block above reads.
do
  -- The panel's copy key goes through raw_diff, which hands the path to git as
  -- a pathspec. Unescaped, `star*.txt` is a glob, and the copied patch would
  -- carry whatever else the glob matched — silently, into a review comment.
  local glob_root = vim.fn.resolve(temp .. "/globby")
  vim.fn.mkdir(glob_root, "p")
  git(glob_root, "init", "-q", "-b", "main")
  write_bytes(glob_root .. "/star*.txt", "one\ntwo\n")
  write_bytes(glob_root .. "/stars.txt", "one\ntwo\n")
  git(glob_root, "add", "-A")
  git(glob_root, "commit", "-qm", "two names, one of which globs the other")
  write_bytes(glob_root .. "/star*.txt", "one\nSTAR\n")
  write_bytes(glob_root .. "/stars.txt", "one\nSTARS\n")

  -- An in-memory provider, so the + register round-trips without a desktop.
  local copied = { "" }
  local real_clipboard = vim.g.clipboard
  vim.g.clipboard = {
    name = "spec",
    copy = {
      ["+"] = function(lines)
        copied = lines
      end,
      ["*"] = function(lines)
        copied = lines
      end,
    },
    paste = {
      ["+"] = function()
        return copied
      end,
      ["*"] = function()
        return copied
      end,
    },
    cache_enabled = 0,
  }

  ui.close()
  -- Both the working directory and the current buffer: the view detects the
  -- backend from the buffer it was opened over, so a leftover buffer from the
  -- fixture above would quietly point it back at that repository.
  vim.cmd("cd " .. vim.fn.fnameescape(glob_root))
  vim.cmd("edit " .. vim.fn.fnameescape(glob_root .. "/stars.txt"))
  vcs.clear_cache()
  ui.open({ scope = "working" })
  settle()

  local target
  for _, row in ipairs(file_rows()) do
    if (panel_lines()[row] or ""):find("star*.txt", 1, true) then
      target = row
    end
  end
  check("copy: the glob-ish file has a row", target ~= nil, vim.inspect(panel_lines()))

  local pw = panel_win()
  vim.api.nvim_set_current_win(pw)
  vim.api.nvim_win_set_cursor(pw, { target or 1, 0 })
  vim.api.nvim_feedkeys("y", "x", false)
  vim.wait(3000, function()
    return #copied > 1
  end)
  settle()

  local patch = table.concat(copied, "\n")
  check("copy: something was copied", #patch > 0, "the register stayed empty")
  check("copy: the patch names the file asked for", patch:find("star*.txt", 1, true) ~= nil, patch:sub(1, 300))
  check(
    "copy: and nothing the glob would have swept up with it",
    patch:find("stars.txt", 1, true) == nil,
    patch:sub(1, 400)
  )

  vim.g.clipboard = real_clipboard
  ui.close()
  vcs.clear_cache()
  vim.cmd("cd " .. vim.fn.fnameescape(root))
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
