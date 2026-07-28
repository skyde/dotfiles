-- Run after plugins are installed:
-- nvim --headless -u NONE -i NONE -l tests/nvim_diff_tool_spec.lua

local script = debug.getinfo(1, "S").source:sub(2)
local repo_root = vim.fn.fnamemodify(script, ":p:h:h")
local lazy_root = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy")
local diffview_root = vim.fs.joinpath(lazy_root, "diffview-plus.nvim")
local plenary_root = vim.fs.joinpath(lazy_root, "plenary.nvim")

for _, path in ipairs({ plenary_root, diffview_root }) do
	assert(vim.uv.fs_stat(path), "required pinned plugin is missing: " .. path)
	vim.opt.runtimepath:prepend(path)
end

local config_root = vim.fs.joinpath(repo_root, "common", ".config", "nvim", "lua")
package.path = table.concat({
	vim.fs.joinpath(config_root, "?.lua"),
	vim.fs.joinpath(config_root, "?", "init.lua"),
	package.path,
}, ";")

local diffview = require("diffview")
diffview.setup({})

local test_root = vim.fn.tempname() .. " diff tool ü [*] #%"
vim.fn.mkdir(test_root, "p")
test_root = vim.uv.fs_realpath(test_root) or test_root

local function assert_equal(expected, actual, message)
	if expected ~= actual then
		error(("%s\nexpected: %s\nactual:   %s"):format(message, expected, tostring(actual)), 0)
	end
end

local function view()
	return assert(require("diffview.lib").get_current_view(), "Diffview did not create a view")
end

local function close()
	assert(diffview.close(nil, { force = true }) ~= false, "Diffview refused to close")
end

local ok, err = xpcall(function()
	local left_file = vim.fs.joinpath(test_root, "left ü [*] #%.txt")
	local right_file = vim.fs.joinpath(test_root, "right ü [*] #%.txt")
	vim.fn.writefile({ "left" }, left_file)
	vim.fn.writefile({ "right" }, right_file)
	vim.fn.writefile({ "collision" }, vim.fs.joinpath(test_root, "left ü x #%.txt"))

	require("config.diff_tool").open("files", { left_file, right_file })
	local file_view = view()
	assert_equal(left_file, file_view.left_path, "file diff changed the left special path")
	assert_equal(right_file, file_view.right_path, "file diff changed the right special path")
	close()

	local left_dir = vim.fs.joinpath(test_root, "left dir [*]")
	local right_dir = vim.fs.joinpath(test_root, "right dir [*]")
	local output_dir = vim.fs.joinpath(test_root, "output dir [*]")
	vim.fn.mkdir(left_dir, "p")
	vim.fn.mkdir(right_dir, "p")
	vim.fn.mkdir(output_dir, "p")
	vim.fn.writefile({ "left" }, vim.fs.joinpath(left_dir, "nested ü.txt"))
	vim.fn.writefile({ "right" }, vim.fs.joinpath(right_dir, "nested ü.txt"))
	vim.fn.writefile({ "right" }, vim.fs.joinpath(output_dir, "nested ü.txt"))

	require("config.diff_tool").open("dirs", { left_dir, right_dir, output_dir })
	local dir_view = view()
	assert_equal(left_dir, dir_view.left_path, "directory diff changed the left special path")
	assert_equal(right_dir, dir_view.right_path, "directory diff changed the right special path")
	assert_equal(output_dir, dir_view.output_path, "directory diff changed the output special path")
	close()

	local output = vim.fs.joinpath(test_root, "merge output ü [*] #%.txt")
	local base = vim.fs.joinpath(test_root, "merge base ü [*] #%.txt")
	local ours = vim.fs.joinpath(test_root, "merge ours ü [*] #%.txt")
	local theirs = vim.fs.joinpath(test_root, "merge theirs ü [*] #%.txt")
	vim.fn.writefile({ "output" }, output)
	vim.fn.writefile({ "base" }, base)
	vim.fn.writefile({ "ours" }, ours)
	vim.fn.writefile({ "theirs" }, theirs)

	require("config.diff_tool").open("merge", { output, base, ours, theirs })
	local merge_view = view()
	assert_equal(output, merge_view.output_path, "merge changed the output special path")
	assert_equal(base, merge_view.base_path, "merge changed the base special path")
	assert_equal(ours, merge_view.left_path, "merge changed the left special path")
	assert_equal(theirs, merge_view.right_path, "merge changed the right special path")
	close()
end, debug.traceback)

vim.fn.delete(test_root, "rf")
if not ok then
	error(err, 0)
end

print("nvim direct diff-tool tests passed")
