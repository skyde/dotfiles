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

local M = {}

function M:peek(job)
	local w = math.max(1, math.floor(job.area.w))
	local h = math.max(1, math.floor(job.area.h))

	local child = Command("bat")
		-- bat picks 24-bit vs 256-colour from COLORTERM, and a subprocess
		-- spawned by yazi does not reliably inherit it (notably under tmux and
		-- the VS Code terminal). Without this bat silently downgrades to the
		-- 256-colour cube and the preview stops matching VS Code exactly.
		:env("COLORTERM", "truecolor")
		:arg({
			"--color=always",
			"--style=plain", -- no line numbers/grid; yazi draws its own chrome
			"--paging=never",
			"--wrap=never",
			"--terminal-width=" .. tostring(w),
			-- Ask bat for exactly the visible window instead of reading the
			-- whole file and throwing most of it away.
			"--line-range=" .. tostring(job.skip + 1) .. ":" .. tostring(job.skip + h),
			tostring(job.file.url),
		})
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:spawn()

	if not child then
		return self:fallback(job, h)
	end

	local lines, count = "", 0
	repeat
		local line, event = child:read_line()
		if event ~= 0 then
			break
		end
		lines = lines .. line
		count = count + 1
	until count >= h

	child:start_kill()

	if count == 0 and job.skip == 0 then
		-- bat produced nothing (missing binary, unreadable file): don't leave
		-- the pane blank, show the file as plain text.
		return self:fallback(job, h)
	end

	if job.skip > 0 and count < h then
		-- Scrolled past the end: pull the viewport back so the last page stays
		-- filled, matching how yazi's built-in previewers behave.
		ya.mgr_emit("peek", {
			math.max(0, job.skip - (h - count)),
			only_if = job.file.url,
			upper_bound = true,
		})
	else
		ya.preview_widget(job, ui.Text.parse(lines):area(job.area))
	end
end

-- Plain-text rendering used when bat is unavailable or produces nothing.
-- Uses ui.Text.parse for consistency with the bat path above; on plain text it
-- simply finds no escape sequences.
function M:fallback(job, h)
	local f = io.open(tostring(job.file.url), "r")
	if not f then
		return ya.preview_widget(job, ui.Text.parse("Cannot read file"):area(job.area))
	end

	local lines, n = {}, 0
	for line in f:lines() do
		n = n + 1
		if n > job.skip then
			lines[#lines + 1] = line
			if #lines >= h then
				break
			end
		end
	end
	f:close()

	ya.preview_widget(job, ui.Text.parse(table.concat(lines, "\n")):area(job.area))
end

function M:seek(job)
	local step = math.floor(job.units * job.area.h / 10)
	ya.mgr_emit("peek", {
		math.max(0, job.skip + step),
		only_if = job.file.url,
	})
end

return M
