-- The diff UI that sits on top of util.vcs.
--
-- Layout mirrors the VS Code source-control view that these keys replace: a
-- narrow tree of changed files on the left, the diff for the selected file on
-- the right. Moving the cursor in the list re-renders the diff, so `<leader>gc`
-- then j/k is the whole review loop.
--
-- The right-hand side has two renderings, toggled with `<leader>ci`:
--   * side-by-side  native diff mode, so ]c/[c/do/dp all work and the working
--                   copy is a real editable buffer
--   * inline        the unified patch piped through delta, matching
--                   `diffEditor.renderSideBySide: false` from the VS Code setup
--
-- Browsing leaves no trace: the working side is always the real, editable
-- buffer, opened as an unlisted preview — and the moment the view moves off
-- a file, that preview is deleted again unless it carries unsaved edits. At
-- most one looked-at file is ever loaded, and closing the view drops that
-- too (surfacing anything edited into the buffer list). The view also folds
-- itself away before a session is written (VimLeavePre / PersistenceSavePre),
-- since a session that captured the diff tab would restore it as junk.
--
-- Everything a backend says is remembered across opens of the view (the
-- listing per scope, base content per file), so `<leader>gc` in a large or
-- server-backed repository paints instantly from the last known state and
-- revalidates in the background instead of blocking on subprocesses.
--
-- Only one diff tab exists at a time; asking for another reuses it.

local vcs = require("util.vcs")
local inline_diff = require("util.inline_diff")

local M = {}

local PANEL_WIDTH = 42
local ns = vim.api.nvim_create_namespace("vcs_ui")

---@class PanelRow
---@field kind "dir"|"file"
---@field depth integer
---@field name string  directory label (possibly a compacted a/b/c chain) or the file's basename
---@field file VcsFile|nil

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
---@field rows PanelRow[]  files grouped into a directory tree, one entry per panel line
---@field first_line integer
---@field inline boolean
---@field inline_buf integer|nil  buffer currently carrying the inline overlay
---@field diff_win integer|nil  the pane J/K scroll and <CR> focuses
---@field shown VcsFile|nil  the selection the diff windows currently render
---@field refreshing boolean|nil  a background revalidation is in flight
---@field previews table<integer, true>  buffers this view opened and unlisted
---@field navmapped table<integer, true>  real file buffers carrying view-local maps
local state = nil

-- The inline / side-by-side choice outlives the view, the way VS Code's
-- renderSideBySide is a setting rather than something you re-toggle per diff.
-- Inline is the default, matching `diffEditor.renderSideBySide: false` in the
-- VS Code config this mirrors.
local remembered_inline = true

-- What the backends said, remembered across opens (and closes) of the view.
-- Reopening paints from here instantly; a background pass revalidates.
--   listing_cache: root \0 scope        -> { rev, files }
--   base_cache:    root \0 rev \0 path  -> file content at that revision
local listing_cache = {} ---@type table<string, {rev: string, files: VcsFile[]}>
local base_cache = {} ---@type table<string, string[]>
local base_count = 0

-- The base cache is a speed tool, not a database: past the point where it
-- could matter in memory, starting over beats managing it.
local BASE_CACHE_MAX = 512

-- Generation counters orphan background work that outlived its usefulness: a
-- revalidation from a previous open, a prefetch for a replaced listing, a
-- render for a file the cursor has already left.
local refresh_gen = 0
local render_gen = 0
local prefetch_gen = 0
local prefetch_busy = false
local render_busy = 0
-- The newest revalidation in flight per listing key. A newer one supersedes
-- an older one's result; merely closing the view does not.
local refresh_inflight = {} ---@type table<string, integer>

local STATUS = {
  M = { icon = "M", hl = "DiffChange", label = "modified" },
  A = { icon = "A", hl = "DiffAdd", label = "added" },
  D = { icon = "D", hl = "DiffDelete", label = "deleted" },
  R = { icon = "R", hl = "DiffChange", label = "renamed" },
  C = { icon = "!", hl = "DiffText", label = "conflict" },
  ["?"] = { icon = "?", hl = "Comment", label = "untracked" },
}

--------------------------------------------------------------------------
-- small helpers
--------------------------------------------------------------------------

local function valid()
  return state ~= nil
    and vim.api.nvim_tabpage_is_valid(state.tab)
    and vim.api.nvim_win_is_valid(state.panel_win)
    and vim.api.nvim_buf_is_valid(state.panel_buf)
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
  -- Two diffs of the same file at the same revision would collide on the
  -- name, and the loser would silently end up as a nameless "[No Name]"
  -- pane; suffix instead.
  if vim.fn.bufexists(name) == 1 then
    local n = 2
    while vim.fn.bufexists(("%s (%d)"):format(name, n)) == 1 do
      n = n + 1
    end
    name = ("%s (%d)"):format(name, n)
  end
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
-- the caches
--------------------------------------------------------------------------

local function listing_key(root, scope)
  return root .. "\0" .. scope
end

local function base_key(root, rev, path)
  return root .. "\0" .. rev .. "\0" .. path
end

-- Bumped whenever cached bases are declared untrustworthy, so a fetch that
-- was already in flight when that happened cannot re-insert stale content.
local base_epoch = 0

local function store_base(key, content)
  if base_cache[key] == nil then
    if base_count >= BASE_CACHE_MAX then
      base_cache, base_count = {}, 0
    end
    base_count = base_count + 1
  end
  base_cache[key] = content
end

---Forget every base fetched for `root`, in any revision.
local function drop_bases(root)
  base_epoch = base_epoch + 1
  local prefix = root .. "\0"
  for key in pairs(base_cache) do
    if key:sub(1, #prefix) == prefix then
      base_cache[key] = nil
      base_count = base_count - 1
    end
  end
end

--------------------------------------------------------------------------
-- the file list panel
--------------------------------------------------------------------------

---Group the flat path list into a tree, VS Code explorer style: directories
---first, then files, and chains of single-child directories compacted onto
---one line — so a deeply nested repository shows every filename instead of
---truncating full paths against the panel edge.
---@param files VcsFile[]
---@return PanelRow[]
local function build_rows(files)
  local tree = { dirs = {}, files = {} }
  for _, file in ipairs(files) do
    local node = tree
    local dir = file.path:match("^(.*)/")
    if dir then
      for part in dir:gmatch("[^/]+") do
        node.dirs[part] = node.dirs[part] or { dirs = {}, files = {} }
        node = node.dirs[part]
      end
    end
    table.insert(node.files, file)
  end

  local rows = {}
  local function emit(node, depth)
    local names = vim.tbl_keys(node.dirs)
    table.sort(names)
    for _, name in ipairs(names) do
      local child = node.dirs[name]
      local label = name
      -- a/b/c on one line while the chain has nothing of its own to show
      while #child.files == 0 do
        local only, count = nil, 0
        for dir_name in pairs(child.dirs) do
          only, count = dir_name, count + 1
        end
        if count ~= 1 then
          break
        end
        label = label .. "/" .. only
        child = child.dirs[only]
      end
      table.insert(rows, { kind = "dir", depth = depth, name = label })
      emit(child, depth + 1)
    end
    for _, file in ipairs(node.files) do
      table.insert(rows, { kind = "file", depth = depth, name = file.path:match("[^/]+$"), file = file })
    end
  end
  emit(tree, 0)
  return rows
end

---The panel row under the cursor, or nil on a header line (or before the
---very first render has established where the header ends).
local function row_at_cursor()
  if not valid() or not state.first_line then
    return nil
  end
  local lnum = vim.api.nvim_win_get_cursor(state.panel_win)[1]
  return state.rows[lnum - state.first_line + 1]
end

---The file under the cursor in the panel; nil on a header or directory line.
local function current_file()
  local row = row_at_cursor()
  return row and row.file or nil
end

---Where the selection sits among the file rows — "file 3 of 12" — or just the
---count while the cursor is on a header or directory line.
local function file_position()
  local at, n = nil, 0
  local here = row_at_cursor()
  for _, row in ipairs(state.rows) do
    if row.kind == "file" then
      n = n + 1
      if row == here then
        at = n
      end
    end
  end
  if at then
    return ("file %d of %d"):format(at, n)
  end
  return ("%d file%s"):format(n, n == 1 and "" or "s")
end

local function header_line()
  return ("%s · %s%s"):format(state.rev:sub(1, 12), file_position(), state.refreshing and " · refreshing…" or "")
end

---Redraw just the position line, cheap enough to run on every cursor motion.
local function update_header()
  if not valid() then
    return
  end
  local buf = state.panel_buf
  local line = header_line()
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { line })
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 1, 2)
  vim.api.nvim_buf_set_extmark(buf, ns, 1, 0, { end_col = #line, hl_group = "Comment" })
end

local function render_panel()
  local buf = state.panel_buf
  local scope_label = ({ working = "uncommitted", branch = "since fork point", head = "last commit" })[state.scope]
    or state.scope
  local header = {
    ("%s · %s"):format(state.backend.name, scope_label),
    header_line(),
    "",
  }
  state.first_line = #header + 1

  local lines = vim.list_extend({}, header)
  for _, row in ipairs(state.rows) do
    local indent = ("  "):rep(row.depth)
    if row.kind == "dir" then
      table.insert(lines, ("    %s%s/"):format(indent, row.name))
    else
      local meta = STATUS[row.file.status] or STATUS.M
      local label = row.name
      if row.file.orig then
        -- Renamed: show where it came from, not just the new basename.
        label = ("%s ← %s"):format(row.name, row.file.orig)
      end
      table.insert(lines, (" %s  %s%s"):format(meta.icon, indent, label))
    end
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
  for i, row in ipairs(state.rows) do
    local lnum = state.first_line - 1 + i - 1
    if row.kind == "dir" then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { end_col = #lines[lnum + 1], hl_group = "Directory" })
    else
      local meta = STATUS[row.file.status] or STATUS.M
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { end_col = 3, hl_group = meta.hl })
      if row.file.orig then
        local tail = #(" ← " .. row.file.orig)
        vim.api.nvim_buf_set_extmark(buf, ns, lnum, #lines[lnum + 1] - tail, {
          end_col = #lines[lnum + 1],
          hl_group = "Comment",
        })
      end
    end
  end
end

---Panel line of the first file row (directories can come before it).
local function first_file_lnum()
  for i, row in ipairs(state.rows) do
    if row.kind == "file" then
      return state.first_line + i - 1
    end
  end
  return state.first_line
end

--------------------------------------------------------------------------
-- rendering one file
--------------------------------------------------------------------------

---Does `file` have a base version to fetch at all?
local function has_base(file)
  -- Added and untracked files have no previous version to ask for.
  return file.status ~= "A" and file.status ~= "?"
end

---The revision a file's base comes from: per-file when the backend tracks one
---(p4's haveRev — "#have" is the same string before and after a sync, "#12"
---is not), the listing revision otherwise.
local function base_rev(file)
  return file.rev or state.rev
end

---Base content for a file, memoised across opens of the view. Fetching costs
---a subprocess (tens of milliseconds, and a good deal more on a large file or
---a remote Perforce server), which is worth paying once, not once per visit.
local function base_content(file)
  if not has_base(file) then
    return {}
  end
  -- A renamed file's base lives at its old path.
  local base_path = file.orig or file.path
  local key = base_key(state.root, base_rev(file), base_path)
  local hit = base_cache[key]
  if hit then
    return hit
  end
  local content = state.backend.show(state.root, base_rev(file), base_path) or {}
  store_base(key, content)
  return content
end

---True when rendering `file` would have to shell out for its base first.
local function base_missing(file)
  return has_base(file) and base_cache[base_key(state.root, base_rev(file), file.orig or file.path)] == nil
end

---Diff panes share one look: native diff, folds open, hybrid line numbers —
---absolute on the cursor line, relative everywhere else, so a `3j` between
---changes reads straight off the margin.
local function diff_pane(w)
  vim.api.nvim_win_call(w, function()
    vim.cmd("diffthis")
    vim.wo.foldlevel = 99
    vim.wo.number = true
    vim.wo.relativenumber = true
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
  if fresh then
    -- `:edit` lists the buffer as a side effect — undone every time, not
    -- just on first tracking, or re-focusing an already-tracked preview
    -- would quietly pin it into the buffer list. That was exactly the
    -- "files randomly staying open" leak.
    vim.bo[buf].buflisted = false
    if not state.previews[buf] then
      state.previews[buf] = true
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
end

-- Forward declarations: the render helpers below wire keys defined further
-- down, and the tab autocmds revalidate with machinery from the refresh
-- section.
local setup_diff_keys
local refresh_listing

---Drop a preview buffer the moment the view moves off it: a file that was
---only looked at, and not edited, has no business staying loaded. This is
---what keeps scrubbing the list from accumulating open files.
local function drop_preview(buf)
  if
    buf
    and state.previews[buf]
    and vim.api.nvim_buf_is_valid(buf)
    and not vim.bo[buf].modified
    and vim.fn.buflisted(buf) == 0
    and #vim.fn.win_findbuf(buf) == 0
  then
    state.previews[buf] = nil
    pcall(vim.api.nvim_buf_delete, buf, {})
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
    vim.wo[win].relativenumber = true
    -- So scrolling up can reveal virtual lines hanging above line 1.
    vim.wo[win].smoothscroll = true
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
    vim.wo[win].relativenumber = true
  end

  balance(win)
  return win
end

---Draw `file` in the right-hand side. Assumes any base content it needs is
---already cached; everything here is buffer and window work.
local function render_file(file, focus)
  -- Re-rendering the file already on screen (the inline toggle, a refresh)
  -- keeps the reading position.
  local keep
  if file and file == state.shown and state.diff_win and vim.api.nvim_win_is_valid(state.diff_win) then
    keep = vim.api.nvim_win_get_cursor(state.diff_win)
  end
  -- Remember what was on screen: whichever preview the view moves off gets
  -- dropped below, so browsing never accumulates open files.
  local before = {}
  for _, w in ipairs(diff_wins()) do
    table.insert(before, vim.api.nvim_win_get_buf(w))
  end

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

  state.diff_win = target
  state.shown = file
  setup_diff_keys()
  if keep then
    pcall(vim.api.nvim_win_set_cursor, target, keep)
  end
  -- Close on switch: previews the render just replaced, unless edited.
  for _, buf in ipairs(before) do
    drop_preview(buf)
  end
  vim.api.nvim_set_current_win(focus and target or state.panel_win)
end

---Render whatever the panel cursor is on. `focus` moves the cursor into the
---diff; leaving it false keeps it in the list so j/k keeps scrubbing. On a
---directory or header line the previous diff stays up (focus still moves).
---
---When the base content is not cached yet and `opts.async` allows it, the
---fetch runs off the UI and the render lands once it is done — unless the
---cursor has moved on by then, in which case the fetch just warms the cache.
local function show(focus, opts)
  if not valid() then
    return
  end
  render_gen = render_gen + 1
  local gen = render_gen

  local file = current_file()
  if not file and #state.files > 0 then
    if focus and state.diff_win and vim.api.nvim_win_is_valid(state.diff_win) then
      vim.api.nvim_set_current_win(state.diff_win)
    end
    return
  end

  -- Focusing a file whose real buffer is already on screen needs no
  -- re-render — just move into it.
  if focus and file and file == state.shown and state.diff_win and vim.api.nvim_win_is_valid(state.diff_win) then
    local shown_buf = vim.api.nvim_win_get_buf(state.diff_win)
    if vim.api.nvim_buf_get_name(shown_buf) == state.root .. "/" .. file.path then
      vim.api.nvim_set_current_win(state.diff_win)
      return
    end
  end

  if file and opts and opts.async and base_missing(file) then
    local backend, root, rev = state.backend, state.root, base_rev(file)
    local base_path = file.orig or file.path
    local epoch = base_epoch
    render_busy = render_busy + 1
    vcs.async(function()
      local ok, err = pcall(function()
        local key = base_key(root, rev, base_path)
        if not base_cache[key] then
          local content = backend.show(root, rev, base_path) or {}
          -- The world may have moved while the subprocess ran; a result from
          -- before drop_bases must not re-poison the cache it just emptied.
          if epoch == base_epoch and not base_cache[key] then
            store_base(key, content)
          end
        end
        if gen ~= render_gen or not valid() or current_file() ~= file then
          return
        end
        -- Same guard as the debounce: never yank focus back to the panel.
        if not focus and vim.api.nvim_get_current_win() ~= state.panel_win then
          return
        end
        render_file(file, focus)
      end)
      render_busy = render_busy - 1
      if not ok then
        vim.notify("vcs render: " .. tostring(err), vim.log.levels.ERROR)
      end
    end)
    return
  end

  render_file(file, focus)
end

---Warm the base cache for the listed files in the background, starting from
---the cursor and wrapping, so scrubbing lands on content that is already
---there. One coroutine, one subprocess at a time: gentle on a loaded server,
---and the UI never waits on any of it. A file the cursor reaches first is
---fetched by the render path instead; whoever gets there first fills the
---cache for both.
local PREFETCH_MAX = 256

local function prefetch_bases()
  prefetch_gen = prefetch_gen + 1
  prefetch_busy = false
  if not valid() or #state.files == 0 then
    return
  end
  local gen = prefetch_gen
  local backend, root, rev = state.backend, state.root, state.rev

  local in_view = {}
  local from = 1
  local at = row_at_cursor()
  for _, row in ipairs(state.rows) do
    if row.kind == "file" then
      table.insert(in_view, row.file)
      if row == at then
        from = #in_view
      end
    end
  end
  local ordered = {}
  for i = from, math.min(#in_view, from + PREFETCH_MAX - 1) do
    table.insert(ordered, in_view[i])
  end
  for i = 1, from - 1 do
    if #ordered >= PREFETCH_MAX then
      break
    end
    table.insert(ordered, in_view[i])
  end

  prefetch_busy = true
  vcs.async(function()
    local ok, err = pcall(function()
      for _, file in ipairs(ordered) do
        if gen ~= prefetch_gen then
          return
        end
        if has_base(file) then
          local base_path = file.orig or file.path
          local file_rev = file.rev or rev
          local key = base_key(root, file_rev, base_path)
          if not base_cache[key] then
            local content = backend.show(root, file_rev, base_path)
            if gen ~= prefetch_gen then
              return
            end
            store_base(key, content or {})
          end
        end
      end
    end)
    -- Only the newest prefetch owns the flag; and it must clear it on error
    -- too, or busy() would report a prefetch that no longer exists.
    if gen == prefetch_gen then
      prefetch_busy = false
    end
    if not ok then
      vim.notify("vcs prefetch: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)
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

---Ask for the selection to be rendered once the cursor settles. Every cursor
---motion in the panel funnels through here — the j/k maps and the CursorMoved
---autocmd alike.
local function schedule_show()
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
        -- Re-rendering the selection already on screen would just flicker.
        local file = current_file()
        if file == state.shown and state.diff_win and vim.api.nvim_win_is_valid(state.diff_win) then
          return
        end
        show(false, { async = true })
      end
    end)
  )
end

---Move the cursor `delta` file rows, stepping over directory lines; from the
---header, forward lands on the first file.
local function move(delta)
  local lnum = vim.api.nvim_win_get_cursor(state.panel_win)[1]
  local idx = lnum - state.first_line + 1
  local i = math.max(idx + delta, 1)
  local target
  while state.rows[i] do
    if state.rows[i].kind == "file" then
      target = i
      break
    end
    i = i + delta
  end
  if target then
    vim.api.nvim_win_set_cursor(state.panel_win, { state.first_line + target - 1, 0 })
  end
  update_header()
  schedule_show()
end

---Half-page the diff pane from the panel, so a file can be skimmed without
---moving focus into it.
local function scroll_diff(dir)
  if not valid() then
    return
  end
  local win = state.diff_win
  if not (win and vim.api.nvim_win_is_valid(win)) then
    win = diff_wins()[1]
  end
  if win then
    vim.api.nvim_win_call(win, function()
      vim.cmd("normal! " .. (dir > 0 and "\4" or "\21"))
    end)
  end
end

---From inside the diff, move the selection without going back to the list:
---]f / [f render the next or previous file and keep focus in the diff.
local function step_file(delta)
  if not (valid() and vim.api.nvim_get_current_tabpage() == state.tab) then
    return
  end
  local lnum = vim.api.nvim_win_get_cursor(state.panel_win)[1]
  local i = lnum - state.first_line + 1 + delta
  while state.rows[i] do
    if state.rows[i].kind == "file" then
      vim.api.nvim_win_set_cursor(state.panel_win, { state.first_line + i - 1, 0 })
      update_header()
      show(true)
      return
    end
    i = i + delta
  end
end

---Buffer-local keys for the diff panes themselves. Scratch buffers die with
---the view; maps put on real file buffers are removed again in close().
function setup_diff_keys()
  for _, w in ipairs(diff_wins()) do
    local buf = vim.api.nvim_win_get_buf(w)
    local function bmap(lhs, fn, desc)
      vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
    end
    bmap("]f", function()
      step_file(1)
    end, "Next changed file")
    bmap("[f", function()
      step_file(-1)
    end, "Previous changed file")
    if vim.bo[buf].buftype == "" then
      state.navmapped[buf] = true
    else
      -- `q` on the real file would shadow macro recording wherever that
      -- buffer is shown later, so only the scratch panes get it.
      bmap("q", function()
        M.close()
      end, "Close diff view")
    end
  end
end

--------------------------------------------------------------------------
-- panel actions
--------------------------------------------------------------------------

---Stage or unstage the selected file, on backends that have an index.
local function stage_toggle()
  local file = current_file()
  if not file then
    return
  end
  local backend, root = state.backend, state.root
  if not backend.stage then
    vim.notify(("%s has no staging area"):format(backend.name), vim.log.levels.INFO)
    return
  end
  vcs.async(function()
    local staged = backend.staged(root, file.path)
    local ok = staged and backend.unstage(root, file.path) or (not staged and backend.stage(root, file.path))
    vim.notify(
      ok and ("%s %s"):format(staged and "Unstaged" or "Staged", file.path)
        or ("Could not %s %s"):format(staged and "unstage" or "stage", file.path),
      ok and vim.log.levels.INFO or vim.log.levels.WARN
    )
  end)
end

---Open the three-way merge view for the selected file, straight from the
---list. The merge view lives in its own tab, so finishing it (<leader>cq)
---drops right back into this view.
local function merge_current()
  local file = current_file()
  if not file then
    return
  end
  local full = state.root .. "/" .. file.path
  if vim.fn.filereadable(full) == 0 then
    vim.notify("No file on disk to merge", vim.log.levels.WARN)
    return
  end
  show(true)
  if vim.api.nvim_buf_get_name(0) ~= full then
    vim.cmd("edit " .. vim.fn.fnameescape(full))
  end
  require("util.conflict").merge_view()
end

-- What `?` shows. Discoverability is the point: none of the panel keys
-- should be learnable only by reading the source.
local HELP = {
  { "j / k", "select file, diff follows" },
  { "<CR> / l", "focus the diff" },
  { "J / K", "scroll the diff from the list" },
  { "]f / [f", "next / previous file, from inside the diff" },
  { "s", "cycle scope: uncommitted / branch / last commit" },
  { "i", "toggle inline and side-by-side" },
  { "a", "stage / unstage file (git)" },
  { "X", "revert file" },
  { "m", "merge view for a conflicted file" },
  { "R", "hard refresh" },
  { "q", "close" },
}

local function show_help()
  local lines = {}
  for _, entry in ipairs(HELP) do
    table.insert(lines, ("  %-11s %s"):format(entry[1], entry[2]))
  end
  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  for i = 1, #lines do
    vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { end_col = 13, hl_group = "Special" })
  end
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.max(0, math.floor((vim.o.lines - #lines) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
    width = width + 2,
    height = #lines,
    style = "minimal",
    border = "rounded",
    title = " changed files ",
    title_pos = "center",
  })
  for _, lhs in ipairs({ "q", "<Esc>", "?" }) do
    vim.keymap.set("n", lhs, function()
      pcall(vim.api.nvim_win_close, win, true)
    end, { buffer = buf, nowait = true, silent = true })
  end
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
  -- <Space> would be the natural "select" key but it is leader, and taking it
  -- over buffer-locally would silently break every <leader> binding while the
  -- panel is focused. l / <Right> are the next-nearest reach.
  for _, lhs in ipairs({ "<CR>", "o", "l", "<Right>" }) do
    map(lhs, function()
      show(true)
    end, "Open diff")
  end
  map("<Tab>", function()
    show(true)
  end, "Focus diff")
  map("J", function()
    scroll_diff(1)
  end, "Scroll diff down")
  map("K", function()
    scroll_diff(-1)
  end, "Scroll diff up")
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
  map("a", stage_toggle, "Stage / unstage file")
  map("X", function()
    M.revert_current()
  end, "Revert file")
  map("m", merge_current, "Merge view for conflicts")
  map("?", show_help, "Help")
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
  -- The global cursorlineopt is "number", and the panel has no numbers — so
  -- without this the selected file would get no highlight at all.
  vim.wo[win].cursorlineopt = "line"
  vim.wo[win].winfixwidth = true

  state = state or {}
  state.tab = vim.api.nvim_get_current_tabpage()
  state.panel_win = win
  state.panel_buf = buf
  state.origin_tab = origin
  if state.inline == nil then
    state.inline = remembered_inline
  end
  state.previews = state.previews or {}
  state.navmapped = state.navmapped or {}

  setup_panel_keys(buf)
  -- Render on any cursor motion in the panel — a mouse click, a search, `G` —
  -- not just the mapped keys. j/k stay mapped so they can step over directory
  -- rows; this catches everything else.
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    callback = function()
      if valid() and vim.api.nvim_get_current_win() == state.panel_win then
        update_header()
        schedule_show()
      end
    end,
  })
  -- The repository can move while the view sits in a background tab — a
  -- commit from a terminal, a sync, an editor left overnight. Coming back to
  -- the tab (or to Neovim itself) revalidates in the background, exactly the
  -- way reopening the view does.
  local group = vim.api.nvim_create_augroup("vcs_ui_revalidate", { clear = true })
  vim.api.nvim_create_autocmd({ "TabEnter", "FocusGained" }, {
    group = group,
    callback = function()
      -- Scheduled so an open() in progress finishes first; the refresh it
      -- starts itself then makes this one redundant, which `refreshing` sees.
      vim.schedule(function()
        if valid() and vim.api.nvim_get_current_tabpage() == state.tab and not state.refreshing then
          refresh_listing()
        end
      end)
    end,
  })
  -- A session saved with the view open would bake the diff tab and any
  -- focused preview buffer into the session file, and restoring it later
  -- resurrects them as real listed buffers plus a junk tab of dead vcs://
  -- windows. Fold the view away before anything is written down.
  -- PersistenceSavePre fires inside persistence.nvim right before mksession;
  -- VimLeavePre covers quitting without it.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      M.close()
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "PersistenceSavePre",
    callback = function()
      M.close()
    end,
  })
  -- The preview buffers must be cleaned up however the view dies — `q` is one
  -- way, but so are :tabclose, :q on its last window, a session switch. When
  -- the diff tab is gone and close() has not run, run it now; otherwise every
  -- file ever scrubbed past stays loaded in the session.
  vim.api.nvim_create_autocmd("TabClosed", {
    group = vim.api.nvim_create_augroup("vcs_ui_lifecycle", { clear = true }),
    callback = function()
      -- Scheduled so close()'s own tabclose does not re-enter it mid-run.
      vim.schedule(function()
        if state and not vim.api.nvim_tabpage_is_valid(state.tab) then
          M.close()
        end
      end)
    end,
  })
end

--------------------------------------------------------------------------
-- background revalidation
--------------------------------------------------------------------------

local function same_listing(a, b)
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    -- rev too: a p4 sync moves a file's haveRev without changing the set of
    -- opened files, and that must read as "the world moved".
    if a[i].path ~= b[i].path or a[i].status ~= b[i].status or a[i].orig ~= b[i].orig or a[i].rev ~= b[i].rev then
      return false
    end
  end
  return true
end

---Re-ask the backend for the listing in the background and reconcile: the
---cached paint stays up and interactive the whole time, and the panel only
---redraws when something actually changed. (Assigns the forward declaration
---above render_file, so the tab autocmds and panel actions can reach it.)
function refresh_listing()
  if not valid() then
    return
  end
  refresh_gen = refresh_gen + 1
  local gen = refresh_gen
  local backend, root, scope = state.backend, state.root, state.scope
  local key = listing_key(root, scope)
  refresh_inflight[key] = gen
  state.refreshing = true
  render_panel()

  vcs.async(function()
    local ok, err = pcall(function()
      local rev = backend.rev(root, scope)
      local files = rev and backend.changed(root, rev) or nil
      -- A newer revalidation of this same listing owns the truth now. The
      -- view merely having closed is not that: its result is still worth
      -- keeping, since the warmed cache is what makes the next open instant.
      if refresh_inflight[key] ~= gen then
        return
      end
      refresh_inflight[key] = nil
      local fresh = false
      if files then
        table.sort(files, function(a, b)
          return a.path < b.path
        end)
        local prev = listing_cache[key]
        fresh = not (prev and rev == prev.rev and same_listing(files, prev.files))
        if fresh then
          -- The world moved; bases fetched against the old listing cannot be
          -- trusted (a commit or a sync changes what a revision string means).
          drop_bases(root)
        end
        listing_cache[key] = { rev = rev, files = files }
      end
      if gen ~= refresh_gen or not valid() or state.root ~= root or state.scope ~= scope then
        return
      end
      state.refreshing = nil
      if not files or not fresh then
        render_panel() -- just drops the refreshing marker
        return
      end

      local selected = current_file()
      state.rev, state.files = rev, files
      state.rows = build_rows(files)
      render_panel()

      -- Keep the cursor on the file it was on; if that file left the listing,
      -- fall back to the first one.
      local lnum
      if selected then
        for i, row in ipairs(state.rows) do
          if row.kind == "file" and row.file.path == selected.path then
            lnum = state.first_line + i - 1
            break
          end
        end
      end
      pcall(vim.api.nvim_win_set_cursor, state.panel_win, { lnum or first_file_lnum(), 0 })
      update_header()
      -- Redraw the diff for the (possibly moved) selection, but never yank
      -- focus away from wherever the user is working.
      if vim.api.nvim_get_current_win() == state.panel_win then
        show(false, { async = true })
      end
      prefetch_bases()
    end)
    if not ok then
      -- The marker must not survive the refresh that owned it dying.
      if state and state.refreshing and gen == refresh_gen then
        state.refreshing = nil
        if valid() then
          pcall(render_panel)
        end
      end
      vim.notify("vcs refresh: " .. tostring(err), vim.log.levels.ERROR)
    end
  end)
end

--------------------------------------------------------------------------
-- public API
--------------------------------------------------------------------------

---Open the changed-files view. With a listing cached for this repository and
---scope the view paints from it instantly and revalidates in the background;
---the first visit fetches synchronously and pays the cost once.
---@param opts? { scope?: string, rev?: string }
function M.open(opts)
  opts = opts or {}
  local backend, root = vcs.require()
  if not backend then
    return
  end

  local scope = opts.scope or (state and state.scope) or "working"
  -- An explicitly given base revision is an ad-hoc question; it bypasses the
  -- caches rather than polluting them.
  local cached = not opts.rev and listing_cache[listing_key(root, scope)] or nil

  local rev = opts.rev or (cached and cached.rev)
  if not rev then
    rev = backend.rev(root, scope)
    if not rev then
      vim.notify(("Could not resolve a base revision for %s"):format(backend.name), vim.log.levels.WARN)
      return
    end
  end

  cancel_scrub()
  ensure_tab()
  state.backend, state.root, state.scope, state.rev = backend, root, scope, rev
  state.refreshing = nil
  if cached then
    state.files = cached.files
  else
    state.files = backend.changed(root, rev)
    table.sort(state.files, function(a, b)
      return a.path < b.path
    end)
    if not opts.rev then
      listing_cache[listing_key(root, scope)] = { rev = rev, files = state.files }
    end
  end
  state.rows = build_rows(state.files)

  render_panel()
  vim.api.nvim_win_set_cursor(state.panel_win, { first_file_lnum(), 0 })
  update_header()
  show(false)
  if cached then
    refresh_listing()
  end
  prefetch_bases()
end

---One key, walking inward: from outside it opens the view; from the diff it
---focuses the file list (whose cursorline is the selection highlight); from
---the list it closes — the way VS Code's "focus SCM view" key first focuses,
---then toggles away. From inside with a *different* scope requested, it
---switches scope instead.
---@param opts? { scope?: string, rev?: string }
function M.toggle(opts)
  opts = opts or {}
  if
    valid()
    and vim.api.nvim_get_current_tabpage() == state.tab
    and not opts.rev
    and (not opts.scope or opts.scope == state.scope)
  then
    if vim.api.nvim_get_current_win() ~= state.panel_win then
      vim.api.nvim_set_current_win(state.panel_win)
    else
      M.close()
    end
    return
  end
  M.open(opts)
end

---True while background work is in flight — a listing revalidation, a base
---prefetch, an async render. The tests settle on this; nothing else should
---need it.
function M.busy()
  return (state ~= nil and state.refreshing == true) or prefetch_busy or render_busy > 0
end

function M.refresh()
  if not valid() then
    return
  end
  -- An explicit refresh distrusts everything remembered about this repository:
  -- a p4 sync or a rebase can change base content without changing the listing.
  refresh_gen = refresh_gen + 1
  -- An in-flight revalidation predates the distrust; its result must not
  -- overwrite the fresh listing fetched below.
  refresh_inflight[listing_key(state.root, state.scope)] = nil
  listing_cache[listing_key(state.root, state.scope)] = nil
  drop_bases(state.root)
  M.open({ scope = state.scope })
end

function M.close()
  cancel_scrub()
  -- Orphan the in-flight render and revalidation; a running prefetch is left
  -- to finish quietly, since the cache it warms is what makes the next open
  -- instant.
  refresh_gen = refresh_gen + 1
  render_gen = render_gen + 1
  local previews = state and state.previews or {}
  local navmapped = state and state.navmapped or {}
  if state and state.inline_buf then
    inline_diff.detach(state.inline_buf)
    state.inline_buf = nil
  end
  if valid() then
    vim.api.nvim_set_current_tabpage(state.tab)
    if vim.fn.tabpagenr("$") == 1 then
      -- The origin tab is gone and a lone tab cannot be closed (E784).
      -- Dissolve the layout into an empty buffer instead — erroring here
      -- would skip the cleanup below and leave the view stuck half-alive,
      -- with every further open/close attempt failing the same way.
      pcall(vim.cmd, "silent! only")
      pcall(vim.cmd, "enew")
    else
      pcall(vim.cmd, "tabclose")
    end
  end
  state = nil
  -- The ]f/[f maps only mean something while the view exists; leaving them
  -- on real file buffers would surprise whoever edits those files later.
  for buf in pairs(navmapped) do
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.keymap.del, "n", "]f", { buffer = buf })
      pcall(vim.keymap.del, "n", "[f", { buffer = buf })
    end
  end
  -- Drop the buffers that only existed because they were previewed; anything
  -- carrying unsaved edits is surfaced into the buffer list instead — edits
  -- must never end up hiding in an unlisted buffer after the view is gone.
  for buf in pairs(previews) do
    if vim.api.nvim_buf_is_valid(buf) then
      if vim.bo[buf].modified then
        vim.bo[buf].buflisted = true
      elseif vim.fn.buflisted(buf) == 0 then
        pcall(vim.api.nvim_buf_delete, buf, {})
      end
    end
  end
end

---Discard the selected file's change — VS Code's SCM "discard". Destructive,
---so it asks first; `opts.force` (used by the tests) skips the prompt.
---@param opts? { force?: boolean }
function M.revert_current(opts)
  if not valid() then
    return
  end
  local file = current_file()
  if not file then
    return
  end
  local deletes = file.status == "A" or file.status == "?"
  local prompt = deletes and ("Delete %s?"):format(file.path)
    or ("Revert %s to %s?"):format(file.path, base_rev(file):sub(1, 12))
  if not (opts and opts.force) and vim.fn.confirm(prompt, "&Yes\n&No", 2) ~= 1 then
    return
  end
  local backend, root, rev = state.backend, state.root, base_rev(file)
  vcs.async(function()
    local ok
    if file.status == "?" then
      ok = vim.fn.delete(root .. "/" .. file.path) == 0
    elseif backend.revert then
      ok = backend.revert(root, rev, file)
    else
      vim.notify(("%s cannot revert files from here"):format(backend.name), vim.log.levels.WARN)
      return
    end
    if not ok then
      vim.notify(("Could not revert %s"):format(file.path), vim.log.levels.WARN)
      return
    end
    -- A loaded buffer still showing the old content would be a lie to edit.
    local buf = vim.fn.bufnr(root .. "/" .. file.path)
    if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) and not vim.bo[buf].modified then
      vim.api.nvim_buf_call(buf, function()
        pcall(vim.cmd.checktime)
      end)
    end
    if valid() then
      refresh_listing()
    end
  end)
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
    remembered_inline = state.inline
    -- On a directory or header row show() would keep the previous rendering;
    -- redraw that file explicitly so the toggle is never silently deferred.
    if current_file() or #state.files == 0 then
      show(false)
    elseif state.shown then
      render_file(state.shown, false)
    end
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

---Which change is the cursor on in a native diff: hunk index and total,
---computed by diffing the two visible sides. Index 0 means the cursor sits
---above the first change. Nil when the current window is not half of a diff.
---@return integer|nil index, integer|nil total
function M.change_position()
  if not vim.wo.diff then
    return nil
  end
  local cur = vim.api.nvim_get_current_win()
  local other
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= cur and vim.wo[w].diff then
      other = w
      break
    end
  end
  if not other then
    return nil
  end
  local function text(win)
    local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
    return table.concat(lines, "\n") .. "\n"
  end
  -- Match the settings native diff mode is using, or the count disagrees with
  -- where ]c actually stops.
  local hunks = vim.diff(text(other), text(cur), {
    result_type = "indices",
    algorithm = vim.o.diffopt:match("algorithm:(%w+)") or "myers",
    indent_heuristic = vim.o.diffopt:find("indent%-heuristic") ~= nil,
  }) or {}
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line_count = vim.api.nvim_buf_line_count(0)
  local index = 0
  for i, h in ipairs(hunks) do
    local start_b, count_b = h[3], h[4]
    -- A pure deletion occupies no lines here; it reads as sitting on the line
    -- its filler is drawn above, same as the inline overlay's anchor.
    local anchor = count_b > 0 and start_b or math.max(math.min(start_b + 1, line_count), 1)
    if anchor <= row then
      index = i
    end
  end
  return index, #hunks
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
