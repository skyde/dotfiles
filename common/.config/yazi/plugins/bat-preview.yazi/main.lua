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
-- Architecture: synchronous render, asynchronous fetch.
--
-- `peek` is synchronous (`@sync peek`) because moving the cursor onto another
-- file makes yazi's `Mgr::peek` call `Preview::reset()`, which drops the old
-- preview immediately. An asynchronous previewer only hands back its widget a
-- few milliseconds later, and yazi paints whatever frames fall in that gap —
-- an empty pane. A synchronous peek is dispatched through the app's own event
-- queue, and yazi drains every pending event before it renders, so the cursor
-- move and the new preview land in the *same* frame: no flicker.
--
-- An earlier version of this plugin also ran `bat` inside that synchronous
-- peek, which blocks the main thread for as long as fork+exec and bat's
-- startup take. On an idle machine that is a few milliseconds; under system
-- load it is arbitrarily long. The whole UI freezes, keypresses queue up, and
-- when the freeze ends they all fire at once against whatever state the app
-- is in by then — the cursor jumps, pickers and prompts open seemingly on
-- their own. So the synchronous side now touches no process and no file: it
-- only renders rows already sitting in the cache below. A miss queues a fetch
-- request and returns; the asynchronous side (`entry`) runs bat off the main
-- thread, hands the rows back through a `ya.sync` bridge, and that bridge
-- re-emits `peek` — which now hits the cache and renders in one frame.
--
-- The price is that the very first hover of a file shows an empty pane for
-- one bat round-trip, exactly like yazi's stock previewers. Every revisit,
-- and every scroll within the fetched rows, still renders flicker-free in the
-- same frame as the keypress. Under load the fetch may take a while — but the
-- UI keeps responding the entire time.
--
-- Scrolling model: `skip` counts *screen rows*, not source lines. bat does the
-- wrapping (--wrap=character), so one line of its output is exactly one row on
-- screen. That is what makes J/K work on a file that is only a few lines long
-- but wraps into a tall block — counting source lines would let a single
-- 2000-character line swallow the whole pane with nothing left to scroll.

local M = {}

-- Cached previews, one per file+width. Entries are small (a table of strings
-- capped by how far the preview was scrolled), so keep a handful around: LRU
-- eviction when a new file pushes the table past this.
local ENTRIES_MAX = 8

-- Rows fetched beyond what the pane needs right now, so scrolling a page or
-- three lands in cache instead of paying another bat run per J.
local LOOKAHEAD = 400

-- A fetch that has produced nothing for this long is presumed lost (the async
-- task errored, or its result was dropped); the next peek queues a fresh one.
local FETCH_TIMEOUT = 3

-- Sync-context state. The async context loads this module separately and gets
-- its own (empty, unused) copies; it may only touch the real ones through the
-- `ya.sync` bridges below.
local entries, by_id, pending = {}, {}, {}
local clock, next_id = 0, 1

local emit = ya.emit or ya.mgr_emit

-- Tabs have to become spaces before rows reach the terminal: a tab moves the
-- cursor to the next tab stop instead of overwriting the cells it skips, which
-- would leave shreds of the previous file's preview behind. yazi's own
-- `preview.tab_size` decides how wide they are, so indentation matches the
-- rest of yazi. Never 0 — that is bat's "pass tabs through" mode, the exact
-- thing we are avoiding.
local function tab_width()
	return math.max(1, math.floor(rt.preview.tab_size or 2))
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

local function evict()
	local n, oldest, oldest_key = 0, nil, nil
	for key, entry in pairs(entries) do
		n = n + 1
		if not oldest or entry.used < oldest.used then
			oldest, oldest_key = entry, key
		end
	end
	if n > ENTRIES_MAX then
		entries[oldest_key] = nil
		by_id[oldest.id] = nil
	end
end

local function entry_for(job, w)
	local url = tostring(job.file.url)
	-- Keyed on the file's identity *and* its content: a rewritten file gets a
	-- new key rather than a stale preview. Width too, because bat wrapped the
	-- rows for one specific pane width.
	local key = string.format("%s\0%d\0%s\0%s", url, w, job.file.cha.mtime, job.file.cha.len)

	clock = clock + 1

	local entry = entries[key]
	if not entry then
		entry = { id = next_id, url = url, rows = {}, eof = false, fetching = false, want = 0 }
		next_id = next_id + 1
		entries[key] = entry
		by_id[entry.id] = entry
		-- `used` has to be set before evicting, or the entry we just created
		-- has no age to compare against the ones already in the table.
		entry.used = clock
		evict()
	end
	entry.used = clock
	return entry
end

----------------------------------------------------------------------
--  Async → sync bridges
----------------------------------------------------------------------

-- Hand the queued fetch requests to the async side, draining the queue.
local take_pending = ya.sync(function()
	local batch = pending
	pending = {}
	return batch
end)

-- Deliver fetched rows into the cache, then re-peek so the waiting pane gets
-- painted — but only if the file is still the hovered one; otherwise the rows
-- just sit in cache for the next visit.
local put_rows = ya.sync(function(_, id, rows, eof)
	local entry = by_id[id]
	if not entry then
		return -- evicted while the fetch was in flight
	end

	-- Two fetches can be in flight when a scroll raised `want` mid-flight;
	-- they may complete out of order, so only ever grow the cached rows.
	if #rows > #entry.rows then
		entry.rows = rows
	end
	entry.eof = entry.eof or eof
	entry.fetching = false

	local h = cx.active.current.hovered
	if h and tostring(h.url) == entry.url then
		emit("peek", { cx.active.preview.skip, only_if = h.url, force = true })
	end
end)

----------------------------------------------------------------------
--  Sync side: render from cache, never block
----------------------------------------------------------------------

function M:peek(job)
	local w = math.max(1, math.floor(job.area.w))
	local h = math.max(1, math.floor(job.area.h))

	-- Our previewer is also selected by filename, so a FIFO, socket or device
	-- node called `queue.log` would land here. Reading one can block forever —
	-- keep them away from the fetcher entirely.
	local cha = job.file.cha
	if cha.is_fifo or cha.is_sock or cha.is_block or cha.is_char then
		return self:render(job, { "Not a regular file" })
	end

	local entry = entry_for(job, w)
	local need = job.skip + h

	local stale = entry.fetching and ya.time() - (entry.started or 0) > FETCH_TIMEOUT
	if not entry.eof and #entry.rows < need and (not entry.fetching or entry.want < need or stale) then
		entry.fetching = true
		entry.started = ya.time()
		entry.want = need + LOOKAHEAD
		pending[#pending + 1] = { id = entry.id, url = entry.url, w = w, want = entry.want, tabs = tab_width() }
		emit("plugin", { "bat-preview" })
	end

	local rows = entry.rows
	local visible = table.move(rows, job.skip + 1, math.min(#rows, job.skip + h), 1, {})

	-- Scrolled past the end: pull the viewport back so the last page stays
	-- filled, matching how yazi's built-in previewers behave. Only once EOF is
	-- known — while rows are still arriving a short cache just means "not
	-- fetched yet", and yanking the viewport around would fight the scroll.
	if entry.eof and job.skip > 0 and #visible < h then
		return emit("peek", {
			math.max(0, job.skip - (h - #visible)),
			only_if = job.file.url,
			upper_bound = true,
		})
	end

	-- On a cache miss this renders an empty pane (rows are still on their
	-- way); on a hit it renders in the same frame as the cursor move.
	self:render(job, visible)
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

	emit("peek", {
		math.max(0, cx.active.preview.skip + job.units),
		only_if = job.file.url,
	})
end

----------------------------------------------------------------------
--  Async side: run bat, ship rows back
----------------------------------------------------------------------

-- bat picks 24-bit vs 256-colour from COLORTERM, and yazi does not reliably
-- have it set itself (notably under tmux and the VS Code terminal). Without
-- this bat silently downgrades to the 256-colour cube and the preview stops
-- matching VS Code. pcall because `Command:env` is newer than some of the
-- yazi versions this config has to survive on; losing it only costs colour
-- depth, not the preview.
local function spawn_bat(req)
	local cmd = Command("bat")
	pcall(function()
		cmd = cmd:env("COLORTERM", "truecolor")
	end)
	local child, _ = cmd
		:arg("--color=always")
		:arg("--style=plain")
		:arg("--paging=never")
		:arg("--wrap=character")
		:arg("--tabs=" .. req.tabs)
		:arg("--terminal-width=" .. req.w)
		:arg("--")
		:arg(req.url)
		:stdin(Command.NULL)
		:stdout(Command.PIPED)
		:stderr(Command.NULL)
		:spawn()
	return child
end

-- Read up to `want` rows, then stop bat rather than letting it highlight the
-- rest of a file nobody scrolled to. eof=false says "there were more rows" —
-- the sync side uses that to queue a deeper fetch when scrolling catches up.
local function bat_rows(req)
	local child = spawn_bat(req)
	if not child then
		return nil
	end

	local rows, eof = {}, false
	while #rows < req.want do
		local line, event = child:read_line()
		if event == 0 then
			rows[#rows + 1] = printable((line:gsub("[\r\n]+$", "")))
		elseif event ~= 1 then
			eof = true
			break
		end
	end
	child:start_kill()
	return rows, eof
end

-- Plain-text fallback used when bat is unavailable or produces nothing
-- (unreadable file, binary it refuses, ...). Wraps by hand, which is safe
-- here precisely because there are no escape sequences to split.
local function plain_rows(req)
	local f = io.open(req.url, "r")
	if not f then
		return { "Cannot read file" }, true
	end

	local indent = string.rep(" ", req.tabs)
	local rows = {}
	for line in f:lines() do
		-- No bat here to expand tabs for us, and a raw one would scramble the
		-- row exactly as it would in the bat path.
		line = printable((line:gsub("\t", indent)))
		-- Expand one source line into as many screen rows as it occupies.
		repeat
			rows[#rows + 1] = line:sub(1, req.w)
			line = line:sub(req.w + 1)
		until line == "" or #rows >= req.want
		if #rows >= req.want then
			f:close()
			return rows, false
		end
	end
	f:close()
	return rows, true
end

-- Invoked as `plugin bat-preview` (no args) from the sync side. Requests
-- travel through the sync-owned queue rather than command arguments, so
-- nothing here depends on how any particular yazi version parses plugin args.
function M:entry(_)
	for _, req in ipairs(take_pending()) do
		local rows, eof = bat_rows(req)
		if not rows or (eof and #rows == 0) then
			rows, eof = plain_rows(req)
		end
		put_rows(req.id, rows, eof)
	end
end

return M
