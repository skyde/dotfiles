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
---@field status string  one of M A D R C U ?
---@field orig string|nil  pre-rename path, when status is R
---@field rev string|nil  per-file base revision, when the backend tracks one (p4's haveRev)
---@field stats {add: integer, del: integer}|nil  line churn, filled in lazily by the UI's stats pass

---@class VcsBackend
---@field name string
---@field bin string
---@field root fun(dir: string): string|nil
---@field rev fun(root: string, scope: string): string  never nil: every backend falls back to a literal ref when the lookup fails
---@field changed fun(root: string, rev: string): VcsFile[]
---@field show fun(root: string, rev: string, path: string): string[]|nil
---@field raw_diff fun(root: string, rev: string, path: string|nil, orig: string|nil): string
---@field log fun(root: string, path: string): table[]
---@field revert fun(root: string, rev: string, file: VcsFile): boolean|nil
---@field staged fun(root: string, path: string, orig: string|nil): boolean|nil
---@field stage fun(root: string, path: string, orig: string|nil): boolean|nil
---@field unstage fun(root: string, path: string, orig: string|nil): boolean|nil

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
local function sh(cmd, cwd)
  if vim.fn.executable(cmd[1]) ~= 1 then
    return nil
  end
  local co = coroutine.running()
  if co and async_threads[co] then
    local ok = pcall(vim.system, cmd, { cwd = cwd, text = true }, function(res)
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
    return vim.system(cmd, { cwd = cwd, text = true }):wait()
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

function git.rev(root, scope)
  if scope == "branch" then
    -- No trunk to fork from (a fresh repo, or trunk *is* the branch) still has
    -- a sensible answer: everything since the first commit is not useful, so
    -- fall back to HEAD and let it read as "uncommitted".
    return git_fork_point(root) or one(sh({ "git", "rev-parse", "--verify", "--quiet", "HEAD" }, root)) or "HEAD"
  end
  local ref = scope == "head" and "HEAD~1" or "HEAD"
  -- Resolved to the hash, not left symbolic: cached base content is keyed by
  -- this string, and "HEAD" would keep meaning the old content after a
  -- commit, amend or rebase moved it.
  return one(sh({ "git", "rev-parse", "--verify", "--quiet", ref }, root)) or ref
end

---Split NUL-separated output into fields, dropping the trailing empty one.
---@param s string|nil
---@return string[]
local function nul_fields(s)
  if not s or s == "" then
    return {}
  end
  local out = vim.split(s, "\0", { plain = true })
  while #out > 0 and out[#out] == "" do
    table.remove(out)
  end
  return out
end

---The names git writes into the git directory while a merge, rebase or
---cherry-pick is unfinished. Checked as files rather than by asking git,
---because this runs on every listing refresh and `git diff --diff-filter=U`
---costs a third of a second on a large tree — worth paying during a conflict,
---not worth paying the rest of the time.
local CONFLICT_MARKERS =
  { "MERGE_HEAD", "REBASE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply" }

local function git_conflict_in_progress(root)
  local dot = root .. "/.git"
  local stat = vim.uv.fs_stat(dot)
  if not stat then
    return false
  end
  if stat.type ~= "directory" then
    -- A linked worktree or a submodule: `.git` is a file pointing elsewhere, so
    -- the markers are not here and only git knows where they are.
    dot = one(sh({ "git", "rev-parse", "--absolute-git-dir" }, root))
    if not dot then
      return false
    end
  end
  for _, marker in ipairs(CONFLICT_MARKERS) do
    if vim.uv.fs_stat(dot .. "/" .. marker) then
      return true
    end
  end
  return false
end

function git.changed(root, rev)
  local out = {}
  local seen = {}

  -- Unmerged paths, while a merge, rebase or cherry-pick is in flight. git
  -- reports a conflicted file as a plain modification in --name-status, so
  -- without this the one file that actually needs attention looks like every
  -- other one in the listing.
  local unmerged = {}
  if git_conflict_in_progress(root) then
    local res = sh({ "git", "diff", "--name-only", "--diff-filter=U", "-z" }, root)
    if res and res.code == 0 then
      for _, path in ipairs(nul_fields(res.stdout)) do
        unmerged[path] = true
      end
    end
  end

  ---@param path string
  ---@param status string
  ---@param orig string|nil
  local function add(path, status, orig)
    if path ~= "" and not seen[path] then
      seen[path] = true
      table.insert(out, { path = path, status = unmerged[path] and "U" or status, orig = orig })
    end
  end

  -- -z, not the default line output. Without it git wraps any path containing a
  -- tab, a double quote, a backslash or a control byte in quotes and C-escapes
  -- the inside — `core.quotepath=false` only turns off the octal escaping of
  -- *non-ASCII* bytes, not the quoting itself — so those files arrived with
  -- quotes and backslashes baked into the name and could not be opened at all.
  -- -z emits the fields raw, separated by NUL, which also makes a filename
  -- containing a newline parse correctly instead of splitting into two rows.
  local res = sh({ "git", "diff", "--name-status", "--find-renames", "-z", rev }, root)
  if res and res.code == 0 then
    local fields = nul_fields(res.stdout)
    local i = 1
    while i <= #fields do
      local status = fields[i]:sub(1, 1)
      if status == "R" or status == "C" then
        -- A rename or copy is three fields: status, old path, new path. The new
        -- path is what can be opened; the old one is where the base content has
        -- to be fetched from, or a rename diffs as a wholly added file.
        add(fields[i + 2] or "", status, fields[i + 1])
        i = i + 3
      else
        add(fields[i + 1] or "", status, nil)
        i = i + 2
      end
    end
  end
  local untracked = sh({ "git", "ls-files", "--others", "--exclude-standard", "-z" }, root)
  if untracked and untracked.code == 0 then
    for _, path in ipairs(nul_fields(untracked.stdout)) do
      add(path, "?", nil)
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

---git reads a path argument as a *pathspec*, where `*`, `?`, `[` and a leading
---`:` are syntax rather than filename characters. `git add -- "star*.txt"`
---stages every file the glob matches, not the one named that, and a file called
---`:notes.txt` cannot be named at all. `:(literal)` turns all of it off.
---@param path string repo-relative path
---@return string pathspec
local function git_path(path)
  return ":(literal)" .. path
end

function git.raw_diff(root, rev, path, orig)
  local cmd = { "git", "diff", "--no-color", "--find-renames", rev }
  if path then
    -- For a renamed file both paths must be in the pathspec, or the rename
    -- pair is split and the diff degenerates into a delete plus an add.
    vim.list_extend(cmd, { "--", git_path(path) })
    if orig then
      table.insert(cmd, git_path(orig))
    end
  end
  local res = sh(cmd, root)
  return res and res.stdout or ""
end

function git.log(root, path)
  local res = sh({
    "git",
    "log",
    "--follow",
    "--date=short",
    "--pretty=format:%H\t%ad\t%an\t%s",
    "--",
    git_path(path),
  }, root)
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

---Discard the local change to one file, restoring what `rev` had.
function git.revert(root, rev, file)
  if file.status == "A" then
    -- Added: there is nothing at `rev` to restore, so reverting means
    -- removing the file — from the index too, when it is staged.
    return ran(sh({ "git", "rm", "-fq", "--ignore-unmatch", "--", git_path(file.path) }, root))
  end
  if file.orig then
    -- A rename reverts as: drop the new path, resurrect the old one.
    sh({ "git", "rm", "-fq", "--ignore-unmatch", "--", git_path(file.path) }, root)
  end
  -- `checkout <rev> -- <path>` resets both the index and the working tree.
  return ran(sh({ "git", "checkout", rev, "--", git_path(file.orig or file.path) }, root))
end

function git.staged(root, path)
  local res = sh({ "git", "diff", "--cached", "--name-only", "--", git_path(path) }, root)
  -- Spelled out rather than `ran(res) and ...`: the short-circuit was correct,
  -- but nothing reading it (a checker included) can tell that ran() is what
  -- rules out the nil res dereferenced on the next line.
  if not (res and res.code == 0) then
    return false
  end
  return vim.trim(res.stdout or "") ~= ""
end

---A rename has to be staged as a pair. Adding only the new path leaves the old
---one still in the index, so what gets committed is a copy plus an untracked
---deletion rather than the move that was made.
function git.stage(root, path, orig)
  local cmd = { "git", "add", "--", git_path(path) }
  if orig then
    table.insert(cmd, git_path(orig))
  end
  return ran(sh(cmd, root))
end

function git.unstage(root, path, orig)
  local cmd = { "git", "restore", "--staged", "--", git_path(path) }
  if orig then
    table.insert(cmd, git_path(orig))
  end
  return ran(sh(cmd, root))
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

local JJ_STATUS = {
  modified = "M",
  added = "A",
  removed = "D",
  copied = "C",
  renamed = "R",
}

---One entry per changed file as four NUL-separated fields: status, the path
---before the change, the path after it, and whether the result is a conflict.
---The last costs nothing here — jj already knows, and asking separately would
---mean another snapshotting command on every refresh.
local JJ_DIFF_TEMPLATE = 'status ++ "\\0" ++ source.path() ++ "\\0" ++ path ++ "\\0" ++ target.conflict() ++ "\\0"'

---Whether the installed jj understands `jj diff -T`. Probed once, and only
---turned off when the template call fails where `--summary` succeeds — a
---failure both ways is the revision's fault, not the template's.
local jj_templates = true

---Undo jj's compacted rename rendering: `--summary` prints the pair as
---`deep/{a => b}/file.txt`, sharing whatever prefix and suffix the two paths
---have in common.
---@param s string
---@return string|nil orig, string path
local function jj_unbrace(s)
  local pre, old, new, post = s:match("^(.-){(.-) => (.-)}(.*)$")
  if not pre then
    return nil, s
  end
  return pre .. old .. post, pre .. new .. post
end

function jj.changed(root, rev)
  local out = {}
  local seen = {}
  ---@param path string
  ---@param status string
  ---@param orig string|nil
  local function add(path, status, orig)
    if path ~= "" and not seen[path] then
      seen[path] = true
      table.insert(out, { path = path, status = status, orig = orig })
    end
  end

  -- The template, not `--summary`, because a rename has to come back as two
  -- separate paths: the old one is what the base content is read from, and
  -- `--summary` fuses the pair into a single `{old => new}` string that no
  -- filename containing `{` or ` => ` can be recovered from.
  if jj_templates then
    local res = sh(jj_cmd("diff", "--from", rev, "--to", "@", "-T", JJ_DIFF_TEMPLATE), root)
    if res and res.code == 0 then
      local fields = nul_fields(res.stdout)
      for i = 1, #fields - 3, 4 do
        local status, source, path, conflict = fields[i], fields[i + 1], fields[i + 2], fields[i + 3]
        -- jj repeats the path in both slots unless the file moved, so a
        -- differing source *is* the pre-rename path.
        local mapped = conflict == "true" and "U" or JJ_STATUS[status] or status:sub(1, 1):upper()
        add(path, mapped, source ~= path and source or nil)
      end
      return out
    end
  end

  local res = sh(jj_cmd("diff", "--summary", "--from", rev, "--to", "@"), root)
  if res and res.code == 0 then
    jj_templates = false
    for _, line in ipairs(lines(res.stdout)) do
      local status, rest = line:match("^(%a)%s+(.+)$")
      if status then
        local orig, path = jj_unbrace(rest)
        add(path, status:upper(), orig)
      end
    end
  end
  return out
end

---jj reads every path argument as a fileset *expression*, so `(`, `)`, `:`,
---`{`, `}` and `"` are syntax there rather than filename characters: a file
---called `report (1).pdf` is a parse error, not a path. The quoted `root:`
---literal form takes the path exactly as written, relative to the repo root.
---@param path string repo-relative path
---@return string fileset
local function jj_path(path)
  return 'root:"' .. path:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

function jj.show(root, rev, path)
  local res = sh(jj_read("file", "show", "-r", rev, jj_path(path)), root)
  if not res or res.code ~= 0 then
    return nil
  end
  return lines(res.stdout)
end

function jj.raw_diff(root, rev, path)
  local cmd = jj_cmd("diff", "--git", "--from", rev, "--to", "@")
  if path then
    -- No need to name the pre-rename path as git does: jj tracks the move
    -- itself, so scoping to the new path still yields the rename pair.
    table.insert(cmd, jj_path(path))
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
      "::@ & files(" .. jj_path(path) .. ")",
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
  local cmd = jj_cmd("restore", "--from", rev, jj_path(file.path))
  if file.orig then
    -- Naming only the new path leaves the rename half-undone: the new path
    -- goes away and the old one stays deleted. Naming both restores the pair.
    table.insert(cmd, jj_path(file.orig))
  end
  return ran(sh(cmd, root))
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

  ---`p4 opened` spells a rename `move/add` and `move/delete`, with a slash.
  ---This table had `move_add` in it, which matches nothing p4 has ever printed,
  ---so both halves of every `p4 move` fell through to "modified" — including
  ---the half that is no longer on disk, which then cannot be opened at all.
  local P4_STATUS = {
    edit = "M",
    add = "A",
    delete = "D",
    integrate = "M",
    branch = "A",
    ["move/add"] = "R",
    ["move/delete"] = "D",
    purge = "D",
    archive = "D",
  }

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

    local prefix = root:gsub("/*$", "") .. "/"
    local out = {}
    for _, rec in ipairs(opened) do
      local local_path = locals[rec.depotFile]
      if local_path then
        local rel = local_path
        if local_path:sub(1, #prefix) == prefix then
          rel = local_path:sub(#prefix + 1)
        end
        local status = P4_STATUS[rec.action or "edit"]
        -- The synced revision per file: "#have" as a base-cache key would keep
        -- meaning the old content after a sync, "#12" cannot.
        local rev = rec.haveRev and rec.haveRev ~= "none" and ("#" .. rec.haveRev) or nil
        table.insert(out, { path = rel, status = status or "M", depot = rec.depotFile, rev = rev })
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

---@param root string
---@param revset string
---@return string|nil
local function hg_node(root, revset)
  return one(sh({ "hg", "log", "-r", revset, "--template", "{node}" }, root))
end

---Where this line of work forked from trunk. hg's own notion is the named
---branch, but plenty of repositories drive bookmarks instead, so try the usual
---names in turn. An unknown name makes hg abort, which reads as nil here.
local function hg_fork_point(root)
  local current = hg_node(root, ".")
  for _, ref in ipairs({ "default", "main", "master" }) do
    local base = hg_node(root, ("ancestor(., %s)"):format(ref))
    -- Equal to `.` means trunk *is* what is checked out, and comparing against
    -- it would report no changes rather than the branch's work.
    if base and base ~= current then
      return base
    end
  end
  return nil
end

function hg.rev(root, scope)
  if scope == "branch" then
    -- Without this, branch scope silently answered the same as uncommitted:
    -- cycling to it in the panel looked like the branch had no committed work.
    return hg_fork_point(root) or hg_node(root, ".") or "."
  end
  local ref = scope == "head" and ".^" or "."
  -- Resolved to the node for the same reason git resolves "HEAD".
  return hg_node(root, ref) or ref
end

---Mercurial's status letters are not this interface's. `R` means removed, not
---renamed, and `!` is a tracked file deleted without telling hg — both are
---deletions here. Anything absent from this table (`C` clean, `I` ignored,
---which only appear with flags we do not pass) is not a change.
local HG_STATUS = {
  M = "M",
  A = "A",
  R = "D",
  ["!"] = "D",
  ["?"] = "?",
}

---Paths hg still calls unresolved, while an uncommitted merge is in progress.
---`hg status` reports a conflicted file as an ordinary modification, so without
---this the file that needs resolving looks like every other one. Gated on the
---merge state directory existing, so the extra command is paid during a merge
---and not on every refresh.
local function hg_unresolved(root)
  if not vim.uv.fs_stat(root .. "/.hg/merge") then
    return {}
  end
  local out = {}
  local res = sh({ "hg", "resolve", "--list" }, root)
  if res and res.code == 0 then
    for _, line in ipairs(lines(res.stdout)) do
      local path = line:match("^U (.+)$")
      if path then
        out[path] = true
      end
    end
  end
  return out
end

function hg.changed(root, rev)
  -- -C prints the source of a copied or renamed file on a continuation line
  -- under it. Without it a rename arrives as an unrelated add plus a delete, so
  -- the added half has no base content to diff against and reads as a wholly
  -- new file. -0 terminates each record with NUL rather than a newline, which
  -- is what keeps a filename containing one from splitting into two records.
  local unresolved = hg_unresolved(root)
  local res = sh({ "hg", "status", "-0", "-C", "--rev", rev }, root)
  local out = {}
  if res and res.code == 0 then
    for _, record in ipairs(nul_fields(res.stdout)) do
      -- Exactly one space after the code, not %s+: hg separates them with a
      -- single space, and a greedy match eats the leading spaces of a filename
      -- that has them.
      local status, path = record:match("^(%S) (.+)$")
      -- %S, not %a: `?` and `!` are status codes and neither is a letter, so a
      -- letters-only pattern silently dropped every untracked and every
      -- missing file instead of listing it.
      local mapped = status and HG_STATUS[status]
      if mapped then
        table.insert(out, { path = path, status = unresolved[path] and "U" or mapped })
      else
        local source = record:match("^  (.+)$")
        if source and out[#out] then
          out[#out].orig = source
        end
      end
    end
  end

  -- hg reports a rename as both halves; git and jj report it as one row on the
  -- new path. Match them: a source hg also lists as removed is a rename and the
  -- removal row goes away, while a source still on disk is a copy.
  local removed = {}
  for _, f in ipairs(out) do
    if f.status == "D" then
      removed[f.path] = true
    end
  end
  local renamed_from = {}
  for _, f in ipairs(out) do
    if f.orig then
      f.status = removed[f.orig] and "R" or "C"
      if f.status == "R" then
        renamed_from[f.orig] = true
      end
    end
  end
  return vim.tbl_filter(function(f)
    return not (f.status == "D" and renamed_from[f.path])
  end, out)
end

---hg reads a path argument as a *pattern*, and a leading `glob:`, `re:`,
---`set:`, `listfile:` and friends select the pattern type — so a file actually
---named `set:notes.txt` resolves to a fileset expression instead. `path:` says
---"this is a literal path from the repository root", which is what these all
---have.
---@param path string repo-relative path
---@return string pattern
local function hg_path(path)
  return "path:" .. path
end

function hg.show(root, rev, path)
  local res = sh({ "hg", "cat", "--rev", rev, hg_path(path) }, root)
  if not res or res.code ~= 0 then
    return nil
  end
  return lines(res.stdout)
end

function hg.raw_diff(root, rev, path)
  local cmd = { "hg", "diff", "--rev", rev }
  if path then
    table.insert(cmd, hg_path(path))
  end
  local res = sh(cmd, root)
  return res and res.stdout or ""
end

function hg.log(root, path)
  local res = sh({
    "hg",
    "log",
    "--template",
    "{node}\\t{date|shortdate}\\t{author|person}\\t{desc|firstline}\\n",
    hg_path(path),
  }, root)
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
  local cmd = { "hg", "revert", "--no-backup", "-r", rev, hg_path(file.path) }
  if file.orig then
    -- The same pairing git and jj need: undoing a rename has to bring the old
    -- path back, not merely take the new one away.
    table.insert(cmd, hg_path(file.orig))
  end
  return ran(sh(cmd, root))
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
