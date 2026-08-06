-- Run with: nvim --headless -u NONE -i NONE -l tests/nvim_clangd_spec.lua
--
-- Exercises common/.config/nvim/lua/util/clangd.lua against a fake GN checkout
-- laid out like Chromium: nested .gn files under third_party/, several out/
-- directories with databases of different ages, and a bundled clangd binary.

local source = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(repo .. "/common/.config/nvim")

local clangd = require("util.clangd")

local passed, failed = 0, 0
local failures = {}

local function check(name, ok, detail)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    table.insert(failures, name .. (detail and ("\n    " .. detail) or ""))
    print("FAIL " .. name .. (detail and ("  -- " .. detail) or ""))
  end
end

local function eq(name, expected, actual)
  check(
    name,
    expected == actual,
    string.format("expected %s, got %s", vim.inspect(expected), vim.inspect(actual))
  )
end

local function contains(name, list, want)
  check(name, vim.tbl_contains(list, want), string.format("%s not in %s", want, vim.inspect(list)))
end

local function excludes(name, list, unwanted)
  check(name, not vim.tbl_contains(list, unwanted), string.format("%s unexpectedly in %s", unwanted, vim.inspect(list)))
end

local function write(path, text)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local fd = assert(io.open(path, "wb"))
  fd:write(text)
  fd:close()
end

local temp = vim.fs.normalize(vim.fn.tempname())
local src = temp .. "/chrome/src"

-- A GN root, plus a nested one the way third_party/dawn carries its own .gn.
write(src .. "/.gn", 'buildconfig = "//build/config/BUILDCONFIG.gn"\n')
write(src .. "/build/config/BUILDCONFIG.gn", "# fake\n")
write(src .. "/third_party/dawn/.gn", 'buildconfig = "//build/config/BUILDCONFIG.gn"\n')
write(src .. "/third_party/dawn/src/dawn/native/Device.cpp", "int main() { return 0; }\n")
write(src .. "/base/logging.cc", "int main() { return 0; }\n")

-- Two databases: the root one is an old symlink, out/Default is current.
write(src .. "/out/Default/compile_commands.json", "[]\n")
write(src .. "/out/Stale/compile_commands.json", "[]\n")
vim.uv.fs_symlink("out/Stale/compile_commands.json", src .. "/compile_commands.json")
local now = os.time()
vim.uv.fs_utime(src .. "/out/Stale/compile_commands.json", now - 86400 * 200, now - 86400 * 200)
vim.uv.fs_utime(src .. "/out/Default/compile_commands.json", now, now)

-- The clangd the checkout ships.
local bundled = src .. "/third_party/llvm-build/Release+Asserts/bin/clangd"
write(bundled, "#!/bin/sh\nexit 0\n")
vim.uv.fs_chmod(bundled, 493) -- 0755

--- gn_root -------------------------------------------------------------------

eq("root from a top-level source file", src, clangd.gn_root(src .. "/base/logging.cc"))
eq(
  "root from inside third_party skips the nested .gn",
  src,
  clangd.gn_root(src .. "/third_party/dawn/src/dawn/native/Device.cpp")
)
eq("root from a directory", src, clangd.gn_root(src .. "/base"))
eq("no root outside a checkout", nil, clangd.gn_root(temp .. "/elsewhere/main.cc"))
eq("no root for an empty path", nil, clangd.gn_root(""))

--- compile_commands_dir ------------------------------------------------------

eq("freshest database wins over a stale root symlink", src .. "/out/Default", clangd.compile_commands_dir(src))

-- With the stale link the newest, clangd should be pointed at the root, since
-- that is where it would open the file.
vim.uv.fs_utime(src .. "/out/Stale/compile_commands.json", now + 60, now + 60)
eq("root symlink wins when it is the freshest", src, clangd.compile_commands_dir(src))
vim.uv.fs_utime(src .. "/out/Stale/compile_commands.json", now - 86400 * 200, now - 86400 * 200)

local bare = temp .. "/bare"
vim.fn.mkdir(bare, "p")
eq("no database found", nil, clangd.compile_commands_dir(bare))

--- binary -------------------------------------------------------------------

eq("checkout's own clangd is preferred", bundled, clangd.binary(src))

--- cmd ----------------------------------------------------------------------

local gn_cmd = clangd.cmd(src)
eq("gn checkout runs the bundled binary", bundled, gn_cmd[1])
contains("gn checkout points at the fresh database", gn_cmd, "--compile-commands-dir=" .. src .. "/out/Default")
contains("gn checkout indexes in the background", gn_cmd, "--background-index")
contains("gn checkout does not invent includes", gn_cmd, "--header-insertion=never")
contains("gn checkout skips clang-tidy", gn_cmd, "--clang-tidy=false")
excludes("gn checkout does not enable clang-tidy", gn_cmd, "--clang-tidy")

local plain_cmd = clangd.cmd(nil)
contains("plain project enables clang-tidy", plain_cmd, "--clang-tidy")
contains("plain project inserts includes", plain_cmd, "--header-insertion=iwyu")
for _, flag in ipairs(plain_cmd) do
  check(
    "plain project has no --compile-commands-dir",
    not flag:match("^%-%-compile%-commands%-dir="),
    flag
  )
end

--- describe -----------------------------------------------------------------

vim.cmd.edit(src .. "/base/logging.cc")
local described = clangd.describe(0)
check("describe names the root", described:find(src, 1, true) ~= nil, described)
check(
  "describe names the database",
  described:find(src .. "/out/Default/compile_commands.json", 1, true) ~= nil,
  described
)

vim.fn.delete(src .. "/out", "rf")
vim.fn.delete(src .. "/compile_commands.json")
local without_db = clangd.describe(0)
check("describe flags a missing database", without_db:find("MISSING", 1, true) ~= nil, without_db)
check("describe says how to fix it", without_db:find("gn gen", 1, true) ~= nil, without_db)

vim.fn.delete(temp, "rf")

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  print("\nfailures:")
  for _, f in ipairs(failures) do
    print("  - " .. f)
  end
  vim.cmd("cq")
end
