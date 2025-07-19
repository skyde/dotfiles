--
-- relative-line-numbers.yazi/main.lua
--
-- A simple Yazi plugin that displays relative line numbers in the file list and
-- provides Vim‑style motions for quick navigation.  The plugin shows a
-- number before each entry: by default the currently hovered line is shown as
-- `0` and the other lines display their distance from the cursor.  This is
-- particularly useful when combined with count‑prefixed movements (e.g.
-- pressing `5j` to jump down five lines).  The optional quick‑jump
-- functionality included here uses the built‑in input facilities of Yazi to
-- capture a sequence of digits followed by a direction key and perform the
-- corresponding movement.

-- Enumerations for the different numbering modes.  These constants mirror the
-- values used by yazi's builtin relative-motions plugin, where 0 means
-- absolute numbers, 1 means relative numbers and 2 means a hybrid of both.
local SHOW_NUMBERS_ABSOLUTE           = 0
local SHOW_NUMBERS_RELATIVE           = 1
local SHOW_NUMBERS_RELATIVE_ABSOLUTE  = 2
local SHOW_NUMBERS_NONE               = 3

-- This function is defined as a sync block so it can override UI rendering
-- primitives that run in the synchronous context.  It rewires `Entity.number`
-- and `Current.redraw` so that numbers are prepended to each row in the
-- directory listing.  The argument `mode` controls which numbering scheme
-- should be used (absolute, relative, hybrid or none).
local apply_render_numbers = ya.sync(function(_, mode)
  -- Trigger a re‑render.  In recent versions of yazi the `ui` table may
  -- provide its own `render` function; otherwise fall back to the global
  -- `ya.render`.  Without this call the overrides would not take effect
  -- immediately.
  if ui.render then
    ui.render()
  else
    ya.render()
  end

  -- Override the number drawing function.  The callback receives the 1‑based
  -- index of the row within the currently visible window (`index`), the total
  -- number of files in the folder (`total`), the file object itself (`file`),
  -- and the index of the currently hovered file (`hovered`).  We compute
  -- either the absolute index (`file.idx`), the relative distance to the
  -- hovered row (`math.abs(hovered - index)`) or a hybrid of the two.  For
  -- the hovered row itself in relative mode we want to display `0` aligned
  -- with the other numbers.
  Entity.number = function(_, index, total, file, hovered)
    -- When numbering is disabled return an empty span.
    if mode == SHOW_NUMBERS_NONE then
      return ui.Span("")
    end

    local idx
    if mode == SHOW_NUMBERS_ABSOLUTE then
      idx = file.idx
    elseif mode == SHOW_NUMBERS_RELATIVE then
      idx = math.abs(hovered - index)
    elseif mode == SHOW_NUMBERS_RELATIVE_ABSOLUTE then
      if hovered == index then
        idx = file.idx
      else
        idx = math.abs(hovered - index)
      end
    else
      idx = 0
    end

    -- Determine the width of the number column.  This uses the total count
    -- rather than the visible count so that numbers line up consistently when
    -- paging through large directories.
    local fmt = "%" .. #tostring(total) .. "d"
    -- Place the number to the left of the file icon.  When the hovered row
    -- displays a relative zero we insert an extra trailing space to keep
    -- alignment with other rows.
    if hovered == index and mode == SHOW_NUMBERS_RELATIVE then
      return ui.Span(string.format(fmt .. " ", idx))
    else
      return ui.Span(string.format(" " .. fmt, idx))
    end
  end

  -- Override the redraw routine for the current pane.  This is responsible
  -- for constructing two UI objects: a list of rows (with the numbering
  -- prepended) and a right‑aligned text block for file metadata.  The
  -- implementation here closely follows yazi's default `Current.redraw`
  -- behaviour but inserts the line numbers at the beginning of each row.
  Current.redraw = function(self)
    local files = self._folder.window
    if #files == 0 then
      return self:empty()
    end

    -- Determine which row is currently hovered to compute relative offsets.
    local hovered_index
    for i, f in ipairs(files) do
      if f.is_hovered then
        hovered_index = i
        break
      end
    end

    local entities, linemodes = {}, {}
    for i, f in ipairs(files) do
      -- Save the original linemode (icons, labels, etc.) so it can be drawn
      -- separately on the right.  This preserves formatting and colouring.
      linemodes[#linemodes + 1] = Linemode:new(f):redraw()
      local entity = Entity:new(f)
      -- Compose a line consisting of the number span and the original entity.
      entities[#entities + 1] =
        ui.Line({ Entity.number(i, #self._folder.files, f, hovered_index), entity:redraw() })
          :style(entity:style())
    end

    return {
      ui.List(entities):area(self._area),
      ui.Text(linemodes):area(self._area):align(ui.Align.RIGHT),
    }
  end
end)

-- Candidate lists for capturing digits and direction keys using `ya.which`.  The
-- table entries consist of a table with an `on` field specifying the key name.
-- See the yazi documentation for details on the `ya.which` function.
local MOTION_DIGIT_KEYS = {
  { on = "0" }, { on = "1" }, { on = "2" }, { on = "3" }, { on = "4" },
  { on = "5" }, { on = "6" }, { on = "7" }, { on = "8" }, { on = "9" },
}

local MOTION_CMD_KEYS = {
  { on = "j" }, { on = "k" }, { on = "h" }, { on = "l" },
  { on = "<Down>" }, { on = "<Up>" }, { on = "<Left>" }, { on = "<Right>" },
}

-- Helper to translate arrow keys into their Vim equivalent.  Yazi exposes
-- arrow names such as `<Down>` which need to be mapped onto `j`, `k`, `h` or
-- `l`.  Any other key is returned unchanged.
local function normalize_direction(key)
  if key == "<Down>" then return "j" end
  if key == "<Up>"   then return "k" end
  if key == "<Left>" then return "h" end
  if key == "<Right>"then return "l" end
  return key
end

-- Perform a quick jump.  This function is run in an async context when the
-- plugin is invoked as a functional plugin.  It collects a sequence of
-- digits followed by a direction key and then performs the appropriate
-- movement.  Supported direction keys are `j`/`k` (move down/up), `h` (leave
-- directory) and `l` (enter directory).  If no digits are entered the count
-- defaults to 1.  The optional argument `initial` allows the first digit to
-- be passed directly when the user triggers the plugin with a numeric prefix.
local function quick_jump(initial)
  local digits = initial or ""
  -- Merge digit and command tables into a single candidate list.  The order
  -- matters: if a key matches an earlier entry it will be selected first.
  local candidates = {}
  for _, c in ipairs(MOTION_DIGIT_KEYS) do table.insert(candidates, c) end
  for _, c in ipairs(MOTION_CMD_KEYS)   do table.insert(candidates, c) end

  while true do
    local idx = ya.which { cands = candidates, silent = true }
    if not idx then return end
    local key = candidates[idx].on
    -- If the key is a digit, append it and continue waiting for more input.
    if key:match("^%d$") then
      digits = digits .. key
    else
      -- Otherwise treat it as a direction and perform the movement.
      local dir = normalize_direction(key)
      local count = tonumber(digits) or 1
      if count <= 0 then count = 1 end
      if dir == "j" then
        ya.mgr_emit("arrow", {  count  })
      elseif dir == "k" then
        ya.mgr_emit("arrow", { -count  })
      elseif dir == "h" then
        for _ = 1, count do ya.mgr_emit("leave", {}) end
      elseif dir == "l" then
        for _ = 1, count do ya.mgr_emit("enter", {}) end
      end
      return
    end
  end
end

-- Plugin entry point.  When bound via `keymap.toml` using the `plugin`
-- command this function is executed in an async context.  It optionally
-- accepts a single positional argument containing an initial count; this
-- allows bindings like `plugin relative-line-numbers 5` so that pressing
-- `5` immediately followed by the plugin key will start with a count of 5.
local function entry(_, job)
  local initial
  if job.args and #job.args > 0 then
    local n = tonumber(job.args[1])
    if n then
      initial = tostring(n)
    end
  end
  quick_jump(initial)
end

-- Setup function called from the user's `init.lua`.  It accepts an optional
-- table of options.  Currently supported options:
--   * show_numbers: "relative" (default), "absolute", "relative_absolute" or "none".
--     This controls the numbering mode applied to the file list.  Hybrid mode
--     shows absolute numbering on the current line and relative numbering on
--     other lines.  Setting "none" disables numbering entirely.
--
-- When called, this function invokes the sync render override defined above.
local function setup(state, opts)
  opts = opts or {}
  local show = opts.show_numbers or "relative"
  local mode
  if show == "absolute" then
    mode = SHOW_NUMBERS_ABSOLUTE
  elseif show == "relative" then
    mode = SHOW_NUMBERS_RELATIVE
  elseif show == "relative_absolute" then
    mode = SHOW_NUMBERS_RELATIVE_ABSOLUTE
  else
    mode = SHOW_NUMBERS_NONE
  end
  apply_render_numbers(mode)
end

-- Expose the entry and setup functions.  Yazi will automatically call
-- `entry` when the plugin is executed via `plugin <name>` and `setup` when the
-- plugin is required in `init.lua`.
return {
  entry = entry,
  setup = setup,
}
