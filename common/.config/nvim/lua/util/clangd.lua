-- Works out how to launch clangd for a given file.
--
-- Plain CMake projects need nothing special, but a GN checkout such as Chromium
-- (~/chrome/src) does:
--
--   * the compilation database lives in an out/ directory, not at the root, and
--     a root-level compile_commands.json is often a stale symlink to an old one,
--   * the checkout ships a clangd matching the toolchain the database was
--     generated with, under third_party/llvm-build, so nothing has to be
--     installed per machine,
--   * every third_party/ library is its own git repo and some carry their own
--     .gn, so the usual "closest root marker wins" search picks the wrong root
--     and clangd then indexes a fragment of the tree.
--
-- Everything here is pure path inspection so it can be exercised by
-- tests/nvim_clangd_spec.lua without plugins or a real checkout.

local M = {}

local uv = vim.uv or vim.loop

local function stat(path)
  return path and uv.fs_stat(path) or nil
end

local function is_dir(path)
  local st = stat(path)
  return st ~= nil and st.type == "directory"
end

local function is_file(path)
  local st = stat(path)
  -- fs_stat follows symlinks, so a link to a real database counts as a file.
  return st ~= nil and st.type == "file"
end

---Outermost ancestor of `path` that looks like a GN build root.
---
---Chromium nests .gn files under third_party/{dawn,skia,angle,...}, so the
---search keeps walking up instead of stopping at the first hit; requiring
---build/config/BUILDCONFIG.gn as well rules out those nested roots anyway.
---@param path string? file or directory to search upwards from
---@return string? root
function M.gn_root(path)
  if not path or path == "" then
    return nil
  end
  path = vim.fs.normalize(path)
  local dir = is_dir(path) and path or vim.fs.dirname(path)
  local root = nil
  while dir and dir ~= "" do
    if is_file(dir .. "/.gn") and is_file(dir .. "/build/config/BUILDCONFIG.gn") then
      root = dir
    end
    local parent = vim.fs.dirname(dir)
    if not parent or parent == dir then
      break
    end
    dir = parent
  end
  return root
end

---GN root for a buffer, falling back to the working directory for scratch buffers.
---@param bufnr integer?
---@return string? root
function M.root_for(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr or 0)
  if name == "" then
    return M.gn_root(uv.cwd())
  end
  return M.gn_root(name)
end

---Directory to hand to clangd's --compile-commands-dir, or nil if there is none.
---
---Candidates are the root itself and every out/ directory; the freshest wins,
---because the root-level file is usually a symlink someone created once and
---never repointed, while out/<dir>/compile_commands.json is rewritten by every
---`gn gen`.
---@param root string
---@return string? dir
function M.compile_commands_dir(root)
  local best, best_mtime = nil, nil

  local function consider(dir)
    local db = dir .. "/compile_commands.json"
    local st = stat(db)
    if not st or st.type ~= "file" then
      return
    end
    if not best_mtime or st.mtime.sec > best_mtime then
      -- The directory clangd should look in, not where a symlink points.
      best, best_mtime = dir, st.mtime.sec
    end
  end

  consider(root)
  local out = root .. "/out"
  if is_dir(out) then
    for name, kind in vim.fs.dir(out) do
      if kind == "directory" then
        consider(out .. "/" .. name)
      end
    end
  end

  return best
end

---Path to a clangd binary: the checkout's own first, then Mason's, then $PATH.
---@param root string? GN root, if the file belongs to one
---@return string? binary
function M.binary(root)
  local candidates = {}
  local exe = vim.fn.has("win32") == 1 and ".exe" or ""

  if root then
    candidates[#candidates + 1] = root .. "/third_party/llvm-build/Release+Asserts/bin/clangd" .. exe
  end
  local mason = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", "clangd")
  candidates[#candidates + 1] = mason .. (vim.fn.has("win32") == 1 and ".cmd" or "")

  for _, candidate in ipairs(candidates) do
    if vim.fn.executable(candidate) == 1 then
      return candidate
    end
  end

  local found = vim.fn.exepath("clangd")
  return found ~= "" and found or nil
end

---Command line for a clangd client.
---@param root string? GN root, if the file belongs to one
---@return string[] cmd
function M.cmd(root)
  local cmd = {
    M.binary(root) or "clangd",
    "--background-index",
    -- Keep indexing off the critical path; a cold Chromium index takes hours
    -- and would otherwise make the machine unusable while it runs.
    "--background-index-priority=background",
    "--completion-style=detailed",
    "--function-arg-placeholders=1",
  }

  if root then
    local jobs = math.max(2, math.floor((uv.available_parallelism and uv.available_parallelism() or 4) / 2))
    vim.list_extend(cmd, {
      -- Chromium's include graph is generated; letting clangd guess new
      -- #includes gets it wrong more often than right.
      "--header-insertion=never",
      -- clang-tidy roughly doubles per-file analysis time on Chromium TUs and
      -- the checkout's .clang-tidy is enforced by the tryjobs anyway.
      "--clang-tidy=false",
      "--limit-results=100",
      "--limit-references=1000",
      "--fallback-style=Chromium",
      "-j=" .. jobs,
    })
    local db = M.compile_commands_dir(root)
    if db then
      cmd[#cmd + 1] = "--compile-commands-dir=" .. db
    end
  else
    vim.list_extend(cmd, {
      "--clang-tidy",
      "--header-insertion=iwyu",
      "--fallback-style=llvm",
    })
  end

  return cmd
end

---Jump between a source file and its header.
---
---Implemented against clangd's textDocument/switchSourceHeader extension rather
---than by calling nvim-lspconfig's buffer command, so the keymaps don't have to
---track a command name owned by someone else.
---@param bufnr integer?
function M.switch_source_header(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local method = "textDocument/switchSourceHeader"
  local client = vim.lsp.get_clients({ bufnr = bufnr, name = "clangd" })[1]
  if not client then
    return vim.notify("clangd is not attached to this buffer", vim.log.levels.WARN)
  end
  if not client:supports_method(method) then
    return vim.notify("clangd does not support " .. method, vim.log.levels.WARN)
  end
  client:request(method, vim.lsp.util.make_text_document_params(bufnr), function(err, result)
    if err then
      return vim.notify("switch source/header failed: " .. tostring(err.message or err), vim.log.levels.ERROR)
    end
    if not result then
      return vim.notify("no matching source/header for this file", vim.log.levels.WARN)
    end
    vim.cmd.edit(vim.uri_to_fname(result))
  end, bufnr)
end

---Human-readable summary of what clangd will do here, for :ClangdStatus.
---@param bufnr integer?
---@return string
function M.describe(bufnr)
  local root = M.root_for(bufnr)
  local lines = {
    "clangd: " .. (M.binary(root) or "not found"),
    "gn root: " .. (root or "none (using root markers)"),
  }
  if root then
    local db = M.compile_commands_dir(root)
    lines[#lines + 1] = "compile_commands.json: " .. (db and (db .. "/compile_commands.json") or "MISSING")
    if not db then
      lines[#lines + 1] = "generate one with: gn gen out/Default --export-compile-commands"
    end
  end
  lines[#lines + 1] = "cmd: " .. table.concat(M.cmd(root), " ")
  return table.concat(lines, "\n")
end

return M
