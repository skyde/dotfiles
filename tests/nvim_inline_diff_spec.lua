-- Run with: nvim --headless -u NONE -i NONE -l tests/nvim_inline_diff_spec.lua
--
-- Exercises the editable inline-diff overlay in
-- common/.config/nvim/lua/util/inline_diff.lua directly: extmark placement at
-- the awkward spots (deletions at the top and bottom of the file), hunk
-- navigation with wrap-around, revert for every hunk shape, and the
-- attach/detach lifecycle. Plugin-free, like the other specs.

local source = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(repo .. "/common/.config/nvim")

local inline = require("util.inline_diff")
local ns = vim.api.nvim_create_namespace("vcs_inline_diff")

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

---A fresh buffer showing `lines`, focused in the only window.
local function mkbuf(lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  return buf
end

---The overlay reduced to what a reader sees: the old lines drawn as virtual
---text (with where they hang), and which buffer lines are highlighted as new.
---Virtual lines can carry several chunks (char emphasis); the text is their
---concatenation.
local function overlay(buf)
  local virt, added = {}, {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    local d = m[4]
    if d.virt_lines then
      for _, vl in ipairs(d.virt_lines) do
        local text = {}
        for _, chunk in ipairs(vl) do
          text[#text + 1] = chunk[1]
        end
        virt[#virt + 1] = { row = m[2] + 1, text = table.concat(text), above = d.virt_lines_above or false }
      end
    end
    if d.line_hl_group == "DiffAdd" then
      added[#added + 1] = m[2] + 1
    end
  end
  table.sort(added)
  return virt, added
end

---The overlay's colouring in detail: every virtual-line chunk as {text, hl},
---each line-level highlight group by row, and the char-emphasis spans on
---buffer lines as {row, from, to} byte ranges.
local function detail(buf)
  local chunks, line_hl, spans = {}, {}, {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    local d = m[4]
    if d.virt_lines then
      for _, vl in ipairs(d.virt_lines) do
        for _, chunk in ipairs(vl) do
          chunks[#chunks + 1] = { chunk[1], chunk[2] }
        end
      end
    end
    if d.line_hl_group then
      line_hl[m[2] + 1] = d.line_hl_group
    end
    if d.end_col and d.hl_group then
      spans[#spans + 1] = { m[2] + 1, m[3], d.end_col }
    end
  end
  return chunks, line_hl, spans
end

--------------------------------------------------------------------------
-- placement
--------------------------------------------------------------------------

do
  local buf = mkbuf({ "one", "two", "three" })
  inline.attach(buf, { "one", "two", "three" })
  local virt, added = overlay(buf)
  eq("identical: no virtual lines", {}, virt)
  eq("identical: no highlights", {}, added)
  check("identical: attached all the same", inline.has(buf))
  inline.detach(buf)
end

do
  local buf = mkbuf({ "one", "TWO", "three", "four" })
  inline.attach(buf, { "one", "two", "three" })
  local virt, added = overlay(buf)
  eq("change: old line hangs above its replacement", { { row = 2, text = "two", above = true } }, virt)
  eq("change: replacement and addition highlighted", { 2, 4 }, added)
  inline.detach(buf)
end

do
  local buf = mkbuf({ "two", "three" })
  inline.attach(buf, { "one", "two", "three" })
  local virt = overlay(buf)
  eq("deletion at the top hangs above line 1", { { row = 1, text = "one", above = true } }, virt)
  inline.detach(buf)
end

do
  local buf = mkbuf({ "one", "three" })
  inline.attach(buf, { "one", "two", "three" })
  local virt = overlay(buf)
  eq("deletion in the middle hangs above the next line", { { row = 2, text = "two", above = true } }, virt)
  inline.detach(buf)
end

do
  local buf = mkbuf({ "one", "two" })
  inline.attach(buf, { "one", "two", "three" })
  local virt = overlay(buf)
  eq("deletion at the end hangs below the last line", { { row = 2, text = "three", above = false } }, virt)
  inline.detach(buf)
end

do
  local buf = mkbuf({ "brand new" })
  inline.attach(buf, {})
  local virt, added = overlay(buf)
  eq("untracked: nothing old to draw", {}, virt)
  eq("untracked: everything is an addition", { 1 }, added)
  inline.detach(buf)
end

do
  local buf = mkbuf({ "" })
  inline.attach(buf, { "a", "b" })
  local virt = overlay(buf)
  eq("emptied buffer: the old content is drawn", 2, #virt)
  inline.detach(buf)
end

--------------------------------------------------------------------------
-- char-level emphasis
--------------------------------------------------------------------------

do
  local buf = mkbuf({ "local value = compute(2)" })
  inline.attach(buf, { "local value = compute(1)" })
  local chunks, line_hl, spans = detail(buf)
  eq("chars: only the changed characters are emphasized on the new line", { { 1, 22, 23 } }, spans)
  eq("chars: the changed line keeps its add wash", "DiffAdd", line_hl[1])
  eq("chars: the old line is split around the changed characters", {
    { "local value = compute(", "DiffDelete" },
    { "1", "InlineDiffDeleteText" },
    { ")", "DiffDelete" },
  }, chunks)
  inline.detach(buf)
end

do
  -- Where exactly xdiff anchors an ambiguous insertion is its business; that
  -- only the four inserted characters light up is ours.
  local buf = mkbuf({ "if not enabled then return end" })
  inline.attach(buf, { "if enabled then return end" })
  local _, _, spans = detail(buf)
  eq("chars: an insertion emphasizes one span", 1, #spans)
  eq("chars: the span covers just the inserted characters", 4, spans[1] and (spans[1][3] - spans[1][2]))
  inline.detach(buf)
end

do
  local buf = mkbuf({ "zzzzzzzzzz" })
  inline.attach(buf, { "aaaaaaaaaa" })
  local chunks, _, spans = detail(buf)
  eq("chars: a fully rewritten line gets no emphasis", {}, spans)
  eq("chars: its old line stays one plain chunk", { { "aaaaaaaaaa", "DiffDelete" } }, chunks)
  inline.detach(buf)
end

--------------------------------------------------------------------------
-- moves
--------------------------------------------------------------------------

do
  local buf = mkbuf({ "keep one", "keep two", "local function relocated()" })
  inline.attach(buf, { "keep one", "local function relocated()", "keep two" })
  local chunks, line_hl = detail(buf)
  eq("moves: the arrival is coloured as a move, not an add", "InlineDiffMovedAdd", line_hl[3])
  eq("moves: the departure is coloured as a move, not a delete", {
    { "local function relocated()", "InlineDiffMovedDelete" },
  }, chunks)
  inline.detach(buf)
end

do
  -- Trivial lines ("end", "}") appear on both sides of unrelated hunks all
  -- the time; they must not be painted as moves.
  local buf = mkbuf({ "alpha", "end", "beta" })
  inline.attach(buf, { "end", "gamma" })
  local _, line_hl = detail(buf)
  for row, hl in pairs(line_hl) do
    check("moves: short lines never count as moved (row " .. row .. ")", hl ~= "InlineDiffMovedAdd", hl)
  end
  inline.detach(buf)
end

do
  -- A moved line that also gains an edit is not a move; it is a change.
  local buf = mkbuf({ "keep one", "keep two", "local function relocated(x)" })
  inline.attach(buf, { "keep one", "local function relocated()", "keep two" })
  local _, line_hl = detail(buf)
  eq("moves: an edited relocation stays an ordinary add", "DiffAdd", line_hl[3])
  inline.detach(buf)
end

--------------------------------------------------------------------------
-- navigation
--------------------------------------------------------------------------

do
  local buf = mkbuf({ "one", "TWO", "three", "four", "five" })
  inline.attach(buf, { "one", "two", "three", "five" })
  -- Hunks: line 2 (change), line 4 (addition).
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  inline.goto_hunk(buf, 1)
  eq("nav: forward to the first hunk", 2, vim.api.nvim_win_get_cursor(0)[1])
  inline.goto_hunk(buf, 1)
  eq("nav: forward to the second hunk", 4, vim.api.nvim_win_get_cursor(0)[1])
  inline.goto_hunk(buf, 1)
  eq("nav: forward wraps to the first hunk", 2, vim.api.nvim_win_get_cursor(0)[1])
  inline.goto_hunk(buf, -1)
  eq("nav: backward wraps to the last hunk", 4, vim.api.nvim_win_get_cursor(0)[1])
  inline.goto_first(buf)
  eq("nav: goto_first", 2, vim.api.nvim_win_get_cursor(0)[1])

  -- A deletion above line 1 must actually be visible when the view opens.
  local topbuf = mkbuf({ "two", "three" })
  inline.attach(topbuf, { "one", "two", "three" })
  inline.goto_first(topbuf)
  check(
    "nav: a top-of-file deletion is scrolled into view",
    (vim.fn.winsaveview().topfill or 0) > 0,
    vim.inspect(vim.fn.winsaveview())
  )
  inline.detach(topbuf)
  vim.api.nvim_set_current_buf(buf)
  check("nav: on an unchanged buffer reports false", not inline.goto_hunk(mkbuf({ "x" }), 1))
  inline.detach(buf)
end

--------------------------------------------------------------------------
-- position
--------------------------------------------------------------------------

do
  local buf = mkbuf({ "one", "TWO", "three", "four", "five" })
  inline.attach(buf, { "one", "two", "three", "five" })
  -- Hunks: line 2 (change), line 4 (addition).
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local idx, total = inline.hunk_position(buf)
  eq("position: total counts every hunk", 2, total)
  eq("position: 0 above the first hunk", 0, idx)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  eq("position: on the first hunk", 1, (inline.hunk_position(buf)))
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  eq("position: between hunks counts the one above", 1, (inline.hunk_position(buf)))
  vim.api.nvim_win_set_cursor(0, { 5, 0 })
  eq("position: past the last hunk", 2, (inline.hunk_position(buf)))
  eq("position: an unattached buffer reports zero", 0, (inline.hunk_position(mkbuf({ "x" }))))
  inline.detach(buf)
end

--------------------------------------------------------------------------
-- revert
--------------------------------------------------------------------------

do
  local buf = mkbuf({ "one", "TWO", "three", "four" })
  inline.attach(buf, { "one", "two", "three" })
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  check("revert: a change hunk", inline.revert_hunk(buf))
  eq("revert: the old line is back", { "one", "two", "three", "four" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  check("revert: an addition hunk", inline.revert_hunk(buf))
  eq("revert: the addition is gone", { "one", "two", "three" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  eq("revert: nothing left to show", {}, (select(1, overlay(buf))))
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  check("revert: off a hunk reports false", not inline.revert_hunk(buf))
  inline.detach(buf)
end

do
  local buf = mkbuf({ "two", "three" })
  inline.attach(buf, { "one", "two", "three" })
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  check("revert: a deletion at the top", inline.revert_hunk(buf))
  eq("revert: the top line is back", { "one", "two", "three" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  inline.detach(buf)
end

do
  local buf = mkbuf({ "one", "two" })
  inline.attach(buf, { "one", "two", "three" })
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  check("revert: a deletion at the end", inline.revert_hunk(buf))
  eq("revert: the last line is back", { "one", "two", "three" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  inline.detach(buf)
end

do
  local buf = mkbuf({ "one", "three" })
  inline.attach(buf, { "one", "two", "three" })
  vim.api.nvim_set_current_buf(buf)
  -- In a headless script every API edit lands in one undo block; force a sync
  -- point so undo stops at the revert, as it would in an interactive session.
  vim.o.undolevels = vim.o.undolevels
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  check("revert: a deletion in the middle", inline.revert_hunk(buf))
  eq("revert: the middle line is back", { "one", "two", "three" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))

  -- Undo undoes the revert like any other edit, and a render catches up.
  vim.cmd("silent! undo")
  inline.render(buf)
  eq("undo: the revert is undone", { "one", "three" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  local virt = overlay(buf)
  eq("undo: the overlay is back too", { { row = 2, text = "two", above = true } }, virt)
  inline.detach(buf)
end

--------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------

do
  local buf = mkbuf({ "one", "changed" })
  inline.attach(buf, { "one", "two" })
  check("lifecycle: attached", inline.has(buf))
  inline.detach(buf)
  check("lifecycle: detached", not inline.has(buf))
  eq("lifecycle: detach clears the overlay", {}, vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}))
  inline.render(buf)
  eq("lifecycle: render after detach stays clear", {}, vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}))

  -- Re-attaching with a different base replaces the old overlay wholesale.
  inline.attach(buf, { "one", "changed" })
  local virt, added = overlay(buf)
  eq("lifecycle: re-attach uses the new base", {}, virt)
  eq("lifecycle: re-attach drops the old highlights", {}, added)
  inline.detach(buf)
  check("lifecycle: double detach is harmless", not inline.has(buf))
  inline.detach(buf)
end

--------------------------------------------------------------------------

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  os.exit(1)
end
