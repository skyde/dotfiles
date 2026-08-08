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

-- Let the initial parse settle before asking questions about the code.
vim.wait(4000)

--------------------------------------------------------------------------
-- the navigation the bindings are for
--------------------------------------------------------------------------

vim.cmd("edit " .. vim.fn.fnameescape(plain .. "/main.cc"))
vim.wait(2000)
local defs = request(client, "textDocument/definition", position_params(client, 3, 12))
local def = defs and (defs[1] or defs)
eq("goto-definition crosses files", vim.uri_from_fname(plain .. "/lib.cc"), def and (def.uri or def.targetUri))

local refs = request(
  client,
  "textDocument/references",
  vim.tbl_extend("force", position_params(client, 3, 12), { context = { includeDeclaration = true } })
)
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
