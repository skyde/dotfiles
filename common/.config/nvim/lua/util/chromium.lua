-- Chromium C++ xrefs, wired the way the ChromiumIDE VS Code extension wires
-- them. Having read that extension's source: there is no magic index behind
-- its goto-definition — it is plain clangd, kept honest. Everything it does,
-- and everything this module therefore does, is:
--
--   * point clangd at Chromium's own bundled binary
--     (third_party/llvm-build/Release+Asserts/bin/clangd), which matches the
--     tip-of-tree clang flags in the compile commands
--   * keep src/compile_commands.json in existence and fresh, by running the
--     command straight out of //docs/clangd.md:
--       tools/clang/scripts/generate_compdb.py -p <out dir> -o compile_commands.json
--     regenerated when it is missing or older than the build dir's
--     build.ninja (GN reruns touch build.ninja; plain ninja builds do not),
--     and again whenever a GN file is written
--   * restart clangd afterwards so it re-reads the database
--
-- The build directory follows ChromiumIDE's convention: an `out/current_link`
-- symlink names the active out dir, so VS Code and Neovim always agree on
-- which build they are indexing. Without the link, the out dir with the
-- newest build.ninja — the one actually being built — is used.
--
-- Inconsistent gd/gu in a Chromium checkout is almost never clangd being
-- flaky; it is clangd being mis-fed (stale or missing compile commands,
-- mismatched binary) or still background-indexing. The first index of
-- Chromium takes hours; it lives in src/.cache/clangd and is worth keeping.

local M = {}

local MARKER = "tools/clang/scripts/generate_compdb.py"
local CURRENT_LINK = "out/current_link"
local BUNDLED = "third_party/llvm-build/Release+Asserts/bin/clangd"

--------------------------------------------------------------------------
-- checkout discovery
--------------------------------------------------------------------------

-- src-root lookups happen per buffer event; the ancestor walk is cheap but
-- not free, so remember answers per starting directory (false = not a
-- Chromium tree, so misses are remembered too).
local root_cache = {} ---@type table<string, string|false>

---The Chromium `src` directory containing `path`, or nil. Detection is the
---same as ChromiumIDE's: the directory that has the compdb generator script.
---@param path string|nil  file or directory; defaults to the cwd
---@return string|nil
function M.src_root(path)
  local dir = vim.fn.fnamemodify(path or assert(vim.uv.cwd()), ":p")
  if vim.fn.isdirectory(dir) == 0 then
    dir = vim.fn.fnamemodify(dir, ":h")
  end
  dir = dir:gsub("/+$", "")
  if dir == "" then
    dir = "/"
  end
  local hit = root_cache[dir]
  if hit ~= nil then
    return hit or nil
  end
  local at = dir
  while true do
    if vim.uv.fs_stat(at .. "/" .. MARKER) then
      root_cache[dir] = at
      return at
    end
    local parent = vim.fn.fnamemodify(at, ":h")
    if parent == at or parent == "" then
      root_cache[dir] = false
      return nil
    end
    at = parent
  end
end

---The clangd to use for `root`: Chromium's bundled one when it is there
---(`checkout_clangd: True` in .gclient keeps it synced), PATH's otherwise.
---@param root string|nil
---@return string
function M.clangd_path(root)
  if root then
    local bundled = root .. "/" .. BUNDLED
    if vim.fn.executable(bundled) == 1 then
      return bundled
    end
  end
  return "clangd"
end

---clangd invocation for a session rooted at `path` (or anywhere else — the
---flags are the ones Chromium's docs recommend and are harmless elsewhere).
---@param path string|nil
---@return string[]
function M.clangd_cmd(path)
  local root = M.src_root(path)
  return {
    M.clangd_path(root),
    "--background-index",
    -- Chromium's docs: automatic include insertion picks wrong headers for
    -- anything that involves generated files.
    "--header-insertion=never",
  }
end

--------------------------------------------------------------------------
-- the build directory
--------------------------------------------------------------------------

---Out dirs under `root` that have actually been generated (contain a
---build.ninja), as paths relative to root, current_link excluded.
---@param root string
---@return string[]
local function generated_out_dirs(root)
  local out = {}
  if vim.fn.isdirectory(root .. "/out") == 0 then
    return out
  end
  for name, kind in vim.fs.dir(root .. "/out") do
    if
      kind == "directory"
      and name ~= "current_link"
      and vim.uv.fs_stat(("%s/out/%s/build.ninja"):format(root, name))
    then
      table.insert(out, "out/" .. name)
    end
  end
  table.sort(out)
  return out
end

---The build dir the compdb should describe, relative to root:
---out/current_link when the symlink exists and points at a real build,
---otherwise the generated out dir whose build.ninja is newest — the one
---being built. Nil when nothing has been generated at all.
---@param root string
---@return string|nil
function M.out_dir(root)
  local link = root .. "/" .. CURRENT_LINK
  if vim.uv.fs_stat(link .. "/build.ninja") then
    return CURRENT_LINK
  end
  local best, best_mtime
  for _, dir in ipairs(generated_out_dirs(root)) do
    local stat = vim.uv.fs_stat(("%s/%s/build.ninja"):format(root, dir))
    if stat and (not best_mtime or stat.mtime.sec > best_mtime) then
      best, best_mtime = dir, stat.mtime.sec
    end
  end
  return best
end

---Point out/current_link at `dir` (relative to root, e.g. "out/Default").
---The same convention ChromiumIDE uses, so both editors track together.
---@param root string
---@param dir string
---@return boolean ok
function M.link_out_dir(root, dir)
  local link = root .. "/" .. CURRENT_LINK
  local stat = vim.uv.fs_lstat(link)
  if stat then
    if stat.type ~= "link" then
      vim.notify("out/current_link exists but is not a symlink; not touching it", vim.log.levels.WARN)
      return false
    end
    vim.uv.fs_unlink(link)
  end
  -- Relative target, like ChromiumIDE writes it: the link lives in out/.
  local ok = vim.uv.fs_symlink(dir:gsub("^out/", ""), link)
  if not ok then
    vim.notify("Could not create out/current_link", vim.log.levels.ERROR)
    return false
  end
  return true
end

---Pick the build dir interactively and re-point current_link at it, then
---regenerate the compdb against it.
function M.pick_out_dir()
  local root = M.src_root(vim.api.nvim_buf_get_name(0))
  if not root then
    vim.notify("Not inside a Chromium checkout", vim.log.levels.WARN)
    return
  end
  local dirs = generated_out_dirs(root)
  if #dirs == 0 then
    vim.notify("No generated build dirs under out/ (run gn gen first)", vim.log.levels.WARN)
    return
  end
  vim.ui.select(dirs, { prompt = "Chromium build dir for xrefs" }, function(choice)
    if choice and M.link_out_dir(root, choice) then
      M.generate({ root = root, force = true })
    end
  end)
end

--------------------------------------------------------------------------
-- the compilation database
--------------------------------------------------------------------------

---Does the compdb need regenerating? Missing counts; so does being older
---than the build dir's build.ninja, which GN touches whenever build rules
---change (a plain ninja build does not).
---@param root string
---@return boolean
function M.stale(root)
  local compdb = vim.uv.fs_stat(root .. "/compile_commands.json")
  if not compdb then
    return true
  end
  local out = M.out_dir(root)
  if not out then
    return false -- nothing to regenerate from
  end
  local ninja = vim.uv.fs_stat(("%s/%s/build.ninja"):format(root, out))
  return ninja ~= nil and ninja.mtime.sec > compdb.mtime.sec
end

local inflight = {} ---@type table<string, true>
local on_idle = {} ---@type fun()[]  test hook: callbacks when a run finishes

local function flush_idle()
  for _, fn in ipairs(on_idle) do
    fn()
  end
  on_idle = {}
end

---Regenerate compile_commands.json for the checkout containing the current
---buffer (or opts.root), asynchronously, then restart clangd so it re-reads
---the database. One run per root at a time; opts.force regenerates even
---when the database looks fresh.
---@param opts? { root?: string, force?: boolean, silent?: boolean }
function M.generate(opts)
  opts = opts or {}
  local root = opts.root or M.src_root(vim.api.nvim_buf_get_name(0))
  if not root then
    if not opts.silent then
      vim.notify("Not inside a Chromium checkout", vim.log.levels.WARN)
    end
    return
  end
  if inflight[root] then
    return
  end
  if not opts.force and not M.stale(root) then
    if not opts.silent then
      vim.notify("compile_commands.json is up to date", vim.log.levels.INFO)
    end
    return
  end
  local out = M.out_dir(root)
  if not out then
    if not opts.silent then
      vim.notify("No generated build dir under out/ (run gn gen, or :ChromiumOutDir)", vim.log.levels.WARN)
    end
    return
  end

  -- Resolved before anything is marked in flight. vim.system raises rather
  -- than reporting when the binary is missing, and the throw would leave
  -- `inflight[root]` set forever — every later attempt then returns early and
  -- silently, so one missing interpreter disabled the command for the session.
  local python = vim.fn.exepath("python3")
  if python == "" then
    python = vim.fn.exepath("python")
  end
  if python == "" then
    vim.notify("python3 is not on PATH; generate_compdb.py cannot run", vim.log.levels.ERROR)
    return
  end

  inflight[root] = true
  if not opts.silent then
    vim.notify(("Regenerating compile_commands.json against %s…"):format(out), vim.log.levels.INFO)
  end
  local cmd = { python, MARKER, "-p", out, "-o", "compile_commands.json" }
  local spawned = pcall(vim.system, cmd, { cwd = root }, function(res)
    vim.schedule(function()
      inflight[root] = nil
      if res.code == 0 then
        if not opts.silent then
          vim.notify(("compile_commands.json regenerated (%s)"):format(out), vim.log.levels.INFO)
        end
        M.restart_clangd()
      else
        local err = vim.trim(res.stderr or "")
        vim.notify("generate_compdb.py failed: " .. err:sub(-400), vim.log.levels.ERROR)
      end
      flush_idle()
    end)
  end)
  if not spawned then
    -- Belt and braces for anything else that keeps the process from starting.
    -- The flag has to come back off either way, or nothing can be regenerated
    -- again for the rest of the session.
    inflight[root] = nil
    vim.notify(("Could not run %s"):format(MARKER), vim.log.levels.ERROR)
    flush_idle()
  end
end

---True while a generation is running; `fn` fires once after the next one
---finishes. The tests settle on this.
---@param fn? fun()
function M.busy(fn)
  if fn then
    table.insert(on_idle, fn)
  end
  return next(inflight) ~= nil
end

---Restart clangd so it re-reads the compilation database — ChromiumIDE's
---`clangd.restart` step. nvim-lspconfig's :LspRestart when present, a
---manual stop-and-reattach otherwise.
function M.restart_clangd()
  local clients = vim.lsp.get_clients({ name = "clangd" })
  if #clients == 0 then
    return
  end
  if pcall(vim.cmd, "LspRestart clangd") then
    return
  end
  for _, client in ipairs(clients) do
    local bufs = vim.tbl_keys(client.attached_buffers or {})
    client:stop()
    vim.defer_fn(function()
      for _, buf in ipairs(bufs) do
        if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
          vim.api.nvim_buf_call(buf, function()
            vim.cmd("silent! edit")
          end)
        end
      end
    end, 500)
  end
end

--------------------------------------------------------------------------
-- the bundled clangd
--------------------------------------------------------------------------
-- clangd itself is a gclient-managed GCS dep, gated on the checkout_clangd
-- custom var (DEPS conditions it; gclient runhooks does NOT fetch GCS deps,
-- only gclient sync does). When the binary is missing, offer to flip the
-- var in .gclient and sync — the manual step //docs/clangd.md describes,
-- automated.

---The .gclient governing `root` — gclient's own convention: the file lives
---in the directory that contains src/. Nil when there is none (tarball or
---otherwise unmanaged checkouts).
---@param root string
---@return string|nil
function M.gclient_path(root)
  local path = vim.fn.fnamemodify(root, ":h") .. "/.gclient"
  return vim.uv.fs_stat(path) and path or nil
end

---Make sure .gclient's custom_vars carry `"checkout_clangd": True`. The
---file is Python that people hand-edit, so the changes are minimal textual
---insertions; anything unrecognizable is refused rather than mangled.
---@param root string
---@return "already"|"edited"|nil state, string? err
function M.enable_checkout_clangd_var(root)
  local path = M.gclient_path(root)
  if not path then
    return nil, ("no .gclient next to %s"):format(root)
  end
  local fd = io.open(path, "rb")
  if not fd then
    return nil, "could not read " .. path
  end
  local text = fd:read("*a")
  fd:close()
  if text:find("['\"]checkout_clangd['\"]%s*:%s*True") then
    return "already"
  end
  -- An explicit False is flipped; otherwise the var is inserted into
  -- custom_vars; a solution with no custom_vars at all gains one.
  local edited, n = text:gsub("(['\"]checkout_clangd['\"]%s*:%s*)False", "%1True", 1)
  if n == 0 then
    edited, n = text:gsub("(['\"]custom_vars['\"]%s*:%s*{)", '%1\n      "checkout_clangd": True,', 1)
  end
  if n == 0 then
    edited, n = text:gsub("(solutions%s*=%s*%[%s*{)", '%1\n    "custom_vars": { "checkout_clangd": True },', 1)
  end
  if n == 0 then
    return nil, ('did not recognize %s; add "checkout_clangd": True to custom_vars by hand'):format(path)
  end
  local out = io.open(path, "wb")
  if not out then
    return nil, "could not write " .. path
  end
  out:write(edited)
  out:close()
  return "edited"
end

---Set checkout_clangd in .gclient and `gclient sync` (asynchronously) so
---the bundled clangd lands, then reconfigure and restart clangd to use it.
---:ChromiumClangd runs this on demand.
---@param root string|nil  defaults to the checkout of the current buffer
function M.install_bundled_clangd(root)
  root = root or M.src_root(vim.api.nvim_buf_get_name(0))
  if not root then
    vim.notify("Not inside a Chromium checkout", vim.log.levels.WARN)
    return
  end
  local state, err = M.enable_checkout_clangd_var(root)
  if not state then
    vim.notify(err .. "\nThen run: gclient sync", vim.log.levels.ERROR)
    return
  end
  if state == "edited" then
    vim.notify(('"checkout_clangd": True added to %s'):format(M.gclient_path(root)), vim.log.levels.INFO)
  end
  if vim.fn.executable("gclient") == 0 then
    vim.notify("gclient is not on PATH; run `gclient sync` yourself to fetch the bundled clangd", vim.log.levels.WARN)
    return
  end
  local key = root .. "#sync"
  if inflight[key] then
    return
  end
  inflight[key] = true
  vim.notify("Fetching the bundled clangd (gclient sync)… this can take a while", vim.log.levels.INFO)
  vim.system({ "gclient", "sync" }, { cwd = vim.fn.fnamemodify(root, ":h") }, function(res)
    vim.schedule(function()
      inflight[key] = nil
      if res.code ~= 0 then
        local tail = vim.trim(res.stderr or "")
        vim.notify("gclient sync failed: " .. tail:sub(-400), vim.log.levels.ERROR)
      elseif vim.fn.executable(root .. "/" .. BUNDLED) == 1 then
        vim.notify("Bundled clangd installed; restarting clangd to use it", vim.log.levels.INFO)
        M.refit_clangd(root)
      else
        vim.notify("gclient sync finished but the bundled clangd did not appear; check .gclient", vim.log.levels.WARN)
      end
      flush_idle()
    end)
  end)
end

local offered = {} ---@type table<string, true>

---Bundled clangd missing inside a checkout: say so once per root per
---session and offer the fix. PATH clangd mostly works, but it can misparse
---the tip-of-tree flags in the compile commands — silently, which is worse.
---@param root string
function M.offer_bundled_clangd(root)
  if offered[root] or M.clangd_path(root) ~= "clangd" then
    return
  end
  offered[root] = true
  -- Scheduled: this fires from FileType autocmds (possibly during startup
  -- catch-up), and a modal prompt does not belong in the middle of that.
  vim.schedule(function()
    if not M.gclient_path(root) then
      vim.notify(
        "Chromium's bundled clangd is missing and there is no .gclient to enable it in; using PATH clangd (it may misparse tip-of-tree flags)",
        vim.log.levels.WARN
      )
      return
    end
    vim.ui.select({ "Install it (set checkout_clangd in .gclient, gclient sync)", "Not now" }, {
      prompt = "Chromium's bundled clangd is missing — PATH clangd may misparse tip-of-tree flags. Install it?",
    }, function(_, idx)
      if idx == 1 then
        M.install_bundled_clangd(root)
      elseif idx == 2 then
        vim.notify("Using PATH clangd for now; :ChromiumClangd installs the bundled one later", vim.log.levels.INFO)
      end
    end)
  end)
end

--------------------------------------------------------------------------
-- keeping it fresh
--------------------------------------------------------------------------

-- A GN-file save means build rules may have changed; regenerate once the
-- writes settle rather than once per write (a format-on-save sweep over
-- BUILD.gn files would otherwise queue a dozen runs).
local GN_DEBOUNCE_MS = 2000
local gn_timers = {} ---@type table<string, uv.uv_timer_t>

---@param root string
function M.gn_changed(root)
  local timer = gn_timers[root]
  if timer then
    timer:stop()
  else
    timer = assert(vim.uv.new_timer())
    gn_timers[root] = timer
  end
  timer:start(
    GN_DEBOUNCE_MS,
    0,
    vim.schedule_wrap(function()
      M.generate({ root = root, force = true, silent = true })
    end)
  )
end

-- clangd is configured once per session (the plugin spec computes the cmd
-- from the cwd). When the first Chromium buffer shows up somewhere else —
-- nvim started at ~, then :e into a checkout — reconfigure and restart so
-- the bundled binary and fresh flags actually apply.
local tuned = {} ---@type table<string, true>

---@param root string
function M.ensure_clangd(root)
  if tuned[root] then
    return
  end
  tuned[root] = true
  if not vim.lsp.config then
    return
  end
  local want = M.clangd_cmd(root)
  local have = (vim.lsp.config.clangd or {}).cmd
  if type(have) == "table" and have[1] == want[1] then
    return
  end
  vim.lsp.config("clangd", { cmd = want })
  M.restart_clangd()
end

---Forget the per-root tuning and re-run ensure_clangd — used when the
---bundled clangd appears mid-session, so the new binary actually attaches.
---@param root string
function M.refit_clangd(root)
  tuned[root] = nil
  M.ensure_clangd(root)
end

return M
