-- relative-line-numbers.yazi/main.lua
-- Show relative/absolute line numbers and provide Vim‑style quick‑jump.

----------------------------------------------------------------------
--  Constants
----------------------------------------------------------------------
local ABS, REL, HYBRID, NONE = 0, 1, 2, 3 -- number modes

----------------------------------------------------------------------
--  Number column (Entity.number + Current:redraw patch)
----------------------------------------------------------------------
-- Patch the number column into Yazi's UI.  When the file list is rendered
-- we prepend a small column showing either absolute or relative line
-- numbers.  This function is wrapped with `ya.sync` to make sure it runs
-- on the main thread and only once.  Depending on the selected mode the
-- numbers will be absolute, purely relative, a hybrid of the two, or
-- completely disabled.
local render_numbers = ya.sync(function(_, mode)
	-- Call the appropriate render function depending on Yazi version.
	-- On newer Yazi releases there is a `ui.render`; fall back to
	-- `ya.render()` on older versions.
	if ui.render then
		ui.render()
	else
		ya.render()
	end

	-- 1) Define how to draw the number for each row.  We compute either the
	-- absolute index, the relative distance from the hovered row, or a
	-- hybrid of both.  A leading space on non‑hovered rows keeps columns
	-- aligned (this mimics Vim's trick for relative line numbers).
	Entity.number = function(_, index, total, file, hovered)
		if mode == NONE then
			return ui.Span("") -- numbers disabled
		end

		local n
		if mode == ABS then
			n = file.idx
		elseif mode == REL then
			n = math.abs(hovered - index)
		else -- HYBRID
			n = (hovered == index) and file.idx or math.abs(hovered - index)
		end

		-- Width of the number column (digits in `total`)
		local width = #tostring(total)
		local num_style = ui.Style():fg("darkgray")
		local text

		-- For pure REL mode, the current line is blank (same width)
		if mode == REL and hovered == index then
			text = string.rep(" ", width + 1)
			-- Do not style the text if we don't render the number - to ensure the background color is correct
			return ui.Span(text)
		else
			-- Right‑align number, add a space on the right for padding
			text = string.format("%" .. width .. "d ", n)

			return ui.Span(text):style(num_style)
		end
	end

	-- 2) Patch Current:redraw so that the number column is prepended to
	-- every row.  We cache the hovered index once so we don't recompute
	-- it for each file.
        Current.redraw = function(self)
                local files = self._folder.window
                if #files == 0 then
                        return self:empty()
                end

		-- Determine which row is currently hovered.
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

        -- Trigger a final render so the layout accounts for the number column.
        -- Defer the render slightly so Yazi's UI has fully initialized; rendering
        -- too early could leave the screen blank until the next user input.
        ya.defer(function()
                if ui.render then
                        ui.render()
                else
                        ya.render()
                end
        end)
end)

----------------------------------------------------------------------
--  Vim‑style quick jump
----------------------------------------------------------------------
-- Define the digit and motion keys that we accept as input.  Users can
-- type a count (like `22`) followed by a motion key (`j`, `k`, `h`, `l` or
-- the corresponding arrow key) to move multiple lines at once.  See
-- Yazi's key notation docs for how special keys like `<Down>` are
-- represented
local DIGITS = { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9" }
local MOTIONS = { "j", "k", "h", "l", "<Down>", "<Up>", "<Left>", "<Right>" }

-- Translate arrow keys into their vim‑style counterparts.  Without this
-- translation the plugin would treat `<Down>` as a literal motion and
-- potentially not move at all.
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

-- Collect a count and a motion key from the user.  We call
-- `ya.which()` repeatedly until a non‑digit is pressed.  Once we have a
-- motion key we compute the count (defaulting to 1) and emit the
-- appropriate command using `ya.mgr_emit`.  Negative counts move up and
-- positive counts move down as documented for the `arrow` command
local function quick_jump(initial)
	local digits = initial or ""
	local cands = {}
	for _, k in ipairs(DIGITS) do
		cands[#cands + 1] = { on = k }
	end
	for _, k in ipairs(MOTIONS) do
		cands[#cands + 1] = { on = k }
	end

	while true do
		local i = ya.which({ cands = cands, silent = true })
		if not i then
			return -- cancelled
		end
		local k = cands[i].on
		if k:match("%d") then
			-- Keep collecting digits.
			digits = digits .. k
		else
			-- We received a motion key.  Determine how far to move.
			local count = tonumber(digits) or 1
			if count < 1 then
				count = 1
			end
			local d = dir_key(k)
			-- Use ya.mgr_emit instead of ya.emit.  ya.mgr_emit() sends a
			-- command to the manager layer of Yazi and is the modern
			-- replacement for ya.manager_emit()/ya.emit()
			if d == "j" then
				ya.mgr_emit("arrow", { count }) -- move down
			elseif d == "k" then
				ya.mgr_emit("arrow", { -count }) -- move up
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
-- Entry point for the plugin.  If the plugin is invoked with a numeric
-- argument (e.g. `:yazi jump 42j`), pre‑seed the digits so the first
-- call to quick_jump uses that count.
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

-- Setup function invoked when the plugin is loaded.  Determine which
-- numbering mode to use based on the user's configuration and patch the
-- number renderer accordingly.
local function setup(_, opts)
	opts = opts or {}
	local mode_map = {
		absolute = ABS,
		relative = REL,
		relative_absolute = HYBRID,
		none = NONE,
	}
	local mode = mode_map[opts.show_numbers] or REL
	render_numbers(mode)
end

return { entry = entry, setup = setup }
