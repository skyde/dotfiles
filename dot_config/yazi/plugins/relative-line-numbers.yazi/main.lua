--- relative-line-numbers.yazi/main.lua
--- Show relative (or absolute) line numbers in Yazi's file list and provide a
--- Vim style quick jump command.

local SHOW_NUMBERS_ABSOLUTE          = 0
local SHOW_NUMBERS_RELATIVE          = 1
local SHOW_NUMBERS_RELATIVE_ABSOLUTE = 2
local SHOW_NUMBERS_NONE              = 3

-- Insert a number column at the beginning of each entry.
local apply_numbers = ya.sync(function(_, mode)
  Linemode:children_add(function(self)
    if mode == SHOW_NUMBERS_NONE then
      return ""
    end

    local files = cx.active.current._folder.window
    local hovered
    for i, f in ipairs(files) do
      if f.is_hovered then
        hovered = i
        break
      end
    end

    local index
    for i, f in ipairs(files) do
      if f.url == self._file.url then
        index = i
        break
      end
    end
    if not index then
      return ""
    end

    local idx
    if mode == SHOW_NUMBERS_ABSOLUTE then
      idx = self._file.idx
    elseif mode == SHOW_NUMBERS_RELATIVE then
      idx = math.abs(hovered - index)
    elseif mode == SHOW_NUMBERS_RELATIVE_ABSOLUTE then
      idx = hovered == index and self._file.idx or math.abs(hovered - index)
    end

    local total = #cx.active.current._folder.files
    local fmt = "%" .. #tostring(total) .. "d "
    return ui.Line { string.format(fmt, idx) }
  end, 0)

  if ui.render then ui.render() else ya.render() end
end)

local MOTION_DIGIT_KEYS = {
  { on = "0" }, { on = "1" }, { on = "2" }, { on = "3" }, { on = "4" },
  { on = "5" }, { on = "6" }, { on = "7" }, { on = "8" }, { on = "9" },
}

local MOTION_CMD_KEYS = {
  { on = "j" }, { on = "k" }, { on = "h" }, { on = "l" },
  { on = "<Down>" }, { on = "<Up>" }, { on = "<Left>" }, { on = "<Right>" },
}

local function normalize_direction(key)
  if key == "<Down>"  then return "j" end
  if key == "<Up>"    then return "k" end
  if key == "<Left>"  then return "h" end
  if key == "<Right>" then return "l" end
  return key
end

local function quick_jump(initial)
  local digits = initial or ""
  local candidates = {}
  for _, c in ipairs(MOTION_DIGIT_KEYS) do table.insert(candidates, c) end
  for _, c in ipairs(MOTION_CMD_KEYS)   do table.insert(candidates, c) end

  while true do
    local idx = ya.which { cands = candidates, silent = true }
    if not idx then return end
    local key = candidates[idx].on
    if key:match("^%d$") then
      digits = digits .. key
    else
      local dir = normalize_direction(key)
      local count = tonumber(digits) or 1
      if count <= 0 then count = 1 end
      if dir == "j" then
        ya.mgr_emit("arrow", {  count })
      elseif dir == "k" then
        ya.mgr_emit("arrow", { -count })
      elseif dir == "h" then
        for _ = 1, count do ya.mgr_emit("leave", {}) end
      elseif dir == "l" then
        for _ = 1, count do ya.mgr_emit("enter", {}) end
      end
      return
    end
  end
end

local function entry(_, job)
  local initial
  if job.args and #job.args > 0 then
    local n = tonumber(job.args[1])
    if n then initial = tostring(n) end
  end
  quick_jump(initial)
end

local function setup(state, opts)
  opts = opts or {}
  local show = opts.show_numbers or "relative"
  local mode
  if show == "absolute" then
    mode = SHOW_NUMBERS_ABSOLUTE
  elseif show == "relative_absolute" then
    mode = SHOW_NUMBERS_RELATIVE_ABSOLUTE
  elseif show == "none" then
    mode = SHOW_NUMBERS_NONE
  else
    mode = SHOW_NUMBERS_RELATIVE
  end
  apply_numbers(mode)
end

return { entry = entry, setup = setup }
