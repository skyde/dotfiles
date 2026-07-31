-- The diff UI that sits on top of util.vcs.
--
-- Layout mirrors the VS Code source-control view that these keys replace: a
-- narrow list of changed files on the left, the diff for the selected file on
-- the right. Moving the cursor in the list re-renders the diff, so `<leader>gc`
-- then j/k is the whole review loop.
--
-- The right-hand side has two renderings, toggled with `<leader>ci`:
--   * side-by-side  native diff mode, so ]c/[c/do/dp all work and the working
--                   copy is a real editable buffer
--   * inline        the unified patch piped through delta, matching
--                   `diffEditor.renderSideBySide: false` from the VS Code setup
--
-- Only one diff tab exists at a time; asking for another reuses it.

local vcs = require("util.vcs")
local inline_diff = require("util.inline_diff")

local M = {}

local PANEL_WIDTH = 42
local ns = vim.api.nvim_create_namespace("vcs_ui")

---@class VcsState
---@field tab integer
---@field panel_win integer
---@field panel_buf integer
---@field origin_tab integer
---@field backend VcsBackend
---@field root string
---@field scope string
---@field rev string
---@field files VcsFile[]
---@field first_line integer
---@field inline boolean
---@field inline_buf integer|nil  buffer currently carrying the inline overlay
---@field base_cache table<string, string[]>
---@field previews table<integer, true>  buffers this view opened and unlisted
local state = nil

local STATUS = {
  M = { icon = "~", hl = "DiffChange", label = "modified" },
  A = { icon = "+", hl = "DiffAdd", label = "added" },
  D = { icon = "-", hl = "DiffDelete", label = "deleted" },
  R = { icon = "»", hl = "DiffChange", label = "renamed" },
  C = { icon = "!", hl = "DiffText", label = "conflict" },
  ["?"] = { icon = "?", hl = "Comment", label = "untracked" },
}

--------------------------------------------------------------------------
-- small helpers
--------------------------------------------------------------------------

local function valid()
  return state ~= nil and vim.api.nvim_tabpage_is_valid(state.tab) and vim.api.nvim_win_is_valid(state.panel_win)
end

---Windows in the diff tab other than the file list.
local function diff_wins()
  local out = {}
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(state.tab)) do
    if w ~= state.panel_win then
      table.insert(out, w)
    end
  end
  return out
end

local function close_diff_wins()
  for _, w in ipairs(diff_wins()) do
    pcall(vim.api.nvim_win_close, w, true)
  end
end

---Pin the panel to its width and split what is left evenly between the diff
---panes. Splitting halves the *current* window each time, so without this the
---two sides come out lopsided.
local function balance(...)
  vim.api.nvim_win_set_width(state.panel_win, PANEL_WIDTH)
  local wins = { ... }
  local available = vim.o.columns - PANEL_WIDTH - #wins
  for _, w in ipairs(wins) do
    if vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim_win_set_width, w, math.floor(available / #wins))
    end
  end
  vim.api.nvim_win_set_width(state.panel_win, PANEL_WIDTH)
end

---A throwaway buffer holding `content`, named so the tabline says something
---useful about which side of the diff it is.
local function scratch(name, content, path)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content or {})
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  pcall(vim.api.nvim_buf_set_name, buf, name)
  if path then
    local ft = vim.filetype.match({ filename = path, buf = buf })
    if ft then
      vim.bo[buf].filetype = ft
    end
  end
  return buf
end

--------------------------------------------------------------------------
-- the file list panel
--------------------------------------------------------------------------

local function render_panel()
  local buf = state.panel_buf
  local scope_label = ({ working = "uncommitted", branch = "since fork point", head = "last commit" })[state.scope]
    or state.scope
  local header = {
    ("%s · %s"):format(state.backend.name, scope_label),
    ("%s · %d file%s"):format(state.rev:sub(1, 12), #state.files, #state.files == 1 and "" or "s"),
    "",
  }
  state.first_line = #header + 1

  local lines = vim.list_extend({}, header)
  for _, file in ipairs(state.files) do
    local meta = STATUS[file.status] or STATUS.M
    table.insert(lines, (" %s  %s"):format(meta.icon, file.path))
  end
  if #state.files == 0 then
    table.insert(lines, " (no changes)")
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { end_col = #lines[1], hl_group = "Title" })
  vim.api.nvim_buf_set_extmark(buf, ns, 1, 0, { end_col = #lines[2], hl_group = "Comment" })
  for i, file in ipairs(state.files) do
    local meta = STATUS[file.status] or STATUS.M
    local row = state.first_line - 1 + i - 1
    vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { end_col = 3, hl_group = meta.hl })
    -- Dim the directory part so the filename is what the eye lands on.
    local dir = file.path:match("^(.*/)")
    if dir then
      vim.api.nvim_buf_set_extmark(buf, ns, row, 4, { end_col = 4 + #dir, hl_group = "Comment" })
    end
  end
end

---The file under the cursor in the panel, or nil on a header line.
local function current_file()
  if not valid() then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(state.panel_win)[1]
  return state.files[row - state.first_line + 1]
end

--------------------------------------------------------------------------
-- rendering one file
--------------------------------------------------------------------------

---Base content for a file, memoised for the lifetime of the current listing.
---Fetching costs a subprocess (tens of milliseconds, and a good deal more on a
---large file), which is worth paying once per file rather than once per visit.
local function base_content(file)
  -- Added and untracked files have no previous version to ask for.
  if file.status == "A" or file.status == "?" then
    return {}
  end
  -- A renamed file's base lives at its old path.
  local base_path = file.orig or file.path
  local key = state.rev .. "\0" .. base_path
  local hit = state.base_cache[key]
  if hit then
    return hit
  end
  local content = state.backend.show(state.root, state.rev, base_path) or {}
  state.base_cache[key] = content
  return content
end

---Diff panes share one look: native diff, folds open, absolute line numbers.
---Splits inherit whatever the window they came from had (the panel has no
---numbers at all, an editing window may have relative ones), and relative
---numbers in a diff make the two sides impossible to line up by eye.
local function diff_pane(w)
  vim.api.nvim_win_call(w, function()
    vim.cmd("diffthis")
    vim.wo.foldlevel = 99
    vim.wo.number = true
    vim.wo.relativenumber = false
  end)
end

---Put the cursor on the first change, the way the VS Code diff editor opens
---scrolled to the first difference rather than the top of the file.
local function goto_first_change(win)
  vim.api.nvim_win_call(win, function()
    if not vim.wo.diff then
      return
    end
    vim.cmd("normal! gg")
    -- `]c` would skip ahead when line 1 is already inside the first hunk.
    if vim.fn.diff_hlID(1, 1) == 0 then
      pcall(vim.cmd, "normal! ]c")
    end
  end)
end

---`edit` a file the way VS Code's preview editors do: scrubbing past a file
---in the changed list must not make it a permanent resident of the buffer
---list. A buffer that was not already open stays unlisted until it is
---actually edited, at which point it earns its place.
local function edit_preview(full)
  local existing = vim.fn.bufnr(full)
  local fresh = existing == -1 or vim.fn.buflisted(existing) == 0
  vim.cmd("edit " .. vim.fn.fnameescape(full))
  local buf = vim.api.nvim_get_current_buf()
  if fresh and not state.previews[buf] then
    state.previews[buf] = true
    vim.bo[buf].buflisted = false
    vim.api.nvim_create_autocmd("BufModifiedSet", {
      buffer = buf,
      callback = function()
        if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified then
          vim.bo[buf].buflisted = true
          return true
        end
      end,
    })
  end
end

---Side-by-side: base on the left as a read-only scratch buffer, the working
---copy on the right as the real file so edits and `do`/`dp` land on disk.
local function render_side_by_side(file)
  local full = state.root .. "/" .. file.path
  local base = base_content(file)
  local base_path = file.orig or file.path

  vim.api.nvim_set_current_win(state.panel_win)

  vim.cmd("vertical rightbelow split")
  local left = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(left, scratch(("vcs://%s/%s"):format(state.rev:sub(1, 12), base_path), base, base_path))

  vim.cmd("vertical rightbelow split")
  local right = vim.api.nvim_get_current_win()
  if vim.fn.filereadable(full) == 1 then
    edit_preview(full)
  else
    vim.api.nvim_win_set_buf(right, scratch(("vcs://deleted/%s"):format(file.path), {}, file.path))
  end

  diff_pane(left)
  diff_pane(right)
  goto_first_change(right)

  balance(left, right)
  return right
end

---Fill `win` with a unified patch, coloured by delta when it is installed so
---it matches what `git diff` looks like in the terminal. Delta's output is
---captured and replayed into a terminal-emulator buffer rather than run as a
---live job: same colours, but no process to accidentally feed keys to and no
---"[Process exited 0]" tail. `keys` adds buffer-local normal-mode maps, so
---each caller decides what q does there.
local function patch_buf(win, text, cwd, keys)
  local buf
  if vim.fn.executable("delta") == 1 then
    local width = vim.api.nvim_win_get_width(win)
    local res = vim
      .system({ "delta", "--paging=never", "--width", tostring(width) }, { stdin = text, cwd = cwd })
      :wait()
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.api.nvim_win_set_buf(win, buf)
    local chan = vim.api.nvim_open_term(buf, {})
    -- The emulator needs carriage returns, not bare line feeds. The extra
    -- parentheses drop gsub's second return value.
    vim.api.nvim_chan_send(chan, ((res.stdout or ""):gsub("\n", "\r\n")))
    -- The emulator processes the bytes asynchronously and follows the output;
    -- put the view back at the top of the patch once it has.
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
        pcall(vim.api.nvim_win_set_cursor, win, { 1, 0 })
      end
    end)
  else
    buf = scratch("vcs://patch", vim.split(text, "\n", { plain = true }))
    vim.bo[buf].filetype = "diff"
    vim.api.nvim_win_set_buf(win, buf)
  end
  for lhs, fn in pairs(keys or {}) do
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  return buf
end

---Inline: the real file with the base version overlaid — deleted lines drawn
---between the lines as virtual text, new lines highlighted. Unlike a rendered
---patch the buffer stays editable, matching what VS Code's diff editor is
---with renderSideBySide off.
local function render_inline(file)
  vim.api.nvim_set_current_win(state.panel_win)
  vim.cmd("vertical rightbelow split")
  local win = vim.api.nvim_get_current_win()

  if not file then
    vim.api.nvim_win_set_buf(win, scratch("vcs://empty", { "(no changes)" }))
    balance(win)
    return win
  end

  local full = state.root .. "/" .. file.path
  local base = base_content(file)

  if vim.fn.filereadable(full) == 1 then
    edit_preview(full)
    local buf = vim.api.nvim_get_current_buf()
    state.inline_buf = buf
    inline_diff.attach(buf, base)
    vim.wo[win].number = true
    vim.wo[win].relativenumber = false
    vim.api.nvim_win_call(win, function()
      inline_diff.goto_first(buf)
    end)
  else
    -- Deleted: nothing on disk to edit, so show what was there, struck red.
    local buf = scratch(("vcs://deleted/%s"):format(file.path), base, file.path)
    vim.api.nvim_win_set_buf(win, buf)
    for row = 0, #base - 1 do
      vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { line_hl_group = "DiffDelete", priority = 50 })
    end
    vim.wo[win].number = true
    vim.wo[win].relativenumber = false
  end

  balance(win)
  return win
end

---Draw the currently selected file. `focus` moves the cursor into the diff;
---leaving it false keeps the cursor in the list so j/k keeps scrubbing.
local function show(focus)
  if not valid() then
    return
  end
  local file = current_file()
  if state.inline_buf then
    inline_diff.detach(state.inline_buf)
    state.inline_buf = nil
  end
  close_diff_wins()

  local target
  if state.inline then
    target = render_inline(file)
  elseif file then
    target = render_side_by_side(file)
  else
    vim.api.nvim_set_current_win(state.panel_win)
    vim.cmd("vertical rightbelow split")
    target = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(target, scratch("vcs://empty", { "" }))
    balance(target)
  end

  vim.api.nvim_set_current_win(focus and target or state.panel_win)
end

--------------------------------------------------------------------------
-- panel construction
--------------------------------------------------------------------------

-- Rendering a diff costs a subprocess and a window rebuild. Doing that on every
-- keystroke makes holding `j` through a large changelist unusable, so cursor
-- movement is immediate and the diff catches up once the keys stop.
local SCRUB_DELAY_MS = 80
local scrub_timer = nil

local function cancel_scrub()
  if scrub_timer then
    scrub_timer:stop()
    scrub_timer:close()
    scrub_timer = nil
  end
end

local function move(delta)
  local row = vim.api.nvim_win_get_cursor(state.panel_win)[1] + delta
  row = math.max(state.first_line, math.min(row, state.first_line + math.max(#state.files, 1) - 1))
  vim.api.nvim_win_set_cursor(state.panel_win, { row, 0 })

  cancel_scrub()
  scrub_timer = vim.uv.new_timer()
  scrub_timer:start(
    SCRUB_DELAY_MS,
    0,
    vim.schedule_wrap(function()
      cancel_scrub()
      -- If focus moved on in the meantime — into the diff, another tab, a
      -- picker — a late render would yank it back to the panel.
      if valid() and vim.api.nvim_get_current_win() == state.panel_win then
        show(false)
      end
    end)
  )
end

local function setup_panel_keys(buf)
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  map("j", function()
    move(1)
  end, "Next changed file")
  map("<Down>", function()
    move(1)
  end, "Next changed file")
  map("k", function()
    move(-1)
  end, "Previous changed file")
  map("<Up>", function()
    move(-1)
  end, "Previous changed file")
  map("<CR>", function()
    show(true)
  end, "Open diff")
  map("o", function()
    show(true)
  end, "Open diff")
  map("<Tab>", function()
    show(true)
  end, "Focus diff")
  map("R", function()
    M.refresh()
  end, "Refresh")
  map("q", function()
    M.close()
  end, "Close diff view")
  map("i", function()
    M.toggle_inline()
  end, "Toggle inline diff")
  -- Cycling the scope in place is much faster than closing and re-opening with
  -- a different key when you realise you wanted the whole branch, not just the
  -- uncommitted part.
  map("s", function()
    local next_scope = ({ working = "branch", branch = "head", head = "working" })[state.scope]
    M.open({ scope = next_scope })
  end, "Cycle scope")
end

---Create (or reuse) the diff tab.
local function ensure_tab()
  if valid() then
    vim.api.nvim_set_current_tabpage(state.tab)
    return
  end
  local origin = vim.api.nvim_get_current_tabpage()
  vim.cmd("tabnew")
  -- `tabnew` leaves an empty unnamed buffer behind once the panel replaces it,
  -- which then sits in the bufferline as "[No Name]".
  local leftover = vim.api.nvim_get_current_buf()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "vcschanges"
  vim.bo[buf].modifiable = false
  pcall(vim.api.nvim_buf_set_name, buf, "vcs://changes")

  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  if vim.api.nvim_buf_is_valid(leftover) and vim.api.nvim_buf_get_name(leftover) == "" then
    pcall(vim.api.nvim_buf_delete, leftover, { force = true })
  end
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].winfixwidth = true

  state = state or {}
  state.tab = vim.api.nvim_get_current_tabpage()
  state.panel_win = win
  state.panel_buf = buf
  state.origin_tab = origin
  state.inline = state.inline or false
  state.previews = state.previews or {}

  setup_panel_keys(buf)
end

--------------------------------------------------------------------------
-- public API
--------------------------------------------------------------------------

---Open the changed-files view.
---@param opts? { scope?: string, rev?: string }
function M.open(opts)
  opts = opts or {}
  local backend, root = vcs.require()
  if not backend then
    return
  end

  local scope = opts.scope or (state and state.scope) or "working"
  local rev = opts.rev or backend.rev(root, scope)
  if not rev then
    vim.notify(("Could not resolve a base revision for %s"):format(backend.name), vim.log.levels.WARN)
    return
  end

  cancel_scrub()
  ensure_tab()
  state.backend, state.root, state.scope, state.rev = backend, root, scope, rev
  state.base_cache = {}
  state.files = backend.changed(root, rev)
  table.sort(state.files, function(a, b)
    return a.path < b.path
  end)

  render_panel()
  vim.api.nvim_win_set_cursor(state.panel_win, { state.first_line, 0 })
  show(false)
end

function M.refresh()
  if valid() then
    M.open({ scope = state.scope })
  end
end

function M.close()
  cancel_scrub()
  local previews = state and state.previews or {}
  if state and state.inline_buf then
    inline_diff.detach(state.inline_buf)
    state.inline_buf = nil
  end
  if valid() then
    vim.api.nvim_set_current_tabpage(state.tab)
    vim.cmd("tabclose")
  end
  state = nil
  -- Drop the buffers that only existed because they were scrubbed past.
  -- Anything the user actually touched has been re-listed and is kept.
  for buf in pairs(previews) do
    if vim.api.nvim_buf_is_valid(buf) and not vim.bo[buf].modified and vim.fn.buflisted(buf) == 0 then
      pcall(vim.api.nvim_buf_delete, buf, {})
    end
  end
end

---Diff just the current buffer's file, without the file list.
---@param scope string
function M.file_diff(scope)
  local backend, root = vcs.require()
  if not backend then
    return
  end
  local path = vcs.rel_path(root)
  if not path then
    vim.notify("Current buffer is not a file inside the repository", vim.log.levels.WARN)
    return
  end
  local rev = backend.rev(root, scope)
  local base = backend.show(root, rev, path)
  if not base then
    vim.notify(("%s has no version at %s (new file?)"):format(path, rev:sub(1, 12)), vim.log.levels.INFO)
    base = {}
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  vim.cmd("tab split")
  local right = vim.api.nvim_get_current_win()
  vim.cmd("leftabove vertical split")
  local left = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(left, scratch(("vcs://%s/%s"):format(rev:sub(1, 12), path), base, path))

  diff_pane(left)
  diff_pane(right)
  vim.api.nvim_set_current_win(right)
  pcall(vim.api.nvim_win_set_cursor, right, { line, 0 })
end

---Swap between the side-by-side and the delta-rendered inline patch.
function M.toggle_inline()
  if valid() then
    state.inline = not state.inline
    show(false)
    return
  end
  -- Outside the diff tab this is still the natural "show me the other layout"
  -- key: flip vertical/horizontal split on an ad-hoc diff.
  if vim.wo.diff then
    vim.cmd("wincmd " .. (vim.fn.winwidth(0) > vim.fn.winheight(0) * 3 and "K" or "H"))
  end
end

---Move between the two sides of whatever diff is focused.
function M.switch_side()
  if not vim.wo.diff then
    return false
  end
  local start = vim.api.nvim_get_current_win()
  for _ = 1, #vim.api.nvim_tabpage_list_wins(0) do
    vim.cmd("wincmd w")
    if vim.wo.diff and vim.api.nvim_get_current_win() ~= start then
      return true
    end
  end
  return true
end

---From a diff, jump to the real file on disk in the tab you came from.
function M.goto_file()
  local name = vim.api.nvim_buf_get_name(0)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local path = name:match("^vcs://[^/]*/(.*)$")

  local _, root = vcs.detect()
  local full
  if path and root then
    full = root .. "/" .. path
  elseif name ~= "" and not name:match("^%a[%w+.-]*://") then
    full = name
  end
  if not full or vim.fn.filereadable(full) == 0 then
    vim.notify("No file on disk for this buffer", vim.log.levels.WARN)
    return
  end

  if valid() and vim.api.nvim_get_current_tabpage() == state.tab then
    local origin = state.origin_tab
    M.close()
    if origin and vim.api.nvim_tabpage_is_valid(origin) then
      vim.api.nvim_set_current_tabpage(origin)
    end
  elseif vim.wo.diff and vim.fn.tabpagenr("$") > 1 then
    -- An ad-hoc diff tab (<leader>gd, history): leave the whole tab, not just
    -- this half of the diff.
    vim.cmd("tabclose")
  end
  vim.cmd("edit " .. vim.fn.fnameescape(full))
  pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
end

---The whole patch for a scope, in one buffer, delta-coloured.
---@param scope string
function M.patch(scope)
  local backend, root = vcs.require()
  if not backend then
    return
  end
  local rev = backend.rev(root, scope)
  local text = backend.raw_diff(root, rev, nil)
  if text == "" then
    vim.notify("No changes", vim.log.levels.INFO)
    return
  end

  vim.cmd("tabnew")
  local win = vim.api.nvim_get_current_win()
  local leftover = vim.api.nvim_get_current_buf()
  patch_buf(win, text, root, {
    q = function()
      if vim.fn.tabpagenr("$") > 1 then
        vim.cmd("tabclose")
      else
        vim.cmd("enew")
      end
    end,
  })
  -- Drop the empty buffer `tabnew` left behind, so it does not sit in the
  -- bufferline as "[No Name]".
  if vim.api.nvim_buf_is_valid(leftover) and vim.api.nvim_buf_get_name(leftover) == "" then
    pcall(vim.api.nvim_buf_delete, leftover, { force = true })
  end
end

---Copy the patch for a scope to the system clipboard.
---@param scope string
function M.copy_patch(scope)
  local backend, root = vcs.require()
  if not backend then
    return
  end
  local text = backend.raw_diff(root, backend.rev(root, scope), nil)
  if text == "" then
    vim.notify("No changes to copy", vim.log.levels.INFO)
    return
  end
  vim.fn.setreg("+", text)
  local count = select(2, text:gsub("\n", "\n"))
  vim.notify(("Copied %d-line %s diff"):format(count, backend.name))
end

---Revision history for the current file; picking one diffs it against now.
function M.history()
  local backend, root = vcs.require()
  if not backend then
    return
  end
  local path = vcs.rel_path(root)
  if not path then
    vim.notify("Current buffer is not a file inside the repository", vim.log.levels.WARN)
    return
  end
  local entries = backend.log(root, path)
  if #entries == 0 then
    vim.notify(("No %s history for %s"):format(backend.name, path), vim.log.levels.INFO)
    return
  end

  vim.ui.select(entries, {
    prompt = ("History: %s"):format(path),
    format_item = function(e)
      return ("%s  %s  %s  %s"):format(e.rev:sub(1, 10), e.date, e.author, e.subject)
    end,
  }, function(choice)
    if not choice then
      return
    end
    local base = backend.show(root, choice.rev, path)
    if not base then
      vim.notify(("%s does not exist at %s"):format(path, choice.rev:sub(1, 10)), vim.log.levels.WARN)
      return
    end
    vim.cmd("tab split")
    local right = vim.api.nvim_get_current_win()
    vim.cmd("leftabove vertical split")
    local left = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(left, scratch(("vcs://%s/%s"):format(choice.rev:sub(1, 10), path), base, path))
    diff_pane(left)
    diff_pane(right)
    vim.api.nvim_set_current_win(right)
    goto_first_change(right)
  end)
end

---Open whichever TUI fits the detected backend.
function M.tui()
  local backend, root = vcs.detect()
  local cwd = root or vim.fn.getcwd()
  local candidates = {
    jj = { "lazyjj", "jjui" },
    p4 = { "p4v" },
    g4 = { "p4v" },
  }
  for _, cmd in ipairs(candidates[backend and backend.name or ""] or {}) do
    if vim.fn.executable(cmd) == 1 then
      require("snacks").terminal(cmd, { cwd = cwd })
      return
    end
  end
  -- Nothing backend-specific installed; lazygit still works in a colocated jj
  -- repo and is the sane default everywhere else.
  require("snacks").lazygit({ cwd = cwd })
end

return M
