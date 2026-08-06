-- An editable inline diff: the real buffer, with the base version's missing
-- lines drawn between the lines as virtual text and the new lines highlighted.
-- This is what VS Code's diff editor shows with renderSideBySide off — and
-- like that editor, the buffer stays a perfectly ordinary editable file.
--
-- Within a changed line the differing tokens are emphasized on both sides,
-- exactly the way delta renders a patch in the terminal: the unchanged part
-- of an edited line dims, the changed tokens brighten — it is the dimming
-- that makes the emphasis carry. Lines that merely moved (deleted in one
-- place, reinserted verbatim in another) get their own colour instead of
-- reading as unrelated delete + add. The palette is delta's, verbatim, from
-- the [delta] section in common/.config/git/config — so this view and
-- `git diff` in a terminal are the same picture.
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

--------------------------------------------------------------------------
-- highlight groups
--------------------------------------------------------------------------

-- The overlay's own groups, mirroring delta's style names one to one. The
-- colours are the ones the [delta] section in common/.config/git/config sets
-- (palette reference: docs/tokyonight.md), so the inline overlay and a
-- delta-rendered patch are indistinguishable:
--   InlineDiffAdd          plus-style            a plain added line
--   InlineDiffAddDim       plus-non-emph-style   unchanged part of an edited line
--   InlineDiffAddEmph      plus-emph-style       changed tokens of an edited line
--   InlineDiffDelete       minus-style           a plain deleted line (virtual)
--   InlineDiffDeleteDim    minus-non-emph-style  unchanged part, old side
--   InlineDiffDeleteEmph   minus-emph-style      changed tokens, old side
--   InlineDiffMovedAdd     map-styles cyan       a line that landed here
--   InlineDiffMovedDelete  map-styles violet     the place a line left from
-- All are set with default=true, so a user (or theme) definition wins.

local PALETTE = {
  InlineDiffAdd = "#20432b",
  InlineDiffAddDim = "#17311f",
  InlineDiffAddEmph = "#2c5a3a",
  InlineDiffDelete = "#532727",
  InlineDiffDeleteDim = "#3f1f1f",
  InlineDiffDeleteEmph = "#683131",
  InlineDiffMovedAdd = "#12384a",
  InlineDiffMovedDelete = "#2e2547",
}

local function setup_highlights()
  for name, bg in pairs(PALETTE) do
    vim.api.nvim_set_hl(0, name, { default = true, bg = bg })
  end
end

setup_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("vcs_inline_diff_hl", { clear = true }),
  callback = setup_highlights,
})

--------------------------------------------------------------------------
-- token-level diff within a changed line pair
--------------------------------------------------------------------------

-- Guards on the intraline diff, both delta's: a pathological line is not
-- worth diffing at all, and a pair whose tokens mostly differ reads better
-- as a plain replacement than as emphasis over nearly everything
-- (max-line-distance, default 0.6).
local INTRALINE_MAX_BYTES = 1024
local INTRALINE_MAX_CHANGED = 0.6

---Delta's tokenization: maximal runs of word characters are tokens, and each
---gap between them (whitespace and punctuation, as one run) is a token too.
---Diffing these instead of characters is what keeps the emphasis on whole
---identifiers rather than on stray characters that happen to coincide.
---Bytes >= 0x80 count as word characters, so multibyte text stays in one
---piece. Returns the token strings and each token's 0-based byte offset.
---@param s string
---@return string[] tokens, integer[] offsets
local function tokenize(s)
  local tokens, offsets = {}, {}
  local i, n = 1, #s
  while i <= n do
    local from = i
    local word = s:find("^[%w_\128-\255]", i) ~= nil
    while i <= n and (s:find("^[%w_\128-\255]", i) ~= nil) == word do
      i = i + 1
    end
    tokens[#tokens + 1] = s:sub(from, i - 1)
    offsets[#offsets + 1] = from - 1
  end
  return tokens, offsets
end

---Differing spans between two single lines, as 0-based end-exclusive byte
---ranges — one list per side. Nil when emphasis would not help (huge lines,
---or lines that share almost nothing).
---@param old string
---@param new string
---@return {[1]: integer, [2]: integer}[]|nil old_spans, {[1]: integer, [2]: integer}[]|nil new_spans
local function token_diff(old, new)
  if #old > INTRALINE_MAX_BYTES or #new > INTRALINE_MAX_BYTES then
    return nil
  end
  local old_toks, old_offs = tokenize(old)
  local new_toks, new_offs = tokenize(new)
  local function joined(toks)
    return #toks > 0 and (table.concat(toks, "\n") .. "\n") or ""
  end
  local hunks = vim.diff(joined(old_toks), joined(new_toks), { result_type = "indices" }) or {}

  local function span(offs, s, start, count)
    local from = offs[start] or #s
    local to = offs[start + count] or #s
    return { from, to }
  end
  local old_spans, new_spans, old_n, new_n = {}, {}, 0, 0
  for _, h in ipairs(hunks) do
    local start_a, count_a, start_b, count_b = h[1], h[2], h[3], h[4]
    if count_a > 0 then
      old_spans[#old_spans + 1] = span(old_offs, old, start_a, count_a)
      old_n = old_n + count_a
    end
    if count_b > 0 then
      new_spans[#new_spans + 1] = span(new_offs, new, start_b, count_b)
      new_n = new_n + count_b
    end
  end
  if old_n + new_n > INTRALINE_MAX_CHANGED * (#old_toks + #new_toks) then
    return nil
  end
  return old_spans, new_spans
end

---A deleted line as virt_lines chunks: `base_hl` everywhere, `span_hl` over
---the differing spans.
local function virt_chunks(text, base_hl, span_hl, spans)
  if not spans or #spans == 0 then
    return { { text, base_hl } }
  end
  local chunks, at = {}, 0
  for _, s in ipairs(spans) do
    if s[1] > at then
      chunks[#chunks + 1] = { text:sub(at + 1, s[1]), base_hl }
    end
    if s[2] > s[1] then
      chunks[#chunks + 1] = { text:sub(s[1] + 1, s[2]), span_hl }
    end
    at = math.max(at, s[2])
  end
  if at < #text then
    chunks[#chunks + 1] = { text:sub(at + 1), base_hl }
  end
  if #chunks == 0 then
    chunks = { { text, base_hl } }
  end
  return chunks
end

--------------------------------------------------------------------------
-- move detection
--------------------------------------------------------------------------

-- A line has to say something to count as moved: `}` or `end` appearing on
-- both sides of a diff is coincidence, not relocation.
local MOVED_MIN_CHARS = 8

---Lines that left one hunk and arrived verbatim in another, matched on
---trimmed text with occurrences paired up one-to-one.
---@return table<integer, true> old_moved  base line numbers
---@return table<integer, true> new_moved  buffer line numbers
local function detect_moves(st, lines)
  local dels, adds = {}, {} ---@type table<string, integer[]>, table<string, integer[]>
  local function collect(into, source, start, count)
    for i = start, start + count - 1 do
      local text = vim.trim(source[i] or "")
      if #text >= MOVED_MIN_CHARS then
        into[text] = into[text] or {}
        table.insert(into[text], i)
      end
    end
  end
  for _, h in ipairs(st.hunks) do
    collect(dels, st.base, h[1], h[2])
    collect(adds, lines, h[3], h[4])
  end
  local old_moved, new_moved = {}, {}
  for text, old_at in pairs(dels) do
    local new_at = adds[text]
    if new_at then
      for i = 1, math.min(#old_at, #new_at) do
        old_moved[old_at[i]] = true
        new_moved[new_at[i]] = true
      end
    end
  end
  return old_moved, new_moved
end

--------------------------------------------------------------------------
-- rendering
--------------------------------------------------------------------------

---Recompute hunks and redraw the overlay for `buf`.
function M.render(buf)
  local st = states[buf]
  if not st or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local buf_text = table.concat(lines, "\n") .. "\n"
  -- Matched to 'diffopt' (histogram, indent-heuristic, linematch) so the
  -- overlay slices hunks the same way native diff mode would — and linematch
  -- pairs each old line with the new line it actually resembles, which is
  -- what makes the char-level emphasis land on the right partner.
  st.hunks = vim.diff(st.base_text, buf_text, {
    result_type = "indices",
    algorithm = "histogram",
    indent_heuristic = true,
    linematch = 60,
  }) or {}

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local old_moved, new_moved = detect_moves(st, lines)
  local last = #lines
  for _, h in ipairs(st.hunks) do
    local start_a, count_a, start_b, count_b = h[1], h[2], h[3], h[4]

    -- Pair the i-th old line with the i-th new line and emphasize the tokens
    -- that changed between them. Moved lines are excluded: their colour
    -- already says what happened.
    local old_spans, new_spans = {}, {} ---@type table<integer, table>, table<integer, table>
    for i = 0, math.min(count_a, count_b) - 1 do
      local old_line, new_line = st.base[start_a + i], lines[start_b + i]
      if old_line and new_line and not old_moved[start_a + i] and not new_moved[start_b + i] then
        local o, n = token_diff(old_line, new_line)
        old_spans[i], new_spans[i] = o, n
      end
    end

    if count_a > 0 then
      local virt = {}
      for i = start_a, start_a + count_a - 1 do
        -- Delta's scheme: on a line with an emphasized partner the unchanged
        -- part dims and the changed tokens brighten; a line without one gets
        -- the plain wash. The dimming is what makes the emphasis carry.
        local spans = old_spans[i - start_a]
        local base_hl = old_moved[i] and "InlineDiffMovedDelete" or (spans and "InlineDiffDeleteDim" or "InlineDiffDelete")
        virt[#virt + 1] = virt_chunks(st.base[i] or "", base_hl, "InlineDiffDeleteEmph", spans)
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
      local spans = new_spans[row - start_b]
      local line_hl = new_moved[row] and "InlineDiffMovedAdd" or (spans and "InlineDiffAddDim" or "InlineDiffAdd")
      vim.api.nvim_buf_set_extmark(buf, ns, row - 1, 0, {
        line_hl_group = line_hl,
        -- Tint the line number too: with wrapped lines the margin then shows
        -- where a change starts, not just that one is nearby.
        number_hl_group = line_hl,
        priority = 50,
      })
      for _, s in ipairs(spans or {}) do
        if s[2] > s[1] then
          vim.api.nvim_buf_set_extmark(buf, ns, row - 1, s[1], {
            end_col = s[2],
            hl_group = "InlineDiffAddEmph",
            priority = 60,
          })
        end
      end
    end
  end
end

---Overlay `base` onto `buf` and keep it current as the buffer is edited.
---@param buf integer
---@param base string[]
function M.attach(buf, base)
  -- Re-derive here too: a colorscheme applied after this module loaded may
  -- have cleared the groups without firing ColorScheme (LazyVim re-applies
  -- tokyonight by calling its load() directly). default=true keeps any
  -- definition the user or theme made deliberately.
  setup_highlights()
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

---Where a hunk lives for the cursor. A pure deletion occupies no buffer
---lines; its red virtual text hangs above line start_b + 1 (or below the last
---line), so both neighbouring rows count as "on" it.
local function hunk_range(h, line_count)
  local start_b, count_b = h[3], h[4]
  if count_b > 0 then
    return start_b, start_b + count_b - 1
  end
  local first = math.max(start_b, 1)
  return first, math.min(start_b + 1, line_count)
end

---The row to land on when jumping to a hunk: its first real line, or for a
---pure deletion the line its virtual text hangs above.
local function hunk_anchor(h, line_count)
  local start_b, count_b = h[3], h[4]
  if count_b > 0 then
    return start_b
  end
  return math.max(math.min(start_b + 1, line_count), 1)
end

---The hunk under `row`, or nil.
local function hunk_at(st, row, line_count)
  for _, h in ipairs(st.hunks) do
    local first, until_ = hunk_range(h, line_count)
    if row >= first and row <= until_ then
      return h
    end
  end
  return nil
end

---Which change the cursor is on: the index of the hunk at (or the last hunk
---above) the cursor, and the total. Index 0 means the cursor sits before the
---first hunk.
---@return integer index, integer total
function M.hunk_position(buf)
  buf = resolve(buf)
  local st = states[buf]
  if not st then
    return 0, 0
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line_count = vim.api.nvim_buf_line_count(buf)
  local index = 0
  for i, h in ipairs(st.hunks) do
    if hunk_anchor(h, line_count) <= row then
      index = i
    end
  end
  return index, #st.hunks
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
  local line_count = vim.api.nvim_buf_line_count(buf)
  local starts = {}
  for _, h in ipairs(st.hunks) do
    starts[#starts + 1] = hunk_anchor(h, line_count)
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
    local row = hunk_anchor(h, vim.api.nvim_buf_line_count(buf))
    pcall(vim.api.nvim_win_set_cursor, 0, { row, 0 })
    -- A deletion above line 1 draws above the first line, which a window
    -- parked exactly at line 1 does not show; nudge it into view.
    if h[3] == 0 and h[4] == 0 then
      vim.wo.smoothscroll = true
      pcall(vim.cmd, "normal! \25")
    end
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
  local h = hunk_at(st, row, vim.api.nvim_buf_line_count(buf))
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
