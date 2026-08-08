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
-- Navigation from inside a diff pane stays in the view: a jump that lands a
-- file in the pane — gd, gr, <C-o>, :e — is adopted and re-dressed the way
-- selecting that file in the panel would have rendered it, instead of being
-- left as a plain buffer in a half-torn-down diff window. See adopt_nav.
--
-- Everything a backend says is remembered across opens of the view (the
-- listing per scope, base content per file), so `<leader>gc` in a large or
-- server-backed repository paints instantly from the last known state and
-- revalidates in the background instead of blocking on subprocesses.
--
-- Only one diff tab exists at a time; asking for another reuses it.

local vcs = require("util.vcs")
local inline_diff = require("util.inline_diff")
local diff_hunks = require("util.text").hunks

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
---@field collapse boolean  unchanged regions fold away, VS Code's hideUnchangedRegions
---@field inline_buf integer|nil  buffer currently carrying the inline overlay
---@field diff_win integer|nil  the pane J/K scroll and <CR> focuses
---@field shown VcsFile|nil  the selection the diff windows currently render
---@field shown_name string|nil  full path of the file on show, so the navigation autocmds can tell "already rendered" from a jump
---@field refreshing boolean|nil  a background revalidation is in flight
---@field previews table<integer, true>  buffers this view opened and unlisted
---@field navmapped table<integer, true>  real file buffers carrying view-local maps
-- Deliberately left for the checker to infer as VcsState rather than annotated
-- VcsState|nil: nil means "the view is closed", and every access here is behind
-- valid(), a guard no static checker can follow. Spelling the nil out buys one
-- honest warning at the assignment in close() and 170 false ones everywhere
-- else, so close() carries the suppression instead.
local state = nil

-- The inline / side-by-side choice outlives the view, the way VS Code's
-- renderSideBySide is a setting rather than something you re-toggle per diff.
-- Inline is the default, matching `diffEditor.renderSideBySide: false` in the
-- VS Code config this mirrors.
local remembered_inline = true

-- Whether unchanged regions collapse out of the diff, VS Code's
-- hideUnchangedRegions. On by default: a review reads hunk to hunk, the way
-- delta prints a patch — the full file is one zR (or a toggle) away.
local remembered_collapse = true

-- What the backends said, remembered across opens (and closes) of the view.
-- Reopening paints from here instantly; a background pass revalidates.
--   listing_cache: root \0 scope        -> { rev, files }
--   base_cache:    root \0 rev \0 path  -> file content at that revision
local listing_cache = {} ---@type table<string, {rev: string, files: VcsFile[]}>
local base_cache = {} ---@type table<string, string[]>
local base_count = 0

-- The base cache is a speed tool, not a database: past the point where it
-- could matter in memory, starting over beats managing it. Big enough that a
-- whole prefetch sweep (half this, see PREFETCH_MAX_FILES) fits with room to
-- spare for the files the render path fetches on demand.
local BASE_CACHE_MAX = 1024

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

-- True while the view itself is placing buffers into windows, so the
-- navigation autocmds can tell the view's own renders from an actual jump.
local rendering = false
-- One adoption is scheduled per tick; nav_win_pending carries the window it
-- should look at, overwritten by any later navigation in the same tick.
local nav_pending = false
local nav_win_pending = nil ---@type integer|nil
-- Buffers the buffer list picked up from a navigation inside the view —
-- `:edit` and the LSP jumps both list their target as a side effect (BufAdd
-- fires for either). Adoption turns exactly these into previews, and never a
-- buffer the user already had open on purpose.
local nav_listed = {} ---@type table<integer, true>

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

---Set a window-local option locally. `vim.wo[win].x = v` acts like `:set`,
---quietly overwriting the global value too — which is how the panel's
---full-row cursorline once leaked into every other window in the session.
local function wo_local(win, name, value)
  vim.api.nvim_set_option_value(name, value, { win = win, scope = "local" })
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

-- Which files have been looked at, per listing — GitHub's per-file "viewed"
-- checks. Survives close and reopen (a review in progress is a thing worth
-- keeping) but resets itself when the listing's base revision moves.
local viewed_sets = {} ---@type table<string, {rev: string, paths: table<string, true>}>

local function viewed_paths()
  local key = listing_key(state.root, state.scope)
  local v = viewed_sets[key]
  if not v or v.rev ~= state.rev then
    v = { rev = state.rev, paths = {} }
    viewed_sets[key] = v
  end
  return v.paths
end

-- Files past this size do without stats: diffing megabytes to decorate a
-- panel row is the wrong trade, and the numbers would be noise anyway.
local STATS_MAX_BYTES = 4 * 1024 * 1024
local STATS_MAX_LINES = 20000

---Line counts for a file — the "+12 -3" of a diff --stat — from its cached
---base against the loaded buffer (which may be ahead of disk) or the disk
---content. Pure arithmetic over the diff; never shells out. Nil for files
---too large to be worth it.
---@param root string
---@param file VcsFile
---@param base string[]
---@return {add: integer, del: integer}|nil
local function file_stats(root, file, base)
  if #base > STATS_MAX_LINES then
    return nil
  end
  local full = root .. "/" .. file.path
  local lines
  local buf = vim.fn.bufnr(full)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    if vim.api.nvim_buf_line_count(buf) > STATS_MAX_LINES then
      return nil
    end
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  elseif vim.fn.filereadable(full) == 1 then
    local size = (vim.uv.fs_stat(full) or {}).size or 0
    if size > STATS_MAX_BYTES then
      return nil
    end
    lines = vim.fn.readfile(full)
  else
    lines = {}
  end
  local a = #base > 0 and (table.concat(base, "\n") .. "\n") or ""
  local b = #lines > 0 and (table.concat(lines, "\n") .. "\n") or ""
  local add, del = 0, 0
  for _, h in ipairs(diff_hunks(a, b)) do
    del = del + h[2]
    add = add + h[4]
  end
  return { add = add, del = del }
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
  -- Total churn across the listing, once the stats pass has been anywhere.
  local add, del, known = 0, 0, false
  for _, f in ipairs(state.files) do
    if f.stats then
      known = true
      add, del = add + f.stats.add, del + f.stats.del
    end
  end
  return ("%s · %s%s%s"):format(
    state.rev:sub(1, 12),
    file_position(),
    known and (" · +%d -%d"):format(add, del) or "",
    state.refreshing and " · refreshing…" or ""
  )
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

-- Filetype icons for the panel, when mini.icons is around (it is, under
-- LazyVim). The probe is remembered; a bare Neovim renders identically to
-- how the panel always looked.
local icons_ready ---@type boolean|nil
local mini_icons
local function file_icon(kind, name)
  if icons_ready == nil then
    icons_ready, mini_icons = pcall(require, "mini.icons")
    icons_ready = icons_ready and pcall(mini_icons.get, "file", "probe.txt") or false
  end
  if not icons_ready then
    return nil
  end
  local ok, icon, hl = pcall(mini_icons.get, kind, name)
  if ok then
    return icon, hl
  end
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
  local row_icons = {} ---@type table<integer, {[1]: string, [2]: string|nil}>
  for i, row in ipairs(state.rows) do
    local indent = ("  "):rep(row.depth)
    if row.kind == "dir" then
      local icon = file_icon("directory", row.name)
      if icon then
        row_icons[i] = { icon, "Directory" }
        table.insert(lines, ("    %s%s %s/"):format(indent, icon, row.name))
      else
        table.insert(lines, ("    %s%s/"):format(indent, row.name))
      end
    else
      local meta = STATUS[row.file.status] or STATUS.M
      local label = row.name
      if row.file.orig then
        -- Renamed: show where it came from, not just the new basename.
        label = ("%s ← %s"):format(row.name, row.file.orig)
      end
      local icon, icon_hl = file_icon("file", row.name)
      if icon then
        row_icons[i] = { icon, icon_hl }
        table.insert(lines, (" %s  %s%s %s"):format(meta.icon, indent, icon, label))
      else
        table.insert(lines, (" %s  %s%s"):format(meta.icon, indent, label))
      end
    end
  end
  if #state.files == 0 then
    table.insert(lines, " (no changes)")
    table.insert(lines, " s cycles scope · ? for help")
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local viewed = viewed_paths()
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { end_col = #lines[1], hl_group = "Title" })
  vim.api.nvim_buf_set_extmark(buf, ns, 1, 0, { end_col = #lines[2], hl_group = "Comment" })
  if #state.files == 0 then
    vim.api.nvim_buf_set_extmark(buf, ns, #lines - 1, 0, { end_col = #lines[#lines], hl_group = "Comment" })
  end
  for i, row in ipairs(state.rows) do
    local lnum = state.first_line - 1 + i - 1
    if row.kind == "dir" then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { end_col = #lines[lnum + 1], hl_group = "Directory" })
    else
      local meta = STATUS[row.file.status] or STATUS.M
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { end_col = 3, hl_group = meta.hl })
      if row_icons[i] and row_icons[i][2] then
        local from = 4 + 2 * row.depth
        vim.api.nvim_buf_set_extmark(buf, ns, lnum, from, {
          end_col = from + #row_icons[i][1],
          hl_group = row_icons[i][2],
        })
      end
      if row.file.orig then
        local tail = #(" ← " .. row.file.orig)
        vim.api.nvim_buf_set_extmark(buf, ns, lnum, #lines[lnum + 1] - tail, {
          end_col = #lines[lnum + 1],
          hl_group = "Comment",
        })
      end
      -- The right edge carries the review state: a ✓ once the file has been
      -- looked at, and the file's churn as +n -n once the stats pass knows
      -- it. Virtual, so the row text (and everything that parses it) is
      -- untouched.
      local chunks = {}
      if viewed[row.file.path] then
        chunks[#chunks + 1] = { "✓ ", "Comment" }
      end
      local stats = row.file.stats
      if stats and (stats.add > 0 or stats.del > 0) then
        if stats.add > 0 then
          chunks[#chunks + 1] = { ("+%d"):format(stats.add), "Added" }
        end
        if stats.del > 0 then
          chunks[#chunks + 1] = { (stats.add > 0 and " -%d" or "-%d"):format(stats.del), "Removed" }
        end
      end
      if #chunks > 0 then
        chunks[#chunks + 1] = { " ", "Comment" }
        vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { virt_text = chunks, virt_text_pos = "right_align" })
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

---Splitting from the panel makes the new window inherit its window-local
---options — including the full-row cursorline that is the panel's selection
---highlight, which is far too loud on actual text. Back to the global.
local function reset_cursorline(w)
  wo_local(w, "cursorlineopt", vim.go.cursorlineopt)
end

---Add one `group:group` mapping to a window's winhighlight, leaving whatever
---else is already mapped there alone — several of these stack on the same
---pane, and assigning the option outright would drop the others.
local function map_hl(w, from, to)
  local cur = vim.api.nvim_get_option_value("winhighlight", { win = w })
  if not cur:find(from .. ":") then
    wo_local(w, "winhighlight", (cur ~= "" and cur .. "," or "") .. from .. ":" .. to)
  end
end

---The "╌╌ n unchanged lines ╌╌" fold line must whisper, not shout: the
---theme's Folded (blue on a grey fill) turns every gap into a bright bar.
---Repaint it in this window only, with the overlay's near-background group.
local function mute_folds(w)
  map_hl(w, "Folded", "InlineDiffFold")
end

---Keep a code pane's background at the normal colour even when unfocused.
---dim_inactive is off in the theme config, but this pins the code side to
---Normal regardless: in this view the eyes stay on the code while the cursor
---lives in the file list, and any dim-on-blur scheme would read as the page
---changing colour under you.
local function no_dim(w)
  map_hl(w, "NormalNC", "Normal")
end

---Whether this view collapses unchanged regions right now — the view's own
---setting when it is open, the remembered one for ad-hoc diffs (<leader>gd,
---history) that render outside it.
local function collapsing()
  if state and state.collapse ~= nil then
    return state.collapse
  end
  return remembered_collapse
end

---Diff panes share one look: native diff, hybrid line numbers — absolute on
---the cursor line, relative everywhere else, so a `3j` between changes reads
---straight off the margin. Diff mode folds its unchanged regions natively;
---the collapse setting just decides whether those folds start closed.
local function diff_pane(w)
  reset_cursorline(w)
  no_dim(w)
  -- The overlay's fold text works for any fold; using it here too means a
  -- collapsed gap reads the same in both renderings.
  wo_local(w, "foldtext", "v:lua.require'util.inline_diff'.foldtext()")
  mute_folds(w)
  local fc = vim.o.fillchars
  wo_local(w, "fillchars", fc ~= "" and (fc .. ",fold: ") or "fold: ")
  wo_local(w, "number", true)
  wo_local(w, "relativenumber", true)
  vim.api.nvim_win_call(w, function()
    vim.cmd("diffthis")
  end)
  -- After diffthis, never before: entering diff mode sets foldmethod=diff and
  -- resets 'foldlevel' to 0 itself, so a value set ahead of it is thrown away.
  -- That is why the collapse toggle appeared to do nothing to a side-by-side
  -- diff — the panes were always folded, whatever the setting said.
  wo_local(w, "foldlevel", collapsing() and 0 or 99)
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

---Window options for a pane carrying the inline overlay: hybrid line
---numbers, smoothscroll so scrolling up can reveal virtual lines hanging
---above line 1, and folding per the collapse setting. Applied *after* the
---buffer is in the window, never before: Neovim keeps window-local options
---per buffer shown in that window, so anything set ahead of the `:edit` is
---restored away the moment it lands.
local function inline_pane(win)
  no_dim(win)
  wo_local(win, "number", true)
  wo_local(win, "relativenumber", true)
  wo_local(win, "smoothscroll", true)
  if collapsing() then
    -- Collapse unchanged regions, exactly what foldmethod=diff does for the
    -- side-by-side panes; the overlay knows where the hunks are, so its
    -- foldexpr folds everything further than the diff context from one.
    -- zR (or the z toggle in the panel) brings the whole file back.
    wo_local(win, "foldmethod", "expr")
    wo_local(win, "foldexpr", "v:lua.require'util.inline_diff'.foldexpr(v:lnum)")
    wo_local(win, "foldtext", "v:lua.require'util.inline_diff'.foldtext()")
    mute_folds(win)
    wo_local(win, "foldlevel", 0)
    local fc = vim.o.fillchars
    wo_local(win, "fillchars", fc ~= "" and (fc .. ",fold: ") or "fold: ")
  else
    -- Editing a buffer restores the window-local options it last had, so
    -- the expr folding from a collapsed render would silently come back.
    wo_local(win, "foldmethod", "manual")
    wo_local(win, "foldlevel", 99)
  end
end

-- Neovim 0.13 removed BufModifiedSet, pointing at OptionSet with pattern
-- "modified" instead (`:h deprecated`) — and nvim_create_autocmd raises on an
-- unknown event, so naming it unconditionally does not degrade, it breaks the
-- view outright on 0.13.
--
-- Both are watched wherever both exist. They are not quite the same event
-- across versions (BufModifiedSet is documented as a special case of OptionSet,
-- and which internal 'modified' changes reach OptionSet differs by release), so
-- picking one and being wrong means an edited preview quietly stays out of the
-- buffer list. Watching both costs an autocmd and cannot be wrong; promotion is
-- idempotent.
local MODIFIED_EVENTS = vim.fn.exists("##BufModifiedSet") == 1 and { "BufModifiedSet", "OptionSet" } or { "OptionSet" }

---A preview that has actually been edited earns its place in the buffer list.
---@param buf integer
---@return true|nil  true retires the per-buffer autocmd that called this
local function promote_preview(buf)
  if
    state
    and state.previews[buf]
    and vim.api.nvim_buf_is_valid(buf)
    and vim.bo[buf].buflisted == false
    and vim.bo[buf].modified
  then
    vim.bo[buf].buflisted = true
    return true
  end
end

---Track `buf` as a view-opened preview: unlisted — `:edit` lists it as a
---side effect, undone on every call, not just on first tracking, or
---re-focusing an already-tracked preview would quietly pin it into the
---buffer list (exactly the "files randomly staying open" leak) — until it
---is actually edited, at which point it earns its place.
local function track_preview(buf)
  vim.bo[buf].buflisted = false
  if not state.previews[buf] then
    state.previews[buf] = true
    if vim.tbl_contains(MODIFIED_EVENTS, "BufModifiedSet") then
      -- Buffer-local, and retires itself once the buffer has been promoted.
      -- The OptionSet form cannot be either — 'modified' is its pattern, so
      -- there is one autocmd for every buffer — and it is registered with the
      -- view's other autocmds in ensure_tab instead.
      vim.api.nvim_create_autocmd("BufModifiedSet", {
        buffer = buf,
        callback = function()
          return promote_preview(buf)
        end,
      })
    end
  end
end

---`edit` a file the way VS Code's preview editors do: scrubbing past a file
---in the changed list must not make it a permanent resident of the buffer
---list. A buffer that was not already open stays unlisted until it is
---actually edited, at which point it earns its place.
local function edit_preview(full)
  local existing = vim.fn.bufnr(full)
  local fresh = existing == -1 or vim.fn.buflisted(existing) == 0
  vim.cmd("edit " .. vim.fn.fnameescape(full))
  if fresh then
    track_preview(vim.api.nvim_get_current_buf())
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
  reset_cursorline(win)

  if not file then
    vim.api.nvim_win_set_buf(win, scratch("vcs://empty", { "(no changes)" }))
    no_dim(win)
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
    inline_pane(win)
    vim.api.nvim_win_call(win, function()
      inline_diff.goto_first(buf)
    end)
  else
    -- Deleted: nothing on disk to edit, so show what was there, struck red —
    -- in the same delta minus wash the overlay uses for deleted lines.
    local buf = scratch(("vcs://deleted/%s"):format(file.path), base, file.path)
    vim.api.nvim_win_set_buf(win, buf)
    for row = 0, #base - 1 do
      vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { line_hl_group = "InlineDiffDelete", priority = 50 })
    end
    no_dim(win)
    wo_local(win, "number", true)
    wo_local(win, "relativenumber", true)
  end

  balance(win)
  return win
end

---Rendering a file is looking at it: mark it viewed, and refresh its stats
---from what is actually on screen — an edit in the overlay moves the
---numbers in the panel on the next render.
local function mark_rendered(file)
  local panel_dirty = false
  local viewed = viewed_paths()
  if not viewed[file.path] then
    viewed[file.path] = true
    panel_dirty = true
  end
  if not base_missing(file) then
    local ok, stats = pcall(file_stats, state.root, file, base_content(file))
    if ok and stats and not (file.stats and file.stats.add == stats.add and file.stats.del == stats.del) then
      file.stats = stats
      panel_dirty = true
    end
  end
  if panel_dirty then
    render_panel()
  end
end

---Draw `file` in the right-hand side. Assumes any base content it needs is
---already cached; everything here is buffer and window work. Always called
---through the render_file wrapper below, which flags the render so the
---navigation autocmds do not mistake it for a jump to adopt.
local function do_render_file(file, focus)
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
    reset_cursorline(target)
    vim.api.nvim_win_set_buf(target, scratch("vcs://empty", { "" }))
    no_dim(target)
    balance(target)
  end

  state.diff_win = target
  state.shown = file
  state.shown_name = file and (state.root .. "/" .. file.path) or nil

  if file then
    mark_rendered(file)
  end

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

---All renders funnel through here so the navigation autocmds can tell the
---view placing its own buffers apart from an actual jump landing in a pane.
---
---Re-raises, so the pcall is only about clearing the `rendering` flag: a render
---that threw must not leave every later navigation looking like the view's own
---work. Callers decide what to do with the error; every one of them goes
---through report_render_failure below.
local function render_file(file, focus)
  rendering = true
  local ok, err = pcall(do_render_file, file, focus)
  rendering = false
  if not ok then
    error(err, 0)
  end
end

---Render, and report a failure the way the async path already did.
---
---A diff that cannot be drawn is worth saying out loud once; it is not worth an
---unhandled error. The debounce timer and the panel keys used to call
---render_file bare, so a render that threw surfaced as Neovim's raw
---"vim.schedule callback" traceback — mid-scrub, with the view left half drawn
---and nothing said about which file caused it.
---@return boolean ok
local function try_render(file, focus)
  local ok, err = pcall(render_file, file, focus)
  if not ok then
    vim.notify(("vcs render: %s%s"):format(file and (file.path .. ": ") or "", tostring(err)), vim.log.levels.ERROR)
  end
  return ok
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

  try_render(file, focus)
end

---Warm the base cache for the listed files in the background, so a diff is
---already in hand by the time the selection reaches it. One coroutine, one
---subprocess at a time: gentle on a loaded server, and the UI never waits on
---any of it.
---
---The sweep is steered rather than scheduled. Every iteration re-reads where
---the cursor is and takes the nearest file that still has no base, so moving
---the selection re-aims the prefetch at the neighbourhood being read instead
---of working through an order fixed when the view opened — and it stands
---aside while an interactive render holds a subprocess, since the file being
---looked at is always worth more than the one being guessed at. Between those
---two it keeps going until the listing is covered or the budget runs out.
---
---A file the cursor reaches first is fetched by the render path instead;
---whoever gets there first fills the cache for both.

-- What one sweep may pull in. The file count stays well inside the cache's
-- capacity: filling it to eviction would wipe the base of the file being
-- looked at (the policy above is deliberately crude) and the sweep would
-- start over. The byte budget is the real backstop — a changelist of
-- generated, vendored or minified files must not quietly eat hundreds of
-- megabytes just because it is short enough to fit the count.
local PREFETCH_MAX_FILES = math.floor(BASE_CACHE_MAX / 2)
local PREFETCH_MAX_BYTES = 32 * 1024 * 1024
-- How long to stand aside for a render in flight before looking again, and
-- how many times running before pressing on regardless.
local PREFETCH_YIELD_MS = 60
local PREFETCH_YIELD_MAX = 50

---Roughly how much memory a cached base occupies.
local function content_bytes(lines)
  local n = 0
  for _, l in ipairs(lines or {}) do
    n = n + #l + 1
  end
  return n
end

---Suspend the running prefetch coroutine for `ms`. Lets it wait out an
---interactive render without blocking the loop it runs on — the same trick
---vcs.async plays for subprocesses, on a timer instead.
local function nap(ms)
  local co = coroutine.running()
  if not co then
    return
  end
  vim.defer_fn(function()
    local ok, err = coroutine.resume(co)
    if not ok then
      vim.notify("vcs prefetch: " .. tostring(err), vim.log.levels.ERROR)
    end
  end, ms)
  coroutine.yield()
end

---The next file worth fetching: the nearest one to the cursor — forward,
---then wrapping — that this sweep has not handled yet. Re-derived per fetch,
---which is what makes the sweep follow the selection around.
local function next_prefetch(done)
  local files, at = {}, 1
  local here = row_at_cursor()
  for _, row in ipairs(state.rows) do
    if row.kind == "file" then
      files[#files + 1] = row.file
      if row == here then
        at = #files
      end
    end
  end
  for i = 0, #files - 1 do
    local file = files[((at - 1 + i) % #files) + 1]
    if not done[file] then
      return file
    end
  end
  return nil
end

local function prefetch_bases()
  prefetch_gen = prefetch_gen + 1
  prefetch_busy = false
  if not valid() or #state.files == 0 then
    return
  end
  local gen = prefetch_gen
  local backend, root, rev = state.backend, state.root, state.rev

  prefetch_busy = true
  vcs.async(function()
    local ok, err = pcall(function()
      local stats_dirty = 0
      local function paint()
        if stats_dirty > 0 and gen == prefetch_gen and valid() then
          render_panel()
          stats_dirty = 0
        end
      end
      -- Files this sweep has already looked at, so one the render path filled
      -- in is passed over rather than reconsidered on every pick.
      local done = {}
      local fetched, bytes = 0, 0
      while fetched < PREFETCH_MAX_FILES and bytes < PREFETCH_MAX_BYTES do
        if gen ~= prefetch_gen or not valid() then
          return
        end
        -- Stand aside for a render: it is fetching what the user is actually
        -- waiting on. Show what the sweep has learned so far while waiting.
        -- Bounded, so a render that never reports back stalls the sweep for a
        -- moment rather than retiring it.
        for _ = 1, PREFETCH_YIELD_MAX do
          if render_busy == 0 then
            break
          end
          paint()
          nap(PREFETCH_YIELD_MS)
          if gen ~= prefetch_gen or not valid() then
            return
          end
        end
        local file = next_prefetch(done)
        if not file then
          break
        end
        done[file] = true
        local base = {}
        if has_base(file) then
          local base_path = file.orig or file.path
          local file_rev = file.rev or rev
          local key = base_key(root, file_rev, base_path)
          if not base_cache[key] then
            local epoch = base_epoch
            local content = backend.show(root, file_rev, base_path)
            if gen ~= prefetch_gen then
              return
            end
            -- A drop_bases while the subprocess ran means this content
            -- describes a revision the view no longer believes in; the sweep
            -- that replaces this one will re-ask.
            if epoch ~= base_epoch then
              return
            end
            store_base(key, content or {})
            fetched = fetched + 1
            bytes = bytes + content_bytes(content)
          end
          base = base_cache[key] or {}
        end
        -- With the base in hand the file's +n -n is free. Files judged too
        -- big get zeros rather than staying nil, so they are not re-judged
        -- on every sweep.
        if not file.stats then
          local ok_stats, stats = pcall(file_stats, root, file, base)
          if ok_stats then
            file.stats = stats or { add = 0, del = 0 }
            if stats then
              stats_dirty = stats_dirty + 1
              -- Repaint in batches, so a long sweep over a cold server shows
              -- numbers trickling in rather than nothing until the end.
              if stats_dirty >= 16 then
                paint()
              end
            end
          end
        end
      end
      paint()
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
  -- Out of libuv handles is not something to paper over: the debounce is what
  -- keeps holding `j` through a changelist from rendering a diff per keystroke.
  scrub_timer = assert(vim.uv.new_timer())
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

---Step the diff to the next / previous change from the list, cursor staying
---in the panel: the right-hand side moves to follow its own cursor, so a
---file can be walked hunk by hunk without leaving the list.
local function change_diff(dir)
  if not valid() then
    return
  end
  local win = state.diff_win
  if not (win and vim.api.nvim_win_is_valid(win)) then
    win = diff_wins()[1]
  end
  if not win then
    return
  end
  vim.api.nvim_win_call(win, function()
    local buf = vim.api.nvim_win_get_buf(win)
    local index, total
    if vim.wo.diff then
      pcall(vim.cmd, "normal! " .. (dir > 0 and "]c" or "[c"))
      index, total = M.change_position()
    elseif inline_diff.has(buf) then
      inline_diff.goto_hunk(buf, dir)
      index, total = inline_diff.hunk_position(buf)
    end
    if total and total > 0 then
      vim.api.nvim_echo({ { ("Change %d of %d"):format(index, total), "None" } }, false, {})
    end
  end)
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
-- adopting navigation: gd and friends keep the diff rendering
--------------------------------------------------------------------------

-- A jump from inside a diff pane — goto-definition, a reference picker,
-- <C-o>, a plain :e — lands its target in that pane as an ordinary buffer:
-- the window would keep stale diff mode or expr folds, the overlay would
-- still hang on the buffer left behind, and the panel selection would point
-- somewhere else entirely. Instead the view adopts the navigation. The pane
-- is re-dressed in place — the window is reused, never rebuilt, so the
-- jumplist keeps working and <C-o> walks back — and the old preview is kept
-- loaded (hidden, unlisted) rather than dropped, because wiping it would
-- take its jumplist entries with it. close() still cleans those up.

---Re-dress the window a navigation just landed `buf` in. A file from the
---changed listing gets its full diff rendering (inline overlay or
---side-by-side against the same base) and the panel selection follows;
---anything else — an unchanged file, one outside the repository — shows
---plain, with the previous rendering's diff mode and folds scrubbed off.
local function do_adopt_nav(win, buf)
  if not valid() then
    return
  end
  if not (vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf) then
    return
  end
  if vim.api.nvim_win_get_tabpage(win) ~= state.tab or win == state.panel_win then
    return
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" or name == state.shown_name then
    return
  end

  cancel_scrub()
  -- Orphan any in-flight render of the panel selection; the navigation is
  -- newer than whatever a debounce or an async base fetch was about to paint.
  render_gen = render_gen + 1

  -- Which listed file did the jump land in, if any? The panel selection
  -- follows it, so j/k and ]f/[f continue from here.
  local file
  local prefix = state.root .. "/"
  local rel = name:sub(1, #prefix) == prefix and name:sub(#prefix + 1) or nil
  if rel then
    for i, row in ipairs(state.rows) do
      if row.kind == "file" and row.file.path == rel then
        file = row.file
        pcall(vim.api.nvim_win_set_cursor, state.panel_win, { state.first_line + i - 1, 0 })
        break
      end
    end
  end

  -- The jump listed the buffer as a side effect; a file that was not already
  -- open on purpose stays a preview here, exactly as if the panel had
  -- rendered it — following definitions around leaves no trace either.
  if nav_listed[buf] then
    track_preview(buf)
  end
  nav_listed = {}

  -- Whatever else the old rendering had on screen — a side-by-side base, an
  -- empty placeholder — belongs to the file the view just moved off.
  if state.inline_buf then
    inline_diff.detach(state.inline_buf)
    state.inline_buf = nil
  end
  for _, w in ipairs(diff_wins()) do
    if w ~= win then
      pcall(vim.api.nvim_win_close, w, true)
    end
  end

  reset_cursorline(win)
  no_dim(win)
  if file and state.inline then
    state.inline_buf = buf
    inline_diff.attach(buf, base_content(file))
    inline_pane(win)
    balance(win)
  elseif file then
    local base = base_content(file)
    local base_path = file.orig or file.path
    vim.api.nvim_set_current_win(win)
    vim.cmd("vertical leftabove split")
    local left = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(left, scratch(("vcs://%s/%s"):format(state.rev:sub(1, 12), base_path), base, base_path))
    diff_pane(left)
    diff_pane(win)
    balance(left, win)
  else
    -- Not a changed file (or outside the repository): its diff is empty, so
    -- show it plain — but sanitized, since diff mode or expr folds left over
    -- from the previous rendering must not bleed onto an unrelated file.
    if vim.wo[win].diff then
      vim.api.nvim_win_call(win, function()
        vim.cmd("diffoff")
      end)
    end
    wo_local(win, "foldmethod", "manual")
    wo_local(win, "foldlevel", 99)
    wo_local(win, "number", true)
    wo_local(win, "relativenumber", true)
    balance(win)
  end

  state.diff_win = win
  state.shown = file
  state.shown_name = name
  if file then
    mark_rendered(file)
  end
  update_header()
  setup_diff_keys()
  vim.api.nvim_set_current_win(win)
  -- The jump target may sit inside a collapsed region; open just enough
  -- folds that it is actually visible.
  vim.api.nvim_win_call(win, function()
    pcall(vim.cmd, "normal! zv")
  end)
end

local function adopt_nav(win, buf)
  rendering = true
  local ok, err = pcall(do_adopt_nav, win, buf)
  rendering = false
  if not ok then
    vim.notify("vcs adopt: " .. tostring(err), vim.log.levels.ERROR)
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

---Copy the selected file's diff to the clipboard — for pasting into a chat
---or a review comment without leaving the list.
local function yank_file_diff()
  local file = current_file()
  if not file then
    return
  end
  local backend, root, rev = state.backend, state.root, base_rev(file)
  vcs.async(function()
    local text = backend.raw_diff(root, rev, file.path, file.orig)
    if not text or text == "" then
      vim.notify(("No diff for %s"):format(file.path), vim.log.levels.INFO)
      return
    end
    vim.fn.setreg("+", text)
    local count = select(2, text:gsub("\n", "\n"))
    vim.notify(("Copied %d-line diff of %s"):format(count, file.path))
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
  { "<CR> / Space", "focus the diff" },
  { "J / K", "scroll the diff from the list" },
  { "]c / [c", "next / previous change in the diff" },
  { "]f / [f", "next / previous file, from inside the diff" },
  { "s", "cycle scope: uncommitted / branch / last commit" },
  { "i", "toggle inline and side-by-side" },
  { "z", "toggle collapsing unchanged regions" },
  { "a", "stage / unstage file (git)" },
  { "y", "copy this file's diff" },
  { "X", "revert file" },
  { "m", "merge view for a conflicted file" },
  { "r", "hard refresh" },
  { "q", "close" },
}

local function show_help()
  local lines = {}
  for _, entry in ipairs(HELP) do
    table.insert(lines, ("  %-12s %s"):format(entry[1], entry[2]))
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
    vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { end_col = 14, hl_group = "Special" })
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
  -- <Space> is leader, and mapping it here (nowait, so it fires immediately)
  -- makes every <leader> binding unreachable while the panel is focused.
  -- Deliberate: selecting a file is what this panel is for, constantly, and
  -- the leader keys are all one window away.
  for _, lhs in ipairs({ "<CR>", "<Space>", "o", "l", "<Right>" }) do
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
  map("]c", function()
    change_diff(1)
  end, "Next change in the diff")
  map("[c", function()
    change_diff(-1)
  end, "Previous change in the diff")
  map("r", function()
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
  map("z", function()
    M.toggle_collapse()
  end, "Toggle collapsing unchanged regions")
  map("a", stage_toggle, "Stage / unstage file")
  map("y", yank_file_diff, "Copy this file's diff")
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
  wo_local(win, "number", false)
  wo_local(win, "relativenumber", false)
  wo_local(win, "wrap", false)
  wo_local(win, "cursorline", true)
  -- The global cursorlineopt is "number", and the panel has no numbers — so
  -- without this the selected file would get no highlight at all.
  wo_local(win, "cursorlineopt", "line")
  wo_local(win, "winfixwidth", true)

  state = state or {}
  state.tab = vim.api.nvim_get_current_tabpage()
  state.panel_win = win
  state.panel_buf = buf
  state.origin_tab = origin
  if state.inline == nil then
    state.inline = remembered_inline
  end
  if state.collapse == nil then
    state.collapse = remembered_collapse
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
  -- A navigation inside the view replaces the buffer in a diff pane without
  -- telling the view; adopt it (see do_adopt_nav). Scheduled, so the jump
  -- has finished placing the cursor before the pane is re-dressed — and both
  -- events are watched because :edit and nvim_win_set_buf fire them in
  -- different orders.
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    group = group,
    callback = function(ev)
      if rendering or not valid() then
        return
      end
      if vim.api.nvim_get_current_tabpage() ~= state.tab then
        return
      end
      local nav_win = vim.api.nvim_get_current_win()
      -- Floats too: a picker's preview shows real file buffers without them
      -- being navigated to.
      if nav_win == state.panel_win or vim.api.nvim_win_get_config(nav_win).relative ~= "" then
        return
      end
      if vim.api.nvim_win_get_buf(nav_win) ~= ev.buf or vim.bo[ev.buf].buftype ~= "" then
        return
      end
      local name = vim.api.nvim_buf_get_name(ev.buf)
      if name == "" or name == state.shown_name then
        return
      end
      -- Coalesce to one adoption per tick — a single jump fires several of
      -- these — but resolve the buffer only when it runs, never here. Two
      -- jumps can share a tick (`<C-o><C-o>` arrives as one chunk of
      -- typeahead, which Neovim drains ahead of scheduled callbacks), and
      -- adopting the buffer the *first* event named would find the pane
      -- holding the second one and bail, leaving the navigation unadopted.
      nav_win_pending = nav_win
      if nav_pending then
        return
      end
      nav_pending = true
      vim.schedule(function()
        nav_pending = false
        local win = nav_win_pending
        nav_win_pending = nil
        if win and vim.api.nvim_win_is_valid(win) then
          adopt_nav(win, vim.api.nvim_win_get_buf(win))
        end
      end)
    end,
  })
  -- `:edit` and the LSP jumps list their target as a side effect; remember
  -- which buffers joined the list from inside a diff pane, so adoption can
  -- tell a file the jump itself opened (a preview) from one the user already
  -- had open (left alone).
  vim.api.nvim_create_autocmd("BufAdd", {
    group = group,
    callback = function(ev)
      if rendering or not valid() then
        return
      end
      if vim.api.nvim_get_current_tabpage() ~= state.tab then
        return
      end
      local add_win = vim.api.nvim_get_current_win()
      if add_win ~= state.panel_win and vim.api.nvim_win_get_config(add_win).relative == "" then
        nav_listed[ev.buf] = true
      end
    end,
  })
  -- The other half of track_preview's promotion, and the only half on 0.13.
  -- 'modified' is buffer-local, so OptionSet fires with its buffer current
  -- rather than naming it in the event — ev.buf is 0 here. Never returns true:
  -- unlike the per-buffer form this one serves every preview and must outlive
  -- any single promotion.
  vim.api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = "modified",
    callback = function()
      promote_preview(vim.api.nvim_get_current_buf())
    end,
  })
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
  if not (backend and root) then
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

---Open the view, or when it is already open just go to it: jump to its tab
---and focus the file list, whose cursorline is the selection highlight —
---never closing, and never resetting the selection the way a re-open would.
---Closing is its own action (`<leader>gC`, or q in the list). A *different*
---scope requested from inside switches scope instead.
---@param opts? { scope?: string, rev?: string }
function M.focus(opts)
  opts = opts or {}
  if valid() and not opts.rev and (not opts.scope or opts.scope == state.scope) then
    vim.api.nvim_set_current_tabpage(state.tab)
    vim.api.nvim_set_current_win(state.panel_win)
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
  -- A refresh is not a restart: the reviewer's place — which file is
  -- selected, and where in its diff they were reading — survives it.
  local selected = current_file()
  local diff_pos
  if
    selected
    and state.shown
    and state.shown.path == selected.path
    and state.diff_win
    and vim.api.nvim_win_is_valid(state.diff_win)
  then
    diff_pos = vim.api.nvim_win_get_cursor(state.diff_win)
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
  -- Put the cursor back on the file it was on (open() reset it to the first
  -- one); if that file left the listing, the first file is the right answer.
  if selected and valid() then
    for i, row in ipairs(state.rows) do
      if row.kind == "file" and row.file.path == selected.path then
        vim.api.nvim_win_set_cursor(state.panel_win, { state.first_line + i - 1, 0 })
        update_header()
        if not (state.shown and state.shown.path == selected.path) then
          show(false)
        end
        if diff_pos and state.diff_win and vim.api.nvim_win_is_valid(state.diff_win) then
          pcall(vim.api.nvim_win_set_cursor, state.diff_win, diff_pos)
        end
        break
      end
    end
  end
end

function M.close()
  cancel_scrub()
  -- Orphan the in-flight render and revalidation; a running prefetch is left
  -- to finish quietly, since the cache it warms is what makes the next open
  -- instant.
  refresh_gen = refresh_gen + 1
  render_gen = render_gen + 1
  nav_listed = {}
  nav_win_pending = nil
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
  -- The one place the view is torn down; see the note on the declaration.
  ---@diagnostic disable-next-line: cast-local-type
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
  if not (backend and root) then
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
---Redraw after a rendering toggle, leaving focus (and with it the reading
---position, which render_file preserves for the file already on show) where
---it is: a toggle pressed from inside the diff must not dump the cursor back
---into the file list.
local function rerender_for_toggle()
  local in_diff = vim.api.nvim_get_current_tabpage() == state.tab and vim.api.nvim_get_current_win() ~= state.panel_win
  if in_diff then
    -- The pane can hold something the view is not rendering — an adopted
    -- unchanged file, the empty placeholder. There is nothing to redraw in
    -- the other mode, and re-rendering the panel selection would replace
    -- what is being looked at; the flipped setting takes hold next render.
    if state.shown then
      try_render(state.shown, true)
    end
    return
  end
  -- On a directory or header row show() would keep the previous rendering;
  -- redraw that file explicitly so the toggle is never silently deferred.
  if current_file() or #state.files == 0 then
    show(false)
  elseif state.shown then
    try_render(state.shown, false)
  end
end

function M.toggle_inline()
  if valid() then
    state.inline = not state.inline
    remembered_inline = state.inline
    rerender_for_toggle()
    return
  end
  -- Outside the diff tab this is still the natural "show me the other layout"
  -- key: flip vertical/horizontal split on an ad-hoc diff.
  if vim.wo.diff then
    vim.cmd("wincmd " .. (vim.fn.winwidth(0) > vim.fn.winheight(0) * 3 and "K" or "H"))
  end
end

---Toggle collapsing unchanged regions, in whichever rendering is up: the
---overlay's expr folds inline, diff mode's native folds side-by-side. Works
---from anywhere — inside the view it re-renders, and in any other tab (an
---ad-hoc <leader>gd, a history diff) it re-levels the diff windows in place,
---never yanking focus to the view's tab.
function M.toggle_collapse()
  local on
  if valid() then
    state.collapse = not state.collapse
    remembered_collapse = state.collapse
    on = state.collapse
    if vim.api.nvim_get_current_tabpage() == state.tab then
      rerender_for_toggle()
      return
    end
  else
    remembered_collapse = not remembered_collapse
    on = remembered_collapse
  end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.wo[w].diff then
      wo_local(w, "foldlevel", on and 0 or 99)
    end
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
  local function win_text(win)
    local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
    return table.concat(lines, "\n") .. "\n"
  end
  -- Match the settings native diff mode is using, or the count disagrees with
  -- where ]c actually stops.
  local hunks = diff_hunks(win_text(other), win_text(cur), {
    algorithm = vim.o.diffopt:match("algorithm:(%w+)") or "myers",
    indent_heuristic = vim.o.diffopt:find("indent%-heuristic") ~= nil,
  })
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

---Absolute path of the file the current buffer stands for, when that buffer
---belongs to a diff and its own name is not a real path: anywhere in the
---view's tab the selection answers (so the base side of a side-by-side and a
---deleted-file pane resolve, and a rename resolves to the new path), and a
---vcs:// scratch from an ad-hoc diff (<leader>gd, history) is parsed back to
---the file it renders. Nil for ordinary buffers — their own name is already
---the answer.
function M.current_path()
  if valid() and vim.api.nvim_get_current_tabpage() == state.tab then
    local file = state.shown or current_file()
    if file then
      return state.root .. "/" .. file.path
    end
  end
  local path = vim.api.nvim_buf_get_name(0):match("^vcs://[^/]*/(.*)$")
  if path then
    local _, root = vcs.detect()
    if root then
      return root .. "/" .. path
    end
  end
  return nil
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
  if not (backend and root) then
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
  if not (backend and root) then
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
  if not (backend and root) then
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
