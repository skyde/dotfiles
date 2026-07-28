--- @sync peek
--- @since 25.5.31

-- Render a bounded text preview on Yazi's main event loop.
--
-- Yazi normally clears the old preview before its asynchronous highlighter has
-- produced the replacement.  On large files that intermediate empty state can
-- survive long enough to be displayed.  A synchronous preview is coalesced
-- into the same render cycle as the cursor move, so the terminal changes
-- directly from one populated preview to the next.
--
-- Keep the read and render budgets deliberately small.  This makes the
-- synchronous work independent of total file size, including for minified
-- files with a single very long line.

local M = {}

local READ_LIMIT = 256 * 1024
local MIN_RENDER_LIMIT = 8 * 1024
local MAX_RENDER_LIMIT = 64 * 1024

local function sanitize_utf8(text)
	local chunks = {}
	local first = 1

	while first <= #text do
		local _, invalid = utf8.len(text, first)
		if not invalid then
			chunks[#chunks + 1] = text:sub(first)
			break
		end
		if invalid > first then
			chunks[#chunks + 1] = text:sub(first, invalid - 1)
		end
		chunks[#chunks + 1] = "�"
		first = invalid + 1
	end

	return table.concat(chunks)
end

local function bounded_view(data, skip, width, height)
	data = data:gsub("\r\n", "\n"):gsub("\r", "\n")

	local first = 1
	for _ = 1, skip do
		local newline = data:find("\n", first, true)
		if not newline then
			return nil
		end
		first = newline + 1
	end

	local render_limit = math.max(MIN_RENDER_LIMIT, width * height * 2)
	render_limit = math.min(MAX_RENDER_LIMIT, render_limit)

	local limit_end = math.min(#data, first + render_limit - 1)
	local last = limit_end
	local lines = 0
	local cursor = first
	while lines < height do
		local newline = data:find("\n", cursor, true)
		if not newline or newline > limit_end then
			break
		end
		cursor = newline + 1
		lines = lines + 1
		if lines == height then
			last = newline
		end
	end

	local view = data:sub(first, last)
	-- Preserve tabs and newlines, but prevent file contents from injecting
	-- terminal control sequences into the preview.
	view = view:gsub("[%z\1-\8\11\12\14-\31\127]", "�")
	return sanitize_utf8(view)
end

function M:peek(job)
	local file = io.open(tostring(job.file.url), "rb")
	if not file then
		return ya.preview_widget(job, ui.Text.parse("Cannot read file"):area(job.area))
	end

	local data = file:read(READ_LIMIT) or ""
	file:close()

	local view = bounded_view(data, job.skip, math.max(1, math.floor(job.area.w)), math.max(1, math.floor(job.area.h)))

	if not view then
		return ya.mgr_emit("peek", {
			math.max(0, job.skip - math.max(1, math.floor(job.area.h / 2))),
			only_if = job.file.url,
			upper_bound = true,
		})
	end

	if view == "" then
		view = "Empty file"
	end

	local wrap = rt.preview.wrap == "yes" and ui.Wrap.YES or ui.Wrap.NO
	ya.preview_widget(job, ui.Text.parse(view):area(job.area):wrap(wrap))
end

function M:seek(job)
	local step = math.floor(job.units * job.area.h / 10)
	if step == 0 then
		step = job.units < 0 and -1 or 1
	end

	ya.mgr_emit("peek", {
		math.max(0, cx.active.preview.skip + step),
		only_if = job.file.url,
	})
end

return M
