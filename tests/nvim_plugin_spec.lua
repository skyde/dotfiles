-- Run with the installed full config:
-- nvim --headless -i NONE -c 'luafile tests/nvim_plugin_spec.lua' +qa

local function fail(message)
	error(message, 0)
end

local function assert_equal(expected, actual, message)
	if not vim.deep_equal(expected, actual) then
		fail(("%s\nexpected: %s\nactual:   %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
	end
end

local spec_source = debug.getinfo(1, "S").source
assert(spec_source:sub(1, 1) == "@", "unable to locate the Neovim plugin spec")
local spec_path = vim.fn.fnamemodify(spec_source:sub(2), ":p")
local repo_root = vim.fs.dirname(vim.fs.dirname(spec_path))

local lazy_config = require("lazy.core.config")
for _, name in ipairs({ "nvim-dap", "neotest", "rustaceanvim", "overseer.nvim" }) do
	local plugin = assert(lazy_config.plugins[name], "missing plugin spec: " .. name)
	assert(plugin._.loaded == nil, name .. " eagerly loaded during ordinary startup")
end
assert(package.loaded.dap == nil, "DAP Lua module eagerly loaded during ordinary startup")
assert(package.loaded.neotest == nil, "Neotest Lua module eagerly loaded during ordinary startup")
assert(package.loaded.rustaceanvim == nil, "Rustaceanvim eagerly loaded during ordinary startup")

local mason_tools = LazyVim.opts("mason.nvim").ensure_installed or {}
local seen = {}
for _, tool in ipairs(mason_tools) do
	assert(not seen[tool], "duplicate Mason install request: " .. tool)
	seen[tool] = true
end

-- The Debian harness intentionally clears Mason's merged installation list.
-- Exercise the checked-in source spec directly to keep ownership verifiable.
local language_specs =
	dofile(vim.fs.joinpath(repo_root, "common", ".config", "nvim", "lua", "plugins", "languages.lua"))
local source_mason_opts = { ensure_installed = {} }
for _, plugin in ipairs(language_specs) do
	if plugin[1] == "mason-org/mason.nvim" then
		plugin.opts(nil, source_mason_opts)
		break
	end
end
assert(
	vim.tbl_contains(source_mason_opts.ensure_installed, "debugpy"),
	"global Mason does not own the debugpy installation"
)

local cpp_test_file = require("config.testing").cpp_test_file
for _, path in ipairs({
	"foo_test.cpp",
	"test_widget.cxx",
	"foo_unittest.cc",
	"foo_browsertest.cc",
}) do
	assert(cpp_test_file(path), "expected C++ test file was rejected: " .. path)
end
for _, path in ipairs({ "contest.cpp", "latest.cc", "foo_test.c", "testimony.cxx" }) do
	assert(not cpp_test_file(path), "ordinary C++ file was classified as a test: " .. path)
end

-- Instrument the one supported setup path. Requiring the dependency first is
-- safe because its plugin spec has a deliberate no-op config.
local mason_dap = require("mason-nvim-dap")
local original_setup = mason_dap.setup
local setup_calls = 0
local setup_opts
mason_dap.setup = function(opts)
	setup_calls = setup_calls + 1
	setup_opts = vim.deepcopy(opts)
end
require("lazy").load({ plugins = { "nvim-dap" } })
mason_dap.setup = original_setup
assert_equal(1, setup_calls, "mason-nvim-dap was not configured exactly once")
assert_equal({}, setup_opts.ensure_installed, "mason-nvim-dap unexpectedly owns adapter installation")
assert_equal(false, setup_opts.automatic_installation, "mason-nvim-dap automatic installation was enabled")

local dap = require("dap")
assert(type(dap.adapters) == "table", "DAP did not initialize its adapters")
local windows_adapter, windows_liblldb = require("config.dap").codelldb_paths("C:/mason/codelldb", "Windows_NT")
assert_equal("C:/mason/codelldb/extension/adapter/codelldb.exe", windows_adapter, "Windows CodeLLDB adapter path")
assert_equal("C:/mason/codelldb/extension/lldb/bin/liblldb.dll", windows_liblldb, "Windows liblldb fallback path")

-- VS Code launch files are JSONC, not strict JSON. Verify comments, trailing
-- commas, adapter aliases, and ${command:pickProcess} normalization together.
local test_root = vim.fn.tempname() .. " launch jsonc"
vim.fn.mkdir(test_root, "p")
test_root = vim.uv.fs_realpath(test_root) or test_root
local vscode_dir = vim.fs.joinpath(test_root, ".vscode")
vim.fn.mkdir(vscode_dir, "p")
local launch = vim.fs.joinpath(vscode_dir, "launch.json")
local settings = vim.fs.joinpath(vscode_dir, "settings.json")
local tasks = vim.fs.joinpath(vscode_dir, "tasks.json")
local source = vim.fs.joinpath(test_root, "main.cpp")
vim.fn.writefile({ "int main() { return 0; }" }, source)
vim.fn.writefile({
	"{",
	"  // Workspace settings may themselves contain VS Code variables.",
	'  "chromium.buildDir": "out/Test",',
	'  "chromium.runtimeExecutable": "chrome",',
	'  "chromium.userDataDir": "${workspaceFolder}/.vscode/test-data",',
	"}",
}, settings)
vim.fn.writefile({
	"{",
	"  // inline comments are valid in VS Code files",
	'  "version": "0.2.0",',
	'  "configurations": [',
	"    {",
	'      "name": "JSONC attach fixture",',
	'      "type": "codelldb",',
	'      "request": "attach",',
	'      "processId": "${command:pickProcess}",',
	"    },",
	"    {",
	'      "name": "Node attach fixture",',
	'      "type": "pwa-node",',
	'      "request": "attach",',
	'      "processId": "${command:pickProcess}",',
	'      "cwd": "${workspaceFolder}",',
	'      "program": "${workspaceFolder}/server.js",',
	'      "relative": "${relativeFile}",',
	"    },",
	"    {",
	'      "name": "Config variable fixture",',
	'      "type": "codelldb",',
	'      "request": "launch",',
	'      "program": "${workspaceFolder}/${config:chromium.buildDir}/${config:chromium.runtimeExecutable}",',
	'      "cwd": "${workspaceFolder}/${config:chromium.buildDir}",',
	'      "args": ["--user-data-dir=${config:chromium.userDataDir}"],',
	"    },",
	"  ],",
	"}",
}, launch)
vim.fn.writefile({
	"{",
	'  "version": "2.0.0",',
	'  "tasks": [',
	"    {",
	'      "label": "Config task fixture",',
	'      "type": "shell",',
	'      "command": "${workspaceFolder}/${config:chromium.buildDir}/${config:chromium.runtimeExecutable}",',
	'      "args": ["--user-data-dir=${config:chromium.userDataDir}"],',
	'      "options": { "cwd": "${workspaceFolder}/${config:chromium.buildDir}" },',
	"    },",
	"  ],",
	"}",
}, tasks)
local original_cwd = vim.fn.getcwd()
local unrelated_cwd = vim.fn.tempname() .. " unrelated cwd"
vim.fn.mkdir(unrelated_cwd, "p")
vim.cmd.cd(vim.fn.fnameescape(unrelated_cwd))
local original_buffer = vim.api.nvim_get_current_buf()
local source_buffer = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(source_buffer, source)
vim.bo[source_buffer].filetype = "cpp"
vim.api.nvim_set_current_buf(source_buffer)
local original_cpp_configurations = dap.configurations.cpp
dap.configurations.cpp = {
	{
		name = "JSONC attach fixture",
		type = "codelldb",
		request = "attach",
		source = "built-in duplicate",
	},
	{
		name = "Built-in launch fixture",
		type = "codelldb",
		request = "launch",
	},
}

local provider_configurations = dap.providers.configs["dap.global"](source_buffer)
assert_equal({}, dap.providers.configs["dap.launch.json"](source_buffer), "launch provider was not merged")
local provider_duplicates = 0
for _, configuration in ipairs(provider_configurations) do
	if configuration.name == "JSONC attach fixture" and configuration.type == "codelldb" then
		provider_duplicates = provider_duplicates + 1
		assert(configuration.source ~= "built-in duplicate", "launch.json did not override the built-in configuration")
	end
end
assert_equal(1, provider_duplicates, "ordinary dap.continue providers still contain a duplicate launch entry")
assert(require("config.dap").load_launch(), "JSONC launch file failed to load from the active buffer's workspace")

local found
for _, configuration in ipairs(require("config.dap").configurations()) do
	if configuration.name == "JSONC attach fixture" then
		found = configuration
		break
	end
end
assert(found, "JSONC launch configuration was not registered")
assert_equal("${command:pickProcess}", found.pid, "CodeLLDB pickProcess was not moved to pid")
assert(found.processId == nil, "legacy processId remained after normalization")

local node_found
for _, configuration in ipairs(require("config.dap").configurations()) do
	if configuration.name == "Node attach fixture" then
		node_found = configuration
		break
	end
end
assert(node_found and node_found.processId == "${command:pickProcess}", "non-CodeLLDB processId was renamed")
assert(node_found.pid == nil, "non-CodeLLDB attach unexpectedly gained a pid field")
assert_equal(test_root, node_found.cwd, "workspaceFolder expanded from process cwd instead of buffer root")
assert_equal(
	vim.fs.joinpath(test_root, "server.js"),
	node_found.program,
	"workspaceFolder program path used the wrong root"
)
assert_equal("main.cpp", node_found.relative, "relativeFile expanded against process cwd")

local config_found
for _, configuration in ipairs(require("config.dap").configurations()) do
	if configuration.name == "Config variable fixture" then
		config_found = configuration
		break
	end
end
assert(config_found, "launch configuration using ${config:*} was not registered")
assert_equal(
	vim.fs.joinpath(test_root, "out", "Test", "chrome"),
	config_found.program,
	"DAP did not expand workspace settings in program"
)
assert_equal(
	vim.fs.joinpath(test_root, "out", "Test"),
	config_found.cwd,
	"DAP did not expand workspace settings in cwd"
)
assert_equal(
	"--user-data-dir=" .. vim.fs.joinpath(test_root, ".vscode", "test-data"),
	config_found.args[1],
	"DAP did not recursively expand workspace settings"
)

local dotfiles_vscode = require("config.vscode")
dotfiles_vscode.setup_overseer()
local task_variables = require("overseer.vscode.variables").precalculate_vars()
assert_equal(test_root, task_variables.workspaceFolder, "Overseer task root ignored the active buffer")
local task_content = require("overseer.vscode.vs_util").load_tasks_file(tasks)
local task_template = assert(require("overseer.vscode").convert_vscode_task(task_content.tasks[1], task_variables))
local task_definition = task_template.builder({})
assert_equal(
	vim.fs.joinpath(test_root, "out", "Test"),
	task_definition.cwd,
	"Overseer did not expand workspace settings in task cwd"
)
assert(not task_definition.cmd:find("${config:", 1, true), "Overseer left a literal config variable in task command")
assert(
	task_definition.cmd:find(vim.fs.joinpath(test_root, "out", "Test", "chrome"), 1, true),
	"Overseer task command used the wrong workspace setting"
)
assert(
	task_definition.cmd:find(vim.fs.joinpath(test_root, ".vscode", "test-data"), 1, true),
	"Overseer task argument did not recursively expand a workspace setting"
)
local _, missing_setting_error = dotfiles_vscode.expand_config("${config:missing.setting}", {})
assert(missing_setting_error:find("missing.setting", 1, true), "missing VS Code setting did not fail explicitly")

local breakpoints = require("dap.breakpoints")
breakpoints.clear()
breakpoints.set({ condition = "keep-me" }, source_buffer, 1)
local function source_breakpoints()
	return breakpoints.get(source_buffer)[source_buffer] or {}
end
local original_continue = dap.continue
local continue_options
dap.continue = function(options)
	continue_options = options
end
local break_here_handler =
	assert(lazy_config.plugins["overseer.nvim"]._.handlers.keys[" mp"], "missing fresh break-at-cursor handler")
break_here_handler.rhs()
assert(continue_options and type(continue_options.before) == "function", "break-at-cursor bypassed the DAP picker")
assert(
	dap.listeners.after.event_stopped.dotfiles_break_here_once == nil,
	"canceling the break-at-cursor picker left a listener armed"
)
assert_equal("keep-me", source_breakpoints()[1].condition, "picker setup changed breakpoints before selection")

local prepared = continue_options.before({
	name = "Break-at-cursor fixture",
	type = "codelldb",
	request = "launch",
})
assert(continue_options.before == nil, "break-at-cursor leaked its temporary hook into DAP Run Last")
local temporary = source_breakpoints()
assert_equal(1, #temporary, "fresh break-at-cursor did not isolate one temporary breakpoint")
assert_equal(nil, temporary[1].condition, "fresh break-at-cursor retained the user's condition temporarily")
local synced_breakpoints
local fake_session = {
	closed = false,
	config = prepared,
	set_breakpoints = function(_, entries)
		synced_breakpoints = entries
	end,
}
dap.listeners.on_session.dotfiles_break_here_once(nil, fake_session)
dap.listeners.after.event_stopped.dotfiles_break_here_once(fake_session)
assert_equal("keep-me", source_breakpoints()[1].condition, "fresh break-at-cursor lost user breakpoints")
assert_equal(
	"keep-me",
	synced_breakpoints[source_buffer][1].condition,
	"restored breakpoints were not synchronized to the debug session"
)
assert(
	dap.listeners.on_session.dotfiles_break_here_once == nil
		and dap.listeners.after.event_stopped.dotfiles_break_here_once == nil,
	"fresh break-at-cursor listeners were not one-shot"
)

break_here_handler.rhs()
continue_options.before({
	name = "Failed break-at-cursor fixture",
	type = "missing-adapter",
	request = "launch",
})
local unrelated_session = {
	closed = false,
	config = { name = "Unrelated debug session" },
	set_breakpoints = function() end,
}
dap.listeners.on_session.dotfiles_break_here_once(nil, unrelated_session)
assert_equal(
	"keep-me",
	source_breakpoints()[1].condition,
	"a failed break-at-cursor launch leaked temporary breakpoints into an unrelated session"
)
assert(
	dap.listeners.on_session.dotfiles_break_here_once == nil,
	"a failed break-at-cursor launch left its session listener armed"
)
dap.continue = original_continue
breakpoints.clear()
dap.configurations.cpp = original_cpp_configurations
vim.api.nvim_set_current_buf(original_buffer)
vim.api.nvim_buf_delete(source_buffer, { force = true })
vim.cmd.cd(vim.fn.fnameescape(original_cwd))
vim.fn.delete(unrelated_cwd, "rf")
vim.fn.delete(test_root, "rf")

-- Keep the checked-in Chromium workspace honest. It relies heavily on
-- ${config:*}, including nested ${workspaceFolder} values and platform
-- overrides, so a synthetic fixture alone is not enough.
local chrome_root = vim.fs.joinpath(repo_root, "helpers", "chrome")
assert(
	vim.uv.fs_stat(vim.fs.joinpath(chrome_root, ".vscode", "launch.json")),
	"checked-in Chromium launch fixture is missing"
)
local chrome_source = vim.fs.joinpath(chrome_root, "trim_compile_commands.py")
local chrome_buffer = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(chrome_buffer, chrome_source)
vim.bo[chrome_buffer].filetype = "python"
vim.api.nvim_set_current_buf(chrome_buffer)

local chrome_launch
for _, configuration in ipairs(require("config.dap").configurations(chrome_root)) do
	if configuration.name == "Chromium: LLDB (CodeLLDB)" then
		chrome_launch = configuration
		break
	end
end
assert(chrome_launch, "checked-in Chromium launch configuration was not registered")
local runtime = vim.uv.os_uname().sysname == "Darwin" and "Chromium.app/Contents/MacOS/Chromium" or "chrome"
assert_equal(
	vim.fs.joinpath(chrome_root, "out", "Default", runtime),
	chrome_launch.program,
	"checked-in Chromium runtime did not resolve platform/config variables"
)
assert_equal(
	vim.fs.joinpath(chrome_root, "out", "Default"),
	chrome_launch.cwd,
	"checked-in Chromium launch cwd did not resolve config variables"
)
assert(
	not vim.inspect(chrome_launch):find("${config:", 1, true),
	"checked-in Chromium launch left a literal config variable"
)

local chrome_task_path = vim.fs.joinpath(chrome_root, ".vscode", "tasks.json")
local chrome_task_vars = require("overseer.vscode.variables").precalculate_vars()
assert_equal(chrome_root, chrome_task_vars.workspaceFolder, "checked-in Chromium task root ignored its active buffer")
local chrome_task_content = require("overseer.vscode.vs_util").load_tasks_file(chrome_task_path)
for _, task in ipairs(chrome_task_content.tasks) do
	local template = assert(require("overseer.vscode").convert_vscode_task(task, chrome_task_vars))
	local definition = template.builder({})
	assert(
		not vim.inspect(definition):find("${config:", 1, true),
		("checked-in Chromium task left a literal config variable: %s"):format(task.label)
	)
end

vim.api.nvim_set_current_buf(original_buffer)
vim.api.nvim_buf_delete(chrome_buffer, { force = true })

local rust_opts = LazyVim.opts("rustaceanvim")
assert(type(rust_opts.dap.adapter) == "function", "Rust DAP adapter was frozen during startup")
local codelldb = vim.fn.exepath("codelldb")
local rust_adapter = rust_opts.dap.adapter()
if codelldb == "" then
	assert_equal(false, rust_adapter, "Rust DAP should be disabled until codelldb is installed")
else
	assert_equal(codelldb, rust_adapter.executable.command, "Rust DAP did not resolve codelldb dynamically")
end

if vim.fn.executable("gemini") ~= 1 then
	local notifications = {}
	local original_notify = vim.notify
	vim.notify = function(message)
		table.insert(notifications, tostring(message))
	end
	local ai_handler =
		assert(lazy_config.plugins["codecompanion.nvim"]._.handlers.keys[" aA"], "missing Gemini CLI key handler")
	ai_handler.rhs()
	vim.notify = original_notify
	assert_equal(
		"Gemini CLI is not installed; use <leader>ac for API-key chat",
		notifications[#notifications],
		"missing Gemini CLI did not fail gracefully"
	)
end

local original_gemini_key = vim.env.GEMINI_API_KEY
vim.env.GEMINI_API_KEY = "nvim-test-placeholder"
require("lazy").load({ plugins = { "codecompanion.nvim" } })
local codecompanion = require("codecompanion.config")
assert_equal("gemini", codecompanion.interactions.chat.adapter.name, "Gemini is not the chat adapter")
assert_equal(
	"gemini-3.1-pro-preview",
	codecompanion.interactions.chat.adapter.model,
	"Gemini chat model changed unexpectedly"
)
assert_equal(
	"gemini-3.1-pro-preview",
	codecompanion.interactions.inline.adapter.model,
	"Gemini inline model changed unexpectedly"
)
assert_equal(
	"gemini-3.6-flash",
	codecompanion.interactions.cmd.adapter.model,
	"Gemini command model changed unexpectedly"
)
assert_equal(
	"gemini-3.6-flash",
	codecompanion.interactions.background.adapter.model,
	"Gemini background model changed unexpectedly"
)
local gemini = require("codecompanion.adapters").resolve(codecompanion.interactions.chat.adapter)
assert_equal("http", gemini.type, "Gemini did not resolve as an HTTP adapter")
assert_equal("GEMINI_API_KEY", gemini.env.api_key, "Gemini adapter stopped reading GEMINI_API_KEY")
local gemini_flash = require("codecompanion.adapters").resolve(codecompanion.interactions.cmd.adapter)
assert_equal("gemini-3.6-flash", gemini_flash.schema.model.default, "Gemini Flash model did not resolve")
assert(
	gemini_flash.schema.model.choices["gemini-3.6-flash"].opts.can_reason,
	"Gemini 3.6 capability metadata was not registered"
)
assert(vim.fn.exists(":CodeCompanionChat") == 2, "CodeCompanion chat command was not registered")
vim.env.GEMINI_API_KEY = original_gemini_key

print("nvim pinned plugin integration tests passed")
