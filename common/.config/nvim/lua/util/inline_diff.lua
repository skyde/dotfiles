-- An editable inline diff: the real buffer, with the base version's missing
-- lines drawn between the lines as virtual text and the new lines highlighted.
-- This is what VS Code's diff editor shows with renderSideBySide off — and
-- like that editor, the buffer stays a perfectly ordinary editable file.
--
-- The overlay is recomputed from the buffer contents on every edit, so it
-- tracks typing; the base side is fixed at attach time. Backend-agnostic by
-- construction: all it needs is the base content as a list of lines.

local M = {}

local ns = vim.api.nvim_create_namespace("vcs_inline_diff")

---@class InlineDiffState
---@field base string[]
---@field base_text string
---@field hunks integer[][]  { start_a, count_a, start_b, count_b } as vim.diff returns
local states = {} ---@type table<integer, InlineDiffState>

---Recompute hunks and redraw the overlay for `buf`.
function M.render(buf)
  local st = states[buf]
  if not st or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local buf_text = table.concat(lines, "\n") .. "\n"
  st.hunks = vim.diff(st.base_text, buf_text, { result_type = "indices" }) or {}

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local last = #lines
  for _, h in ipairs(st.hunks) do
    local start_a, count_a, start_b, count_b = h[1], h[2], h[3], h[4]

    if count_a > 0 then
      local virt = {}
      for i = start_a, start_a + count_a - 1 do
        virt[#virt + 1] = { { st.base[i] or "", "DiffDelete" } }
      end
      if count_b > 0 then
        -- A change: the old lines sit directly above their replacements.
        vim.api.nvim_buf_set_extmark(buf, ns, start_b - 1, 0, { virt_lines = virt, virt_lines_above = true })
      elseif start_b == 0 then
        -- Deleted from the very top of the file.
        vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { virt_lines = virt, virt_lines_above = true })
      elseif start_b >= last then
        -- Deleted from the end; there is no line below to hang them above.
        vim.api.nvim_buf_set_extmark(buf, ns, last - 1, 0, { virt_lines = virt })
      else
        vim.api.nvim_buf_set_extmark(buf, ns, start_b, 0, { virt_lines = virt, virt_lines_above = true })
      end
    end

    for row = start_b, start_b + count_b - 1 do
      vim.api.nvim_buf_set_extmark(buf, ns, row - 1, 0, { line_hl_group = "DiffAdd", priority = 50 })
    end
  end
end

---Overlay `base` onto `buf` and keep it current as the buffer is edited.
---@param buf integer
---@param base string[]
function M.attach(buf, base)
  M.detach(buf)
  states[buf] = { base = base, base_text = #base > 0 and (table.concat(base, "\n") .. "\n") or "" }
  M.render(buf)
  vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave" }, {
    group = vim.api.nvim_create_augroup("vcs_inline_diff_" .. buf, { clear = true }),
    buffer = buf,
    callback = function()
      if states[buf] then
        M.render(buf)
      end
    end,
  })
end

function M.detach(buf)
  if not states[buf] then
    return
  end
  states[buf] = nil
  pcall(vim.api.nvim_del_augroup_by_name, "vcs_inline_diff_" .. buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  end
end

local function resolve(buf)
  return (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
end

---True when `buf` (default: current) has an overlay.
function M.has(buf)
  return states[resolve(buf)] ~= nil
end

---The hunk whose new side contains `row`, or nil.
local function hunk_at(st, row)
  for _, h in ipairs(st.hunks) do
    local start_b, count_b = h[3], h[4]
    local first = count_b > 0 and start_b or math.max(start_b, 1)
    local until_ = count_b > 0 and (start_b + count_b - 1) or math.max(start_b, 1)
    if row >= first and row <= until_ then
      return h
    end
  end
  return nil
end

---Jump to the next/previous hunk, wrapping like `n` does.
---@param dir 1|-1
function M.goto_hunk(buf, dir)
  buf = resolve(buf)
  local st = states[buf]
  if not st or #st.hunks == 0 then
    return false
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local starts = {}
  for _, h in ipairs(st.hunks) do
    starts[#starts + 1] = h[4] > 0 and h[3] or math.max(h[3], 1)
  end
  local target
  if dir > 0 then
    for _, s in ipairs(starts) do
      if s > row then
        target = s
        break
      end
    end
    target = target or starts[1]
  else
    for i = #starts, 1, -1 do
      if starts[i] < row then
        target = starts[i]
        break
      end
    end
    target = target or starts[#starts]
  end
  vim.api.nvim_win_set_cursor(0, { math.min(target, vim.api.nvim_buf_line_count(buf)), 0 })
  return true
end

---Put the cursor on the first hunk.
function M.goto_first(buf)
  buf = resolve(buf)
  local st = states[buf]
  local h = st and st.hunks[1]
  if h then
    local row = h[4] > 0 and h[3] or math.max(h[3], 1)
    pcall(vim.api.nvim_win_set_cursor, 0, { math.min(row, vim.api.nvim_buf_line_count(buf)), 0 })
  end
end

---Revert the hunk under the cursor to the base version, VS Code's inline
---revert arrow. Returns false when the cursor is not on a hunk.
function M.revert_hunk(buf)
  buf = resolve(buf)
  local st = states[buf]
  if not st then
    return false
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local h = hunk_at(st, row)
  if not h then
    return false
  end
  local start_a, count_a, start_b, count_b = h[1], h[2], h[3], h[4]
  local replacement = {}
  for i = start_a, start_a + count_a - 1 do
    replacement[#replacement + 1] = st.base[i]
  end
  local from, to
  if count_b > 0 then
    from, to = start_b - 1, start_b - 1 + count_b
  else
    -- Pure deletion: the base lines go back in after start_b.
    from, to = start_b, start_b
  end
  vim.api.nvim_buf_set_lines(buf, from, to, false, replacement)
  M.render(buf)
  return true
end

return M
