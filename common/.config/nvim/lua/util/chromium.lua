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
  local cmd = {
    M.clangd_path(root),
    "--background-index",
    -- Chromium's docs: automatic include insertion picks wrong headers for
    -- anything that involves generated files.
    "--header-insertion=never",
    -- clangd caps find-references at 1000 by default and truncates
    -- *silently*; plenty of Chromium symbols have more usages than that.
    -- 0 removes the cap — "find usages" must mean all of them.
    "--limit-references=0",
    -- At the default log level a Chromium session grows lsp.log by the
    -- gigabyte; errors are the part worth keeping.
    "--log=error",
  }
  if root then
    -- Pin database discovery instead of letting clangd walk up from each
    -- file: a buffer under out/ (generated sources reached via gd) would
    -- otherwise bind to whatever partial compile_commands.json sits inside
    -- the build dir rather than the real one at the src root.
    table.insert(cmd, "--compile-commands-dir=" .. root)
  end
  return cmd
end

-- What each clangd was actually spawned with, by workspace root ("" when
-- rootless). vim.lsp.config holds one cmd for every clangd client, so a
-- static argv would leak one checkout's --compile-commands-dir (and
-- binary) into other projects and other checkouts in the same session.
-- Instead the plugin registers cmd as a *function*: Neovim resolves
-- root_dir first and hands the config to it, so every client computes its
-- own argv at spawn time — and records it here, which is how ensure_clangd
-- can later tell a running client no longer matches what its root wants.
local spawned = {} ---@type table<string, string[]>

---argv for a client about to spawn, derived from its resolved root.
---@param config? { root_dir?: string }
---@return string[]
function M.spawn_cmd(config)
  local root_dir = config and config.root_dir or nil
  local cmd = M.clangd_cmd(root_dir)
  spawned[root_dir or ""] = cmd
  return cmd
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

-- Staleness by mtime misses one important case: files that appeared since
-- the database was written (a git pull, a new branch, a freshly created
-- file). build.ninja does not move for those until the next gn run, yet
-- clangd is left flag-guessing for them — which is exactly the silent
-- "gd sometimes works" degradation this module exists to prevent. So the
-- checks are layered: M.refresh re-runs the mtime comparison whenever a C++
-- buffer is (re)entered or the editor regains focus, and M.compdb_probe
-- checks once per file per session that the buffer's file is actually *in*
-- the database, regenerating when it is not.

---Scan a (possibly huge) file for a plain byte string without loading it
---whole or blocking the UI: chunked reads on the uv loop, overlapping by
---#needle-1 bytes so a match spanning a chunk boundary is still found.
---`cb` runs in a fast-event context — vim.schedule before touching the API.
---@param path string
---@param needle string
---@param cb fun(found: boolean|nil)  nil = file unreadable
---@param opts? { chunk?: integer }  test hook: tiny chunks exercise the overlap
function M.file_contains(path, needle, cb, opts)
  local chunk = opts and opts.chunk or 4 * 1024 * 1024
  local overlap = math.max(#needle - 1, 0)
  vim.uv.fs_open(path, "r", 292, function(oerr, fd)
    if oerr or not fd then
      return cb(nil)
    end
    local tail = ""
    local offset = 0
    local function step()
      vim.uv.fs_read(fd, chunk, offset, function(rerr, data)
        if rerr then
          vim.uv.fs_close(fd, function() end)
          return cb(nil)
        end
        if not data or #data == 0 then
          vim.uv.fs_close(fd, function() end)
          return cb(false)
        end
        offset = offset + #data
        local hay = tail .. data
        if hay:find(needle, 1, true) then
          vim.uv.fs_close(fd, function() end)
          return cb(true)
        end
        tail = overlap > 0 and hay:sub(-overlap) or ""
        step()
      end)
    end
    step()
  end)
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
  -- Not `spawned`: that name is taken at module scope for the per-root clangd
  -- argv, and shadowing it here is how the two quietly become one bug later.
  local started = pcall(vim.system, cmd, { cwd = root }, function(res)
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
  if not started then
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

-- Buffer switches come in bursts and the staleness check is two stats;
-- throttle it rather than gate it once per session (the once-per-session
-- gate is how a compdb went quietly stale mid-session before).
local REFRESH_THROTTLE_MS = 2000
local last_refresh = {} ---@type table<string, integer>

---Regenerate the compdb if it has gone stale — safe to call from every
---BufEnter/FocusGained; throttled, deduped, loud only when something is
---actually regenerated.
---@param root string
function M.refresh(root)
  local now = vim.uv.now()
  local before = last_refresh[root]
  if before and now - before < REFRESH_THROTTLE_MS then
    return
  end
  last_refresh[root] = now
  if M.stale(root) then
    M.generate({ root = root, force = true })
  end
end

local probed = {} ---@type table<string, true>
local probing = {} ---@type table<string, true>

-- Only translation units appear in the database — `ninja -t compdb` emits
-- one entry per *compiled* file. Headers never show up, so probing one
-- would read a "miss" every time and regenerate for nothing.
local TU_EXTENSIONS = { c = true, cc = true, cpp = true, cxx = true, m = true, mm = true }

---Once per file per session: is this buffer's file actually *in* the
---database? A file the compdb does not mention gets heuristic flags and
---silently degraded navigation — the fate of every file added since the
---last regeneration. A miss forces one regeneration; if the file still is
---not there afterwards it is genuinely not built in this config (a
---platform-excluded source, say), and nothing retries.
---@param root string
---@param file string  absolute path of the buffer's file
function M.compdb_probe(root, file)
  if vim.fn.has("win32") == 1 then
    return -- compdb entries use forward slashes; this probe would only mis-miss
  end
  local ext = file:match("%.(%a+)$")
  if not ext or not TU_EXTENSIONS[ext:lower()] then
    return -- headers (and nameless buffers) are never compdb entries
  end
  file = vim.fn.fnamemodify(file, ":p"):gsub("/+$", "")
  if file:sub(1, #root + 1) ~= root .. "/" then
    return
  end
  local rel = file:sub(#root + 2)
  if rel == "" or rel:sub(1, 4) == "out/" then
    return -- generated files are named relative to the build dir, not src
  end
  local key = root .. "\0" .. rel
  -- One scan per root at a time: the database is hundreds of MB, and a
  -- burst of new buffers must not stack whole-file reads on the uv
  -- threadpool. A file skipped here stays unmarked and is retried by a
  -- later BufEnter.
  if probed[key] or probing[root] or inflight[root] or M.stale(root) then
    return
  end
  local db = root .. "/compile_commands.json"
  local before = vim.uv.fs_stat(db)
  if not before then
    return
  end
  probing[root] = true
  probed[key] = true
  -- Entries look like "file": "../../base/logging.cc" — match the
  -- src-relative path with its closing quote, plain-text.
  M.file_contains(db, "/" .. rel .. '"', function(found)
    vim.schedule(function()
      probing[root] = nil
      if found ~= false then
        return
      end
      -- The database can be rewritten in place *under* the scan (a gn
      -- debounce, a regeneration from VS Code or a terminal): a truncated
      -- read then reports a false miss. Only trust a miss against the
      -- same bytes the scan started on; otherwise forget the probe so a
      -- later event retries against the new database.
      local after = vim.uv.fs_stat(db)
      if not after or after.mtime.sec ~= before.mtime.sec or after.size ~= before.size or inflight[root] then
        probed[key] = nil
        return
      end
      vim.notify(("%s is not in compile_commands.json; regenerating"):format(rel), vim.log.levels.INFO)
      M.generate({ root = root, force = true, silent = true })
    end)
  end)
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

-- Because the plugin registers cmd as a function of the resolved root, a
-- client's very first spawn already carries the right binary and flags —
-- there is nothing to reconfigure when a Chromium buffer first appears.
-- What can still drift is a *running* client: the bundled clangd landing
-- mid-session (gclient sync) changes what its root wants. ensure_clangd
-- notices that drift and restarts. One wrinkle: vim.lsp.get_clients hides
-- clients that have not finished the initialize handshake, so a restart
-- issued the instant after a spawn silently restarts nothing — hence the
-- bounded retry until the client is visible.
local tuned = {} ---@type table<string, true>

---@param root string
---@param tries integer
local function restart_when_visible(root, tries)
  if not spawned[root] then
    return -- nothing has spawned for this root; its first spawn will be right
  end
  local want = M.clangd_cmd(root)
  if vim.deep_equal(spawned[root], want) then
    return -- what runs is already right
  end
  if #vim.lsp.get_clients({ name = "clangd" }) > 0 then
    M.restart_clangd()
    return
  end
  if tries > 0 then
    -- Spawned with a stale command but not yet visible: try again once
    -- the handshake finishes.
    vim.defer_fn(function()
      restart_when_visible(root, tries - 1)
    end, 500)
  end
end

---@param root string
function M.ensure_clangd(root)
  if tuned[root] then
    return
  end
  tuned[root] = true
  restart_when_visible(root, 10)
end

---Forget the per-root tuning and re-run ensure_clangd — used when the
---bundled clangd appears mid-session, so the new binary actually attaches.
---@param root string
function M.refit_clangd(root)
  tuned[root] = nil
  M.ensure_clangd(root)
end

--------------------------------------------------------------------------
-- diagnosis
--------------------------------------------------------------------------
-- "gd is flaky" always decomposes into one of a handful of checkable facts.
-- Check them all, as data; lua/chromium/health.lua renders this for
-- :checkhealth chromium.

---@class chromium.Finding
---@field status "ok"|"warn"|"error"|"info"
---@field msg string
---@field advice? string

---@param bufnr? integer  buffer to diagnose from; defaults to the current one
---@return chromium.Finding[]
function M.diagnose(bufnr)
  local out = {} ---@type chromium.Finding[]
  local function add(status, msg, advice)
    table.insert(out, { status = status, msg = msg, advice = advice })
  end

  bufnr = bufnr or 0
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local root = M.src_root(bufname ~= "" and bufname or nil)
  if not root then
    add("info", "not inside a Chromium checkout — nothing to check")
    return out
  end
  add("ok", "checkout: " .. root)

  -- The binary.
  local clangd = M.clangd_path(root)
  if clangd ~= "clangd" then
    add("ok", "clangd: bundled (" .. clangd .. ")")
  elseif vim.fn.executable("clangd") == 1 then
    add(
      "warn",
      "bundled clangd missing; using PATH clangd ("
        .. vim.fn.exepath("clangd")
        .. "), which can misparse tip-of-tree flags",
      ":ChromiumClangd installs the bundled one"
    )
  else
    add(
      "error",
      "no clangd anywhere: the bundled one is missing and PATH has none",
      ":ChromiumClangd, or install clangd"
    )
  end

  -- The build dir.
  local out_dir = M.out_dir(root)
  if not out_dir then
    add(
      "error",
      "no generated build dir under out/ — no compile commands can exist",
      "gn gen out/Default, or :ChromiumOutDir"
    )
  elseif out_dir == CURRENT_LINK then
    add("ok", "build dir: out/current_link -> " .. (vim.uv.fs_readlink(root .. "/" .. CURRENT_LINK) or "?"))
  else
    add("ok", "build dir: " .. out_dir .. " (newest build.ninja; :ChromiumOutDir pins one)")
  end

  -- The database.
  local db_stat = vim.uv.fs_stat(root .. "/compile_commands.json")
  if not db_stat then
    add("error", "compile_commands.json is missing — clangd is guessing every file's flags", ":ChromiumCompdb")
  elseif M.stale(root) then
    add(
      "warn",
      "compile_commands.json predates the build dir's build.ninja",
      ":ChromiumCompdb (also runs on the next C++ buffer)"
    )
  else
    add("ok", ("compile_commands.json: %.1f MB, current"):format(db_stat.size / 2 ^ 20))
  end

  -- The running client. :ChromiumCompdb is the advice because it both
  -- regenerates and restarts — and unlike :LspRestart it always exists
  -- (nvim 0.12's native :lsp command makes nvim-lspconfig skip defining
  -- its Lsp* commands entirely).
  local clients = vim.lsp.get_clients({ name = "clangd" })
  if #clients == 0 then
    add("info", "clangd is not running yet (it starts with the first C++ buffer)")
  else
    if #clients > 1 then
      add(
        "warn",
        #clients .. " clangd instances are running; one per checkout is intended",
        "duplicate instances double memory and race the index — :ChromiumCompdb restarts clangd"
      )
    end
    local client = clients[1]
    local running = spawned[root]
    if running and not vim.deep_equal(running, M.clangd_cmd(root)) then
      add(
        "warn",
        "the running clangd was spawned with a different command than its root now wants",
        ":ChromiumCompdb restarts clangd onto the new command"
      )
    else
      add("ok", ("clangd running, %d buffers attached"):format(#vim.tbl_keys(client.attached_buffers or {})))
    end
    local croot = client.config and client.config.root_dir
    if croot and croot ~= root then
      add(
        "warn",
        "clangd's workspace root is " .. croot .. ", not the checkout root",
        ":ChromiumCompdb restarts clangd"
      )
    end
  end

  -- The background index. Count only — stat'ing 100k shards would hang
  -- the report on exactly the checkouts it exists for.
  local shards = 0
  local index_dir = root .. "/.cache/clangd/index"
  if vim.fn.isdirectory(index_dir) == 1 then
    for _ in vim.fs.dir(index_dir) do
      shards = shards + 1
      if shards >= 200000 then
        break
      end
    end
  end
  if shards == 0 then
    add(
      "info",
      "background index is empty — the first index of Chromium takes hours, and find-references is incomplete until it finishes"
    )
  else
    add("ok", ("background index: %d shards (still grows while clangd is indexing)"):format(shards))
  end

  -- The tools regeneration needs. generate_compdb.py prefers the
  -- checkout's own third_party/ninja/ninja and only falls back to PATH.
  local own_ninja = root .. "/third_party/ninja/ninja"
  if vim.fn.executable(own_ninja) == 0 and vim.fn.executable("ninja") == 0 then
    add(
      "error",
      "no ninja: neither " .. own_ninja .. " nor PATH has one — `ninja -t compdb` (regeneration) will fail",
      "gclient sync fetches the bundled ninja, or put depot_tools on PATH"
    )
  end
  if vim.fn.executable("python3") == 0 and vim.fn.executable("python") == 0 then
    add("error", "no python on PATH — generate_compdb.py cannot run")
  end
  if vim.fn.executable("gclient") == 0 then
    add("info", "gclient is not on PATH (only needed to install the bundled clangd)")
  end

  -- This buffer.
  local ft = vim.bo[bufnr].filetype
  if (ft == "c" or ft == "cpp" or ft == "objc" or ft == "objcpp") and db_stat and not M.stale(root) then
    local rel = bufname:sub(#root + 2)
    local ext = bufname:match("%.(%a+)$")
    local is_tu = ext ~= nil and TU_EXTENSIONS[ext:lower()] ~= nil
    if is_tu and rel ~= "" and rel:sub(1, 4) ~= "out/" and vim.fn.has("win32") == 0 then
      local found ---@type boolean|nil
      local done = false
      M.file_contains(root .. "/compile_commands.json", "/" .. rel .. '"', function(f)
        found, done = f, true
      end)
      vim.wait(5000, function()
        return done
      end)
      if found == true then
        add("ok", rel .. " is in the database")
      elseif found == false then
        add(
          "warn",
          rel .. " is not in compile_commands.json — clangd is guessing its flags",
          "new file: build once / :ChromiumCompdb; otherwise it is not built in this config"
        )
      else
        add("info", "membership scan of compile_commands.json did not finish in 5s; skipped")
      end
    elseif not is_tu then
      add(
        "info",
        "headers are never compile_commands.json entries; clangd infers their flags from a source file that includes them"
      )
    end
  end

  return out
end

return M
