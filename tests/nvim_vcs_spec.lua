-- Run with: nvim --headless -u NONE -i NONE -l tests/nvim_vcs_spec.lua

local script = debug.getinfo(1, "S").source:sub(2)
local repo_root = vim.fn.fnamemodify(script, ":p:h:h")
local config_root = vim.fs.joinpath(repo_root, "common", ".config", "nvim", "lua")
package.path = table.concat({
	vim.fs.joinpath(config_root, "?.lua"),
	vim.fs.joinpath(config_root, "?", "init.lua"),
	package.path,
}, ";")

local function fail(message)
	error(message, 0)
end

local function assert_equal(expected, actual, message)
	if not vim.deep_equal(expected, actual) then
		fail(("%s\nexpected: %s\nactual:   %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
	end
end

local function assert_match(pattern, actual, message)
	if not tostring(actual):find(pattern, 1, true) then
		fail(("%s\nmissing: %s\nactual:  %s"):format(message, pattern, tostring(actual)))
	end
end

local function system(command, directory, trim)
	local result = vim.system(command, { cwd = directory, text = true }):wait()
	if result.code ~= 0 then
		fail(("command failed (%d): %s\n%s"):format(result.code, table.concat(command, " "), result.stderr or ""))
	end
	return trim == false and (result.stdout or "") or vim.trim(result.stdout or "")
end

local function init_repo(path, filename)
	vim.fn.mkdir(path, "p")
	system({ "git", "init", "--initial-branch=main" }, path)
	system({ "git", "config", "user.name", "Neovim VCS Test" }, path)
	system({ "git", "config", "user.email", "nvim-vcs@example.invalid" }, path)
	vim.fn.writefile({ "first" }, vim.fs.joinpath(path, filename))
	system({ "git", "add", "--", filename }, path)
	system({ "git", "commit", "-m", "initial" }, path)
end

local test_root = vim.fn.tempname() .. " vcs ü"
local special_name = "file with spaces ü [*] #% 😃.txt"
vim.fn.mkdir(test_root, "p")
test_root = vim.uv.fs_realpath(test_root) or test_root
local repo_a = vim.fs.joinpath(test_root, "repo A")
local repo_b = vim.fs.joinpath(test_root, "repo B [special]")

local original_system = vim.system
local ok, error_message = xpcall(function()
	init_repo(repo_a, "a.txt")
	init_repo(repo_b, special_name)
	system({ "git", "switch", "-c", "feature" }, repo_b)
	vim.fn.writefile({ "first", "second   " }, vim.fs.joinpath(repo_b, special_name))
	system({ "git", "add", "--", special_name }, repo_b)
	system({ "git", "commit", "-m", "second" }, repo_b)
	vim.fn.writefile({ "first", "second   ", "working" }, vim.fs.joinpath(repo_b, special_name))
	-- A sibling that would match the brackets/asterisk if fnameescape were
	-- omitted from Diffview's later vim.fn.expand().
	vim.fn.writefile({ "collision" }, vim.fs.joinpath(repo_b, "file with spaces ü x #% 😃.txt"))

	local preferred = "jj"
	package.loaded["diffview.config"] = {
		get_config = function()
			return { preferred_adapter = preferred }
		end,
	}

	local captured = {}
	package.loaded["diffview"] = {
		open = function(args)
			captured.open = vim.deepcopy(args)
		end,
		file_history = function(range, args)
			captured.history = { range = range, args = vim.deepcopy(args) }
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

	-- Start in repository A, then edit a file in repository B. Every action
	-- must derive its command cwd/root from the active file, not process cwd.
	vim.cmd.cd(vim.fn.fnameescape(repo_a))
	local file = vim.fs.joinpath(repo_b, special_name)
	vim.cmd.edit(vim.fn.fnameescape(file))

	vim.system = function(command, opts)
		if command[1] == "jj" then
			error("ENOENT: jj intentionally absent")
		end
		return original_system(command, opts)
	end

	package.loaded["config.vcs"] = nil
	local vcs = require("config.vcs")
	local p4_filespec
	for index = 1, 64 do
		local name, value = debug.getupvalue(vcs.current_file, index)
		if not name then
			break
		end
		if name == "p4_filespec" then
			p4_filespec = value
			break
		end
	end
	assert(p4_filespec, "could not inspect P4 filespec encoding")
	local original_realpath = vim.uv.fs_realpath
	vim.uv.fs_realpath = function()
		error("UNC/depot classification attempted a filesystem probe")
	end
	local unc_filespec = p4_filespec("//server/share/client/source [*] #%.txt", {
		local_path = true,
		windows = true,
	})
	vim.uv.fs_realpath = original_realpath
	assert_equal(
		"\\\\server\\share\\client\\source [%2A] %23%25.txt",
		unc_filespec,
		"UNC local path was not emitted in native Windows syntax"
	)
	assert_equal(
		"//depot/source [*] #%.txt",
		p4_filespec("//depot/source [*] #%.txt"),
		"depot path was encoded as a local path"
	)
	vcs.info()
	assert_match("VCS: GIT", notifications[#notifications], "missing-jj fallback did not detect Git")
	assert_match("root: " .. repo_b, notifications[#notifications], "VCS actions selected the process cwd repository")

	vcs.current_file()
	assert_equal(3, #captured.open, "current-file diff produced the wrong argument count")
	assert_equal("-C=" .. vim.fn.fnameescape(repo_b), captured.open[1], "Diffview received the wrong root")
	assert_equal("--", captured.open[2], "Diffview path divider is missing")
	assert_equal(vim.fn.fnameescape(file), captured.open[3], "special path was not protected for expand()")
	assert_equal(file, vim.fn.expand(captured.open[3]), "special path did not round-trip through expand()")

	vcs.file_history()
	assert_equal(nil, captured.history.range, "file history unexpectedly received a line range")
	assert_equal(
		{ "-C=" .. vim.fn.fnameescape(repo_b), vim.fn.fnameescape(file) },
		captured.history.args,
		"file history changed the current file or root"
	)

	vcs.branch_diff()
	assert_equal(
		{ "-C=" .. vim.fn.fnameescape(repo_b), "main...HEAD" },
		captured.open,
		"branch diff did not use repository B's Git base"
	)

	local copy_wait_timeout = "not called"
	vim.system = function(command, opts)
		local process = original_system(command, opts)
		if command[1] ~= "git" or command[2] ~= "diff" then
			return process
		end
		return {
			wait = function(_, timeout)
				copy_wait_timeout = timeout
				if timeout == nil then
					return process:wait()
				end
				return process:wait(timeout)
			end,
		}
	end
	vcs.copy_diff()
	vim.system = original_system
	assert_equal(nil, copy_wait_timeout, "Git diff generation unexpectedly used the discovery timeout")
	local default_patch = system({ "git", "diff", "main...HEAD", "--" }, repo_b, false)
	assert_equal(default_patch, vim.fn.getreg('"'), "copied Git diff did not match the visible branch range")
	assert(default_patch:find("second   ", 1, true), "default branch patch lost trailing spaces")
	assert(not default_patch:find("working", 1, true), "default branch patch included a working-tree edit")

	-- A chosen two-ended range must be honored byte-for-byte by copy_diff;
	-- working-copy changes after HEAD must not leak into the copied patch.
	vim.ui.input = function(_, callback)
		callback("HEAD^..HEAD")
	end
	vcs.choose_base()
	assert_equal(
		{ "-C=" .. vim.fn.fnameescape(repo_b), "HEAD^..HEAD" },
		captured.open,
		"chosen range changed before reaching Diffview"
	)
	vcs.copy_diff()
	local expected_patch = system({ "git", "diff", "HEAD^..HEAD", "--" }, repo_b, false)
	assert_equal(expected_patch, vim.fn.getreg('"'), "copied Git range lost bytes or used the working tree")
	assert(expected_patch:find("second   ", 1, true), "fixture did not contain trailing spaces")
	assert(not vim.fn.getreg('"'):find("working", 1, true), "copied range included a later working-tree edit")

	-- Comparison bases must be isolated per backend in a colocated workspace.
	preferred = "jj"
	local jj_diff_command
	vim.system = function(command, opts)
		if command[1] == "jj" and command[2] == "root" then
			return {
				wait = function()
					return { code = 0, signal = 0, stdout = repo_b .. "\n", stderr = "" }
				end,
			}
		elseif command[1] == "jj" and command[2] == "diff" then
			jj_diff_command = vim.deepcopy(command)
			return {
				wait = function()
					return { code = 0, signal = 0, stdout = "jj patch\n", stderr = "" }
				end,
			}
		end
		return original_system(command, opts)
	end
	vim.ui.input = function(_, callback)
		callback("root()")
	end
	vcs.choose_base()
	assert_equal(
		{ "-C=" .. vim.fn.fnameescape(repo_b), "root()...@" },
		captured.open,
		"bare JJ comparison base did not become the visible three-dot branch range"
	)
	vcs.copy_diff()
	assert_equal({
		"jj",
		"diff",
		"--git",
		"--color=never",
		"--from",
		"latest(fork_point((root()) | (@)), 1)",
		"--to",
		"@",
	}, jj_diff_command, "copied JJ diff did not match the visible divergent branch range")
	vim.ui.input = function(_, callback)
		callback("root()...")
	end
	vcs.choose_base()
	vcs.copy_diff()
	assert_equal("@", jj_diff_command[#jj_diff_command], "JJ trailing open range did not default its right side to @")
	preferred = "git"
	notifications = {}
	vcs.info()
	assert_match("compare base: HEAD^..HEAD", notifications[#notifications], "Git comparison base was not retained")
	assert(not notifications[#notifications]:find("root()", 1, true), "JJ comparison base leaked into Git")

	-- An unborn repository has no valid HEAD. gD must show working changes,
	-- never construct the invalid HEAD...HEAD range.
	local unborn = vim.fs.joinpath(test_root, "unborn repo")
	vim.fn.mkdir(unborn, "p")
	system({ "git", "init", "--initial-branch=main" }, unborn)
	local unborn_file = vim.fs.joinpath(unborn, "new file.txt")
	vim.fn.writefile({ "new" }, unborn_file)
	vim.cmd.edit(vim.fn.fnameescape(unborn_file))
	preferred = "git"
	vim.system = original_system
	notifications = {}
	vcs.branch_diff()
	assert_equal(
		{ "-C=" .. vim.fn.fnameescape(unborn) },
		captured.open,
		"unborn repository created an invalid revision range"
	)
	assert_match("No comparison base found", notifications[#notifications], "unborn repository lacked a useful notice")
	vcs.copy_diff()
	local unborn_patch = vim.fn.getreg('"')
	assert_match("new file mode", unborn_patch, "unborn Git copy omitted the untracked file metadata")
	assert_match("+new", unborn_patch, "unborn Git copy omitted the untracked file contents")

	-- A slow P4/G4 server must be tried once and bounded. Missing fallbacks
	-- should be ordinary failures rather than ENOENT exceptions.
	vim.cmd.enew()
	vim.cmd.cd("/")
	preferred = "p4"
	local p4_wait_timeout
	local p4_calls = 0
	vim.system = function(command)
		local executable = vim.fs.basename(command[1])
		if executable == "vcs-p4" or executable == "p4" or executable == "g4" then
			p4_calls = p4_calls + 1
			return {
				wait = function(_, timeout)
					p4_wait_timeout = timeout
					return { code = 124, signal = 9, stdout = "", stderr = "" }
				end,
			}
		end
		error("ENOENT: client intentionally absent")
	end
	notifications = {}
	vcs.info()
	assert_equal(1, p4_calls, "P4 detection repeated a remote info probe")
	assert_equal(5000, p4_wait_timeout, "P4 detection did not use its bounded timeout")
	assert_match("timed out after 5000 ms", notifications[#notifications], "P4 timeout was not surfaced")

	vim.system = original_system
end, debug.traceback)

vim.system = original_system
vim.fn.delete(test_root, "rf")

if not ok then
	fail(error_message)
end

print("nvim VCS module tests passed")
