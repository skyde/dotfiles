-- Run with: nvim --headless -u NONE -i NONE -l tests/nvim_lsp_spec.lua
--
-- Exercises common/.config/nvim/lua/util/lsp.lua against a fake clangd:
-- switch-header/source goes to the server as an LSP request, so the binding
-- does not depend on whatever nvim-lspconfig currently calls its buffer-local
-- command. Plugin-free, like the other specs.

local source = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(repo .. "/common/.config/nvim")

local lsp = require("util.lsp")

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

local temp = vim.fn.resolve(vim.fn.tempname())
vim.fn.mkdir(temp, "p")
write(temp .. "/thing.cc", "// source\n")
write(temp .. "/thing.h", "// header\n")

--------------------------------------------------------------------------
-- a fake clangd, and a record of everything it was told
--------------------------------------------------------------------------

local requests = {}
local answer ---@type fun(): any, any  err, result
local client = {
  name = "clangd",
  request = function(_, method, params, handler, bufnr)
    table.insert(requests, { method = method, params = params, bufnr = bufnr })
    handler(answer())
    return true
  end,
}

local attached = true
vim.lsp.get_clients = function(opts) ---@diagnostic disable-line: duplicate-set-field
  if attached and opts and opts.name == "clangd" then
    return { client }
  end
  return {}
end

local notices = {}
vim.notify = function(msg, level) ---@diagnostic disable-line: duplicate-set-field
  table.insert(notices, { msg = msg, level = level })
end

--------------------------------------------------------------------------
-- the happy path: ask the server, open what it answers
--------------------------------------------------------------------------

vim.cmd("edit " .. vim.fn.fnameescape(temp .. "/thing.cc"))
local src = vim.api.nvim_get_current_buf()
answer = function()
  return nil, vim.uri_from_fname(temp .. "/thing.h")
end
lsp.switch_source_header()
eq("switch: asks clangd, not a command", "textDocument/switchSourceHeader", requests[1] and requests[1].method)
eq("switch: asks about this buffer", vim.uri_from_bufnr(src), requests[1] and requests[1].params.uri)
eq("switch: scoped to the buffer", src, requests[1] and requests[1].bufnr)
eq("switch: opens the counterpart", temp .. "/thing.h", vim.api.nvim_buf_get_name(0))

-- And back again, from an explicit buffer number.
answer = function()
  return nil, vim.uri_from_fname(temp .. "/thing.cc")
end
lsp.switch_source_header(vim.api.nvim_get_current_buf())
eq("switch: opens the counterpart again", temp .. "/thing.cc", vim.api.nvim_buf_get_name(0))

--------------------------------------------------------------------------
-- the ways it can come back empty-handed
--------------------------------------------------------------------------

-- clangd answers null when it cannot find a counterpart — usually because
-- the file is not in the compilation database, which is its own report.
notices = {}
answer = function()
  return nil, nil
end
check("switch: a null answer does not raise", pcall(lsp.switch_source_header))
eq("switch: a null answer explains itself", 1, #notices)
check(
  "switch: the message names the missing counterpart",
  (notices[1] and notices[1].msg or ""):find("header/source", 1, true) ~= nil,
  vim.inspect(notices)
)

notices = {}
answer = function()
  return { message = "boom" }, nil
end
check("switch: a server error does not raise", pcall(lsp.switch_source_header))
check(
  "switch: a server error is reported",
  (notices[1] and notices[1].msg or ""):find("boom", 1, true) ~= nil,
  vim.inspect(notices)
)

--------------------------------------------------------------------------
-- no clangd: the buffer-local command if something else defines one, and a
-- plain explanation otherwise
--------------------------------------------------------------------------

attached = false
local ran
vim.api.nvim_create_user_command("LspClangdSwitchSourceHeader", function()
  ran = true
end, {})
lsp.switch_source_header()
check("switch: falls back to the buffer-local command", ran)

vim.api.nvim_del_user_command("LspClangdSwitchSourceHeader")
notices = {}
check("switch: no clangd anywhere does not raise", pcall(lsp.switch_source_header))
check(
  "switch: no clangd anywhere says so",
  (notices[1] and notices[1].msg or ""):find("clangd is not attached", 1, true) ~= nil,
  vim.inspect(notices)
)

--------------------------------------------------------------------------

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  os.exit(1)
end
