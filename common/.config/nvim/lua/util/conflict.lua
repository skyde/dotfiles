-- Merge-conflict resolution driven off the markers in the buffer.
--
-- Deliberately marker-based rather than git-based: p4, jj and git all write the
-- same `<<<<<<< / ||||||| / ======= / >>>>>>>` shape, so one implementation
-- covers every backend, and it also works on a conflicted file that was handed
-- over by some other tool entirely.
--
-- `merge.conflictstyle = zdiff3` in the git config means the base section is
-- usually present, which is why `base` is a choice here and not just ours or
-- theirs.

local M = {}

local ns = vim.api.nvim_create_namespace("vcs_conflict")

---@class Conflict
---@field start integer     line of `<<<<<<<`
---@field base_start integer|nil  line of `|||||||`
---@field mid integer       line of `=======`
---@field finish integer    line of `>>>>>>>`

---Every conflict in the buffer, in order.
---@param buf integer|nil
---@return Conflict[]
function M.list(buf)
  buf = buf or 0
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local out, current = {}, nil
  for i, line in ipairs(lines) do
    if line:match("^<<<<<<<%s") or line:match("^<<<<<<<$") then
      current = { start = i }
    elseif current and (line:match("^|||||||") or line:match("^%|%|%|%|%|%|%|")) then
      current.base_start = i
    elseif current and line:match("^=======%s*$") then
      current.mid = i
    elseif current and (line:match("^>>>>>>>%s") or line:match("^>>>>>>>$")) then
      if current.mid then
        current.finish = i
        table.insert(out, current)
      end
      current = nil
    end
  end
  return out
end

---The conflict containing (or nearest after) the cursor.
---@param buf integer|nil
local function at_cursor(buf)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  for _, c in ipairs(M.list(buf)) do
    if row >= c.start and row <= c.finish then
      return c
    end
  end
  return nil
end

---Highlight the ours/base/theirs regions of every conflict in the buffer.
---Called on write and on entering a buffer so the colours track edits.
---@param buf integer|nil
function M.highlight(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, c in ipairs(M.list(buf)) do
    local ours_end = (c.base_start or c.mid) - 1
    for row = c.start - 1, ours_end - 1 do
      vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { line_hl_group = "DiffAdd", priority = 50 })
    end
    if c.base_start then
      for row = c.base_start - 1, c.mid - 2 do
        vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { line_hl_group = "DiffChange", priority = 50 })
      end
    end
    for row = c.mid - 1, c.finish - 1 do
      vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { line_hl_group = "DiffText", priority = 50 })
    end
  end
end

---Jump to the next/previous conflict, wrapping like `n` does.
---@param dir 1|-1
function M.goto_conflict(dir)
  local conflicts = M.list(0)
  if #conflicts == 0 then
    vim.notify("No conflicts in this buffer", vim.log.levels.INFO)
    return
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local target
  if dir > 0 then
    for _, c in ipairs(conflicts) do
      if c.start > row then
        target = c
        break
      end
    end
    target = target or conflicts[1]
  else
    for i = #conflicts, 1, -1 do
      if conflicts[i].start < row then
        target = conflicts[i]
        break
      end
    end
    target = target or conflicts[#conflicts]
  end
  vim.api.nvim_win_set_cursor(0, { target.start, 0 })
  vim.cmd("normal! zz")
end

---Resolve the conflict under the cursor.
---@param which "ours"|"theirs"|"both"|"base"|"none"
function M.choose(which)
  local buf = vim.api.nvim_get_current_buf()
  local c = at_cursor(buf)
  if not c then
    vim.notify("Cursor is not inside a conflict", vim.log.levels.WARN)
    return
  end

  local function slice(from, to)
    if to < from then
      return {}
    end
    return vim.api.nvim_buf_get_lines(buf, from - 1, to, false)
  end

  local ours = slice(c.start + 1, (c.base_start or c.mid) - 1)
  local base = c.base_start and slice(c.base_start + 1, c.mid - 1) or {}
  local theirs = slice(c.mid + 1, c.finish - 1)

  local replacement = ({
    ours = ours,
    theirs = theirs,
    base = base,
    both = vim.list_extend(vim.list_extend({}, ours), theirs),
    none = {},
  })[which]

  vim.api.nvim_buf_set_lines(buf, c.start - 1, c.finish, false, replacement)
  vim.api.nvim_win_set_cursor(0, { math.min(c.start, vim.api.nvim_buf_line_count(buf)), 0 })
  M.highlight(buf)

  local left = #M.list(buf)
  vim.notify(("Took %s · %d conflict%s left"):format(which, left, left == 1 and "" or "s"))
end

---Resolve every conflict in the buffer the same way.
---@param which "ours"|"theirs"|"both"|"base"|"none"
function M.choose_all(which)
  local buf = vim.api.nvim_get_current_buf()
  local n = 0
  -- Resolving shifts every line below, so always work on the last conflict
  -- first and re-list after each edit rather than caching positions.
  while true do
    local conflicts = M.list(buf)
    if #conflicts == 0 then
      break
    end
    local c = conflicts[#conflicts]
    vim.api.nvim_win_set_cursor(0, { c.start, 0 })
    M.choose(which)
    n = n + 1
    if n > 1000 then
      break
    end
  end
  vim.notify(("Took %s for %d conflict%s"):format(which, n, n == 1 and "" or "s"))
end

---True when the current buffer has unresolved markers; used by `<leader>cn` to
---decide between conflict navigation and plain diff-hunk navigation.
function M.has_conflicts(buf)
  return #M.list(buf or 0) > 0
end

---A three-way view of the conflicted file, standing in for VS Code's merge
---editor: ours on the left, the file you are editing in the middle, theirs on
---the right, all three in diff mode. The outer panes are reconstructions from
---the markers, so this works for any backend and needs no index access.
---Resolve in the middle pane with the choose keys, or with `do`/`dp` from the
---sides, then `<leader>cq` to save and close.
function M.merge_view()
  local buf = vim.api.nvim_get_current_buf()
  local conflicts = M.list(buf)
  if #conflicts == 0 then
    vim.notify("No conflicts in this buffer", vim.log.levels.WARN)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local path = vim.api.nvim_buf_get_name(buf)
  local ft = vim.bo[buf].filetype

  ---Rebuild the file as it would read if every conflict were resolved `which`.
  local function side(which)
    local out = {}
    local row, idx = 1, 1
    while row <= #lines do
      local c = conflicts[idx]
      if c and row == c.start then
        local from, to
        if which == "ours" then
          from, to = c.start + 1, (c.base_start or c.mid) - 1
        elseif which == "base" then
          from, to = c.base_start and c.base_start + 1 or c.mid, c.mid - 1
        else
          from, to = c.mid + 1, c.finish - 1
        end
        for i = from, to do
          table.insert(out, lines[i])
        end
        row = c.finish + 1
        idx = idx + 1
      else
        table.insert(out, lines[row])
        row = row + 1
      end
    end
    return out
  end

  local function pane(name, content)
    local b = vim.api.nvim_create_buf(false, true)
    vim.bo[b].buftype = "nofile"
    vim.bo[b].bufhidden = "wipe"
    vim.bo[b].swapfile = false
    vim.api.nvim_buf_set_lines(b, 0, -1, false, content)
    vim.bo[b].modifiable = false
    vim.bo[b].filetype = ft
    pcall(vim.api.nvim_buf_set_name, b, ("merge://%s/%s"):format(name, vim.fn.fnamemodify(path, ":t")))
    return b
  end

  vim.cmd("tab split")
  local middle = vim.api.nvim_get_current_win()
  vim.cmd("leftabove vertical split")
  local left = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(left, pane("ours", side("ours")))
  vim.api.nvim_set_current_win(middle)
  vim.cmd("rightbelow vertical split")
  local right = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(right, pane("theirs", side("theirs")))

  for _, w in ipairs({ left, middle, right }) do
    vim.api.nvim_win_call(w, function()
      vim.cmd("diffthis")
      vim.wo.foldlevel = 99
      -- Relative numbers make three diffed panes impossible to line up.
      vim.wo.number = true
      vim.wo.relativenumber = false
    end)
  end
  vim.api.nvim_set_current_win(middle)
  M.highlight(buf)
  vim.notify("Merge view: ours | working | theirs — <leader>co/ct/cb to resolve, <leader>cq to finish")
end

---Save the resolved file and drop back out of the merge view.
function M.finish()
  -- The merge view's outer panes are read-only reconstructions that never
  -- carry markers, and `<leader>cc` is how you get to them — so asking the
  -- *focused* buffer whether anything is left would answer "nothing" and
  -- close the view with the real file still conflicted. That is exactly the
  -- accident this refusal exists to prevent. Answer for the working copy.
  if vim.api.nvim_buf_get_name(0):match("^merge://") then
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.bo[vim.api.nvim_win_get_buf(w)].buftype == "" then
        vim.api.nvim_set_current_win(w)
        break
      end
    end
  end
  if M.has_conflicts(0) then
    local left = #M.list(0)
    vim.notify(("Still %d unresolved conflict%s"):format(left, left == 1 and "" or "s"), vim.log.levels.WARN)
    return
  end
  if vim.bo.modifiable and vim.api.nvim_buf_get_name(0) ~= "" then
    vim.cmd("write")
  end
  if vim.fn.tabpagenr("$") > 1 then
    vim.cmd("tabclose")
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("vcs_conflict", { clear = true })

  -- Scan on read, and only keep watching buffers that turned out to be
  -- conflicted. Re-scanning every buffer on every keystroke would mean reading
  -- the whole file on each character typed, which is exactly the cost you
  -- cannot pay in the large repos this config is aimed at.
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
    group = group,
    callback = function(args)
      if vim.bo[args.buf].buftype ~= "" then
        return
      end
      local had = vim.b[args.buf].vcs_conflict_watched
      local has = #M.list(args.buf) > 0
      if not has and not had then
        return
      end
      M.highlight(args.buf)
      if has and not had then
        vim.b[args.buf].vcs_conflict_watched = true
        vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave" }, {
          group = group,
          buffer = args.buf,
          callback = function()
            M.highlight(args.buf)
          end,
        })
      end
    end,
  })
end

return M
