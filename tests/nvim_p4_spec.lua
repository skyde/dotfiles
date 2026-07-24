-- Run from tests/nvim_p4_spec.sh with a disposable p4d.

local script = debug.getinfo(1, "S").source:sub(2)
local repo_root = vim.fn.fnamemodify(script, ":p:h:h")
local config_root = vim.fs.joinpath(repo_root, "common", ".config", "nvim", "lua")
package.path = table.concat({
	vim.fs.joinpath(config_root, "?.lua"),
	vim.fs.joinpath(config_root, "?", "init.lua"),
	package.path,
}, ";")

local workspace = assert(vim.env.P4_TEST_WORKSPACE)
local subtree = assert(vim.env.P4_TEST_SUBTREE)
local current = assert(vim.env.P4_TEST_CURRENT_FILE)
local current_filespec = assert(vim.env.P4_TEST_CURRENT_FILESPEC)
local other = assert(vim.env.P4_TEST_OTHER_FILE)
local outside = assert(vim.env.P4_TEST_OUTSIDE_FILE)
local unrelated = assert(vim.env.P4_TEST_UNRELATED_CWD)
local command_log = assert(vim.env.P4_COMMAND_LOG)
local depot_current = assert(vim.env.P4_TEST_DEPOT_CURRENT)
local depot_subtree = "//depot/src one/..."

local function fail(message)
	error(message, 0)
end

local function assert_equal(expected, actual, message)
	if not vim.deep_equal(expected, actual) then
		fail(("%s\nexpected: %s\nactual:   %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
	end
end

local captured = {}
package.loaded["diffview"] = {
	open = function(args)
		captured.open = vim.deepcopy(args)
	end,
	file_history = function(_, args)
		captured.history = vim.deepcopy(args)
	end,
	close = function() end,
	emit = function() end,
}
package.loaded["diffview.lib"] = {
	get_current_view = function()
		return nil
	end,
}

local notifications = {}
vim.notify = function(message)
	table.insert(notifications, tostring(message))
end

vim.env.NVIM_VCS = "p4"
assert_equal(nil, vim.env.P4CLIENT, "fixture unexpectedly exported a global P4CLIENT")
assert_equal(unrelated, vim.uv.cwd(), "fixture did not start Neovim from the unrelated cwd")
vim.cmd.edit(vim.fn.fnameescape(current))
local original_system = vim.system
local diff_wait_timeout = "not called"
vim.system = function(command, opts)
	local process = original_system(command, opts)
	if command[2] ~= "diff" then
		return process
	end
	return {
		wait = function(_, timeout)
			diff_wait_timeout = timeout
			if timeout == nil then
				return process:wait()
			end
			return process:wait(timeout)
		end,
	}
end
package.loaded["config.vcs"] = nil
local vcs = require("config.vcs")

vim.fn.writefile({}, command_log)
vcs.changes()
assert_equal({
	"-C=" .. vim.fn.fnameescape(subtree),
	"--",
	vim.fn.fnameescape(subtree .. "/..."),
}, captured.open, "P4 working-copy view was not scoped to the active subtree")

vcs.all_changes()
assert_equal(
	{ "-C=" .. vim.fn.fnameescape(subtree) },
	captured.open,
	"explicit whole-client P4 view unexpectedly retained a subtree scope"
)

vcs.current_file()
assert_equal({
	"-C=" .. vim.fn.fnameescape(subtree),
	"--",
	vim.fn.fnameescape(current_filespec),
}, captured.open, "P4 current-file diff changed its path")

vcs.branch_diff()
assert_equal({
	"-C=" .. vim.fn.fnameescape(subtree),
	"--",
	vim.fn.fnameescape(subtree .. "/..."),
}, captured.open, "P4 branch diff was not scoped to the active subtree")

vcs.upstream_patch()
assert_equal({
	"-C=" .. vim.fn.fnameescape(subtree),
	"--",
	vim.fn.fnameescape(subtree .. "/..."),
}, captured.open, "P4 upstream patch was not scoped to the active subtree")

vcs.file_history()
assert_equal({
	"-C=" .. vim.fn.fnameescape(subtree),
	vim.fn.fnameescape(depot_current),
}, captured.history, "P4 file history changed the current file path")

vcs.repo_history()
assert_equal({
	"-C=" .. vim.fn.fnameescape(subtree),
	vim.fn.fnameescape(depot_subtree),
}, captured.history, "P4 repository history was not scoped to the active subtree")

vcs.copy_diff()
assert_equal(nil, diff_wait_timeout, "P4 diff generation unexpectedly used the discovery timeout")
local patch = vim.fn.getreg('"')
assert(patch:find(depot_current, 1, true), "scoped P4 patch omitted the encoded current-file depot path")
assert(not patch:find(vim.fs.basename(other), 1, true), "scoped P4 patch included another subtree")

vcs.info()
local info_calls = 0
for _, line in ipairs(vim.fn.readfile(command_log)) do
	if line == "info" then
		info_calls = info_calls + 1
	end
end
assert_equal(1, info_calls, "successive P4 actions repeated the remote workspace probe")
assert(notifications[#notifications]:find("scope: " .. subtree .. "/...", 1, true), "P4 info omitted scope")

local original_user = vim.env.P4USER
vim.env.P4USER = original_user .. "-alternate"
vcs.info()
vim.env.P4USER = original_user

info_calls = 0
for _, line in ipairs(vim.fn.readfile(command_log)) do
	if line == "info" then
		info_calls = info_calls + 1
	end
end
assert_equal(2, info_calls, "changing P4USER did not invalidate the workspace cache")

vim.env.NVIM_P4_CONTEXT_CACHE_MS = "0"
vcs.info()
vim.env.NVIM_P4_CONTEXT_CACHE_MS = nil

info_calls = 0
for _, line in ipairs(vim.fn.readfile(command_log)) do
	if line == "info" then
		info_calls = info_calls + 1
	end
end
assert_equal(3, info_calls, "NVIM_P4_CONTEXT_CACHE_MS=0 did not disable the workspace cache")

captured.open = nil
vim.cmd.edit(vim.fn.fnameescape(outside))
vcs.changes()
assert_equal(nil, captured.open, "a path outside the P4 client opened an unscoped whole-client view")

vim.system = original_system
print("nvim P4 glue tests passed")
