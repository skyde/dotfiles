local M = {}

local compare_bases = {}
local p4_contexts = {}

local function canonical_path(path)
  path = vim.fs.normalize(path)
  return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

local function normal_file()
  if vim.bo.buftype ~= "" then
    return nil
  end

  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    return nil
  end

  return canonical_path(path)
end

local function context_dir()
  local path = normal_file()
  if path then
    local stat = vim.uv.fs_stat(path)
    return stat and stat.type == "directory" and path or vim.fs.dirname(path)
  end
  return canonical_path(vim.fn.getcwd())
end

local function current_file()
  local path = normal_file()
  if not path then
    vim.notify("The current buffer is not a file", vim.log.levels.WARN)
  end
  return path
end

local function positive_number(value, fallback)
  local number = tonumber(value)
  return number and number > 0 and number or fallback
end

local function timeout_ms(remote)
  if remote then
    local milliseconds = tonumber(vim.env.NVIM_P4_TIMEOUT_MS)
    if milliseconds and milliseconds > 0 then
      return milliseconds
    end
    local seconds = tonumber(vim.env.NVIM_P4_TIMEOUT_SECONDS)
    return seconds and seconds > 0 and (seconds * 1000) or 5000
  end
  return positive_number(vim.env.NVIM_VCS_TIMEOUT_MS, 2000)
end

local function run(command, directory, opts)
  opts = opts or {}
  local ok, process = pcall(vim.system, command, {
    cwd = directory or context_dir(),
    text = true,
  })
  if not ok then
    return false, "", tostring(process), nil
  end

  local wait_timeout = opts.timeout
  if wait_timeout == nil then
    wait_timeout = timeout_ms(opts.remote)
  end
  local waited, result = pcall(function()
    if wait_timeout == false then
      return process:wait()
    end
    return process:wait(wait_timeout)
  end)
  if not waited then
    return false, "", tostring(result), nil
  end

  local stdout = result.stdout or ""
  local stderr = vim.trim(result.stderr or "")
  if opts.trim ~= false then
    stdout = vim.trim(stdout)
  end
  if result.code == 124 and wait_timeout ~= false then
    return false, stdout, ("timed out after %d ms"):format(wait_timeout), result.code
  end

  return result.code == 0, stdout, stderr, result.code
end

local function is_windows()
  return vim.fn.has("win32") == 1
end

local function p4_command()
  local configured = vim.env.NVIM_PERFORCE_CMD
  if configured and configured ~= "" then
    return configured
  end

  -- libuv cannot execute .cmd shims directly. Native Windows Neovim should
  -- call the real client; the batch shim remains available to interactive
  -- shells and P4 itself.
  if not is_windows() then
    local shim = vim.fn.exepath("vcs-p4")
    if shim ~= "" then
      return shim
    end
  end
  if vim.fn.executable("g4") == 1 then
    return "g4"
  end
  return "p4"
end

local function preferred_adapter()
  local configured = vim.env.NVIM_VCS
  if configured == "g4" then
    return "p4"
  end
  if vim.tbl_contains({ "git", "jj", "p4" }, configured) then
    return configured
  end

  local ok, config = pcall(require, "diffview.config")
  if ok then
    return config.get_config().preferred_adapter
  end
  return "jj"
end

local function parse_p4_root(output)
  local root = output:match("Client root:%s*([^\n]+)")
  if not root then
    return nil
  end
  return canonical_path(vim.trim(root))
end

local function path_within(path, root)
  path = canonical_path(path)
  root = canonical_path(root):gsub("[/\\]+$", "")
  if is_windows() then
    path = path:lower()
    root = root:lower()
  end
  return path == root or path:sub(1, #root + 1) == root .. "/"
end

local p4_context_environment = {
  "P4PORT",
  "P4CLIENT",
  "P4USER",
  "P4HOST",
  "P4CONFIG",
  "P4CHARSET",
  "P4TICKETS",
  "P4TRUST",
}

local function p4_context_key(command, directory)
  local parts = { command, vim.fs.normalize(directory) }
  for _, name in ipairs(p4_context_environment) do
    table.insert(parts, name .. "=" .. (vim.env[name] or ""))
  end
  return table.concat(parts, "\0")
end

local function p4_context_cache_ms()
  local configured = tonumber(vim.env.NVIM_P4_CONTEXT_CACHE_MS)
  if configured and configured >= 0 then
    return configured
  end
  return 30000
end

local function probe(kind, directory)
  if kind == "git" then
    local ok, root, err = run({ "git", "rev-parse", "--show-toplevel" }, directory)
    if ok then
      return { kind = kind, root = vim.fs.normalize(root), directory = directory }
    end
    return nil, err
  elseif kind == "jj" then
    local ok, root, err = run({ "jj", "root" }, directory)
    if ok then
      return { kind = kind, root = vim.fs.normalize(root), directory = directory }
    end
    return nil, err
  elseif kind == "p4" then
    local command = p4_command()
    local cache_key = p4_context_key(command, directory)
    local cached = p4_contexts[cache_key]
    local cache_ms = p4_context_cache_ms()
    if cached and cache_ms > 0 and vim.uv.now() - cached.time <= cache_ms then
      return vim.deepcopy(cached.context)
    end

    local ok, output, err = run({ command, "info" }, directory, { remote = true })
    local root = ok and parse_p4_root(output) or nil
    if root then
      if not path_within(directory, root) then
        return nil, "current path is outside the Perforce client root"
      end
      local context = {
        kind = kind,
        root = root,
        directory = directory,
        command = command,
        info = output,
      }
      p4_contexts[cache_key] = {
        context = context,
        time = vim.uv.now(),
      }
      return vim.deepcopy(context)
    end
    return nil, err ~= "" and err or "Perforce did not report a client root"
  end
end

local function resolve_context()
  local directory = context_dir()
  local preferred = preferred_adapter()
  local order = {}
  local seen = {}

  local function add(kind)
    if kind and not seen[kind] then
      seen[kind] = true
      table.insert(order, kind)
    end
  end

  add(preferred)
  add("git")
  add("jj")
  add("p4")

  local last_error
  for _, kind in ipairs(order) do
    local context, err = probe(kind, directory)
    if context then
      return context
    end
    if kind == preferred and err and err ~= "" then
      last_error = err
    end
  end

  return nil, last_error
end

local function require_context()
  local context, err = resolve_context()
  if not context then
    local message = "No Git, JJ, P4, or G4 workspace found"
    if err and err:find("timed out", 1, true) then
      message = message .. " (" .. err .. ")"
    end
    vim.notify(message, vim.log.levels.WARN)
  end
  return context
end

local function git_upstream(context)
  local ok, upstream = run({ "git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}" }, context.root)
  return ok and upstream ~= "" and upstream or nil
end

local function git_has_head(context)
  return run({ "git", "rev-parse", "--verify", "--quiet", "HEAD" }, context.root)
end

local function git_base(context)
  if not git_has_head(context) then
    return nil
  end

  local remotes = { "origin" }
  local ok, output = run({ "git", "remote" }, context.root)
  if ok then
    for remote in output:gmatch("[^\n]+") do
      if remote ~= "origin" then
        table.insert(remotes, remote)
      end
    end
  end

  for _, remote in ipairs(remotes) do
    local found, remote_head =
      run({ "git", "symbolic-ref", "--quiet", "--short", "refs/remotes/" .. remote .. "/HEAD" }, context.root)
    if found and remote_head ~= "" then
      return remote_head
    end
  end

  local upstream = git_upstream(context)
  if upstream then
    return upstream
  end

  for _, candidate in ipairs({ "origin/main", "origin/master", "main", "master" }) do
    local exists = run({ "git", "rev-parse", "--verify", "--quiet", candidate }, context.root)
    if exists then
      return candidate
    end
  end
end

local function default_base(context)
  if context.kind == "git" then
    return git_base(context)
  elseif context.kind == "jj" then
    return "trunk()"
  end
end

local function base_key(context)
  return context.kind .. "\0" .. vim.fs.normalize(context.root)
end

local function remembered_base(context)
  return compare_bases[base_key(context)] or default_base(context)
end

local function revision_range(kind, base)
  if not base or base == "" then
    return nil
  end
  if base:find("..", 1, true) then
    return base
  end
  if kind == "git" then
    return base .. "...HEAD"
  elseif kind == "jj" then
    return base .. "...@"
  end
  return base
end

local function escaped_path(path)
  return vim.fn.fnameescape(vim.fs.normalize(path))
end

-- P4 reserves @, #, *, and % in filespecs. Files containing those
-- characters are added with `p4 add -f`, then addressed through their ASCII
-- expansions. Depot paths reported by P4 are already encoded and must not be
-- encoded a second time.
local function p4_lexically_within(path, root)
  -- Normalize UNC separators lexically. This deliberately avoids
  -- fs_realpath(): a leading // is also valid Perforce depot syntax and must
  -- never trigger a filesystem (or redirected-network-share) probe.
  path = vim.fs.normalize(path):gsub("\\", "/"):gsub("/+$", "")
  root = vim.fs.normalize(root):gsub("\\", "/"):gsub("/+$", "")
  if is_windows() then
    path = path:lower()
    root = root:lower()
  end
  return path == root or path:sub(1, #root + 1) == root .. "/"
end

local function p4_path_is_local(path, root)
  if path:match("^\\\\") then
    return true
  end
  if not path:match("^//") then
    return true
  end
  local root_is_unc = root ~= nil and (root:match("^//") ~= nil or root:match("^\\\\") ~= nil)
  return root_is_unc and p4_lexically_within(path, root)
end

local function p4_native_local_path(path, windows)
  if (windows == true or (windows == nil and is_windows())) and path:match("^//") then
    return path:gsub("/", "\\")
  end
  return path
end

local function p4_filespec(path, opts)
  opts = opts or {}
  if path:match("^//") and not opts.local_path then
    return path
  end
  path = path:gsub("%%", "%%25"):gsub("@", "%%40"):gsub("#", "%%23"):gsub("%*", "%%2A")
  return opts.local_path and p4_native_local_path(path, opts.windows) or path
end

local function p4_local_path(path, root, local_path)
  if local_path == nil then
    local_path = p4_path_is_local(path, root)
  end
  local absolute = path:sub(1, 1) == "/"
    or (is_windows() and (path:match("^%a:[/\\]") ~= nil or path:match("^\\\\") ~= nil))
  if not local_path or absolute then
    return path
  end
  return vim.fs.normalize(vim.fs.joinpath(root or context_dir(), path))
end

local function p4_adapter_filespec(path, root)
  local local_path = p4_path_is_local(path, root)
  return p4_filespec(p4_local_path(path, root, local_path), { local_path = local_path })
end

local function diffview()
  local ok, lazy = pcall(require, "lazy")
  if ok then
    lazy.load({ plugins = { "diffview-plus.nvim" } })
  end
  return require("diffview")
end

local function enable_p4_adapter_compat()
  local ok, adapter_module = pcall(require, "diffview.vcs.adapters.p4")
  if not ok then
    return
  end

  local P4Adapter = adapter_module.P4Adapter

  if not P4Adapter._nvim_adapter_compat then
    local config = require("diffview.config")
    local utils = require("diffview.utils")
    local VCSAdapter = require("diffview.vcs.adapter").VCSAdapter
    local Job = require("diffview.job").Job
    local pl = utils.path
    local main_thread = {}
    local pending_jobs = setmetatable({}, { __mode = "k" })

    local function thread_key()
      return coroutine.running() or main_thread
    end

    local function register_job_context(adapter, command)
      local directory = adapter.ctx and adapter.ctx.nvim_p4_cwd
      if directory then
        pending_jobs[thread_key()] = {
          command = command,
          cwd = directory,
        }
      end
    end

    -- Diffview's P4 adapter uses the client root for path math and as every
    -- process cwd. Keep the former, but run commands from the active file's
    -- discovery directory so a nested P4CONFIG continues to apply. bin() is
    -- evaluated immediately before asynchronous Job construction, allowing
    -- the originating adapter's cwd to be carried per coroutine without
    -- mutating Neovim's global P4 environment.
    local original_job_init = Job.init
    Job.init = function(self, opts)
      local key = thread_key()
      local job_context = pending_jobs[key]
      pending_jobs[key] = nil
      if job_context and opts.command == job_context.command then
        opts = vim.tbl_extend("force", {}, opts)
        opts.cwd = job_context.cwd
        opts.env = vim.tbl_extend("force", vim.uv.os_environ(), opts.env or {}, {
          PWD = job_context.cwd,
        })
      end
      return original_job_init(self, opts)
    end

    local original_create = P4Adapter.create
    P4Adapter.create = function(toplevel, path_args, cpath)
      local err, adapter = original_create(toplevel, path_args, cpath)
      if adapter then
        adapter.ctx.nvim_p4_cwd = canonical_path(cpath or context_dir())
      end
      return err, adapter
    end

    local original_bin = P4Adapter.bin
    P4Adapter.bin = function(self)
      local command = original_bin(self)
      register_job_context(self, command)
      return command
    end

    local original_exec_sync = P4Adapter.exec_sync
    P4Adapter.exec_sync = function(self, args, cwd_or_opts)
      register_job_context(self, self:get_command()[1])
      local stdout, code, stderr = original_exec_sync(self, args, cwd_or_opts)
      pending_jobs[thread_key()] = nil
      return stdout, code, stderr
    end

    local function p4_info(directory)
      return utils.job(utils.flatten({ config.get_config().p4_cmd, "info" }), {
        cwd = canonical_path(directory),
        timeout = timeout_ms(true),
        silent = true,
      })
    end

    P4Adapter.run_bootstrap = function()
      local command = config.get_config().p4_cmd
      local bootstrap = P4Adapter.bootstrap
      bootstrap.ok = false
      bootstrap.err = nil
      local report_error = VCSAdapter.bootstrap_preamble(bootstrap, command, "P4Adapter", "p4_cmd")
      if not report_error then
        return
      end

      local _, code, stderr = p4_info(context_dir())
      if code ~= 0 then
        local message = "Could not connect to Perforce server. Check P4PORT, P4USER, P4CLIENT settings."
        if stderr and #stderr > 0 then
          message = message .. "\nError: " .. table.concat(stderr, " ")
        end
        report_error(message)
        return
      end
      bootstrap.ok = true
    end

    P4Adapter.get_repo_paths = function(path_args, cpath)
      path_args = path_args or {}
      local directory = canonical_path(cpath or context_dir())
      local info, code = p4_info(directory)
      local client_root
      if code == 0 then
        for _, line in ipairs(info) do
          local root = line:match("^Client root: (.*)")
          if root then
            client_root = canonical_path(vim.trim(root))
            break
          end
        end
      end

      if not client_root then
        return path_args, { directory }
      end

      local paths = {}
      for _, path_arg in ipairs(path_args) do
        if path_arg:match("^//") then
          -- vim.fn.expand() collapses a leading "//" to "/" on Unix.
          -- Preserve mapped depot paths while still undoing fnameescape().
          local expanded = vim.fn.expand(path_arg)
          if not expanded:match("^//") then
            expanded = "/" .. expanded
          end
          table.insert(paths, expanded)
        else
          local expanded_paths = pl:vim_expand(path_arg, false, true) or { path_arg }
          for _, path in ipairs(expanded_paths) do
            if path:match("^//") then
              table.insert(paths, path)
            else
              local absolute = canonical_path(pl:absolute(path, cpath or directory))
              table.insert(paths, path_within(absolute, client_root) and absolute or path)
            end
          end
        end
      end
      -- Keep discovery anchored to this invocation's explicit -C directory.
      -- The client root has no P4CONFIG in common nested-config layouts, so
      -- re-probing from it would discard the configuration we just resolved.
      return paths, { directory }
    end

    P4Adapter.find_toplevel = function(top_indicators)
      for _, indicator in ipairs(top_indicators or {}) do
        local directory = indicator
        if not pl:is_dir(directory) then
          directory = pl:parent(directory)
        end
        if directory and pl:readable(directory) then
          local info, code = p4_info(directory)
          if code == 0 then
            for _, line in ipairs(info) do
              local found = line:match("^Client root: (.*)")
              if found then
                found = canonical_path(vim.trim(found))
                if pl:is_dir(found) then
                  return nil, found
                end
              end
            end
          end
        end
      end
      return "Could not determine Perforce client root from provided paths.", ""
    end

    P4Adapter.get_show_args = function(self, path, rev)
      local rev_spec = (rev and rev:object_name()) or "#head"
      return { "print", "-q", p4_adapter_filespec(path, self.ctx.toplevel) .. rev_spec }
    end

    P4Adapter.is_binary = function(self, path, rev)
      local RevType = require("diffview.vcs.rev").RevType
      local path_spec = p4_adapter_filespec(path, self.ctx.toplevel)
      if rev and rev.type == RevType.COMMIT then
        path_spec = path_spec .. rev:object_name()
      elseif not rev or rev.type ~= RevType.LOCAL then
        path_spec = path_spec .. "#head"
      end

      local output, code = self:exec_sync({ "fstat", "-T", "headType", path_spec }, self.ctx.toplevel)
      if code ~= 0 then
        return true
      end
      for _, line in ipairs(output) do
        local file_type = line:match("headType (%S+)")
        if file_type then
          return file_type:find("binary", 1, true) ~= nil
            or file_type:find("apple", 1, true) ~= nil
            or file_type:find("resource", 1, true) ~= nil
            or file_type:find("unicode", 1, true) ~= nil
            or file_type:find("utf16", 1, true) ~= nil
        end
      end
      return true
    end

    P4Adapter.file_restore = require("diffview.async").wrap(function(self, path, _, _, callback)
      local Job = require("diffview.job").Job
      local ok = require("diffview.async").await(Job({
        command = self:bin(),
        args = { "revert", p4_adapter_filespec(path, self.ctx.toplevel) },
        cwd = self.ctx.toplevel,
        log_opt = { label = "P4Adapter:file_restore(revert)" },
      }))
      callback(ok == true, nil)
    end)

    P4Adapter.add_files = function(self, paths)
      local local_paths = vim.tbl_map(function(path)
        return p4_native_local_path(p4_local_path(path, self.ctx.toplevel, true))
      end, paths)
      local _, code = self:exec_sync(vim.list_extend({ "add", "-f" }, local_paths), self.ctx.toplevel)
      return code == 0
    end

    P4Adapter.reset_files = function(self, paths)
      local specs = vim.tbl_map(function(path)
        return p4_adapter_filespec(path, self.ctx.toplevel)
      end, paths)
      local _, code = self:exec_sync(vim.list_extend({ "revert" }, specs), self.ctx.toplevel)
      return code == 0
    end

    P4Adapter._nvim_adapter_compat = true
  end

  -- Repository discovery below performs the bounded, invocation-aware info
  -- probe. Mark the context-free bootstrap complete so it cannot probe from
  -- Neovim's process cwd before an explicit -C has been interpreted.
  P4Adapter.bootstrap.done = true
  P4Adapter.bootstrap.ok = true
  P4Adapter.bootstrap.err = nil
end

local function contextual_diffview(context)
  local view = diffview()
  local ok, config = pcall(require, "diffview.config")
  if ok then
    config.get_config().preferred_adapter = context.kind
  end
  if context.kind == "p4" then
    enable_p4_adapter_compat()
  end
  return view
end

local function enable_p4_history_compat()
  local ok, p4_commit = pcall(require, "diffview.vcs.adapters.p4.commit")
  if not ok or p4_commit._nvim_history_compat then
    return
  end

  local adapter_module = require("diffview.vcs.adapters.p4")
  local P4Adapter = adapter_module.P4Adapter

  local _, history_worker = debug.getupvalue(P4Adapter.file_history_worker, 2)
  if type(history_worker) == "function" then
    for index = 1, 32 do
      local name, original_parser = debug.getupvalue(history_worker, index)
      if not name then
        break
      end
      if name == "parse_describe_output" and type(original_parser) == "function" then
        debug.setupvalue(history_worker, index, function(lines)
          local parsed = original_parser(lines)

          -- The pinned parser uses %S+ for depot paths, dropping every
          -- affected file whose path contains spaces. Always rebuild the
          -- complete list: accepting a partially parsed mixed changelist can
          -- silently omit the requested file. Depot paths encode a literal
          -- '#', so greedily matching up to "#<rev> <action>" is safe.
          local files = {}
          for _, line in ipairs(lines) do
            local path, revision, action = line:match("^%.%.%. (.+)#(%d+) ([^%s]+)")
            if path then
              table.insert(files, {
                path = path,
                rev = revision,
                action = action,
              })
            end
          end
          parsed.files = files
          return parsed
        end)
        break
      end
    end
  end

  local P4Commit = p4_commit.P4Commit
  local Commit = require("diffview.vcs.commit").Commit
  local original = P4Commit.from_rev_arg
  local needs_tagged_fallback = false

  local function tagged_commit(rev_arg, adapter)
    local changelist = rev_arg:match("^@(%d+)$") or rev_arg:match("^(%d+)$")
    if not changelist then
      local resolved, resolve_code = adapter:exec_sync({ "changes", "-m1", rev_arg }, adapter.ctx.toplevel)
      if resolve_code ~= 0 or not resolved[1] then
        return nil
      end
      changelist = resolved[1]:match("^Change (%d+)")
      if not changelist then
        return nil
      end
    end

    local output, code = adapter:exec_sync({ "-ztag", "describe", "-s", changelist }, adapter.ctx.toplevel)
    if code ~= 0 or #output == 0 then
      return nil
    end

    local fields = {}
    for _, line in ipairs(output) do
      local name, value = line:match("^%.%.%. ([^ ]+) ?(.*)$")
      if name and not fields[name] then
        fields[name] = value
      end
    end

    local timestamp = tonumber(fields.time) or os.time()
    local age = math.max(0, os.time() - timestamp)
    local amount, unit
    if age < 60 then
      amount, unit = age, "second"
    elseif age < 3600 then
      amount, unit = math.floor(age / 60), "minute"
    elseif age < 86400 then
      amount, unit = math.floor(age / 3600), "hour"
    else
      amount, unit = math.floor(age / 86400), "day"
    end
    local relative_date = ("%d %s%s ago"):format(amount, unit, amount == 1 and "" or "s")
    local iso_date = os.date("%Y-%m-%d %H:%M:%S", timestamp)
    local description = vim.trim(fields.desc or "")
    local subject = description:match("^[^\n]+") or ("Changelist " .. changelist)
    local commit = Commit({
      changelist = fields.change or changelist,
      hash = fields.change or changelist,
      author = fields.user or vim.env.P4USER or "unknown",
      time = timestamp,
      subject = subject,
      body = description ~= "" and description or subject,
      rel_date = relative_date,
    })
    commit.iso_date = iso_date
    return commit
  end

  P4Commit.from_rev_arg = function(rev_arg, adapter)
    if not needs_tagged_fallback then
      local parsed, commit = pcall(original, rev_arg, adapter)
      if parsed and commit then
        return commit
      end
      -- The pinned P4 adapter expects a non-standard `p4 describe` header.
      -- Once that parser fails, use stable tagged output for the remaining
      -- changelists instead of issuing two describe calls for every entry.
      needs_tagged_fallback = true
    end
    return tagged_commit(rev_arg, adapter)
  end
  p4_commit._nvim_history_compat = true
end

local function p4_scope(context)
  local directory = vim.fs.normalize(context.directory)
  if not path_within(directory, context.root) then
    vim.notify("The active path is outside the Perforce client root", vim.log.levels.ERROR)
    return nil
  end
  local spec = p4_filespec(directory:gsub("[/\\]+$", ""), { local_path = true })
  return spec .. (is_windows() and "\\..." or "/...")
end

local function p4_depot_path(context, path)
  local ok, output, err = run({ context.command, "-ztag", "where", path }, context.directory, { remote = true })
  if not ok then
    vim.notify(err ~= "" and err or "Unable to map the Perforce path", vim.log.levels.ERROR)
    return nil
  end
  local depot_path = output:match("%.%.%. depotFile ([^\n]+)")
  if not depot_path or depot_path == "" then
    vim.notify("Perforce did not return a depot path for " .. path, vim.log.levels.ERROR)
    return nil
  end
  return depot_path
end

local function operation_timeout(kind)
  local configured
  if kind == "p4" then
    configured = tonumber(vim.env.NVIM_P4_OPERATION_TIMEOUT_MS)
  end
  configured = configured or tonumber(vim.env.NVIM_VCS_OPERATION_TIMEOUT_MS)
  return configured and configured > 0 and configured or false
end

local function git_working_copy_diff(context)
  local patches = {}
  local function append(output)
    if output and output ~= "" then
      table.insert(patches, output)
    end
  end

  local has_head = git_has_head(context)
  local tracked_command = has_head and { "git", "diff", "--binary", "HEAD", "--" }
    or { "git", "diff", "--cached", "--binary", "--" }
  local ok, output, err = run(tracked_command, context.root, {
    trim = false,
    timeout = operation_timeout("git"),
  })
  if not ok then
    return false, "", err
  end
  append(output)

  if not has_head then
    local unstaged_ok, unstaged, unstaged_err = run(
      { "git", "diff", "--binary", "--" },
      context.root,
      { trim = false, timeout = operation_timeout("git") }
    )
    if not unstaged_ok then
      return false, "", unstaged_err
    end
    append(unstaged)
  end

  local listed, untracked, list_err = run(
    { "git", "ls-files", "--others", "--exclude-standard", "-z" },
    context.root,
    { trim = false, timeout = operation_timeout("git") }
  )
  if not listed then
    return false, "", list_err
  end

  local null_device = is_windows() and "NUL" or "/dev/null"
  for path in untracked:gmatch("([^%z]+)%z") do
    local _, patch, patch_err, code = run(
      { "git", "diff", "--no-index", "--binary", "--", null_device, path },
      context.root,
      { trim = false, timeout = operation_timeout("git") }
    )
    if code ~= 0 and code ~= 1 then
      return false, "", patch_err
    end
    append(patch)
  end

  return true, table.concat(patches)
end

local function diff_args(context, range, path)
  local args = {}
  if context then
    local directory = context.kind == "p4" and context.directory or context.root
    table.insert(args, "-C=" .. escaped_path(directory))
  end
  if range and range ~= "" then
    table.insert(args, range)
  end
  if path then
    vim.list_extend(args, { "--", escaped_path(path) })
  end
  return args
end

local function history_args(context, path)
  local directory = context.kind == "p4" and context.directory or context.root
  local args = { "-C=" .. escaped_path(directory) }
  if path then
    table.insert(args, escaped_path(path))
  end
  return args
end

local function open_diff(context, range, path)
  contextual_diffview(context).open(diff_args(context, range, path))
end

function M.changes()
  local ok, lib = pcall(require, "diffview.lib")
  if ok and lib.get_current_view() then
    require("diffview.actions").focus_files()
    return
  end

  local context = require_context()
  if context then
    local path
    if context.kind == "p4" then
      path = p4_scope(context)
      if not path then
        return
      end
    end
    open_diff(context, nil, path)
  end
end

function M.all_changes()
  local context = require_context()
  if context then
    local range = context.kind == "p4" and nil or revision_range(context.kind, remembered_base(context))
    open_diff(context, range)
  end
end

function M.current_file()
  local path = current_file()
  if not path then
    return
  end
  local context = require_context()
  if context then
    if context.kind == "p4" then
      path = p4_filespec(path, { local_path = true })
    end
    open_diff(context, nil, path)
  end
end

function M.current_change()
  local path = current_file()
  if not path then
    return
  end

  local context = require_context()
  if not context then
    return
  end

  local base
  if context.kind == "git" and git_has_head(context) then
    base = "HEAD"
  elseif context.kind == "jj" then
    base = "@-"
  elseif context.kind == "p4" then
    path = p4_filespec(path, { local_path = true })
  end
  open_diff(context, base, path)
end

function M.branch_diff()
  local context = require_context()
  if not context then
    return
  end

  if context.kind == "p4" then
    local path = p4_scope(context)
    if path then
      open_diff(context, nil, path)
    end
    return
  end

  local range = revision_range(context.kind, remembered_base(context))
  if not range then
    vim.notify("No comparison base found; showing working-copy changes", vim.log.levels.INFO)
  end
  open_diff(context, range)
end

function M.upstream_patch()
  local context = require_context()
  if not context then
    return
  end

  if context.kind == "git" then
    local base = git_upstream(context) or git_base(context)
    if not base then
      vim.notify("No upstream or default branch found; showing working-copy changes", vim.log.levels.INFO)
    end
    open_diff(context, revision_range(context.kind, base))
  elseif context.kind == "jj" then
    open_diff(context, "@-...@")
  else
    local path = p4_scope(context)
    if path then
      open_diff(context, nil, path)
    end
  end
end

function M.choose_base()
  local context = require_context()
  if not context then
    return
  end

  local default = revision_range(context.kind, remembered_base(context)) or ""
  vim.ui.input({
    prompt = ("%s compare revision/range: "):format(context.kind:upper()),
    default = default,
  }, function(choice)
    if not choice or vim.trim(choice) == "" then
      return
    end
    choice = vim.trim(choice)
    compare_bases[base_key(context)] = choice
    open_diff(context, revision_range(context.kind, choice))
  end)
end

function M.choose_adapter()
  local ok, lazy = pcall(require, "lazy")
  if ok then
    lazy.load({ plugins = { "diffview-plus.nvim" } })
  end

  local choices = {
    { label = "Auto detect", value = nil },
    { label = "Jujutsu", value = "jj" },
    { label = "Git", value = "git" },
    { label = "Perforce / G4", value = "p4" },
  }

  vim.ui.select(choices, {
    prompt = "Preferred VCS for this Neovim session",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if not choice then
      return
    end
    require("diffview.config").get_config().preferred_adapter = choice.value
    vim.notify("Diffview adapter: " .. choice.label)
  end)
end

function M.file_history()
  local path = current_file()
  if not path then
    return
  end
  local context = require_context()
  if context then
    local view = contextual_diffview(context)
    if context.kind == "p4" then
      enable_p4_history_compat()
      path = p4_depot_path(context, p4_filespec(path, { local_path = true }))
      if not path then
        return
      end
    end
    view.file_history(nil, history_args(context, path))
  end
end

function M.repo_history()
  local context = require_context()
  if context then
    local path
    local view = contextual_diffview(context)
    if context.kind == "p4" then
      enable_p4_history_compat()
      path = p4_scope(context)
      if not path then
        return
      end
      path = p4_depot_path(context, path)
      if not path then
        return
      end
    end
    view.file_history(nil, history_args(context, path))
  end
end

function M.refresh()
  local ok, lib = pcall(require, "diffview.lib")
  if ok and lib.get_current_view() then
    diffview().emit("refresh_files", { force = true })
  else
    vim.notify("Not currently in a Diffview", vim.log.levels.INFO)
  end
end

function M.worktree_file()
  local ok, lib = pcall(require, "diffview.lib")
  if not ok or not lib.get_current_view() then
    vim.notify("Not currently in a Diffview", vim.log.levels.INFO)
    return
  end
  require("diffview.actions").goto_file_edit_close()
end

function M.close()
  diffview().close(nil, { force = false })
end

local function jj_copy_range(base)
  if not base or base == "" then
    return "@-", "@"
  end

  local left, right = base:match("^(.-)%.%.%.(.*)$")
  if left then
    left = left ~= "" and left or "@"
    right = right ~= "" and right or "@"
    return ("latest(fork_point((%s) | (%s)), 1)"):format(left, right), right
  end

  left, right = base:match("^(.-)%.%.(.-)$")
  if left then
    return left ~= "" and left or "@", right ~= "" and right or "@"
  end
  return base, "@"
end

function M.copy_diff()
  local context = require_context()
  if not context then
    return
  end

  local base = remembered_base(context)
  local command
  local ok, output, err
  if context.kind == "git" then
    local range = revision_range(context.kind, base)
    if range then
      command = { "git", "diff" }
      table.insert(command, range)
      table.insert(command, "--")
    else
      ok, output, err = git_working_copy_diff(context)
    end
  elseif context.kind == "jj" then
    local from, to = jj_copy_range(revision_range(context.kind, base))
    command = { "jj", "diff", "--git", "--color=never", "--from", from, "--to", to }
  else
    local path = p4_scope(context)
    if not path then
      return
    end
    command = { context.command, "diff", "-du", path }
  end

  if command then
    local directory = context.kind == "p4" and context.directory or context.root
    ok, output, err = run(command, directory, {
      trim = false,
      remote = context.kind == "p4",
      timeout = operation_timeout(context.kind),
    })
  end
  if not ok then
    vim.notify(err ~= "" and err or "Unable to create diff", vim.log.levels.ERROR)
    return
  end
  if output == "" then
    vim.notify("There are no changes to copy", vim.log.levels.INFO)
    return
  end

  -- Always keep a usable copy inside Neovim. Minimal/headless Linux installs
  -- often have no xclip/wl-copy provider, in which case writing only to "+"
  -- reports an error and silently leaves the user with an empty register.
  vim.fn.setreg('"', output)
  local has_system_clipboard = vim.fn.has("clipboard") == 1
  if has_system_clipboard then
    vim.fn.setreg("+", output)
  end
  local _, newlines = output:gsub("\n", "\n")
  local lines = newlines + (output:sub(-1) == "\n" and 0 or 1)
  local destination = has_system_clipboard and "clipboard" or "Neovim register (system clipboard unavailable)"
  vim.notify(("Copied %s diff (%d lines) to %s"):format(context.kind:upper(), lines, destination))
end

function M.info()
  local context, err = resolve_context()
  if not context then
    local message = "VCS: none detected"
    if err and err:find("timed out", 1, true) then
      message = message .. " (" .. err .. ")"
    end
    vim.notify(message)
    return
  end

  local base = remembered_base(context)
  local details = { "VCS: " .. context.kind:upper(), "root: " .. context.root }
  if base then
    table.insert(details, "compare base: " .. base)
  end
  if context.kind == "p4" then
    table.insert(details, "command: " .. context.command)
    table.insert(details, "scope: " .. p4_scope(context))
  end
  vim.notify(table.concat(details, "\n"))
end

-- Call from Diffview's plugin setup so raw :DiffviewOpen,
-- :DiffviewFileHistory, and restored sessions receive the same P4 fixes
-- before their first adapter is created.
function M.setup_diffview()
  enable_p4_adapter_compat()
end

return M
