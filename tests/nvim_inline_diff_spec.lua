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

---Chunks a reader does not see as content: the full-width wash padding at
---the end of every virtual line.
local function is_padding(chunk)
  return #chunk[1] >= 100 and chunk[1]:match("^%s+$") ~= nil
end

---The overlay reduced to what a reader sees: the old lines drawn as virtual
---text (with where they hang), and which buffer lines are highlighted as new.
---Virtual lines can carry several chunks (char emphasis); the text is their
---concatenation, without the wash padding.
local function overlay(buf)
  local virt, added = {}, {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    local d = m[4]
    if d.virt_lines then
      for _, vl in ipairs(d.virt_lines) do
        local text = {}
        for _, chunk in ipairs(vl) do
          if not is_padding(chunk) then
            text[#text + 1] = chunk[1]
          end
        end
        virt[#virt + 1] = { row = m[2] + 1, text = table.concat(text), above = d.virt_lines_above or false }
      end
    end
    local wash = d.line_hl_group or (d.hl_eol and d.hl_group)
    if wash and wash:find("^InlineDiffAdd") then
      added[#added + 1] = m[2] + 1
    end
  end
  table.sort(added)
  return virt, added
end

---The overlay's colouring in detail: every virtual-line chunk as {text, hl},
---each line-level highlight group by row, the emphasis spans on buffer lines
---as {row, from, to} byte ranges (with the group when it is not the usual
---add-emphasis), and any end-of-line hints by row.
local function detail(buf)
  local chunks, line_hl, spans, eol = {}, {}, {}, {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    local d = m[4]
    if d.virt_lines then
      for _, vl in ipairs(d.virt_lines) do
        for _, chunk in ipairs(vl) do
          if not is_padding(chunk) then
            chunks[#chunks + 1] = { chunk[1], chunk[2] }
          end
        end
      end
    end
    if d.virt_text then
      eol[m[2] + 1] = d.virt_text[1][1]
    end
    -- The full-row wash is an eol range highlight (line_hl_group would
    -- swallow the emphasis); either counts as the row's line colour here.
    local wash = d.line_hl_group or (d.hl_eol and d.hl_group)
    if wash then
      line_hl[m[2] + 1] = wash
    end
    if d.end_col and d.hl_group and not d.hl_eol then
      local span = { m[2] + 1, m[3], d.end_col }
      if d.hl_group ~= "InlineDiffAddEmph" then
        span[4] = d.hl_group
      end
      spans[#spans + 1] = span
    end
  end
  return chunks, line_hl, spans, eol
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
-- token-level emphasis
--------------------------------------------------------------------------

do
  local buf = mkbuf({ "local value = compute(2)" })
  inline.attach(buf, { "local value = compute(1)" })
  local chunks, line_hl, spans = detail(buf)
  eq("tokens: only the changed token is emphasized on the new line", { { 1, 22, 23 } }, spans)
  eq("tokens: the unchanged part of an edited line dims", "InlineDiffAddDim", line_hl[1])
  eq("tokens: the old line dims around its emphasized token", {
    { "local value = compute(", "InlineDiffDeleteDim" },
    { "1", "InlineDiffDeleteEmph" },
    { ")", "InlineDiffDeleteDim" },
  }, chunks)
  inline.detach(buf)
end

do
  -- Token, not character, granularity: renaming an identifier emphasizes the
  -- whole identifier on both sides, even where characters coincide.
  local buf = mkbuf({ "local counter = counter + 1" })
  inline.attach(buf, { "local count = count + 1" })
  local chunks, _, spans = detail(buf)
  eq("tokens: a rename emphasizes the whole identifier", { { 1, 6, 13 }, { 1, 16, 23 } }, spans)
  eq("tokens: both old occurrences are emphasized", {
    { "local ", "InlineDiffDeleteDim" },
    { "count", "InlineDiffDeleteEmph" },
    { " = ", "InlineDiffDeleteDim" },
    { "count", "InlineDiffDeleteEmph" },
    { " + 1", "InlineDiffDeleteDim" },
  }, chunks)
  inline.detach(buf)
end

do
  -- Where exactly xdiff anchors an ambiguous insertion is its business; that
  -- only the four inserted characters light up is ours.
  local buf = mkbuf({ "if not enabled then return end" })
  inline.attach(buf, { "if enabled then return end" })
  local _, _, spans = detail(buf)
  eq("tokens: an insertion emphasizes one span", 1, #spans)
  eq("tokens: the span covers just the inserted word", 4, spans[1] and (spans[1][3] - spans[1][2]))
  inline.detach(buf)
end

do
  local buf = mkbuf({ "zzzzzzzzzz" })
  inline.attach(buf, { "aaaaaaaaaa" })
  local chunks, line_hl, spans = detail(buf)
  eq("tokens: a fully rewritten line gets no emphasis", {}, spans)
  eq("tokens: its old line stays one plain chunk", { { "aaaaaaaaaa", "InlineDiffDelete" } }, chunks)
  eq("tokens: a fully rewritten line keeps the plain add wash", "InlineDiffAdd", line_hl[1])
  inline.detach(buf)
end

--------------------------------------------------------------------------
-- moves
--------------------------------------------------------------------------

do
  local buf = mkbuf({ "keep one", "keep two", "local function relocated()" })
  inline.attach(buf, { "keep one", "local function relocated()", "keep two" })
  local chunks, line_hl, _, eol = detail(buf)
  eq("moves: the arrival is coloured as a move, not an add", "InlineDiffMovedToSubtle2", line_hl[3])
  eq("moves: the departure is coloured as a move, not a delete", {
    { "local function relocated()", "InlineDiffMovedFromSubtle2" },
  }, chunks)
  eq("moves: colour-only — no pointer at the arrival", nil, eol[3])

  -- The alternative colourings and hints stay selectable.
  inline.move_colors, inline.move_hint = "delta", "absolute"
  inline.render(buf)
  local chunks2, line_hl2, _, eol2 = detail(buf)
  eq("moves: delta colours are still selectable", "InlineDiffMovedAdd", line_hl2[3])
  eq("moves: absolute hints are still selectable", {
    { "local function relocated()", "InlineDiffMovedDelete" },
    { "  → 3", "InlineDiffMovedHint" },
  }, chunks2)
  eq("moves: the arrival points back under absolute hints", "← 2", eol2[3])
  inline.move_colors, inline.move_hint = "subtle2", "none"
  inline.detach(buf)
end

do
  -- Trivial lines ("end", "}") appear on both sides of unrelated hunks all
  -- the time; they must not be painted as moves.
  local buf = mkbuf({ "alpha", "end", "beta" })
  inline.attach(buf, { "end", "gamma" })
  local _, line_hl = detail(buf)
  for row, hl in pairs(line_hl) do
    check("moves: short lines never count as moved (row " .. row .. ")", not hl:find("^InlineDiffMovedTo"), hl)
  end
  inline.detach(buf)
end

do
  -- A moved line that also gains an edit is not a move; it is a change.
  local buf = mkbuf({ "keep one", "keep two", "local function relocated(x)" })
  inline.attach(buf, { "keep one", "local function relocated()", "keep two" })
  local _, line_hl = detail(buf)
  eq("moves: an edited relocation stays an ordinary add", "InlineDiffAdd", line_hl[3])
  inline.detach(buf)
end

--------------------------------------------------------------------------
-- trailing whitespace
--------------------------------------------------------------------------

do
  local buf = mkbuf({ "clean", "trailing  " })
  inline.attach(buf, { "clean" })
  local _, _, spans = detail(buf)
  eq("whitespace: trailing whitespace on a new line is flagged", { { 2, 8, 10, "InlineDiffWsError" } }, spans)
  inline.detach(buf)
end

do
  local buf = mkbuf({ "unchanged has trailing  " })
  inline.attach(buf, { "unchanged has trailing  " })
  local _, _, spans = detail(buf)
  eq("whitespace: untouched lines are not flagged", {}, spans)
  inline.detach(buf)
end

--------------------------------------------------------------------------
-- collapsing unchanged regions
--------------------------------------------------------------------------

do
  local base, work = {}, {}
  for i = 1, 30 do
    base[i] = "line " .. i
    work[i] = i == 15 and "line fifteen edited" or ("line " .. i)
  end
  local buf = mkbuf(work)
  inline.attach(buf, base)

  -- The pure logic first: context (6 without a diffopt setting) around the
  -- hunk stays, everything further folds.
  eq("collapse: far-away lines fold", "1", (inline.foldexpr(1)))
  eq("collapse: the context edge stays visible", "0", (inline.foldexpr(9)))
  eq("collapse: the hunk stays visible", "0", (inline.foldexpr(15)))
  eq("collapse: the other context edge stays visible", "0", (inline.foldexpr(21)))
  eq("collapse: the tail folds", "1", (inline.foldexpr(30)))

  -- And wired into a real window: the unchanged regions actually close.
  vim.wo.foldmethod = "expr"
  vim.wo.foldexpr = "v:lua.require'util.inline_diff'.foldexpr(v:lnum)"
  vim.wo.foldlevel = 0
  check("collapse: the head region is closed", vim.fn.foldclosed(1) == 1, tostring(vim.fn.foldclosed(1)))
  check("collapse: the hunk is open", vim.fn.foldclosed(15) == -1, tostring(vim.fn.foldclosed(15)))
  check("collapse: the tail region is closed", vim.fn.foldclosed(25) == 22, tostring(vim.fn.foldclosed(25)))
  vim.wo.foldmethod = "manual"
  inline.detach(buf)
end

do
  -- A buffer with no changes must not fold into one line.
  local buf = mkbuf({ "same", "same again", "and again" })
  inline.attach(buf, { "same", "same again", "and again" })
  eq("collapse: an unchanged buffer folds nothing", "0", (inline.foldexpr(1)))
  inline.detach(buf)
  eq("collapse: a detached buffer folds nothing", "0", (inline.foldexpr(1)))
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
-- properties, over randomly generated file pairs
--------------------------------------------------------------------------

-- The cases above are hand-picked shapes: a deletion at the top, at the bottom,
-- an edit next to an insert. They cover what someone thought to write down.
-- These check invariants that must hold for *any* pair of files, over a few
-- hundred generated ones — empty files, blank lines, non-ASCII, long lines, and
-- edits piled on top of each other in whatever order the generator picks.
--
-- The seed is fixed, so a failure here is reproducible rather than a spooky
-- once-a-week red build.
do
  math.randomseed(2024)

  local function rand_lines(n)
    local out = {}
    for i = 1, n do
      local r = math.random(6)
      if r == 1 then
        out[i] = ""
      elseif r == 2 then
        out[i] = "  indented " .. math.random(5)
      elseif r == 3 then
        out[i] = string.rep("x", math.random(1, 40))
      elseif r == 4 then
        out[i] = "ünïcode ✓ " .. math.random(9)
      else
        out[i] = "line " .. math.random(20)
      end
    end
    return out
  end

  ---A few random edits: deletions, replacements and insertions, in any order.
  local function mutate(lines)
    local out = vim.deepcopy(lines)
    for _ = 1, math.random(0, 5) do
      local op = math.random(3)
      if #out == 0 then
        op = 3
      end
      if op == 1 then
        table.remove(out, math.random(#out))
      elseif op == 2 then
        out[math.random(#out)] = "CHANGED " .. math.random(99)
      else
        table.insert(out, math.random(#out + 1), "ADDED " .. math.random(99))
      end
    end
    return out
  end

  local CASES = 300
  local attach_failures, revert_failures, bounds_failures, restore_failures = {}, {}, {}, {}

  for case = 1, CASES do
    local base = rand_lines(math.random(0, 25))
    local work = mutate(base)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, work)
    vim.api.nvim_set_current_buf(buf)

    local ok, err = pcall(inline.attach, buf, base)
    if not ok then
      table.insert(attach_failures, ("case %d: %s"):format(case, tostring(err)))
    else
      -- Every mark the overlay places has to sit on a row the buffer has.
      local count = vim.api.nvim_buf_line_count(buf)
      for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})) do
        if m[2] < 0 or m[2] > count - 1 then
          table.insert(bounds_failures, ("case %d: mark at row %d of %d"):format(case, m[2], count))
        end
      end

      -- The index is a position among the hunks, so it cannot exceed the total.
      local index, total = inline.hunk_position(buf)
      if index < 0 or index > total then
        table.insert(bounds_failures, ("case %d: hunk %d of %d"):format(case, index, total))
      end

      -- Reverting every hunk has to reconstruct the base exactly. This is the
      -- property that matters: <leader>cv is destructive, and a revert that
      -- lands the wrong lines is silent data loss.
      local guard = 0
      while guard < 100 do
        guard = guard + 1
        local _, remaining = inline.hunk_position(buf)
        if remaining == 0 then
          break
        end
        pcall(vim.api.nvim_win_set_cursor, 0, { 1, 0 })
        local moved = inline.goto_hunk(buf, -1)
        local row = vim.api.nvim_win_get_cursor(0)[1]
        if row < 1 or row > math.max(vim.api.nvim_buf_line_count(buf), 1) then
          table.insert(bounds_failures, ("case %d: goto_hunk landed on row %d"):format(case, row))
        end
        local rok, rerr = pcall(inline.revert_hunk, buf)
        if not rok then
          table.insert(revert_failures, ("case %d: %s"):format(case, tostring(rerr)))
          break
        end
        if not moved then
          break
        end
      end

      local got = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      -- An empty base is the one shape a buffer cannot represent: Neovim has no
      -- zero-line buffer, so { "" } is as close as reverting can get.
      local expected = #base > 0 and base or { "" }
      if not vim.deep_equal(got, expected) then
        table.insert(
          restore_failures,
          ("case %d: base=%s got=%s"):format(
            case,
            vim.inspect(base):gsub("%s+", " "),
            vim.inspect(got):gsub("%s+", " ")
          )
        )
      end
    end

    inline.detach(buf)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  check(("properties: attach never raises (%d cases)"):format(CASES), #attach_failures == 0, attach_failures[1])
  check("properties: revert never raises", #revert_failures == 0, revert_failures[1])
  check("properties: marks and hunk indices stay in bounds", #bounds_failures == 0, bounds_failures[1])
  check("properties: reverting every hunk restores the base exactly", #restore_failures == 0, restore_failures[1])
end

--------------------------------------------------------------------------

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  os.exit(1)
end
