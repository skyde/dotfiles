-- Run with: tests/check-nvim-lsp.sh
--
-- Unlike the *_spec.lua files this drives the real config, the real plugins
-- and a real clangd, because the failures it exists to catch are exactly the
-- ones a plugin-free unit test cannot see: a server that is configured but
-- never enabled, a keymap pointing at a command a plugin has renamed, a
-- setting LazyVim replaces after config/options.lua has had its say.
--
-- The sandbox is prepared by check-nvim-lsp.sh and named in NVIM_LSP_SANDBOX:
--   <sandbox>/plain/           a C++ project with its own compile_commands.json
--   <sandbox>/chromium/src/    a fake Chromium checkout (real generate_compdb.py
--                              stub, real out/Default/build.ninja)

local sandbox = assert(vim.env.NVIM_LSP_SANDBOX, "NVIM_LSP_SANDBOX is not set")
local report = vim.env.NVIM_LSP_REPORT or "/tmp/nvim-lsp-check.txt"

local passed, failures = 0, {}

local function check(name, ok, detail)
  if ok then
    passed = passed + 1
  else
    table.insert(failures, name .. (detail and ("  -- " .. detail) or ""))
  end
end

local function eq(name, expected, actual)
  check(
    name,
    vim.deep_equal(expected, actual),
    string.format("expected %s, got %s", vim.inspect(expected), vim.inspect(actual))
  )
end

-- Nothing here should ever get as far as prompting; if it does, decline
-- rather than hang (offer_bundled_clangd asks about `gclient sync`).
vim.ui.select = function(_, _, cb) ---@diagnostic disable-line: duplicate-set-field
  cb(nil)
end
vim.ui.input = function(_, cb) ---@diagnostic disable-line: duplicate-set-field
  cb(nil)
end

---@return vim.lsp.Client|nil
local function open_and_attach(path, timeout)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local buf = vim.api.nvim_get_current_buf()
  vim.wait(timeout or 20000, function()
    return #vim.lsp.get_clients({ bufnr = buf, name = "clangd" }) > 0
  end, 100)
  return vim.lsp.get_clients({ bufnr = buf, name = "clangd" })[1]
end

---Synchronous LSP request against the current buffer, so the checks read in
---order instead of as a pile of callbacks.
local function request(client, method, params, timeout)
  local res = client:request_sync(method, params, timeout or 10000, vim.api.nvim_get_current_buf())
  return res and res.result or nil
end

local function position_params(client, line, col)
  vim.api.nvim_win_set_cursor(0, { line, col })
  return vim.lsp.util.make_position_params(0, client.offset_encoding)
end

--------------------------------------------------------------------------
-- a plain C++ project: clangd has to be running at all
--------------------------------------------------------------------------

local plain = sandbox .. "/plain"
local client = open_and_attach(plain .. "/lib.cc")
check("clangd attaches to a C++ buffer", client ~= nil, "no clangd client after 20s")

if not client then
  -- Everything below needs a server; report what there is and stop.
  vim.fn.writefile(vim.list_extend({ ("passed %d, failed %d"):format(passed, #failures) }, failures), report)
  return
end

eq("clangd is rooted at the project", plain, client.config.root_dir)
check("clangd's command is computed per client", type(client.config.cmd) == "function")

local argv = require("util.chromium").clangd_cmd(plain)
check("argv keeps header insertion off", vim.tbl_contains(argv, "--header-insertion=never"))
check("argv uncaps find-references", vim.tbl_contains(argv, "--limit-references=0"))

--------------------------------------------------------------------------
-- the navigation the bindings are for
--------------------------------------------------------------------------

-- clangd answers an unparsed file with an empty result rather than blocking,
-- so a fixed sleep here is a flaky test on a loaded machine. Ask until there
-- is an answer, or until it is fair to call it a failure.
local function ask_until(method, params, ok_enough, tries)
  local result
  for _ = 1, tries or 20 do
    result = request(client, method, params)
    if ok_enough(result) then
      return result
    end
    vim.wait(500)
  end
  return result
end

vim.cmd("edit " .. vim.fn.fnameescape(plain .. "/main.cc"))
vim.wait(500)
local defs = ask_until("textDocument/definition", position_params(client, 3, 12), function(r)
  return type(r) == "table" and #r > 0
end)
local def = defs and (defs[1] or defs)
eq("goto-definition crosses files", vim.uri_from_fname(plain .. "/lib.cc"), def and (def.uri or def.targetUri))

-- Three usages: the declaration in lib.h, the definition in lib.cc, and the
-- two calls in main.cc. clangd only sees the cross-file ones once its
-- background index has caught up, which is the thing --limit-references=0
-- and the index are for.
local ref_params = vim.tbl_extend("force", position_params(client, 3, 12), { context = { includeDeclaration = true } })
local refs = ask_until("textDocument/references", ref_params, function(r)
  return type(r) == "table" and #r >= 3
end)
check("find-references sees every usage", type(refs) == "table" and #refs >= 3, "got " .. vim.inspect(refs and #refs))

-- switch header/source, through the helper both `gh` and `<A-o>` call. The
-- binding used to name nvim-lspconfig's command, which that plugin renamed.
vim.cmd("edit " .. vim.fn.fnameescape(plain .. "/lib.cc"))
vim.wait(1000)
require("util.lsp").switch_source_header()
vim.wait(5000, function()
  return vim.api.nvim_buf_get_name(0) ~= plain .. "/lib.cc"
end, 100)
eq("switch header/source: source to header", plain .. "/lib.h", vim.api.nvim_buf_get_name(0))
require("util.lsp").switch_source_header()
vim.wait(5000, function()
  return vim.api.nvim_buf_get_name(0) ~= plain .. "/lib.h"
end, 100)
eq("switch header/source: header back to source", plain .. "/lib.cc", vim.api.nvim_buf_get_name(0))

--------------------------------------------------------------------------
-- the bindings themselves, as they end up after everything has had its say
--------------------------------------------------------------------------

local function mapping(lhs)
  local want = vim.keycode(lhs)
  for _, list in ipairs({ vim.api.nvim_buf_get_keymap(0, "n"), vim.api.nvim_get_keymap("n") }) do
    for _, m in ipairs(list) do
      if m.lhs == want or vim.keycode(m.lhs) == want then
        return m
      end
    end
  end
end

for _, lhs in ipairs({ "gh", "<A-o>", "gu", "gp", "gi", "gn" }) do
  check("mapped: " .. lhs, mapping(lhs) ~= nil)
end
-- LazyVim attaches these per buffer on LspAttach, so they only exist once a
-- server is actually running — which is the point.
for _, lhs in ipairs({ "gd", "gr" }) do
  local m = mapping(lhs)
  check("mapped on attach: " .. lhs, m ~= nil and m.buffer == 1)
end

--------------------------------------------------------------------------
-- diagnostics: what config/options.lua asks for has to survive LazyVim
--------------------------------------------------------------------------

eq("diagnostic underline stays off", false, vim.diagnostic.config().underline)

--------------------------------------------------------------------------
-- a Chromium checkout: pinned root, generated database, health report
--------------------------------------------------------------------------

local chromium = require("util.chromium")
local src = sandbox .. "/chromium/src"
eq("the fake checkout is detected", src, chromium.src_root(src .. "/base/logging.cc"))
eq("the build dir is found", "out/Default", chromium.out_dir(src))

local cbuf_client = open_and_attach(src .. "/main.cc")
check("clangd attaches inside the checkout", cbuf_client ~= nil)
if cbuf_client then
  eq("clangd is pinned to the checkout's src root", src, cbuf_client.config.root_dir)
  check(
    "argv pins the compilation database directory",
    vim.tbl_contains(chromium.clangd_cmd(src), "--compile-commands-dir=" .. src)
  )
end

-- The automation regenerates the database on the first C++ buffer; wait for
-- the run it starts, then for the file it should have written.
vim.wait(20000, function()
  return not chromium.busy() and vim.uv.fs_stat(src .. "/compile_commands.json") ~= nil
end, 200)
check("compile_commands.json was generated", vim.uv.fs_stat(src .. "/compile_commands.json") ~= nil)
check("the database is not stale afterwards", not chromium.stale(src))

-- `ninja -t compdb` names each file relative to the build dir, so entries
-- read "file": "../../main.cc". The membership probe matches on that; if it
-- ever stops matching, every C++ file opened reads as missing and forces a
-- regeneration, which is a rebuild of a several-hundred-megabyte database
-- per buffer. Ask the probe's own question, through the report.
local scanned, scan_done = nil, false
chromium.file_contains(src .. "/compile_commands.json", '/main.cc"', function(f)
  scanned, scan_done = f, true
end)
vim.wait(10000, function()
  return scan_done
end, 50)
eq("the database names files the way the probe looks for them", true, scanned)

-- The restart after a regeneration is what makes clangd re-read the database.
-- It has to leave exactly one client, attached to the buffers the old one was
-- serving — including buffers with unsaved changes, and including the case
-- where nothing else in the session would ever re-trigger an attach.
local function clangd_for(root)
  local found = {}
  for _, c in ipairs(vim.lsp.get_clients({ name = "clangd" })) do
    if c.config.root_dir == root then
      table.insert(found, c)
    end
  end
  return found
end
vim.wait(10000, function()
  return not chromium.busy()
end, 200)
vim.wait(3000)
local cbuf = vim.api.nvim_get_current_buf()
local was = clangd_for(src)[1]
local plain_before = clangd_for(plain)[1]
vim.api.nvim_buf_set_lines(cbuf, 0, 0, false, { "// unsaved" })
chromium.restart_clangd(src)
local back = vim.wait(25000, function()
  local now = clangd_for(src)[1]
  return now ~= nil and (not was or now.id ~= was.id) and now.attached_buffers[cbuf] ~= nil
end, 200)
check("restart: clangd comes back attached", back)
check("restart: unsaved changes are kept", vim.bo[cbuf].modified)
vim.wait(2000)
eq("restart: exactly one clangd is left for the checkout", 1, #clangd_for(src))
-- The other project's client is not this checkout's to restart.
local plain_after = clangd_for(plain)[1]
check(
  "restart: another project's clangd is untouched",
  plain_before ~= nil and plain_after ~= nil and plain_after.id == plain_before.id,
  ("before %s, after %s"):format(plain_before and plain_before.id, plain_after and plain_after.id)
)
vim.bo[cbuf].modified = false

-- And again with the checkout's clangd as the only one in the session, which
-- is the ordinary case and the one a plugin-provided :LspRestart used to be
-- delegated to. Its reattach runs on a fixed timer and behind a
-- `v:vim_did_enter` guard, so it could leave clangd simply stopped.
for _, c in ipairs(clangd_for(plain)) do
  c:stop()
end
vim.wait(10000, function()
  return #vim.lsp.get_clients({ name = "clangd" }) == #clangd_for(src)
end, 200)
local only = clangd_for(src)[1]
eq("restart: the checkout's clangd is now the only one", 1, #vim.lsp.get_clients({ name = "clangd" }))
chromium.restart_clangd(src)
local back_alone = vim.wait(25000, function()
  local now = clangd_for(src)[1]
  return now ~= nil and (not only or now.id ~= only.id) and now.attached_buffers[cbuf] ~= nil
end, 200)
check("restart: a lone clangd comes back attached too", back_alone)

-- Two kinds of buffer that must not set the machinery off. A header is never
-- a compile_commands.json entry (`ninja -t compdb` lists translation units),
-- and a generated file under out/ is named relative to the build dir, not the
-- source root — probing either reads as a miss and rebuilds the database on
-- every one of them. Generated files also have to land on the checkout's own
-- client: they are what gd jumps to, and a second client for them would mean
-- a second background index of Chromium.
local function db_mtime()
  local st = vim.uv.fs_stat(src .. "/compile_commands.json")
  return st and (st.mtime.sec * 1e9 + (st.mtime.nsec or 0)) or 0
end
local checkout_client = clangd_for(src)[1]
local quiet_before = db_mtime()
vim.cmd("edit " .. vim.fn.fnameescape(src .. "/base/logging.h"))
vim.wait(3000)
vim.cmd("edit " .. vim.fn.fnameescape(src .. "/out/Default/gen/generated.cc"))
vim.wait(20000, function()
  return #vim.lsp.get_clients({ bufnr = 0, name = "clangd" }) > 0
end, 100)
vim.wait(3000, function()
  return chromium.busy()
end, 100)
vim.wait(10000, function()
  return not chromium.busy()
end, 100)
local gen_client = vim.lsp.get_clients({ bufnr = 0, name = "clangd" })[1]
check(
  "a generated file under out/ joins the checkout's clangd",
  gen_client ~= nil and checkout_client ~= nil and gen_client.id == checkout_client.id,
  ("checkout %s, generated %s"):format(checkout_client and checkout_client.id, gen_client and gen_client.id)
)
eq("a header and a generated file regenerate nothing", quiet_before, db_mtime())

vim.cmd("edit " .. vim.fn.fnameescape(src .. "/main.cc"))
vim.wait(1000)

-- The commands, as a user reaches them. :ChromiumCompdb is the one every
-- piece of advice in the health report points at, so it has to both
-- regenerate and leave clangd running.
for _, cmd in ipairs({ "ChromiumCompdb", "ChromiumOutDir", "ChromiumClangd", "ChromiumHealth" }) do
  eq("command exists: :" .. cmd, 2, vim.fn.exists(":" .. cmd))
end
local before_cmd = db_mtime()
local client_before_cmd = clangd_for(src)[1]
vim.cmd("ChromiumCompdb")
vim.wait(20000, function()
  return not chromium.busy() and db_mtime() ~= before_cmd
end, 200)
check(":ChromiumCompdb regenerates the database", db_mtime() ~= before_cmd)
local cmd_back = vim.wait(25000, function()
  local now = clangd_for(src)[1]
  return now ~= nil and (not client_before_cmd or now.id ~= client_before_cmd.id)
end, 200)
check(":ChromiumCompdb leaves clangd running", cmd_back)

local findings = chromium.diagnose(vim.api.nvim_get_current_buf())
local function finding(pattern)
  for _, f in ipairs(findings) do
    if f.msg:find(pattern, 1, true) then
      return f
    end
  end
end
check("health: reports the checkout", finding("checkout: " .. src) ~= nil)
check("health: reports the build dir", finding("build dir: ") ~= nil)
local errors = {}
for _, f in ipairs(findings) do
  if f.status == "error" then
    table.insert(errors, f.msg)
  end
end
eq("health: a working checkout reports no errors", {}, errors)
check("health: :checkhealth chromium runs", pcall(vim.cmd, "checkhealth chromium"))

--------------------------------------------------------------------------

vim.fn.writefile(vim.list_extend({ ("passed %d, failed %d"):format(passed, #failures) }, failures), report)
