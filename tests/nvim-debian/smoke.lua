local function fail(message)
	vim.api.nvim_err_writeln(message)
	vim.cmd("cquit 1")
end

local function normalize(path)
	return path and vim.fs.normalize(path) or nil
end

local function assert_equal(expected, actual, message)
	expected = normalize(expected)
	actual = normalize(actual)
	if expected ~= actual then
		fail(("%s (expected %s, got %s)"):format(message, tostring(expected), tostring(actual)))
	end
end

if vim.v.errmsg ~= "" then
	fail("startup left v:errmsg set: " .. vim.v.errmsg)
end

local ok_lazy, lazy = pcall(require, "lazy")
if not ok_lazy then
	fail("lazy.nvim did not load: " .. tostring(lazy))
end

local ok_config, config = pcall(require, "lazy.core.config")
if not ok_config then
	fail("lazy.nvim config was unavailable: " .. tostring(config))
end

local plugin_count = 0
for _ in pairs(config.plugins) do
	plugin_count = plugin_count + 1
end

if plugin_count == 0 then
	fail("lazy.nvim resolved no enabled plugins")
end

lazy.load({ plugins = { "LazyVim", "snacks.nvim", "telescope.nvim" }, wait = true })
for _, name in ipairs({ "LazyVim", "snacks.nvim", "telescope.nvim" }) do
	local plugin = config.plugins[name]
	if not plugin then
		fail("expected smoke plugin was not in the resolved spec: " .. name)
	end
	if not (vim.uv or vim.loop).fs_stat(plugin.dir) then
		fail(("expected smoke plugin was missing from disk: %s (%s)"):format(name, plugin.dir))
	end
	if not plugin._.loaded then
		fail("expected smoke plugin did not load: " .. name)
	end
end

local mode = vim.env.NVIM_DEBIAN_SMOKE_MODE or "startup"

if mode == "full" then
	local full_plugins = {
		"codecompanion.nvim",
		"diffview-plus.nvim",
		"neotest",
		"nvim-dap",
		"overseer.nvim",
	}
	lazy.load({ plugins = full_plugins, wait = true })
	for _, name in ipairs(full_plugins) do
		local plugin = config.plugins[name]
		if not plugin or not plugin._.loaded then
			fail("full-config smoke did not load plugin: " .. name)
		end
	end
elseif mode == "vcs" then
	local target = vim.env.NVIM_DEBIAN_TARGET
	local expected_adapter = vim.env.NVIM_VCS
	if not target or target == "" then
		fail("NVIM_DEBIAN_TARGET is required for the VCS smoke")
	end

	vim.cmd.edit(vim.fn.fnameescape(target))
	require("config.vcs").changes()
	local view
	local ready = vim.wait(20000, function()
		view = require("diffview.lib").get_current_view()
		return view and view.files and view.files:len() > 0
	end, 50)
	if not ready then
		fail("timed out waiting for the " .. tostring(expected_adapter) .. " Diffview")
	end
	if view.adapter.config_key ~= expected_adapter then
		fail(
			("Diffview selected %s instead of %s"):format(tostring(view.adapter.config_key), tostring(expected_adapter))
		)
	end
	if require("diffview").close(nil, { force = true }) == false then
		fail("could not close the VCS Diffview")
	end
elseif mode == "assert-view" then
	local view = require("diffview.lib").get_current_view()
	if not view then
		fail("external diff wrapper did not create a Diffview")
	end

	if vim.env.NVIM_MERGE_OUTPUT and vim.env.NVIM_MERGE_OUTPUT ~= "" then
		assert_equal(vim.env.NVIM_MERGE_OUTPUT, view.output_path, "merge output path changed")
		assert_equal(vim.env.NVIM_MERGE_BASE, view.base_path, "merge base path changed")
		assert_equal(vim.env.NVIM_MERGE_LEFT, view.left_path, "merge left path changed")
		assert_equal(vim.env.NVIM_MERGE_RIGHT, view.right_path, "merge right path changed")
	else
		assert_equal(vim.env.NVIM_DIFF_LEFT, view.left_path, "diff left path changed")
		assert_equal(vim.env.NVIM_DIFF_RIGHT, view.right_path, "diff right path changed")
		if vim.env.NVIM_DIFF_OUTPUT and vim.env.NVIM_DIFF_OUTPUT ~= "" then
			assert_equal(vim.env.NVIM_DIFF_OUTPUT, view.output_path, "diff output path changed")
		end
	end

	if require("diffview").close(nil, { force = true }) == false then
		fail("could not close the external-tool Diffview")
	end
elseif mode ~= "startup" then
	fail("unknown NVIM_DEBIAN_SMOKE_MODE: " .. mode)
end

print(("Neovim %s smoke passed (%d enabled plugins)"):format(mode, plugin_count))
