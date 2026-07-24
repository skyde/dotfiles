-- Run with the installed full config and disposable p4d environment.

local workspace = assert(vim.env.P4_TEST_WORKSPACE)
local subtree = assert(vim.env.P4_TEST_SUBTREE)
local direct_cpath = assert(vim.env.P4_TEST_DIRECT_CPATH)
local current = assert(vim.env.P4_TEST_CURRENT_FILE)
local current_filespec = assert(vim.env.P4_TEST_CURRENT_FILESPEC)
local other = assert(vim.env.P4_TEST_OTHER_FILE)
local unrelated = assert(vim.env.P4_TEST_UNRELATED_CWD)
local hanging_p4 = assert(vim.env.P4_TEST_HANGING_P4)
local hang_log = assert(vim.env.P4_HANG_LOG)
local depot_current = assert(vim.env.P4_TEST_DEPOT_CURRENT)
local depot_subtree = "//depot/src one/..."

vim.env.NVIM_VCS = "p4"
assert(vim.env.P4CLIENT == nil, "fixture unexpectedly exported a global P4CLIENT")
assert(vim.uv.cwd() == unrelated, "fixture did not start Neovim from the unrelated cwd")
vim.cmd.edit(vim.fn.fnameescape(current))

local vcs = require("config.vcs")
local lib
local function current_view()
	local ok, loaded = pcall(require, "diffview.lib")
	lib = ok and loaded or lib
	return lib and lib.get_current_view() or nil
end

local function diff_view_ready(minimum_files)
	local view = current_view()
	return view
		and view.ready
		and view.is_loading == false
		and view.panel
		and view.panel.is_loading == false
		and view.files
		and view.files:len() >= minimum_files
end

local function history_view_ready()
	local view = current_view()
	return view
		and view.ready
		and view.panel
		and view.panel.updating == false
		and view.panel.entries
		and #view.panel.entries > 0
end

-- A direct command must receive the compatibility layer from Diffview's
-- plugin setup even before any config.vcs shortcut has run.
require("diffview").open({ "-C=" .. vim.fn.fnameescape(direct_cpath) })
assert(
	vim.wait(20000, function()
		return diff_view_ready(2)
	end, 50),
	"timed out waiting for fresh direct explicit-cpath P4 Diffview"
)
local fresh_direct = assert(current_view())
assert(
	vim.fs.normalize(fresh_direct.adapter.ctx.nvim_p4_cwd) == direct_cpath,
	"fresh direct P4 Diffview did not preserve its explicit discovery directory"
)
assert(
	vim.fs.normalize(fresh_direct.adapter.ctx.toplevel) == workspace,
	"fresh direct P4 Diffview selected the wrong client root"
)
assert(require("diffview").close(nil, { force = true }) ~= false, "could not close fresh direct P4 Diffview")

vcs.changes()
assert(
	vim.wait(20000, function()
		return diff_view_ready(1)
	end, 50),
	"timed out waiting for the scoped P4 Diffview"
)

local scoped = assert(current_view())
assert(scoped.adapter.config_key == "p4", "Diffview did not select the P4 adapter")
assert(
	vim.fs.normalize(scoped.adapter.ctx.toplevel) == workspace,
	"Diffview selected the decoy P4CONFIG client from Neovim's process cwd"
)
assert(
	vim.fs.normalize(scoped.adapter.ctx.nvim_p4_cwd) == subtree,
	"Diffview did not preserve the nested P4CONFIG discovery directory"
)
assert(#scoped.adapter.ctx.path_args == 1, "scoped P4 Diffview received the wrong path count")
assert(
	vim.fn.expand(scoped.adapter.ctx.path_args[1]) == subtree .. "/...",
	"scoped P4 Diffview changed the subtree path"
)
assert(scoped.files:len() == 1, "scoped P4 Diffview included files outside the active subtree")
local found_current = false
for _, entry in scoped.files:iter() do
	if vim.fs.normalize(entry.absolute_path) == current then
		found_current = true
	end
	assert(entry.absolute_path ~= other, "scoped P4 Diffview included the other subtree")
end
assert(found_current, "scoped P4 Diffview did not preserve the exact local current-file path")
local relative_current = assert(vim.fs.relpath(workspace, current))
assert(
	vim.deep_equal({ "print", "-q", current_filespec .. "#head" }, scoped.adapter:get_show_args(relative_current)),
	"P4 show arguments did not resolve a relative path against the client root"
)
assert(
	scoped.adapter:is_binary(relative_current) == false,
	"P4 binary detection could not resolve a relative text file against the client root"
)
assert(require("diffview").close(nil, { force = true }) ~= false, "could not close scoped P4 Diffview")

vcs.current_file()
assert(
	vim.wait(20000, function()
		return diff_view_ready(1)
	end, 50),
	"timed out waiting for the current-file P4 Diffview"
)
local current_diff = assert(current_view())
assert(#current_diff.adapter.ctx.path_args == 1, "current-file P4 Diffview received the wrong path count")
assert(
	vim.fn.expand(current_diff.adapter.ctx.path_args[1]) == current_filespec,
	"current-file P4 Diffview did not use the encoded P4 filespec"
)
assert(current_diff.files:len() == 1, "current-file P4 Diffview included another file")
for _, entry in current_diff.files:iter() do
	assert(
		vim.fs.normalize(entry.absolute_path) == current,
		"current-file P4 Diffview did not preserve the exact local path"
	)
end
assert(require("diffview").close(nil, { force = true }) ~= false, "could not close current-file P4 Diffview")

vcs.all_changes()
assert(
	vim.wait(20000, function()
		return diff_view_ready(2)
	end, 50),
	"timed out waiting for the whole-client P4 Diffview"
)
local all = assert(current_view())
assert(#all.adapter.ctx.path_args == 0, "whole-client P4 action unexpectedly had a path scope")
assert(all.files:len() == 2, "whole-client P4 Diffview did not show both opened files")
assert(require("diffview").close(nil, { force = true }) ~= false, "could not close whole-client P4 Diffview")

assert(
	vim.fs.normalize(vim.api.nvim_buf_get_name(0)) == current,
	"closing whole-client P4 Diffview did not restore the original file buffer: " .. vim.api.nvim_buf_get_name(0)
)
vcs.file_history()
assert(vim.wait(20000, history_view_ready, 50), "timed out waiting for P4 file history")
local file_history = assert(current_view())
assert(file_history.adapter.config_key == "p4", "file history did not select the P4 adapter")
assert(#file_history.adapter.ctx.path_args == 1, "P4 file history received the wrong path count")
local file_history_commit = assert(file_history.panel.entries[1].commit)
assert(file_history_commit.iso_date ~= "", "P4 file history omitted the ISO date")
assert(file_history_commit.rel_date ~= "", "P4 file history omitted the relative date")
assert(
	vim.fn.expand(file_history.adapter.ctx.path_args[1]) == depot_current,
	"P4 file history did not use the mapped depot path"
)
assert(require("diffview").close(nil, { force = true }) ~= false, "could not close P4 file history")

vcs.repo_history()
assert(vim.wait(20000, history_view_ready, 50), "timed out waiting for scoped P4 repository history")
local repo_history = assert(current_view())
assert(repo_history.adapter.config_key == "p4", "repository history did not select the P4 adapter")
assert(#repo_history.adapter.ctx.path_args == 1, "P4 repository history received the wrong path count")
assert(
	vim.fn.expand(repo_history.adapter.ctx.path_args[1]) == depot_subtree,
	"P4 repository history did not use the mapped depot subtree"
)
assert(require("diffview").close(nil, { force = true }) ~= false, "could not close P4 repository history")

-- A raw command after a config.vcs shortcut must honor its own explicit -C;
-- it must not inherit the shortcut's nested P4CONFIG directory.
require("diffview").open({ "-C=" .. vim.fn.fnameescape(direct_cpath) })
assert(
	vim.wait(20000, function()
		return diff_view_ready(2)
	end, 50),
	"timed out waiting for direct explicit-cpath P4 Diffview"
)
local direct = assert(current_view())
assert(
	vim.fs.normalize(direct.adapter.ctx.nvim_p4_cwd) == direct_cpath,
	"direct P4 Diffview inherited a stale config.vcs discovery directory"
)
assert(vim.fs.normalize(direct.adapter.ctx.toplevel) == workspace, "direct P4 Diffview selected the wrong client root")
assert(require("diffview").close(nil, { force = true }) ~= false, "could not close direct P4 Diffview")

-- All three compatibility paths must remain bounded even when an explicit
-- client bypasses the shell shim (as native Windows Neovim does).
local config = require("diffview.config").get_config()
local P4Adapter = require("diffview.vcs.adapters.p4").P4Adapter
local VCSAdapter = require("diffview.vcs.adapter").VCSAdapter
local saved_command = config.p4_cmd
local saved_timeout = vim.env.NVIM_P4_TIMEOUT_MS
local saved_bootstrap = {
	done = P4Adapter.bootstrap.done,
	ok = P4Adapter.bootstrap.ok,
	err = P4Adapter.bootstrap.err,
}
config.p4_cmd = { hanging_p4 }
vim.env.NVIM_P4_TIMEOUT_MS = "500"

-- The failed bootstrap below is deliberate. Silence only its logger upvalue
-- so the soak's global error scan remains reserved for unexpected failures.
local logger_index
local saved_logger
for index = 1, 32 do
	local name, value = debug.getupvalue(VCSAdapter.bootstrap_preamble, index)
	if name == "logger" then
		logger_index = index
		saved_logger = value
		break
	end
end
assert(logger_index, "could not isolate the expected P4 bootstrap error logger")
debug.setupvalue(VCSAdapter.bootstrap_preamble, logger_index, require("diffview.logger").Logger.mock)

local function assert_bounded(label, callback)
	local started = vim.uv.hrtime()
	callback()
	local elapsed = (vim.uv.hrtime() - started) / 1000000
	assert(elapsed < 3000, ("%s took %.0f ms despite a 500 ms timeout"):format(label, elapsed))
end

P4Adapter.bootstrap.done = false
P4Adapter.bootstrap.ok = false
P4Adapter.bootstrap.err = nil
assert_bounded("P4 bootstrap", P4Adapter.run_bootstrap)
assert_bounded("P4 repository path discovery", function()
	P4Adapter.get_repo_paths({}, workspace)
end)
assert_bounded("P4 top-level discovery", function()
	P4Adapter.find_toplevel({ unrelated })
end)
debug.setupvalue(VCSAdapter.bootstrap_preamble, logger_index, saved_logger)
local hang_calls = vim.fn.filereadable(hang_log) == 1 and vim.fn.readfile(hang_log) or {}
assert(
	#hang_calls == 3,
	(
		"not every synchronous P4 info path invoked the hanging fixture"
		.. " (calls=%d, configured=%s, executable=%d, compat=%s, source=%s)"
	):format(
		#hang_calls,
		tostring(require("diffview.config").get_config().p4_cmd[1]),
		vim.fn.executable(hanging_p4),
		tostring(P4Adapter._nvim_adapter_compat),
		debug.getinfo(P4Adapter.run_bootstrap, "S").source
	)
)

config.p4_cmd = saved_command
vim.env.NVIM_P4_TIMEOUT_MS = saved_timeout
P4Adapter.bootstrap.done = saved_bootstrap.done
P4Adapter.bootstrap.ok = saved_bootstrap.ok
P4Adapter.bootstrap.err = saved_bootstrap.err

print("nvim real P4 Diffview tests passed")
