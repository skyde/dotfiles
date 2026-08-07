--- @sync peek

-- json-preview.yazi
--
-- Preview .json / .jsonl files with `json-pretty` (see
-- common/.local/bin/json-pretty) instead of bat, so the pane shows the same
-- readable rendering as `json-view`: escaped newlines broken into real lines,
-- JSON embedded in strings expanded, long values wrapped to the pane width.
-- bat can only ever show the file as it is on disk, which for a log dump means
-- one 4000-character line per record.
--
-- This is a sibling of bat-preview.yazi rather than a mode of it: the reasoning
-- behind the design (why `@sync peek`, why the pipe is kept open per file, why
-- `skip` counts screen rows and not source lines, why control characters have
-- to be scrubbed) is written out in full over there and applies verbatim here.
-- Keeping them separate means a bug in this one cannot take every other text
-- preview down with it.
--
-- Two things are specific to this previewer:
--
--   * json-pretty has to parse the whole document before it can print its first
--     row, and this peek runs on yazi's main thread. So above LARGE_FILE bytes
--     we hand off to bat, which streams: a huge file previews instantly as raw
--     JSON rather than freezing the UI while python parses it.
--   * a file that is not valid JSON is not an error here. json-pretty reports
--     the parse error, then prints the file unparsed, which is exactly what you
--     want to see when the reason you opened the file is that something wrote
--     broken JSON into it.

local M = {}

-- Files above this size skip json-pretty and preview as raw JSON through bat.
local LARGE_FILE = 8 * 1024 * 1024

-- One live child process per previewed file+width, least recently used evicted.
local ENTRIES_MAX = 4

local entries, clock = {}, 0

local function shell_quote(s)
	local escaped = tostring(s):gsub("'", "'\\''")
	return "'" .. escaped .. "'"
end

local function tab_width()
	return math.max(1, math.floor(rt.preview.tab_size or 2))
end

-- </dev/null keeps the child off yazi's terminal input; 2>/dev/null stops a
-- missing interpreter from painting its complaint into the pane (producing no
-- rows routes that to `fallback` instead).
--
-- COLORTERM is forced for the same reason bat-preview forces it: 24-bit vs the
-- 256-colour cube is decided from it, and it is not reliably set under tmux, the
-- VS Code terminal, or over ssh.
local function spawn(url, w, big)
	local command
	if big then
		command = string.format(
			"COLORTERM=truecolor bat --color=always --language=json --style=plain "
				.. "--paging=never --wrap=character --tabs=%d --terminal-width=%d -- %s",
			tab_width(),
			w,
			shell_quote(url)
		)
	else
		-- ~/.local/bin is where stow puts json-pretty, and it is not necessarily
		-- on the PATH yazi inherited (a GUI launch on macOS gets a very short
		-- one). Appending it rather than prepending leaves a system-wide install
		-- in charge if there is one.
		local runner = 'PATH="$PATH:$HOME/.local/bin" exec json-pretty --color=always --width %d -- %s'
		command = "COLORTERM=truecolor sh -c "
			.. shell_quote(string.format(runner, w, shell_quote(url)))
	end
	return io.popen(command .. " </dev/null 2>/dev/null", "r")
end

local function printable(row)
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

local function rows_for(job, w, need)
	local url = tostring(job.file.url)
	-- Keyed on identity, content and width: a rewritten file gets a fresh
	-- render, and so does the same file in a resized pane.
	local key = string.format("%s\0%d\0%s\0%s", url, w, job.file.cha.mtime, job.file.cha.len)

	clock = clock + 1

	local entry = entries[key]
	if entry then
		entry.used = clock
	else
		entry = {
			rows = {},
			handle = spawn(url, w, (job.file.cha.len or 0) > LARGE_FILE),
			used = clock,
		}
		entries[key] = entry
		evict()
	end

	while entry.handle and #entry.rows < need do
		local row = entry.handle:read("l")
		if row == nil then
			close(entry)
			break
		end
		entry.rows[#entry.rows + 1] = printable(row)
	end

	return entry.rows
end

function M:peek(job)
	local w = math.max(1, math.floor(job.area.w))
	local h = math.max(1, math.floor(job.area.h))

	-- This previewer is selected by filename, so a FIFO, socket or device node
	-- called `events.json` would land here. Reading one can block forever, and
	-- this peek is on the main thread: that would freeze yazi outright.
	local cha = job.file.cha
	if cha.is_fifo or cha.is_sock or cha.is_block or cha.is_char then
		return self:render(job, { "Not a regular file" })
	end

	local rows = rows_for(job, w, job.skip + h)

	if #rows == 0 and job.skip == 0 then
		return self:fallback(job, w, h)
	end

	local visible = table.move(rows, job.skip + 1, math.min(#rows, job.skip + h), 1, {})

	if job.skip > 0 and #visible < h then
		-- Scrolled past the end: pull the viewport back so the last page stays
		-- full, matching yazi's built-in previewers.
		return ya.mgr_emit("peek", {
			math.max(0, job.skip - (h - #visible)),
			only_if = job.file.url,
			upper_bound = true,
		})
	end

	self:render(job, visible)
end

-- Plain text, used when neither json-pretty nor bat produced anything.
function M:fallback(job, w, h)
	local f = io.open(tostring(job.file.url), "r")
	if not f then
		return self:render(job, { "Cannot read file" })
	end

	local indent = string.rep(" ", tab_width())

	local rows, seen = {}, 0
	for line in f:lines() do
		line = printable((line:gsub("\t", indent)))
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

-- ui.Clear first: without it a shorter file leaves the tail of the previous
-- preview on screen, because yazi only paints the rows the new widget covers.
function M:render(job, rows)
	ya.preview_widget(job, {
		ui.Clear(job.area),
		ui.Text.parse(table.concat(rows, "\n")):area(job.area),
	})
end

function M:seek(job)
	-- job.skip does not exist on the seek job; the live offset is on the
	-- context, and reading job.skip here throws (which looks exactly like "J and
	-- K do nothing").
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
