-- relative-line-numbers.yazi/main.lua
-- Show relative/absolute line numbers and provide vim‑style quick‑jump.

----------------------------------------------------------------------
--  Constants
----------------------------------------------------------------------
local ABS, REL, HYBRID, NONE = 0, 1, 2, 3 -- number modes

----------------------------------------------------------------------
--  Number column (Entity.number + Current:redraw patch)
----------------------------------------------------------------------
local render_numbers = ya.sync(function(_, mode)
	if ui.render then
		ui.render()
	else
		ya.render()
	end

	-- 1) What to paint in front of every row
	Entity.number = function(_, index, total, file, hovered)
		if mode == NONE then
			return ui.Span("")
		end -- disabled

		local n
		if mode == ABS then
			n = file.idx
		elseif mode == REL then
			n = math.abs(hovered - index)
		else -- HYBRID
			n = (hovered == index) and file.idx or math.abs(hovered - index)
		end

		local fmt = "%" .. #tostring(total) .. "d"
		-- keep columns aligned (Vim’s trick: leading space on non‑hovered rows)
		if hovered == index then
			return ui.Span(string.format(fmt .. " ", n))
		else
			return ui.Span(string.format(" " .. fmt, n))
		end
	end

	-- 2) Patch Current:redraw once so the number column is prepended
	Current.redraw = function(self)
		local files = self._folder.window
		if #files == 0 then
			return self:empty()
		end

		-- cache hovered index (we need it for every row)
		local hovered = 1
		for i, f in ipairs(files) do
			if f.is_hovered then
				hovered = i
				break
			end
		end

		local entities, linemodes = {}, {}
		for i, f in ipairs(files) do
			linemodes[#linemodes + 1] = Linemode:new(f):redraw()

			local ent = Entity:new(f)
			entities[#entities + 1] = ui.Line({
				Entity:number(i, #self._folder.files, f, hovered),
				ent:redraw(),
			}):style(ent:style())
		end

		return {
			ui.List(entities):area(self._area),
			ui.Text(linemodes):area(self._area):align(ui.Align.RIGHT),
		}
	end
end)

----------------------------------------------------------------------
--  Vim‑style quick jump (mostly your original code, just tidied up)
----------------------------------------------------------------------
local DIGITS = { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9" }
local MOTIONS = { "j", "k", "h", "l", "<Down>", "<Up>", "<Left>", "<Right>" }

local function dir_key(k)
	if k == "<Down>" then
		return "j"
	elseif k == "<Up>" then
		return "k"
	elseif k == "<Left>" then
		return "h"
	elseif k == "<Right>" then
		return "l"
	else
		return k
	end
end

local function quick_jump(initial)
	local digits, cands = initial or "", {}
	for _, k in ipairs(DIGITS) do
		cands[#cands + 1] = { on = k }
	end
	for _, k in ipairs(MOTIONS) do
		cands[#cands + 1] = { on = k }
	end

	while true do
		local i = ya.which({ cands = cands, silent = true })
		if not i then
			return
		end -- cancelled
		local k = cands[i].on
		if k:match("%d") then -- keep collecting digits
			digits = digits .. k
		else -- got a motion key
			local count = tonumber(digits) or 1
			if count < 1 then
				count = 1
			end
			local d = dir_key(k)
			if d == "j" then
				ya.mgr_emit("arrow", { count })
			elseif d == "k" then
				ya.mgr_emit("arrow", { -count })
			elseif d == "h" then
				for _ = 1, count do
					ya.mgr_emit("leave", {})
				end
			elseif d == "l" then
				for _ = 1, count do
					ya.mgr_emit("enter", {})
				end
			end
			return
		end
	end
end

----------------------------------------------------------------------
--  Plugin glue (entry / setup)
----------------------------------------------------------------------
local function entry(_, job)
	local first
	if job.args and job.args[1] then
		local n = tonumber(job.args[1])
		if n then
			first = tostring(n)
		end
	end
	quick_jump(first)
end

local function setup(state, opts)
	opts = opts or {}
	local mode = ({ absolute = ABS, relative = REL, relative_absolute = HYBRID, none = NONE })[opts.show_numbers] or REL
	render_numbers(mode)
end

return { entry = entry, setup = setup }
