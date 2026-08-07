-- Run with: nvim --headless -u NONE -i NONE -l tests/nvim_chromium_spec.lua
--
-- Exercises common/.config/nvim/lua/util/chromium.lua against a fake
-- Chromium checkout: src-root detection, clangd selection, build-dir
-- resolution (current_link convention and newest-build fallback), compdb
-- staleness, the async generate flow (with a stub generate_compdb.py), the
-- GN debounce, and the out-dir picker. Plugin-free, like the other specs.

local source = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(repo .. "/common/.config/nvim")

local chromium = require("util.chromium")

local passed, failed = 0, 0
local failures = {}

local function check(name, ok, detail)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    table.insert(failures, name)
    print("FAIL " .. name .. (detail and ("  -- " .. detail) or ""))
  end
end

local function eq(name, expected, actual)
  check(
    name,
    vim.deep_equal(expected, actual),
    string.format("expected %s, got %s", vim.inspect(expected), vim.inspect(actual))
  )
end

local function write(path, text)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local fd = assert(io.open(path, "wb"))
  fd:write(text)
  fd:close()
end

local function settle(timeout)
  vim.wait(timeout or 5000, function()
    return not chromium.busy()
  end)
end

--------------------------------------------------------------------------
-- fixture: a fake checkout whose generate_compdb.py records its arguments
--------------------------------------------------------------------------

local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")
temp = vim.fn.resolve(temp)
local root = temp .. "/chromium/src"
local script = root .. "/tools/clang/scripts/generate_compdb.py"
-- The stub is invoked the way the real one is (python3, cwd = src root);
-- it records its arguments and writes an empty database where told to.
write(
  script,
  table.concat({
    "import sys",
    'open("generate.log", "a").write(" ".join(sys.argv[1:]) + "\\n")',
    'open(sys.argv[4], "w").write("[]")',
  }, "\n") .. "\n"
)
write(root .. "/out/Default/build.ninja", "ninja\n")
write(root .. "/base/logging.cc", "// c++\n")

local function generate_log()
  local ok, lines = pcall(vim.fn.readfile, root .. "/generate.log")
  return ok and lines or {}
end

--------------------------------------------------------------------------
-- checkout discovery
--------------------------------------------------------------------------

eq("root: found from a nested file", root, chromium.src_root(root .. "/base/logging.cc"))
eq("root: found from a nested directory", root, chromium.src_root(root .. "/base"))
eq("root: found from the root itself", root, chromium.src_root(root))
eq("root: nil outside a checkout", nil, chromium.src_root(temp))
eq("root: nil for unrelated paths", nil, chromium.src_root("/"))

--------------------------------------------------------------------------
-- clangd selection
--------------------------------------------------------------------------

eq("clangd: PATH fallback without the bundled binary", "clangd", chromium.clangd_path(root))
local bundled = root .. "/third_party/llvm-build/Release+Asserts/bin/clangd"
write(bundled, "#!/bin/sh\n")
assert(vim.uv.fs_chmod(bundled, 493))
eq("clangd: bundled binary when present", bundled, chromium.clangd_path(root))
eq("clangd: PATH fallback outside a checkout", "clangd", chromium.clangd_path(nil))

local cmd = chromium.clangd_cmd(root .. "/base/logging.cc")
eq("clangd: cmd uses the bundled binary", bundled, cmd[1])
check("clangd: cmd keeps header insertion off", vim.tbl_contains(cmd, "--header-insertion=never"))

--------------------------------------------------------------------------
-- build-dir resolution
--------------------------------------------------------------------------

eq("out: single generated dir wins", "out/Default", chromium.out_dir(root))

-- A second, newer build dir takes over…
write(root .. "/out/Debug/build.ninja", "ninja\n")
local now = os.time()
assert(vim.uv.fs_utime(root .. "/out/Default/build.ninja", now - 100, now - 100))
assert(vim.uv.fs_utime(root .. "/out/Debug/build.ninja", now, now))
eq("out: the newest build.ninja wins", "out/Debug", chromium.out_dir(root))

-- …unless current_link says otherwise.
check("out: linking the build dir succeeds", chromium.link_out_dir(root, "out/Default"))
eq("out: current_link wins over recency", "out/current_link", chromium.out_dir(root))
eq(
  "out: the link points at the chosen dir",
  vim.fn.resolve(root .. "/out/Default"),
  vim.fn.resolve(root .. "/out/current_link")
)
check("out: relinking replaces the link", chromium.link_out_dir(root, "out/Debug"))
eq(
  "out: the replaced link points at the new dir",
  vim.fn.resolve(root .. "/out/Debug"),
  vim.fn.resolve(root .. "/out/current_link")
)

--------------------------------------------------------------------------
-- staleness
--------------------------------------------------------------------------

check("stale: missing compdb is stale", chromium.stale(root))
write(root .. "/compile_commands.json", "[]")
assert(vim.uv.fs_utime(root .. "/compile_commands.json", now + 100, now + 100))
check("stale: fresh compdb is not stale", not chromium.stale(root))
assert(vim.uv.fs_utime(root .. "/compile_commands.json", now - 300, now - 300))
check("stale: compdb older than build.ninja is stale", chromium.stale(root))

--------------------------------------------------------------------------
-- generation
--------------------------------------------------------------------------

vim.fn.delete(root .. "/compile_commands.json")
chromium.generate({ root = root, silent = true })
settle()
eq("generate: one run", 1, #generate_log())
check(
  "generate: against current_link, into compile_commands.json",
  generate_log()[1] == "-p out/current_link -o compile_commands.json",
  vim.inspect(generate_log())
)
check("generate: the compdb exists afterwards", vim.uv.fs_stat(root .. "/compile_commands.json") ~= nil)

-- Fresh database, no force: nothing runs.
assert(vim.uv.fs_utime(root .. "/compile_commands.json", now + 100, now + 100))
chromium.generate({ root = root, silent = true })
settle()
eq("generate: fresh database is left alone", 1, #generate_log())

-- Force runs regardless.
chromium.generate({ root = root, force = true, silent = true })
settle()
eq("generate: force regenerates", 2, #generate_log())

-- Outside a checkout: a no-op, not an error.
chromium.generate({ root = nil, silent = true })
settle()
eq("generate: outside a checkout does nothing", 2, #generate_log())

--------------------------------------------------------------------------
-- GN debounce
--------------------------------------------------------------------------

chromium.gn_changed(root)
chromium.gn_changed(root)
chromium.gn_changed(root)
vim.wait(4000, function()
  return #generate_log() >= 3 and not chromium.busy()
end)
eq("gn: a burst of saves regenerates once", 3, #generate_log())

--------------------------------------------------------------------------
-- picker
--------------------------------------------------------------------------

local offered
vim.ui.select = function(items, _, cb) ---@diagnostic disable-line: duplicate-set-field
  offered = items
  cb(items[1])
end
vim.cmd("edit " .. vim.fn.fnameescape(root .. "/base/logging.cc"))
chromium.pick_out_dir()
settle()
eq("picker: offers the generated build dirs", { "out/Debug", "out/Default" }, offered)
eq(
  "picker: repoints current_link at the choice",
  vim.fn.resolve(root .. "/out/Debug"),
  vim.fn.resolve(root .. "/out/current_link")
)
eq("picker: regenerates against the choice", 4, #generate_log())

--------------------------------------------------------------------------
-- config module: catches up buffers opened before it loads
--------------------------------------------------------------------------

-- config/chromium.lua is pulled in on VeryLazy, after the FileType event
-- for buffers named on the command line (`nvim foo.cc`) has fired — its
-- autocmd alone would miss them. Loading the module must check them.
vim.fn.delete(root .. "/compile_commands.json")
vim.bo.filetype = "cpp" -- FileType fires here, before the autocmd exists
require("config.chromium")
settle()
eq("config: loading catches up already-open C++ buffers", 5, #generate_log())
check("config: the compdb exists afterwards", vim.uv.fs_stat(root .. "/compile_commands.json") ~= nil)

--------------------------------------------------------------------------

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  os.exit(1)
end
