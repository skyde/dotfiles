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
write(script, table.concat({
  "import sys",
  'open("generate.log", "a").write(" ".join(sys.argv[1:]) + "\\n")',
  'open(sys.argv[4], "w").write("[]")',
}, "\n") .. "\n")
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
check("clangd: cmd uncaps find-references", vim.tbl_contains(cmd, "--limit-references=0"))
check("clangd: cmd keeps the log quiet", vim.tbl_contains(cmd, "--log=error"))
check("clangd: cmd pins the database dir", vim.tbl_contains(cmd, "--compile-commands-dir=" .. root))
local outside_cmd = chromium.clangd_cmd(temp)
local pinned = false
for _, arg in ipairs(outside_cmd) do
  pinned = pinned or arg:find("--compile-commands-dir", 1, true) ~= nil
end
check("clangd: no database pin outside a checkout", not pinned)

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
-- the scanner behind the membership probe
--------------------------------------------------------------------------

local hay = temp .. "/haystack.txt"
write(hay, string.rep("x", 64) .. "NEEDLE_ABC" .. string.rep("y", 64))
local function scan(path, needle, opts)
  local got, done = nil, false
  chromium.file_contains(path, needle, function(f)
    got, done = f, true
  end, opts)
  vim.wait(2000, function()
    return done
  end)
  return got
end
eq("scan: present string found", true, scan(hay, "NEEDLE_ABC"))
eq("scan: found across chunk boundaries", true, scan(hay, "NEEDLE_ABC", { chunk = 7 }))
eq("scan: absent string is false", false, scan(hay, "NOT_THERE"))
eq("scan: unreadable file is nil", nil, scan(temp .. "/no-such-file", "x"))

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
-- bundled clangd: .gclient editing
--------------------------------------------------------------------------

-- A second checkout, without a bundled clangd, managed by a .gclient.
local root2 = temp .. "/chrome2/src"
write(root2 .. "/tools/clang/scripts/generate_compdb.py", "pass\n")
eq("gclient: nil without a .gclient", nil, chromium.gclient_path(root2))

local gclient_file = temp .. "/chrome2/.gclient"
local function gclient_text()
  return table.concat(vim.fn.readfile(gclient_file), "\n")
end
local STOCK_GCLIENT = table.concat({
  "solutions = [",
  "  {",
  '    "name": "src",',
  '    "url": "https://chromium.googlesource.com/chromium/src.git",',
  '    "custom_deps": {},',
  '    "custom_vars": {},',
  "  },",
  "]",
}, "\n") .. "\n"

write(gclient_file, STOCK_GCLIENT)
eq("gclient: found next to src", gclient_file, chromium.gclient_path(root2))

eq("gclient: empty custom_vars gains the var", "edited", (chromium.enable_checkout_clangd_var(root2)))
check("gclient: the var is written", gclient_text():find('"checkout_clangd": True', 1, true) ~= nil)
eq("gclient: enabling twice is a no-op", "already", (chromium.enable_checkout_clangd_var(root2)))

write(gclient_file, STOCK_GCLIENT:gsub('"custom_vars": {}', '"custom_vars": { "checkout_clangd": False }'))
eq("gclient: an explicit False is flipped", "edited", (chromium.enable_checkout_clangd_var(root2)))
check("gclient: flipped to True", gclient_text():find('"checkout_clangd": True', 1, true) ~= nil)

write(gclient_file, STOCK_GCLIENT:gsub('%s*"custom_vars": {},', ""))
eq("gclient: a solution without custom_vars gains one", "edited", (chromium.enable_checkout_clangd_var(root2)))
check("gclient: custom_vars added with the var", gclient_text():find('"checkout_clangd": True', 1, true) ~= nil)

write(gclient_file, "# nothing gclient-shaped here\n")
local state, err = chromium.enable_checkout_clangd_var(root2)
eq("gclient: an unrecognizable file is refused", nil, state)
check("gclient: the refusal says what to do", type(err) == "string" and err:find("by hand") ~= nil)

--------------------------------------------------------------------------
-- bundled clangd: the offer and the sync
--------------------------------------------------------------------------

-- A stub gclient on PATH: logs its argv and cwd, then drops the bundled
-- clangd where a real sync would.
local stub_bin = temp .. "/bin"
write(stub_bin .. "/gclient", table.concat({
  "#!/bin/sh",
  "pwd >> gclient.log",
  'echo "$@" >> gclient.log',
  "mkdir -p src/third_party/llvm-build/Release+Asserts/bin",
  "printf '#!/bin/sh\\n' > src/third_party/llvm-build/Release+Asserts/bin/clangd",
  "chmod +x src/third_party/llvm-build/Release+Asserts/bin/clangd",
}, "\n") .. "\n")
assert(vim.uv.fs_chmod(stub_bin .. "/gclient", 493))
vim.env.PATH = stub_bin .. ":" .. vim.env.PATH

write(gclient_file, STOCK_GCLIENT)
local prompts = 0
vim.ui.select = function(items, _, cb) ---@diagnostic disable-line: duplicate-set-field
  prompts = prompts + 1
  cb(items[1], 1) -- take the offer
end

chromium.offer_bundled_clangd(root2)
vim.wait(1000, function()
  return prompts > 0
end)
eq("offer: missing bundled clangd prompts", 1, prompts)
settle()
eq(
  "offer: accepting runs gclient sync at the gclient root",
  { temp .. "/chrome2", "sync" },
  vim.fn.readfile(temp .. "/chrome2/gclient.log")
)
check("offer: the var was written first", gclient_text():find('"checkout_clangd": True', 1, true) ~= nil)
eq(
  "offer: the bundled clangd is used afterwards",
  root2 .. "/third_party/llvm-build/Release+Asserts/bin/clangd",
  chromium.clangd_path(root2)
)

chromium.offer_bundled_clangd(root2)
vim.wait(100)
eq("offer: asked once per root per session", 1, prompts)

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
-- freshness after load: probed and re-stat'd, not checked once per session
--------------------------------------------------------------------------

-- The stub compdb ("[]") does not contain logging.cc: re-entering the
-- buffer notices via the membership probe and regenerates once.
local curbuf = vim.api.nvim_get_current_buf()
vim.api.nvim_exec_autocmds("BufEnter", { buffer = curbuf })
vim.wait(5000, function()
  return #generate_log() >= 6
end)
settle()
eq("probe: a file missing from the compdb regenerates once", 6, #generate_log())

-- Probed once per file per session: entering again does not loop.
vim.api.nvim_exec_autocmds("BufEnter", { buffer = curbuf })
vim.wait(300)
settle()
eq("probe: the same file is not probed twice", 6, #generate_log())

-- Files under out/ and outside the checkout are never probed.
chromium.compdb_probe(root, root .. "/out/Default/gen/foo.cc")
chromium.compdb_probe(root, temp .. "/elsewhere.cc")
vim.wait(300)
settle()
eq("probe: generated and foreign files are skipped", 6, #generate_log())

-- Headers are never compdb entries (`ninja -t compdb` lists translation
-- units only); probing one would regenerate on every header opened.
write(root .. "/base/logging.h", "// header\n")
chromium.compdb_probe(root, root .. "/base/logging.h")
chromium.compdb_probe(root, "")
vim.wait(300)
settle()
eq("probe: headers and nameless buffers are skipped", 6, #generate_log())

-- A build.ninja that moved regenerates on re-entry, mid-session — the old
-- behavior checked once per session and went quietly stale.
vim.wait(2100) -- clear the refresh throttle
local later = os.time() + 200
assert(vim.uv.fs_utime(root .. "/out/Debug/build.ninja", later, later))
vim.api.nvim_exec_autocmds("BufEnter", { buffer = curbuf })
vim.wait(5000, function()
  return #generate_log() >= 7
end)
settle()
eq("refresh: a stale compdb regenerates on re-entry", 7, #generate_log())

--------------------------------------------------------------------------
-- the plugin spec: one clangd per checkout
--------------------------------------------------------------------------

local plug = dofile(repo .. "/common/.config/nvim/lua/plugins/chromium-clangd.lua")
local popts = { servers = {} }
plug[1].opts(nil, popts)
local clangd_opts = popts.servers.clangd
check("plugin: cmd is a per-client function", type(clangd_opts.cmd) == "function")
eq("spawn: argv follows the client's root", chromium.clangd_cmd(root), chromium.spawn_cmd({ root_dir = root }))
eq("spawn: rootless argv is the stock one", chromium.clangd_cmd(nil), chromium.spawn_cmd({}))
local called, got_root = false, nil
clangd_opts.root_dir(vim.api.nvim_get_current_buf(), function(r)
  called, got_root = true, r
end)
check("plugin: root_dir answers inside a checkout", called)
eq("plugin: pinned to the checkout root", root, got_root)

vim.cmd("edit " .. vim.fn.fnameescape(temp .. "/outside.cc"))
called, got_root = false, nil
clangd_opts.root_dir(vim.api.nvim_get_current_buf(), function(r)
  called, got_root = true, r
end)
check("plugin: root_dir answers outside a checkout", called)
eq("plugin: no pin outside a checkout (stock markers apply)", nil, got_root)

-- LazyVim hands every server mason knows about to mason-lspconfig, which
-- calls vim.lsp.enable only once the package is installed. Since cmd picks
-- the binary itself, mason's clangd is downloaded and never run — and a
-- mason install that cannot happen leaves C++ with no language server at
-- all, next to a perfectly usable clangd. mason is for when there is none.
vim.cmd("edit " .. vim.fn.fnameescape(root .. "/base/logging.cc"))
popts = { servers = {} }
plug[1].opts(nil, popts)
eq("plugin: no mason when the checkout has a bundled clangd", false, popts.servers.clangd.mason)

local saved_path = vim.env.PATH
vim.env.PATH = temp .. "/nothing-here"
vim.cmd("edit " .. vim.fn.fnameescape(temp .. "/outside.cc"))
popts = { servers = {} }
plug[1].opts(nil, popts)
eq("plugin: mason installs one when there is no clangd anywhere", true, popts.servers.clangd.mason)

vim.env.PATH = saved_path
vim.fn.mkdir(temp .. "/path-clangd", "p")
write(temp .. "/path-clangd/clangd", "#!/bin/sh\n")
assert(vim.uv.fs_chmod(temp .. "/path-clangd/clangd", 493))
vim.env.PATH = temp .. "/path-clangd"
popts = { servers = {} }
plug[1].opts(nil, popts)
eq("plugin: no mason when PATH has a clangd", false, popts.servers.clangd.mason)
vim.env.PATH = saved_path

--------------------------------------------------------------------------
-- symlinked build dirs
--------------------------------------------------------------------------

-- `out/Default -> /ssd/chromium-out/Default` is how a 100 GB build is kept
-- off the checkout's disk. readdir calls that entry a "link", not a
-- "directory"; requiring the latter made the build dir invisible, so no
-- compile commands could ever be generated for such a checkout.
local root3 = temp .. "/chrome3/src"
write(root3 .. "/tools/clang/scripts/generate_compdb.py", "pass\n")
vim.fn.mkdir(root3 .. "/out", "p")
write(temp .. "/elsewhere-build/build.ninja", "ninja\n")
assert(vim.uv.fs_symlink(temp .. "/elsewhere-build", root3 .. "/out/Linked"))
eq("out: a symlinked build dir is found", "out/Linked", chromium.out_dir(root3))

local picked
vim.ui.select = function(items, _, cb) ---@diagnostic disable-line: duplicate-set-field
  picked = items
  cb(nil) -- cancel: this checkout has no generator stub to run
end
vim.cmd("edit " .. vim.fn.fnameescape(root3 .. "/a.cc"))
chromium.pick_out_dir()
eq("picker: offers a symlinked build dir", { "out/Linked" }, picked)

-- A dangling link is not a build dir.
assert(vim.uv.fs_symlink(temp .. "/no-such-build", root3 .. "/out/Dangling"))
eq("out: a dangling link is ignored", "out/Linked", chromium.out_dir(root3))

--------------------------------------------------------------------------
-- a generator that cannot be spawned at all
--------------------------------------------------------------------------

-- vim.system raises (rather than reporting through its callback) when the
-- binary does not exist — no python on PATH, say. Unhandled, that threw out
-- of the autocmd with the run still marked inflight, and every later
-- regeneration for the checkout was skipped for the rest of the session.
local real_system = vim.system
vim.system = function() ---@diagnostic disable-line: duplicate-set-field
  error("ENOENT: no such file or directory (cmd): 'python3'")
end
local before_fail = #generate_log()
local spawn_ok = pcall(chromium.generate, { root = root, force = true, silent = true })
vim.system = real_system
check("spawn: a failed spawn is reported, not raised out of the caller", spawn_ok)
check("spawn: a failed spawn does not leave the checkout busy", not chromium.busy())
eq("spawn: nothing ran", before_fail, #generate_log())

chromium.generate({ root = root, force = true, silent = true })
settle()
eq("spawn: the next regeneration still runs", before_fail + 1, #generate_log())

--------------------------------------------------------------------------
-- the membership probe when the database cannot be read
--------------------------------------------------------------------------

-- A probe that could not read the database learned nothing. Recording a
-- verdict anyway retired the file for the session, so the one regeneration
-- its absence should have forced never happened.
local ahead = os.time() + 400
assert(vim.uv.fs_utime(root .. "/compile_commands.json", ahead, ahead))
write(root .. "/base/other.cc", "// c++\n")
local before_probe = #generate_log()
local real_contains = chromium.file_contains
chromium.file_contains = function(_, _, cb) ---@diagnostic disable-line: duplicate-set-field
  cb(nil) -- unreadable: rewritten under the scan, or deleted
end
chromium.compdb_probe(root, root .. "/base/other.cc")
vim.wait(300)
settle()
eq("probe: an unreadable database regenerates nothing", before_probe, #generate_log())

chromium.file_contains = real_contains
chromium.compdb_probe(root, root .. "/base/other.cc")
vim.wait(5000, function()
  return #generate_log() > before_probe
end)
settle()
eq("probe: the file is probed again once the database is readable", before_probe + 1, #generate_log())

--------------------------------------------------------------------------
-- the running client: scoped restarts, drift, diagnosis
--------------------------------------------------------------------------

-- A fake clangd, so the client half of the module can be exercised without
-- a language server: what matters is which clients get stopped and which
-- buffers they are put back on.
local function fake_client(root_dir)
  local client
  client = {
    name = "clangd",
    config = { name = "clangd", root_dir = root_dir, cmd = { "clangd" } },
    attached_buffers = {},
    stopped = false,
    stop = function(self)
      self.stopped = true
    end,
    is_stopped = function(self)
      return self.stopped
    end,
  }
  return client
end

local fake_clients = {}
local real_get_clients = vim.lsp.get_clients
vim.lsp.get_clients = function(opts) ---@diagnostic disable-line: duplicate-set-field
  if opts and opts.name == "clangd" then
    return fake_clients
  end
  return real_get_clients(opts)
end
local restarted_on = {}
local real_lsp_start = vim.lsp.start
vim.lsp.start = function(config) ---@diagnostic disable-line: duplicate-set-field
  table.insert(restarted_on, config.root_dir)
  return 1
end

vim.cmd("edit " .. vim.fn.fnameescape(root .. "/base/logging.cc"))
local cppbuf = vim.api.nvim_get_current_buf()
local mine, theirs = fake_client(root), fake_client(root2)
mine.attached_buffers = { [cppbuf] = true }
fake_clients = { mine, theirs }

-- Unsaved changes are the case that matters: the buffer being worked on is
-- the one that most needs its server back, and `silent! edit` — the old
-- reattach — refuses to reload a modified buffer and swallows the refusal.
vim.bo[cppbuf].modified = true
chromium.restart_clangd(root)
check("restart: the checkout's own client is stopped", mine.stopped)
check("restart: another checkout's client is left alone", not theirs.stopped)
vim.wait(2000, function()
  return #restarted_on > 0
end)
eq("restart: the client is put back on its buffers, unsaved changes and all", { root }, restarted_on)
vim.bo[cppbuf].modified = false

-- Drift: the bundled clangd landing mid-session changes what the root wants.
-- The check used to be memoized by a bare flag set on the first C++ buffer —
-- before anything had spawned — so it never ran at all.
local root2_bundled = root2 .. "/third_party/llvm-build/Release+Asserts/bin/clangd"
vim.fn.delete(root2_bundled)
chromium.spawn_cmd({ root_dir = root2 }) -- what is running: PATH clangd
mine.stopped, theirs.stopped = false, false
chromium.ensure_clangd(root2)
check("drift: a client already matching its root is left running", not theirs.stopped)

write(root2_bundled, "#!/bin/sh\n")
assert(vim.uv.fs_chmod(root2_bundled, 493))
chromium.ensure_clangd(root2)
check("drift: the bundled clangd appearing restarts the client", theirs.stopped)
check("drift: only the drifted root is restarted", not mine.stopped)

theirs.stopped = false
chromium.ensure_clangd(root2)
check("drift: the same drift is not acted on twice", not theirs.stopped)

--------------------------------------------------------------------------
-- diagnosis
--------------------------------------------------------------------------

local okh, health = pcall(require, "chromium.health")
check("health: module loads", okh and type(health.check) == "function")

-- Freshen the compdb so the report describes a healthy checkout, then
-- diagnose from the logging.cc buffer.
local fresh = later + 100
assert(vim.uv.fs_utime(root .. "/compile_commands.json", fresh, fresh))
vim.cmd("edit " .. vim.fn.fnameescape(root .. "/base/logging.cc"))
vim.bo.filetype = "cpp"
settle()
local findings = chromium.diagnose(vim.api.nvim_get_current_buf())
local function finding(pattern)
  for _, f in ipairs(findings) do
    if f.msg:find(pattern, 1, true) then
      return f
    end
  end
end
check("diagnose: reports the checkout", finding("checkout: " .. root) ~= nil)
local bin = finding("bundled")
check("diagnose: sees the bundled clangd", bin ~= nil and bin.status == "ok")
check("diagnose: compdb reported current", finding("compile_commands.json:") ~= nil)
local member = finding("is not in compile_commands.json")
check("diagnose: flags a buffer missing from the compdb", member ~= nil and member.status == "warn")

-- The client half of the report is about *this* checkout's clangd. Counting
-- every clangd in the session made a second checkout read as both a
-- duplicate instance and the wrong workspace root: two warnings, no bug.
check("diagnose: reports the checkout's own client", finding("clangd running") ~= nil)
check("diagnose: another checkout's client is not a duplicate", finding("instances are running") == nil)
check("diagnose: another checkout's root is not a mismatch", finding("not at this checkout") == nil)

fake_clients = { theirs }
findings = chromium.diagnose(vim.api.nvim_get_current_buf())
local elsewhere = finding("not at this checkout")
check("diagnose: a clangd rooted elsewhere is flagged", elsewhere ~= nil and elsewhere.status == "warn")

fake_clients = { mine, fake_client(root) }
findings = chromium.diagnose(vim.api.nvim_get_current_buf())
local split = finding("instances are running for this checkout")
check("diagnose: two clients for one checkout is flagged", split ~= nil and split.status == "warn")
fake_clients = {}

-- Outside a checkout the report is a single line.
vim.cmd("edit " .. vim.fn.fnameescape(temp .. "/outside.cc"))
local outside_findings = chromium.diagnose(vim.api.nvim_get_current_buf())
eq("diagnose: one line outside a checkout", 1, #outside_findings)

--------------------------------------------------------------------------

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  os.exit(1)
end
