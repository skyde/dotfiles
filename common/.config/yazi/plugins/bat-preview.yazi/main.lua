--- @sync peek

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
--
-- Why `@sync peek`: moving the cursor onto another file makes yazi's
-- `Mgr::peek` call `Preview::reset()`, which drops the previous preview
-- immediately. An asynchronous previewer only hands back its widget a few
-- milliseconds later, and yazi paints whatever frames fall in that gap — an
-- empty pane. That is the flicker. A synchronous peek is dispatched through
-- the app's own event queue, and yazi drains every pending event before it
-- renders, so the cursor move and the new preview land in the *same* frame:
-- there is no intermediate state left to draw.
--
-- The price of running on the main thread is that `bat` blocks the UI while it
-- produces the rows. Two things keep that short:
--
--   * we only ever read the rows the pane can show, never the whole file;
--   * bat's pipe is kept open per file (see `entries` below), so scrolling
--     pulls the next few rows from a process that is already running and
--     already ahead, instead of re-rendering from the top on every J/K.

local M = {}

-- One live `bat` per previewed file+width. Each entry owns a child process, so
-- the table is small and the least recently used entry is closed when a new
-- file pushes it out.
local ENTRIES_MAX = 4

local entries, clock = {}, 0

local function shell_quote(s)
	local escaped = tostring(s):gsub("'", "'\\''")
	return "'" .. escaped .. "'"
end

-- </dev/null keeps the child off yazi's terminal input, and 2>/dev/null stops a
-- missing or unhappy bat from painting its complaint into the preview;
-- producing no rows routes that to `fallback` instead.
-- Tabs have to become spaces before they reach the terminal: a tab moves the
-- cursor to the next tab stop instead of overwriting the cells it skips, which
-- leaves shreds of the previous file's preview behind now that the pane is no
-- longer blanked between files. yazi's own `preview.tab_size` decides how wide
-- they are, so indentation matches the rest of yazi. Never 0 — that is bat's
-- "pass tabs through" mode, the exact thing we are avoiding.
local function tab_width()
	return math.max(1, math.floor(rt.preview.tab_size or 2))
end

local function spawn(url, w)
	return io.popen(
		string.format(
			-- bat picks 24-bit vs 256-colour from COLORTERM, and yazi does not
			-- reliably have it set itself (notably under tmux and the VS Code
			-- terminal). Without this bat silently downgrades to the 256-colour
			-- cube and the preview stops matching VS Code.
			"COLORTERM=truecolor bat --color=always --style=plain --paging=never "
				.. "--wrap=character --tabs=%d --terminal-width=%d -- %s </dev/null 2>/dev/null",
			tab_width(),
			w,
			shell_quote(url)
		),
		"r"
	)
end

-- Anything else that steers the cursor rather than printing a glyph gets the
-- same treatment: a stray CR, backspace or bell inside a file would otherwise
-- shift the rest of the row and strand pixels from the previous preview. ESC
-- is deliberately kept — that is how bat delivers the colours, and the only
-- other bytes in an SGR sequence are printable.
local function printable(row)
	-- Everything below 0x20 and DEL, except ESC (0x1B) which opens the SGR
	-- sequences carrying bat's colours.
	return (row:gsub("[%z\1-\26\28-\31\127]", "\u{FFFD}"))
end

local function close(entry)
	if entry.handle then
		entry.handle:close()
		entry.handle = nil
	end
end

local function evict()
	local n, oldest, oldest_key = 0, nil, nil
	for key, entry in pairs(entries) do
		n = n + 1
		if not oldest or entry.used < oldest.used then
			oldest, oldest_key = entry, key
		end
	end
	if n > ENTRIES_MAX then
		close(oldest)
		entries[oldest_key] = nil
	end
end

-- Rows rendered for this file so far, extended from the live pipe until we
-- have `need` of them or bat runs out of file.
local function rows_for(job, w, need)
	local url = tostring(job.file.url)
	-- Keyed on the file's identity *and* its content: a rewritten file gets a
	-- new key rather than a stale preview. Width too, because bat wrapped the
	-- rows for one specific pane width.
	local key = string.format("%s\0%d\0%s\0%s", url, w, job.file.cha.mtime, job.file.cha.len)

	clock = clock + 1

	local entry = entries[key]
	if entry then
		entry.used = clock
	else
		-- `used` has to be set before evicting, or the entry we just created
		-- has no age to compare against the ones already in the table.
		entry = { rows = {}, handle = spawn(url, w), used = clock }
		entries[key] = entry
		evict()
	end

	while entry.handle and #entry.rows < need do
		local row = entry.handle:read("l")
		if row == nil then
			close(entry) -- end of file: every row there will ever be is cached
			break
		end
		entry.rows[#entry.rows + 1] = printable(row)
	end

	return entry.rows
end

function M:peek(job)
	local w = math.max(1, math.floor(job.area.w))
	local h = math.max(1, math.floor(job.area.h))

	-- Our previewer is also selected by filename, so a FIFO, socket or device
	-- node called `queue.log` would land here. Reading one can block forever,
	-- and this peek runs on the main thread — that would freeze yazi outright,
	-- not merely flicker it. Only regular files get opened.
	local cha = job.file.cha
	if cha.is_fifo or cha.is_sock or cha.is_block or cha.is_char then
		return self:render(job, { "Not a regular file" })
	end

	local rows = rows_for(job, w, job.skip + h)

	if #rows == 0 and job.skip == 0 then
		-- bat produced nothing (unreadable file, or not installed): don't leave
		-- the pane blank, show the file as plain text.
		return self:fallback(job, w, h)
	end

	local visible = table.move(rows, job.skip + 1, math.min(#rows, job.skip + h), 1, {})

	if job.skip > 0 and #visible < h then
		-- Scrolled past the end: pull the viewport back so the last page stays
		-- filled, matching how yazi's built-in previewers behave.
		return ya.mgr_emit("peek", {
			math.max(0, job.skip - (h - #visible)),
			only_if = job.file.url,
			upper_bound = true,
		})
	end

	self:render(job, visible)
end

-- Plain-text rendering used when bat is unavailable or produces nothing.
-- Wraps by hand, which is safe here precisely because there are no escape
-- sequences to split.
function M:fallback(job, w, h)
	local f = io.open(tostring(job.file.url), "r")
	if not f then
		return self:render(job, { "Cannot read file" })
	end

	local indent = string.rep(" ", tab_width())

	local rows, seen = {}, 0
	for line in f:lines() do
		-- No bat here to expand tabs for us, and a raw one would scramble the
		-- row exactly as it would in the bat path.
		line = printable((line:gsub("\t", indent)))
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
		ui.Text.parse(table.concat(rows, "\n")):area(job.area),
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
