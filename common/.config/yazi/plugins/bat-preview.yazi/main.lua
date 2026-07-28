-- bat-preview.yazi
--
-- Preview text files with `bat` instead of yazi's built-in syntect previewer.
--
-- Why: yazi's built-in previewer carries its own syntax set and needs a
-- .tmTheme file on disk for `mgr.syntect_theme`. Delegating to bat instead
-- means the preview inherits two things we already maintain elsewhere:
--
--   1. BAT_THEME (set in ~/.zshenv, "Visual Studio Dark+") — the same syntax
--      theme bat, delta and VS Code use, so a file looks identical whether you
--      read it in yazi, `cat` it, or open it in the editor. Change BAT_THEME in
--      one place and everything follows, including this preview.
--   2. The custom syntaxes in ~/.config/bat/syntaxes (C#, C++, JSON, TOML,
--      YAML), compiled into bat's cache. Yazi's own previewer has no idea
--      those exist.
--
-- Deliberately no --theme flag here: letting bat resolve its own theme is the
-- whole point. If bat is missing or fails, we fall back to plain uncoloured
-- text rather than showing an error.
--
-- Scrolling model: `skip` counts *screen rows*, not source lines. bat does the
-- wrapping (--wrap=character), so one line of its output is exactly one row on
-- screen. That is what makes J/K work on a file that is only a few lines long
-- but wraps into a tall block — counting source lines would let a single
-- 2000-character line swallow the whole pane with nothing left to scroll.

local M = {}

-- Read `h` rows starting at `skip`, streaming so we stop as soon as we have
-- enough instead of rendering the whole file.
local function collect(child, skip, h)
	local rows, seen = {}, 0
	while true do
		local line, event = child:read_line()
		if event ~= 0 then
			break
		end
		seen = seen + 1
		if seen > skip then
			rows[#rows + 1] = line
			if #rows >= h then
				break
			end
		end
	end
	return rows
end

function M:peek(job)
	local w = math.max(1, math.floor(job.area.w))
	local h = math.max(1, math.floor(job.area.h))

	local child = Command("bat")
		-- bat picks 24-bit vs 256-colour from COLORTERM, and a subprocess
		-- spawned by yazi does not reliably inherit it (notably under tmux and
		-- the VS Code terminal). Without this bat silently downgrades to the
		-- 256-colour cube and the preview stops matching VS Code.
		:env("COLORTERM", "truecolor")
		:arg({
			"--color=always",
			"--style=plain", -- no line numbers/grid; yazi draws its own chrome
			"--paging=never",
			-- Wrap in bat, not in the widget, so output rows map 1:1 to screen
			-- rows and `skip` stays meaningful. Also keeps ANSI styles correct
			-- across a wrap, which hand-rolled wrapping tends to get wrong.
			"--wrap=character",
			"--terminal-width=" .. tostring(w),
			tostring(job.file.url),
		})
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:spawn()

	if not child then
		return self:fallback(job, w, h)
	end

	local rows = collect(child, job.skip, h)
	child:start_kill()

	if #rows == 0 and job.skip == 0 then
		-- bat produced nothing (unreadable file, or not installed): don't leave
		-- the pane blank, show the file as plain text.
		return self:fallback(job, w, h)
	end

	if job.skip > 0 and #rows < h then
		-- Scrolled past the end: pull the viewport back so the last page stays
		-- filled, matching how yazi's built-in previewers behave.
		return ya.mgr_emit("peek", {
			math.max(0, job.skip - (h - #rows)),
			only_if = job.file.url,
			upper_bound = true,
		})
	end

	self:render(job, rows)
end

-- Plain-text rendering used when bat is unavailable or produces nothing.
-- Wraps by hand, which is safe here precisely because there are no escape
-- sequences to split.
function M:fallback(job, w, h)
	local f = io.open(tostring(job.file.url), "r")
	if not f then
		return self:render(job, { "Cannot read file" })
	end

	local rows, seen = {}, 0
	for line in f:lines() do
		-- Expand one source line into as many screen rows as it occupies.
		repeat
			local chunk = line:sub(1, w)
			line = line:sub(w + 1)
			seen = seen + 1
			if seen > job.skip then
				rows[#rows + 1] = chunk
			end
		until line == "" or #rows >= h
		if #rows >= h then
			break
		end
	end
	f:close()

	self:render(job, rows)
end

-- ui.Clear wipes the pane first. Without it a shorter file leaves the tail of
-- the previous file's preview on screen, because yazi only paints the rows the
-- new widget actually covers.
function M:render(job, rows)
	ya.preview_widget(job, {
		ui.Clear(job.area),
		-- Rows from read_line already carry their trailing newline, so join
		-- with "" rather than "\n" or every other row comes out blank.
		ui.Text.parse(table.concat(rows, "")):area(job.area),
	})
end

function M:seek(job)
	-- `job.skip` is nil in seek (it only exists on the peek job); the live
	-- offset lives on the context, which is only available on this thread.
	-- Reading job.skip here throws, and the throw is swallowed — which looks
	-- exactly like "J and K do nothing".
	local h = cx.active.current.hovered
	if not h or h.url ~= job.file.url then
		return
	end

	ya.mgr_emit("peek", {
		math.max(0, cx.active.preview.skip + job.units),
		only_if = job.file.url,
	})
end

return M
