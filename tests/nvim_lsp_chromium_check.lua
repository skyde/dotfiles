-- Run with: tests/check-nvim-lsp-chromium.sh
--
-- The fixture in tests/nvim_lsp_check.lua proves the machinery is correct.
-- This proves it survives the real thing: a compilation database of hundreds
-- of megabytes, translation units that take seconds to parse, a background
-- index that is still building, and platform sources the mac build never
-- compiles.
--
-- Targets are discovered from the checkout rather than hardcoded, because
-- Chromium moves; anything not found is skipped rather than failed, so this
-- stays useful as the tree evolves.

local src = assert(vim.env.CHROMIUM_SRC, "CHROMIUM_SRC is not set")
local report = vim.env.NVIM_CHROMIUM_REPORT or "/tmp/nvim-lsp-chromium.txt"
local chromium = require("util.chromium")

local passed, failures, notes = 0, {}, {}
local function flush()
  local lines = { ("passed %d, failed %d"):format(passed, #failures) }
  vim.list_extend(lines, failures)
  vim.list_extend(lines, notes)
  vim.fn.writefile(lines, report)
end
local function note(fmt, ...)
  table.insert(notes, "  " .. (select("#", ...) > 0 and string.format(fmt, ...) or fmt))
  flush()
end
local function check(name, ok, detail)
  if ok then
    passed = passed + 1
  else
    table.insert(failures, name .. (detail and ("  -- " .. detail) or ""))
  end
  flush()
end
local function eq(name, want, got)
  check(name, vim.deep_equal(want, got), ("expected %s, got %s"):format(vim.inspect(want), vim.inspect(got)))
end

vim.ui.select = function(_, _, cb) ---@diagnostic disable-line: duplicate-set-field
  cb(nil)
end
vim.ui.input = function(_, cb) ---@diagnostic disable-line: duplicate-set-field
  cb(nil)
end

-- Chromium translation units are large; clangd needs room to answer.
local ATTACH_MS = 120000

local function rel(p)
  return (p:sub(1, #src + 1) == src .. "/") and p:sub(#src + 2) or p
end
local function exists(p)
  return vim.uv.fs_stat(p) ~= nil
end
local function open(path, timeout)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local buf = vim.api.nvim_get_current_buf()
  vim.wait(timeout or ATTACH_MS, function()
    return #vim.lsp.get_clients({ bufnr = buf, name = "clangd" }) > 0
  end, 200)
  return buf, vim.lsp.get_clients({ bufnr = buf, name = "clangd" })[1]
end
local function clients_for(root)
  local found = {}
  for _, c in ipairs(vim.lsp.get_clients({ name = "clangd" })) do
    if c.config and c.config.root_dir == root then
      table.insert(found, c)
    end
  end
  return found
end
local function db_path()
  return src .. "/compile_commands.json"
end
local function in_db(relpath, timeout)
  local hit, done = nil, false
  chromium.file_contains(db_path(), "/" .. relpath .. '"', function(f)
    hit, done = f, true
  end)
  vim.wait(timeout or 120000, function()
    return done
  end, 50)
  return hit
end

--------------------------------------------------------------------------
-- the checkout
--------------------------------------------------------------------------

eq("src_root detects the checkout", src, chromium.src_root(src .. "/base/logging.cc"))
local outdir = chromium.out_dir(src)
check("out_dir finds a generated build dir", outdir ~= nil, tostring(outdir))
note("build dir: %s", tostring(outdir))

local st = vim.uv.fs_stat(db_path())
check("the compilation database is a real file", st ~= nil and st.size > 1024 * 1024, st and ("%.1f MB"):format(st.size / 1e6) or "missing")
if st then
  note("compile_commands.json: %.1f MB", st.size / 1e6)
end
check("the database is not stale", not chromium.stale(src))

--------------------------------------------------------------------------
-- attach, on a real translation unit taken from the database itself
--------------------------------------------------------------------------

-- Pick a TU the database actually lists, so this does not depend on any
-- particular file surviving in the tree.
local tu
do
  local fh = io.open(db_path(), "r")
  if fh then
    for _ = 1, 4000 do
      local line = fh:read("l")
      if not line then
        break
      end
      local f = line:match('"file":%s*"%.%./%.%./([^"]+)"')
      if f and f:match("%.cc$") and not f:match("^out/") and exists(src .. "/" .. f) then
        tu = f
        break
      end
    end
    fh:close()
  end
end
check("a translation unit was found in the database", tu ~= nil)
if not tu then
  flush()
  return
end
note("translation unit: %s", tu)

local t0 = vim.uv.now()
local _, client = open(src .. "/" .. tu)
check("clangd attaches inside the checkout", client ~= nil, "no client after 120s")
if not client then
  flush()
  return
end
note("attach took %d ms", vim.uv.now() - t0)
eq("clangd is pinned to the src root", src, client.config.root_dir)
check(
  "argv pins the compilation database directory",
  vim.tbl_contains(chromium.clangd_cmd(src), "--compile-commands-dir=" .. src)
)
check("argv uncaps find-references", vim.tbl_contains(chromium.clangd_cmd(src), "--limit-references=0"))
note("clangd: %s", chromium.clangd_cmd(src)[1])

--------------------------------------------------------------------------
-- the membership probe, against a database of this size
--------------------------------------------------------------------------
-- The probe runs on buffer switches, so its cost matters. It scans until it
-- matches, which means the cost depends on where in the file the entry sits:
-- an entry near the end is a full read of the whole database. The number is
-- reported rather than gated, because it is a property of the machine's disk
-- and cache as much as of the code -- but it must terminate and be correct.
local probe_start = vim.uv.now()
local found = in_db(tu)
local probe_ms = vim.uv.now() - probe_start
eq("the probe finds a built TU in the real database", true, found)
note("probe over the real database: %d ms", probe_ms)
check("the probe terminates in a workable time", probe_ms < 30000, ("%d ms"):format(probe_ms))

--------------------------------------------------------------------------
-- cross-platform sources, as the real database has them
--------------------------------------------------------------------------
-- On a mac build the posix and ObjC++ sources are compiled and the Windows
-- and Android ones are not. Whatever the answer, every one of them must still
-- get a language server.
local platform = {
  { "posix", "base/files/file_util_posix.cc", true },
  { "Windows", "base/files/file_util_win.cc", false },
}
-- Any ObjC++ TU the database lists, discovered rather than named.
do
  local fh = io.open(db_path(), "r")
  if fh then
    for _ = 1, 20000 do
      local line = fh:read("l")
      if not line then
        break
      end
      local f = line:match('"file":%s*"%.%./%.%./([^"]+%.mm)"')
      if f and exists(src .. "/" .. f) then
        table.insert(platform, { "ObjC++", f, true })
        break
      end
    end
    fh:close()
  end
end

for _, case in ipairs(platform) do
  local label, path, want_in_db = case[1], case[2], case[3]
  if exists(src .. "/" .. path) then
    eq(("%s source membership (%s)"):format(label, path), want_in_db, in_db(path))
    local _, c = open(src .. "/" .. path, 90000)
    check(("%s source still gets a language server"):format(label), c ~= nil)
  else
    note("skipped %s: %s is not in this tree", label, path)
  end
end

-- A header is never a database entry, and must not be probed as one.
local header = src .. "/base/files/file_util.h"
if exists(header) then
  eq("a header is not a database entry", false, in_db("base/files/file_util.h"))
  local _, hc = open(header, 90000)
  check("a header still gets a language server", hc ~= nil)
end

--------------------------------------------------------------------------
-- switch header/source on real pairs, including ObjC++
--------------------------------------------------------------------------

local switched, tried = 0, 0
for _, base in ipairs({
  "base/files/file_util",
  "base/strings/string_util",
  "base/logging",
  "base/values",
  "base/apple/foundation_util",
  "base/apple/bundle_locations",
}) do
  for _, ext in ipairs({ ".cc", ".mm" }) do
    local impl, head = src .. "/" .. base .. ext, src .. "/" .. base .. ".h"
    if exists(impl) and exists(head) then
      tried = tried + 1
      open(impl, 90000)
      vim.wait(1200)
      require("util.lsp").switch_source_header()
      if vim.wait(30000, function()
        return vim.api.nvim_buf_get_name(0) == head
      end, 200) then
        switched = switched + 1
      else
        note("switch missed: %s%s -> %s", base, ext, rel(vim.api.nvim_buf_get_name(0)))
      end
    end
  end
end
check(("switch header/source on %d real pairs"):format(tried), tried > 0 and switched == tried, ("%d/%d"):format(switched, tried))
note("switch header/source: %d/%d real pairs", switched, tried)

--------------------------------------------------------------------------
-- goto-definition that does not depend on the background index
--------------------------------------------------------------------------
-- An #include resolves from this translation unit's own AST, so it is
-- answerable however cold the index is.
do
  open(src .. "/" .. tu, 90000)
  local c = vim.lsp.get_clients({ bufnr = 0, name = "clangd" })[1]
  if c then
    local pos
    for i, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, 80, false)) do
      local col = line:find('#include "', 1, true)
      if col then
        vim.api.nvim_win_set_cursor(0, { i, col + 9 })
        pos = vim.lsp.util.make_position_params(0, c.offset_encoding)
        break
      end
    end
    if pos then
      local target
      local deadline = vim.uv.now() + 120000
      while vim.uv.now() < deadline do
        local res = c:request_sync("textDocument/definition", pos, 30000, 0)
        local r = res and res.result
        local one = r and (r[1] or r)
        local uri = one and (one.uri or one.targetUri)
        if uri then
          target = rel(vim.uri_to_fname(uri))
          break
        end
        vim.wait(1500)
      end
      check("goto-definition on an #include reaches a header", target ~= nil and target:match("%.h$") ~= nil, tostring(target))
      note("gd on #include -> %s", tostring(target))
    end
  end
end

--------------------------------------------------------------------------
-- find-references: index-bound, so reported honestly
--------------------------------------------------------------------------
-- Cross-translation-unit references need clangd's background index, which
-- takes hours to build for Chromium. A cold index is not a failure of the
-- configuration, so this reports rather than gates.
do
  local idx, shards = src .. "/.cache/clangd/index", 0
  if vim.uv.fs_stat(idx) then
    for _ in vim.fs.dir(idx) do
      shards = shards + 1
    end
  end
  note("background index: %d shards", shards)
  if shards < 1000 then
    note("find-references: index still cold, skipping (this is not a failure)")
  else
    local c = vim.lsp.get_clients({ bufnr = 0, name = "clangd" })[1]
    local h = src .. "/base/files/file_util.h"
    if c and exists(h) then
      open(h, 90000)
      c = vim.lsp.get_clients({ bufnr = 0, name = "clangd" })[1]
      local pos
      for i, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
        local col = line:find("PathExists", 1, true)
        if col then
          vim.api.nvim_win_set_cursor(0, { i, col - 1 })
          pos = vim.lsp.util.make_position_params(0, c.offset_encoding)
          break
        end
      end
      if pos and c then
        local params = vim.tbl_extend("force", pos, { context = { includeDeclaration = true } })
        local res = c:request_sync("textDocument/references", params, 180000, 0)
        local refs = res and res.result or {}
        local files = {}
        for _, r in ipairs(refs) do
          files[vim.uri_to_fname(r.uri)] = true
        end
        note("find-references: %d refs across %d files", #refs, vim.tbl_count(files))
        check("find-references spans multiple files with a warm index", vim.tbl_count(files) >= 2, ("%d files"):format(vim.tbl_count(files)))
      end
    end
  end
end

--------------------------------------------------------------------------
-- restart, on a checkout this size
--------------------------------------------------------------------------
-- The restart exists so clangd re-reads a regenerated database. On Chromium
-- it must also not throw away the on-disk index, and must put the client back
-- on the buffers it was serving including one with unsaved changes.
do
  local buf = open(src .. "/" .. tu, 90000)
  local was = clients_for(src)[1]
  local shards_before = 0
  if vim.uv.fs_stat(src .. "/.cache/clangd/index") then
    for _ in vim.fs.dir(src .. "/.cache/clangd/index") do
      shards_before = shards_before + 1
    end
  end
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "// nvim-lsp-chromium-check" })
  local dirty = vim.bo[buf].modified

  chromium.restart_clangd(src)
  local back = vim.wait(120000, function()
    local now = clients_for(src)[1]
    return now ~= nil and (not was or now.id ~= was.id) and now.attached_buffers[buf] ~= nil
  end, 250)
  check("restart: clangd comes back attached", back)
  check("restart: unsaved changes are kept", dirty and vim.bo[buf].modified)
  vim.wait(4000)
  eq("restart: exactly one clangd is left for the checkout", 1, #clients_for(src))

  local shards_after = 0
  if vim.uv.fs_stat(src .. "/.cache/clangd/index") then
    for _ in vim.fs.dir(src .. "/.cache/clangd/index") do
      shards_after = shards_after + 1
    end
  end
  check("restart: the on-disk index survives", shards_after >= shards_before - 5, ("%d -> %d"):format(shards_before, shards_after))
  -- Leave no unsaved buffer behind; nothing here writes to the checkout.
  vim.bo[buf].modified = false
end

--------------------------------------------------------------------------
-- health
--------------------------------------------------------------------------

do
  open(src .. "/" .. tu, 90000)
  local findings = chromium.diagnose(vim.api.nvim_get_current_buf())
  local errors = {}
  for _, f in ipairs(findings) do
    note("health [%s] %s", f.status, f.msg)
    if f.status == "error" then
      table.insert(errors, f.msg)
    end
  end
  eq("health: a working checkout reports no errors", {}, errors)
  check("health: :checkhealth chromium runs", pcall(vim.cmd, "checkhealth chromium"))
end

flush()
