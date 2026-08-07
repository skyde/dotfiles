-- fzf-preview.yazi
--
-- Fork of yazi's shipped `fzf` plugin (yazi-plugin/preset/plugins/fzf.lua)
-- with one addition: a preview pane on the right while filtering, in the same
-- shape as the `ff` script (bat, numbered lines, right 55%). The shipped
-- plugin launches bare `fzf`, which only previews if FZF_DEFAULT_OPTS says so
-- — and exporting that globally would drag a preview into every other fzf use
-- (history search, tmux pickers, ...). Keeping the flags here scopes them to
-- this binding.
--
-- Everything else matches the shipped plugin: fzf walks the cwd (or filters
-- the current selection when one exists), picking a file reveals it, picking
-- a directory cds into it, and multi-select toggles the chosen entries.

local M = {}

-- Directories get a listing, everything else goes through bat. COLORTERM is
-- forced for the same reason as in bat-preview.yazi: without it bat silently
-- downgrades to 256 colours under tmux and the VS Code terminal.
--
-- bat is resolved rather than named, because Debian and Ubuntu install it as
-- `batcat` and a bare `bat` there put "command not found" in the preview pane
-- for every file. Plain cat is the last resort, so the pane still shows the
-- file when neither exists.
local PREVIEW = [[if [ -d {} ]; then ls -A -- {}; ]]
	.. [[else bat=$(command -v bat || command -v batcat); ]]
	.. [[if [ -n "$bat" ]; then COLORTERM=truecolor "$bat" --style=numbers --color=always --line-range :500 -- {}; ]]
	.. [[else cat -- {}; fi; fi]]

local state = ya.sync(function()
	local selected = {}
	for _, url in pairs(cx.active.selected) do
		selected[#selected + 1] = url
	end
	return cx.active.current.cwd, selected
end)

-- `ya.mgr_emit` became `ya.emit` partway through the 25.x line; resolve at
-- call time so the plugin works on either side of the rename.
local function emit(cmd, args)
	return (ya.emit or ya.mgr_emit)(cmd, args)
end

function M:entry()
	emit("escape", { visual = true })

	local cwd, selected = state()

	-- Url.scheme only exists on newer yazi; where it does, refuse virtual
	-- filesystems the same way the shipped plugin does.
	local ok, virtual = pcall(function()
		return cwd.scheme.is_virtual
	end)
	if ok and virtual then
		return ya.notify { title = "Fzf", content = "Not supported under virtual filesystems", timeout = 5, level = "warn" }
	end

	-- `ya.hide` became `ui.hide`, same story as emit above.
	local permit = (ui.hide or ya.hide)()
	local output, err = M.run_with(cwd, selected)

	permit:drop()
	if not output then
		return ya.notify { title = "Fzf", content = tostring(err), timeout = 5, level = "error" }
	end

	local urls = M.split_urls(cwd, output)
	if #urls == 1 then
		local cha = #selected == 0 and fs.cha(urls[1])
		emit(cha and cha.is_dir and "cd" or "reveal", { urls[1], raw = true })
	elseif #urls > 1 then
		urls.state = #selected > 0 and "off" or "on"
		emit("toggle_all", urls)
	end
end

---@param cwd Url
---@param selected Url[]
---@return string?, Error?
function M.run_with(cwd, selected)
	local child, err = Command("fzf")
		:arg("-m")
		:arg("--preview=" .. PREVIEW)
		:arg("--preview-window=right,55%")
		:cwd(tostring(cwd))
		:stdin(#selected > 0 and Command.PIPED or Command.INHERIT)
		:stdout(Command.PIPED)
		:spawn()

	if not child then
		return nil, Err("Failed to start `fzf`, error: %s", err)
	end

	for _, u in ipairs(selected) do
		child:write_all(string.format("%s\n", u))
	end
	if #selected > 0 then
		child:flush()
	end

	local output, err = child:wait_with_output()
	if not output then
		return nil, Err("Cannot read `fzf` output, error: %s", err)
	elseif not output.status.success and output.status.code ~= 130 then
		return nil, Err("`fzf` exited with error code %s", output.status.code)
	end
	return output.stdout, nil
end

function M.split_urls(cwd, output)
	local t = {}
	for line in output:gmatch("[^\r\n]+") do
		local u = Url(line)
		if u.is_absolute then
			t[#t + 1] = u
		else
			t[#t + 1] = cwd:join(u)
		end
	end
	return t
end

return M
