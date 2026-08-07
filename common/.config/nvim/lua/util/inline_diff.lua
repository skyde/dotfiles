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
---@field keep table<integer, true>|nil  buffer rows that stay visible when unchanged regions collapse
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
--   InlineDiffWsError      whitespace-error      trailing whitespace on a new line
--   InlineDiffMovedHint    (no delta equivalent) "→ 87" pointers between the
--                          two ends of a move, in the comment grey
--   InlineDiffFold         the "╌╌ n unchanged lines ╌╌" fold line, barely
--                          above the background: it marks a gap, and a gap
--                          should not compete with the changes for the eye
-- All are set with default=true, so a user (or theme) definition wins.

local PALETTE = {
  InlineDiffAdd = { bg = "#20432b" },
  InlineDiffAddDim = { bg = "#17311f" },
  InlineDiffAddEmph = { bg = "#2c5a3a" },
  InlineDiffDelete = { bg = "#532727" },
  InlineDiffDeleteDim = { bg = "#3f1f1f" },
  InlineDiffDeleteEmph = { bg = "#683131" },
  InlineDiffMovedAdd = { bg = "#12384a" },
  InlineDiffMovedDelete = { bg = "#2e2547" },
  InlineDiffWsError = { bg = "#db4b4b" },
  InlineDiffMovedHint = { fg = "#565f89", italic = true },
  -- fg only, a shade over bg_highlight; no bg, so the fold line never reads
  -- as a filled bar the way the theme's Folded does.
  InlineDiffFold = { fg = "#2f334d" },
  InlineDiffMovedGhost = { bg = "#2e2547", fg = "#565f89" },
  -- Family-coloured move candidates: the departure stays in the red family,
  -- the arrival in the green family, each held apart from a real delete/add
  -- by dimming, a hue lean, or a strikethrough.
  InlineDiffMovedFromDim = { bg = "#3f1f1f", fg = "#8a7080" },
  InlineDiffMovedToDim = { bg = "#17311f" },
  -- The dim pair with a whisper of the delta move hues: the red leans
  -- violet, the green leans teal — enough to say "not a real delete/add"
  -- without leaving the red/green families. Two intensities.
  InlineDiffMovedFromSubtle = { bg = "#3a212b", fg = "#8a7080" },
  InlineDiffMovedToSubtle = { bg = "#16332c" },
  InlineDiffMovedFromSubtle2 = { bg = "#352337", fg = "#8a7080" },
  InlineDiffMovedToSubtle2 = { bg = "#143539" },
  InlineDiffMovedFromTint = { bg = "#4a2139" },
  InlineDiffMovedToTint = { bg = "#175035" },
  InlineDiffMovedFromStrike = { bg = "#3f1f1f", fg = "#8a7080", strikethrough = true },
  -- Line numbers, fg only: delta's line-numbers-plus-style "#9ece6a dim",
  -- pre-dimmed toward the background since highlights have no dim attribute.
  -- fg-only matters: a number_hl_group background bleeds into the blank
  -- gutters of the virtual deleted lines above, which read as stray colour.
  InlineDiffAddNr = { fg = "#6f9157" },
  InlineDiffMovedAddNr = { fg = "#5a7f9c" },
}

local function setup_highlights()
  for name, spec in pairs(PALETTE) do
    local def = vim.tbl_extend("force", { default = true }, spec)
    vim.api.nvim_set_hl(0, name, def)
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

-- How the two ends of a move refer to each other:
-- Move presentation, two independent knobs.
--
-- Colours (`M.move_colors`) — which pair of groups paints the two ends:
--   "delta"      the delta map-styles violet / cyan
--   "dim"        red family, dimmed: faded dim-red departure, dim-green arrival
--   "strike"     dim-red struck-through departure, plain add-green arrival
--   "strikedim"  dim-red struck-through departure, dim-green arrival
--   "tint"       red-plum departure, emerald arrival — full strength, held
--                apart from real delete/add by hue
--   "ghost"      violet with faded text at the departure, cyan arrival
--
-- Hints (`M.move_hint`) — the small grey pointer each end carries:
--   "absolute"  buffer line numbers: "→ 92" / "← 20"
--   "relative"  direction arrows with the row distance: "↓ 18" / "↑ 18"
--   "signed"    relative-jump offsets, no arrows: "+18" at the departure
--               (partner is 18 below), "-18" at the arrival — the address a
--               :+18 / 18j jump uses, and nothing that reads as motion
--   "elbow"     the glyph says where the partner is: "↴ 18" partner below,
--               "↳ 18" partner up there (the continuation elbow — comes from
--               above, lands here; no upward arrow anywhere)
--   "deponly"   only the departure points ("↓ 18"); the arrival is colour only
--   "none"      colour only, the way git --color-moved and delta render moves
--
-- The shipped look: the dim red/green family pair with a violet/teal lean
-- ("subtle2" — quiet like a dimmed delete/add, but recognizably neither),
-- and no hints at all. The alternatives stay selectable for tuning.
M.move_colors = "subtle2"
M.move_hint = "none"

local MOVE_COLOR_GROUPS = {
  delta = { from = "InlineDiffMovedDelete", to = "InlineDiffMovedAdd" },
  dim = { from = "InlineDiffMovedFromDim", to = "InlineDiffMovedToDim" },
  subtle = { from = "InlineDiffMovedFromSubtle", to = "InlineDiffMovedToSubtle" },
  subtle2 = { from = "InlineDiffMovedFromSubtle2", to = "InlineDiffMovedToSubtle2" },
  strike = { from = "InlineDiffMovedFromStrike", to = "InlineDiffAdd" },
  strikedim = { from = "InlineDiffMovedFromStrike", to = "InlineDiffMovedToDim" },
  tint = { from = "InlineDiffMovedFromTint", to = "InlineDiffMovedToTint" },
  ghost = { from = "InlineDiffMovedGhost", to = "InlineDiffMovedAdd" },
}

---Highlight groups for the two ends of a move under the current colours.
---@return string from_hl, string to_hl
local function move_colors()
  local c = MOVE_COLOR_GROUPS[M.move_colors] or MOVE_COLOR_GROUPS.delta
  return c.from, c.to
end

---Hint texts for a move: what the departure's virtual line appends, and
---what the arrival shows at end of line. Either can be nil for "no hint".
---@param dep integer  buffer row the departure marker is drawn at
---@param arr integer  buffer row the line landed on
---@return string|nil dep_hint, string|nil arr_hint
local function move_hints(dep, arr)
  local down = arr >= dep
  local dist = math.abs(arr - dep)
  local hint = M.move_hint
  if hint == "none" then
    return nil, nil
  elseif hint == "signed" then
    return ("  %+d"):format(down and dist or -dist), ("%+d"):format(down and -dist or dist)
  elseif hint == "elbow" then
    return ("  %s %d"):format(down and "↴" or "↳", dist), ("%s %d"):format(down and "↳" or "↴", dist)
  elseif hint == "deponly" then
    return ("  %s %d"):format(down and "↓" or "↑", dist), nil
  elseif hint == "relative" then
    return ("  %s %d"):format(down and "↓" or "↑", dist), ("%s %d"):format(down and "↑" or "↓", dist)
  end
  return ("  → %d"):format(arr), ("← %d"):format(dep)
end

-- A line has to say something to count as moved: `}` or `end` appearing on
-- both sides of a diff is coincidence, not relocation.
local MOVED_MIN_CHARS = 8

---Lines that left one hunk and arrived verbatim in another, matched on
---trimmed text with occurrences paired up one-to-one. The two returned maps
---are inverses: each end of a move knows where its partner is.
---@return table<integer, integer> old_moved  base lnum -> buffer lnum it moved to
---@return table<integer, integer> new_moved  buffer lnum -> base lnum it came from
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
        old_moved[old_at[i]] = new_at[i]
        new_moved[new_at[i]] = old_at[i]
      end
    end
  end
  return old_moved, new_moved
end

--------------------------------------------------------------------------
-- rendering
--------------------------------------------------------------------------

---Lines as the one string `vim.diff` wants.
---
---The empty case is the whole reason this is a function. A Neovim buffer can
---never hold zero lines, so an emptied buffer arrives as `{ "" }` while an
---empty base — an added or untracked file — is `{}`. Joined naively those
---become "\n" and "", which never compare equal: the buffer still reports one
---added line, and reverting it produces `{ "" }` again. That is an infinite
---loop for anything walking hunks to convergence, and in the editor it is an
---added file whose "you changed this" wash never goes away no matter how many
---times you revert it. A blank-only buffer *is* an empty file here.
---@param lines string[]
---@return string
function M.difftext(lines)
  if #lines == 0 or (#lines == 1 and lines[1] == "") then
    return ""
  end
  return table.concat(lines, "\n") .. "\n"
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

---Recompute hunks and redraw the overlay for `buf`.
function M.render(buf)
  local st = states[buf]
  if not st or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local buf_text = M.difftext(lines)
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

  -- Both ends of a move point at each other in buffer line numbers — the
  -- departure's virtual text says where the line went, the arrival says where
  -- it left from. The departure end is virtual, so "where it left from" means
  -- the buffer row its red text is drawn at, computed up front because a
  -- move's two hunks can come in either order.
  local departure_row = {} ---@type table<integer, integer>  base lnum -> buffer row
  for _, h in ipairs(st.hunks) do
    for i = h[1], h[1] + h[2] - 1 do
      if old_moved[i] then
        departure_row[i] = hunk_anchor(h, last)
      end
    end
  end

  -- Which lines to keep visible when the window collapses unchanged regions:
  -- every changed or neighbouring row, with the same context 'diffopt' gives
  -- native diff mode. Everything else folds away (see M.foldexpr).
  local context = tonumber(vim.o.diffopt:match("context:(%d+)")) or 6
  local keep = {}
  for _, h in ipairs(st.hunks) do
    local first, until_ = hunk_range(h, last)
    for row = math.max(1, first - context), math.min(last, until_ + context) do
      keep[row] = true
    end
  end
  st.keep = keep

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
        local moved_hl = (move_colors())
        local base_hl = old_moved[i] and moved_hl or (spans and "InlineDiffDeleteDim" or "InlineDiffDelete")
        local chunks = virt_chunks(st.base[i] or "", base_hl, "InlineDiffDeleteEmph", spans)
        if old_moved[i] then
          local dep_hint = move_hints(departure_row[i] or 0, old_moved[i])
          if dep_hint then
            chunks[#chunks + 1] = { dep_hint, "InlineDiffMovedHint" }
          end
        end
        -- Wash the rest of the row too, the way line_hl_group washes the
        -- added lines — a virtual line only paints under its chunks. The
        -- window truncates whatever does not fit.
        -- A struck-through wash would draw its line across the padding too;
        -- pad with the same background minus the decoration.
        local pad_hl = base_hl == "InlineDiffMovedFromStrike" and "InlineDiffMovedFromDim" or base_hl
        chunks[#chunks + 1] = { (" "):rep(math.max(500, vim.o.columns)), pad_hl }
        virt[#virt + 1] = chunks
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
      local line_hl = new_moved[row] and select(2, move_colors()) or (spans and "InlineDiffAddDim" or "InlineDiffAdd")
      local nr_hl = new_moved[row] and "InlineDiffMovedAddNr" or "InlineDiffAddNr"
      local text = lines[row] or ""
      -- The full-row wash is an eol range highlight, NOT line_hl_group: a
      -- range hl_group never paints over line_hl_group whatever its
      -- priority, so a line_hl wash would swallow the token emphasis and
      -- the whitespace flag. hl_eol in turn only paints past the EOL when
      -- the range actually covers the EOL, so the range runs to the start
      -- of the next line — the same full-width wash the deleted side gets
      -- from its padded virtual lines (strict=false clamps the end on the
      -- last buffer line while still covering its EOL). The number tint
      -- rides a separate single-line mark: on the wash itself it would
      -- bleed onto the next line's number.
      vim.api.nvim_buf_set_extmark(buf, ns, row - 1, 0, {
        end_row = row,
        end_col = 0,
        hl_group = line_hl,
        hl_eol = true,
        priority = 50,
        strict = false,
      })
      vim.api.nvim_buf_set_extmark(buf, ns, row - 1, 0, {
        number_hl_group = nr_hl,
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
      if new_moved[row] then
        local arr_hint = select(2, move_hints(departure_row[new_moved[row]] or 0, row))
        if arr_hint then
          vim.api.nvim_buf_set_extmark(buf, ns, row - 1, 0, {
            virt_text = { { arr_hint, "InlineDiffMovedHint" } },
            virt_text_pos = "eol",
          })
        end
      end
      -- Delta's whitespace-error: trailing whitespace on a new line, painted
      -- the hard red that means "you probably did not want this".
      local text = lines[row] or ""
      local ws = text:find("%s+$")
      if ws and not new_moved[row] then
        vim.api.nvim_buf_set_extmark(buf, ns, row - 1, ws - 1, {
          end_col = #text,
          hl_group = "InlineDiffWsError",
          priority = 70,
        })
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
  states[buf] = { base = base, base_text = M.difftext(base) }
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

--------------------------------------------------------------------------
-- collapsing unchanged regions
--------------------------------------------------------------------------

---'foldexpr' for a window showing an attached buffer: unchanged lines beyond
---the diff context fold away — what foldmethod=diff does for native diff
---mode, and VS Code's "hide unchanged regions". The keep-map is rebuilt on
---every render, so the folds track edits; a buffer with no changes (or no
---overlay) folds nothing.
function M.foldexpr(lnum)
  local st = states[vim.api.nvim_get_current_buf()]
  if not st or not st.keep or next(st.keep) == nil then
    return "0"
  end
  return st.keep[lnum] and "0" or "1"
end

---'foldtext' companion: how much is hidden, and nothing else.
function M.foldtext()
  return ("╌╌ %d unchanged lines ╌╌"):format(vim.v.foldend - vim.v.foldstart + 1)
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
