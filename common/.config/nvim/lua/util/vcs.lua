-- Version-control abstraction.
--
-- The diff UI in util.vcs_ui is written against this interface, so `<leader>gc`
-- and friends behave identically whether the repository is git, jj, Perforce
-- (p4 / g4) or Mercurial. Every backend answers the same four questions:
--
--   root(dir)               where does this repository start?
--   rev(root, scope)        which revision does "uncommitted" / "branch" mean?
--   changed(root, rev)      which files differ between that revision and now?
--   show(root, rev, path)   what did one file look like at that revision?
--
-- plus two conveniences used by the "give me the whole patch" keys:
--
--   raw_diff(root, rev, path)   unified diff text
--   log(root, path)             revisions touching a path
--
-- and optional per-file actions, present where the backend can honour them:
--
--   revert(root, rev, file)      discard the local change to one file
--   staged / stage / unstage     git's index; absent everywhere else
--
-- Scopes are deliberately only three, matching how the VS Code setup framed
-- them: `working` (what git calls uncommitted), `branch` (everything since the
-- fork point with trunk) and `head` (the tip commit's own change).

local M = {}

---@class VcsFile
---@field path string  repo-relative path
---@field status string  one of M A D R ? C
---@field orig string|nil  pre-rename path, when status is R
---@field rev string|nil  per-file base revision, when the backend tracks one (p4's haveRev)
---@field stats {add: integer, del: integer}|nil  line churn, filled in lazily by the UI's stats pass

---@class VcsBackend
---@field name string
---@field bin string
---@field root fun(dir: string): string|nil
---@field rev fun(root: string, scope: string): string|nil
---@field changed fun(root: string, rev: string): VcsFile[]
---@field show fun(root: string, rev: string, path: string): string[]|nil
---@field raw_diff fun(root: string, rev: string, path: string|nil, orig: string|nil): string
---@field log fun(root: string, path: string): table[]
---@field revert fun(root: string, rev: string, file: VcsFile): boolean|nil
---@field staged fun(root: string, path: string): boolean|nil
---@field stage fun(root: string, path: string): boolean|nil
---@field unstage fun(root: string, path: string): boolean|nil

--------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------

---Coroutines created by M.async. Inside one of these, sh() suspends while its
---subprocess runs instead of blocking the editor.
local async_threads = setmetatable({}, { __mode = "k" })

local function resume(co, ...)
  local ok, err = coroutine.resume(co, ...)
  if not ok then
    vim.notify("vcs: " .. tostring(err), vim.log.levels.ERROR)
  end
end

---Run a command and return the completed vim.system result, or nil if the
---binary is missing entirely. Callers check `.code` themselves; a non-zero exit
---is normal (e.g. `git show` on a path that did not exist at that revision).
---
---Blocking by default. Inside an M.async coroutine the same call yields while
---the subprocess runs, so every backend works asynchronously without a second
---callback-shaped implementation of itself.
---@param cmd string[]
---@param cwd string|nil
---@param stdin string|nil  written and closed; nil leaves stdin alone
local function sh(cmd, cwd, stdin)
  if vim.fn.executable(cmd[1]) ~= 1 then
    return nil
  end
  local co = coroutine.running()
  if co and async_threads[co] then
    local ok = pcall(vim.system, cmd, { cwd = cwd, text = true, stdin = stdin }, function(res)
      -- on_exit arrives off the main loop; API calls are only legal back on it.
      vim.schedule(function()
        resume(co, res)
      end)
    end)
    if not ok then
      return nil
    end
    return coroutine.yield()
  end
  local ok, res = pcall(function()
    return vim.system(cmd, { cwd = cwd, text = true, stdin = stdin }):wait()
  end)
  if not ok then
    return nil
  end
  return res
end

---Run `fn` on a coroutine where every backend call yields to the event loop
---while its subprocess runs, instead of freezing the UI. `fn` still executes on
---the main thread between calls and may use the API freely; it just has to
---tolerate the world having changed across any backend call.
---@param fn fun()
function M.async(fn)
  local co = coroutine.create(fn)
  async_threads[co] = true
  resume(co)
end

---Split command output into lines, dropping the trailing blank that every
---well-behaved CLI leaves behind.
---@param s string|nil
---@return string[]
local function lines(s)
  if not s or s == "" then
    return {}
  end
  local out = vim.split((s:gsub("\r\n", "\n")), "\n", { plain = true })
  while #out > 0 and out[#out] == "" do
    table.remove(out)
  end
  return out
end

---First line of output, trimmed. nil when the command failed or said nothing.
---@param res table|nil
local function one(res)
  if not res or res.code ~= 0 then
    return nil
  end
  local l = lines(res.stdout)[1]
  if not l then
    return nil
  end
  l = vim.trim(l)
  return l ~= "" and l or nil
end

---Did a command run and succeed? For the action-shaped backend calls, where
---the caller only needs pass/fail.
---@param res table|nil
local function ran(res)
  return res ~= nil and res.code == 0
end

---Walk up from `dir` looking for any of `markers`; return the containing dir.
---@param dir string
---@param markers string[]
local function find_up(dir, markers)
  local found = vim.fs.find(markers, { path = dir, upward = true, limit = 1 })
  if found and found[1] then
    return vim.fs.dirname(found[1])
  end
  return nil
end

--------------------------------------------------------------------------
-- git
--------------------------------------------------------------------------

local git = { name = "git", bin = "git" }

function git.root(dir)
  return one(sh({ "git", "rev-parse", "--show-toplevel" }, dir))
end

---The commit this branch forked from, preferring the configured upstream and
---falling back through the usual trunk names. `--fork-point` handles the case
---where trunk was rebased out from under the branch; plain `merge-base` is the
---answer when it does not (it returns nothing rather than erroring).
local function git_fork_point(root)
  local candidates = {}
  local upstream = one(sh({ "git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}" }, root))
  if upstream then
    table.insert(candidates, upstream)
  end
  local head = one(sh({ "git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD" }, root))
  if head then
    table.insert(candidates, head)
  end
  vim.list_extend(candidates, { "origin/main", "origin/master", "main", "master" })

  local current = one(sh({ "git", "branch", "--show-current" }, root))
  for _, ref in ipairs(candidates) do
    if ref ~= current and one(sh({ "git", "rev-parse", "--verify", "--quiet", ref .. "^{commit}" }, root)) then
      local base = one(sh({ "git", "merge-base", "--fork-point", ref, "HEAD" }, root))
        or one(sh({ "git", "merge-base", ref, "HEAD" }, root))
      if base then
        return base
      end
    end
  end
  return nil
end

---Git's own name for "nothing was there": the empty tree. It is what the very
---first commit has to be diffed against, and the only base a repository with
---no commits at all can offer. Asked for rather than hard-coded, because a
---SHA-256 repository's empty tree has a different id.
local function git_empty_tree(root)
  return one(sh({ "git", "hash-object", "-t", "tree", "--stdin" }, root, ""))
end

function git.rev(root, scope)
  if scope == "branch" then
    -- No trunk to fork from (a fresh repo, or trunk *is* the branch) still has
    -- a sensible answer: everything since the first commit is not useful, so
    -- fall back to HEAD and let it read as "uncommitted".
    return git_fork_point(root)
      or one(sh({ "git", "rev-parse", "--verify", "--quiet", "HEAD" }, root))
      or git_empty_tree(root)
      or "HEAD"
  end
  local ref = scope == "head" and "HEAD~1" or "HEAD"
  -- Resolved to the hash, not left symbolic: cached base content is keyed by
  -- this string, and "HEAD" would keep meaning the old content after a
  -- commit, amend or rebase moved it.
  --
  -- When the ref does not resolve — "last commit" on a repository whose only
  -- commit is the first one, any scope before there is a commit at all — the
  -- literal string is worse than useless: no git command accepts "HEAD~1", so
  -- the listing came back empty and the view said "no changes" about a commit
  -- that is right there. The empty tree is the honest base, and it renders
  -- the whole thing as added, which is what it is.
  return one(sh({ "git", "rev-parse", "--verify", "--quiet", ref }, root)) or git_empty_tree(root) or ref
end

function git.changed(root, rev)
  local out = {}
  local seen = {}
  local res = sh({ "git", "-c", "core.quotepath=false", "diff", "--name-status", "--find-renames", rev }, root)
  if res and res.code == 0 then
    for _, line in ipairs(lines(res.stdout)) do
      local status, path = line:match("^(%a)%d*\t(.+)$")
      if status then
        -- Renames arrive as "R100\told\tnew". The new path is what we can
        -- open; the old one is what the base content has to be fetched as,
        -- otherwise a rename diffs as a wholly added file.
        local old, new = path:match("^(.-)\t(.+)$")
        path = new or path
        if not seen[path] then
          seen[path] = true
          table.insert(out, { path = path, status = status, orig = old })
        end
      end
    end
  end
  local untracked = sh({ "git", "-c", "core.quotepath=false", "ls-files", "--others", "--exclude-standard" }, root)
  if untracked and untracked.code == 0 then
    for _, path in ipairs(lines(untracked.stdout)) do
      if not seen[path] then
        seen[path] = true
        table.insert(out, { path = path, status = "?" })
      end
    end
  end
  return out
end

function git.show(root, rev, path)
  local res = sh({ "git", "show", rev .. ":" .. path }, root)
  if not res or res.code ~= 0 then
    return nil
  end
  return lines(res.stdout)
end

function git.raw_diff(root, rev, path, orig)
  local cmd = { "git", "diff", "--no-color", "--find-renames", rev }
  if path then
    -- For a renamed file both paths must be in the pathspec, or the rename
    -- pair is split and the diff degenerates into a delete plus an add.
    vim.list_extend(cmd, { "--", path })
    if orig then
      table.insert(cmd, orig)
    end
  end
  local res = sh(cmd, root)
  return res and res.stdout or ""
end

function git.log(root, path)
  local res = sh({
    "git",
    "-c",
    "core.quotepath=false",
    "log",
    "--follow",
    "--date=short",
    "--pretty=format:%H\t%ad\t%an\t%s",
    -- `--follow` walks through renames, so half the revisions it returns
    -- describe the file under a name it no longer has. --name-only says which
    -- one, which is what `git show <rev>:<path>` needs to find the content.
    "--name-only",
    "--",
    path,
  }, root)
  local out = {}
  if res and res.code == 0 then
    local current
    for _, line in ipairs(lines(res.stdout)) do
      -- The commit line is the only one with the format's three tabs; a
      -- --name-only path never has any.
      local rev, date, author, subject = line:match("^(%x+)\t(%S+)\t(.-)\t(.*)$")
      if rev then
        current = { rev = rev, date = date, author = author, subject = subject, path = path }
        table.insert(out, current)
      elseif current and line ~= "" then
        current.path = line
        current = nil
      end
    end
  end
  return out
end

---Discard the local change to one file, restoring what `rev` had.
function git.revert(root, rev, file)
  if file.status == "A" then
    -- Added: there is nothing at `rev` to restore, so reverting means
    -- removing the file — from the index too, when it is staged.
    return ran(sh({ "git", "rm", "-fq", "--ignore-unmatch", "--", file.path }, root))
  end
  if file.orig then
    -- A rename reverts as: drop the new path, resurrect the old one.
    sh({ "git", "rm", "-fq", "--ignore-unmatch", "--", file.path }, root)
  end
  -- `checkout <rev> -- <path>` resets both the index and the working tree.
  return ran(sh({ "git", "checkout", rev, "--", file.orig or file.path }, root))
end

function git.staged(root, path)
  local res = sh({ "git", "diff", "--cached", "--name-only", "--", path }, root)
  return ran(res) and vim.trim(res.stdout or "") ~= ""
end

function git.stage(root, path)
  return ran(sh({ "git", "add", "--", path }, root))
end

function git.unstage(root, path)
  return ran(sh({ "git", "restore", "--staged", "--", path }, root))
end

--------------------------------------------------------------------------
-- jj
--------------------------------------------------------------------------

local jj = { name = "jj", bin = "jj" }

---Calls that ask "what does the working copy look like right now" must let jj
---snapshot first. In jj the working copy *is* a commit, and `jj status` /
---`jj diff` snapshot as a matter of course; suppressing it means `<leader>gc`
---reports whatever the last snapshot said and silently misses every edit made
---since. That is a correctness bug, not a courtesy.
local function jj_cmd(...)
  return vim.list_extend({ "jj", "--color=never", "--quiet" }, { ... })
end

---Calls that only read committed history do not need a snapshot, and skipping
---it keeps scrubbing the file list from spawning a snapshot per keystroke.
local function jj_read(...)
  return vim.list_extend({ "jj", "--ignore-working-copy", "--color=never", "--quiet" }, { ... })
end

function jj.root(dir)
  return one(sh(jj_read("root"), dir))
end

function jj.rev(root, scope)
  local ref
  if scope == "branch" then
    -- The newest ancestor of @ that is also on trunk. With no remote bookmarks
    -- configured, trunk() degrades to the root commit, and diffing against the
    -- root reports the entire repository as added — so treat the all-zeros id
    -- as "no trunk here" and fall back to the parent commit.
    local base = one(sh(jj_read("log", "--no-graph", "-r", "latest(::@ & trunk())", "-T", "commit_id"), root))
    if base and not base:match("^0+$") then
      return base
    end
    ref = "@-"
  else
    ref = scope == "head" and "@--" or "@-"
  end
  -- Resolved to the commit id for the same reason git resolves "HEAD": cached
  -- base content keyed by "@-" would survive the parent commit moving.
  return one(sh(jj_read("log", "--no-graph", "-r", ref, "-T", "commit_id"), root)) or ref
end

function jj.changed(root, rev)
  local res = sh(jj_cmd("diff", "--summary", "--from", rev, "--to", "@"), root)
  local out = {}
  if res and res.code == 0 then
    for _, line in ipairs(lines(res.stdout)) do
      local status, path = line:match("^(%a)%s+(.+)$")
      if status then
        table.insert(out, { path = path, status = status:upper() })
      end
    end
  end
  return out
end

function jj.show(root, rev, path)
  local res = sh(jj_read("file", "show", "-r", rev, path), root)
  if not res or res.code ~= 0 then
    return nil
  end
  return lines(res.stdout)
end

function jj.raw_diff(root, rev, path)
  local cmd = jj_cmd("diff", "--git", "--from", rev, "--to", "@")
  if path then
    table.insert(cmd, path)
  end
  local res = sh(cmd, root)
  return res and res.stdout or ""
end

function jj.log(root, path)
  local res = sh(
    jj_cmd(
      "log",
      "--no-graph",
      "-r",
      "::@ & files(" .. string.format("%q", path) .. ")",
      "-T",
      'commit_id ++ "\t" ++ committer.timestamp().format("%Y-%m-%d") ++ "\t" ++ author.name() ++ "\t" ++ description.first_line() ++ "\n"'
    ),
    root
  )
  local out = {}
  if res and res.code == 0 then
    for _, line in ipairs(lines(res.stdout)) do
      local rev, date, author, subject = line:match("^(%S+)\t(%S+)\t(.-)\t(.*)$")
      if rev then
        table.insert(out, { rev = rev, date = date, author = author, subject = subject })
      end
    end
  end
  return out
end

---One command covers every status: restoring from a revision that lacks the
---file deletes it, which is exactly what reverting an add should do.
function jj.revert(root, rev, file)
  return ran(sh(jj_cmd("restore", "--from", rev, file.path), root))
end

--------------------------------------------------------------------------
-- Perforce (p4, and Google's g4 wrapper which speaks the same CLI)
--------------------------------------------------------------------------

---Build a Perforce backend around whichever client binary exists.
---@param bin string
local function perforce(bin)
  local p4 = { name = bin, bin = bin }

  ---`p4 -ztag` emits "... key value" lines; collect them into records, one per
  ---blank-line-separated block.
  local function ztag(args, cwd)
    local res = sh(vim.list_extend({ bin, "-ztag" }, args), cwd)
    if not res or res.code ~= 0 then
      return {}
    end
    local records, current = {}, {}
    for _, line in ipairs(lines(res.stdout)) do
      local key, value = line:match("^%.%.%. (%S+) (.*)$")
      if key then
        if current[key] then
          table.insert(records, current)
          current = {}
        end
        current[key] = value
      elseif line == "" and next(current) then
        table.insert(records, current)
        current = {}
      end
    end
    if next(current) then
      table.insert(records, current)
    end
    return records
  end

  p4.ztag = ztag

  function p4.root(dir)
    -- A P4CONFIG file is the cheap, offline answer and is what most workspaces
    -- have. Asking the server is the fallback, and only pays off inside a real
    -- client, so a missing/blank clientRoot means "not a Perforce tree".
    local cfg = vim.env.P4CONFIG
    if cfg and cfg ~= "" then
      local found = find_up(dir, { cfg })
      if found then
        return found
      end
    end
    local info = ztag({ "info" }, dir)[1]
    local root = info and info.clientRoot
    if root and root ~= "" and root ~= "null" then
      return root
    end
    return nil
  end

  function p4.rev(_, scope)
    -- Perforce has no branch-vs-trunk notion that maps cleanly here; every
    -- scope compares against the synced ("have") revision of each file.
    return scope == "head" and "#head" or "#have"
  end

  function p4.changed(root, _)
    local opened = ztag({ "opened" }, root)
    local depots = {}
    for _, rec in ipairs(opened) do
      if rec.depotFile then
        table.insert(depots, rec.depotFile)
      end
    end
    if #depots == 0 then
      return {}
    end

    -- One `where` for the whole changelist. Asking per file meant a server
    -- round trip each, so a few hundred opened files took as many seconds.
    local locals = {}
    local where_args = vim.list_extend({ "where" }, depots)
    for _, rec in ipairs(ztag(where_args, root)) do
      if rec.depotFile and rec.path then
        locals[rec.depotFile] = rec.path
      end
    end

    -- `p4 opened` spells the move actions with a slash, not an underscore.
    -- `move/delete` is the other half of a rename; the pair is already listed
    -- under its new path, so showing the old one too would double-count it.
    local ACTIONS = {
      edit = "M",
      add = "A",
      delete = "D",
      integrate = "M",
      branch = "A",
      ["move/add"] = "R",
    }

    local prefix = root:gsub("/*$", "") .. "/"
    local out = {}
    for _, rec in ipairs(opened) do
      local local_path = locals[rec.depotFile]
      local action = rec.action or "edit"
      if local_path and action ~= "move/delete" then
        local rel = local_path
        if local_path:sub(1, #prefix) == prefix then
          rel = local_path:sub(#prefix + 1)
        end
        -- The synced revision per file: "#have" as a base-cache key would keep
        -- meaning the old content after a sync, "#12" cannot.
        local rev = rec.haveRev and rec.haveRev ~= "none" and ("#" .. rec.haveRev) or nil
        table.insert(out, { path = rel, status = ACTIONS[action] or "M", depot = rec.depotFile, rev = rev })
      end
    end
    return out
  end

  function p4.show(root, rev, path)
    local res = sh({ bin, "print", "-q", path .. rev }, root)
    if not res or res.code ~= 0 then
      return nil
    end
    return lines(res.stdout)
  end

  function p4.raw_diff(root, _, path)
    local cmd = { bin, "diff", "-du10" }
    if path then
      table.insert(cmd, path)
    end
    local res = sh(cmd, root)
    return res and res.stdout or ""
  end

  function p4.log(root, path)
    local out = {}
    for _, rec in ipairs(ztag({ "filelog", "-l", path }, root)) do
      local i = 0
      while rec["rev" .. i] do
        table.insert(out, {
          rev = "#" .. rec["rev" .. i],
          date = os.date("%Y-%m-%d", tonumber(rec["time" .. i]) or 0),
          author = rec["user" .. i] or "",
          subject = (rec["desc" .. i] or ""):gsub("\n.*", ""),
        })
        i = i + 1
      end
    end
    return out
  end

  function p4.revert(root, _, file)
    return ran(sh({ bin, "revert", file.path }, root))
  end

  return p4
end

--------------------------------------------------------------------------
-- mercurial
--------------------------------------------------------------------------

local hg = { name = "hg", bin = "hg" }

function hg.root(dir)
  return one(sh({ "hg", "root" }, dir))
end

function hg.rev(root, scope)
  local ref = scope == "head" and ".^" or "."
  -- Resolved to the node for the same reason git resolves "HEAD".
  return one(sh({ "hg", "log", "-r", ref, "--template", "{node}" }, root)) or ref
end

-- `hg status` letters, translated into the shared VcsFile vocabulary. Two of
-- them would be actively misleading left as-is: Mercurial's R means *removed*
-- (git's D), and the UI reads R as "renamed"; ! is a tracked file missing from
-- the working copy, which is a deletion as far as a diff is concerned. C
-- (clean) and I (ignored) never make it into a changed-file list.
local HG_STATUS = { M = "M", A = "A", R = "D", ["!"] = "D", ["?"] = "?" }

function hg.changed(root, rev)
  local res = sh({ "hg", "status", "--rev", rev }, root)
  local out = {}
  if res and res.code == 0 then
    for _, line in ipairs(lines(res.stdout)) do
      -- The status column is a single character, and it is not always a
      -- letter: untracked is "?" and missing is "!".
      local status, path = line:match("^(%S)%s+(.+)$")
      status = status and HG_STATUS[status:upper()]
      if status then
        table.insert(out, { path = path, status = status })
      end
    end
  end
  return out
end

function hg.show(root, rev, path)
  local res = sh({ "hg", "cat", "--rev", rev, path }, root)
  if not res or res.code ~= 0 then
    return nil
  end
  return lines(res.stdout)
end

function hg.raw_diff(root, rev, path)
  local cmd = { "hg", "diff", "--rev", rev }
  if path then
    table.insert(cmd, path)
  end
  local res = sh(cmd, root)
  return res and res.stdout or ""
end

function hg.log(root, path)
  local res =
    sh({ "hg", "log", "--template", "{node}\\t{date|shortdate}\\t{author|person}\\t{desc|firstline}\\n", path }, root)
  local out = {}
  if res and res.code == 0 then
    for _, line in ipairs(lines(res.stdout)) do
      local rev, date, author, subject = line:match("^(%S+)\t(%S+)\t(.-)\t(.*)$")
      if rev then
        table.insert(out, { rev = rev, date = date, author = author, subject = subject })
      end
    end
  end
  return out
end

---`hg revert` on an added file un-adds it and leaves it untracked, which is
---the closest Mercurial gets to discarding an add without deleting data.
function hg.revert(root, rev, file)
  local res = sh({ "hg", "revert", "--no-backup", "-r", rev, file.path }, root)
  return ran(res)
end

--------------------------------------------------------------------------
-- detection
--------------------------------------------------------------------------

-- jj comes before git on purpose: a colocated repo has both .jj and .git, and
-- in that case jj is the one the user is actually driving.
M.backends = {
  jj = jj,
  git = git,
  hg = hg,
  p4 = perforce("p4"),
  g4 = perforce("g4"),
}

local order = { "jj", "git", "hg", "g4", "p4" }

-- Detection shells out, so cache it. Keyed by the directory we asked about.
local cache = {}

function M.clear_cache()
  cache = {}
end

---Which VCS owns `dir`?
---@param dir string|nil defaults to the current buffer's directory
---@return VcsBackend|nil backend, string|nil root
function M.detect(dir)
  dir = dir or vim.fn.expand("%:p:h")
  if dir == "" or vim.fn.isdirectory(dir) == 0 then
    dir = vim.fn.getcwd()
  end

  local hit = cache[dir]
  if hit ~= nil then
    if hit == false then
      return nil, nil
    end
    return hit.backend, hit.root
  end

  local forced = vim.g.vcs_backend
  local names = forced and { forced } or order

  for _, name in ipairs(names) do
    local backend = M.backends[name]
    -- Cheap marker check first for the two that have one, so we do not spawn a
    -- p4 process in every plain directory on the machine.
    local skip = false
    if name == "jj" then
      skip = find_up(dir, { ".jj" }) == nil
    elseif name == "git" then
      skip = find_up(dir, { ".git" }) == nil
    elseif name == "hg" then
      skip = find_up(dir, { ".hg" }) == nil
    end
    if backend and not skip and vim.fn.executable(backend.bin) == 1 then
      local root = backend.root(dir)
      if root then
        cache[dir] = { backend = backend, root = root }
        return backend, root
      end
    end
  end

  cache[dir] = false
  return nil, nil
end

---Same as detect(), but reports the problem instead of returning nothing.
---@return VcsBackend|nil, string|nil
function M.require(dir)
  local backend, root = M.detect(dir)
  if not backend then
    vim.notify("No version control detected (tried jj, git, hg, g4, p4)", vim.log.levels.WARN)
    return nil, nil
  end
  return backend, root
end

---Path of the current buffer relative to the repo root, or nil when the buffer
---is not a real file inside it.
---@param root string
---@param buf integer|nil
function M.rel_path(root, buf)
  local name = vim.api.nvim_buf_get_name(buf or 0)
  if name == "" then
    return nil
  end
  local full = vim.fn.fnamemodify(name, ":p")
  local prefix = root:gsub("/*$", "") .. "/"
  if full:sub(1, #prefix) ~= prefix then
    return nil
  end
  return full:sub(#prefix + 1)
end

return M
