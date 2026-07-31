-- Run with: nvim --headless -u NONE -i NONE -l tests/nvim_vcs_spec.lua
--
-- Exercises the version-control backends in common/.config/nvim/lua/util/vcs.lua
-- against throwaway repositories. Perforce is covered by a stub `p4` binary that
-- speaks the real -ztag protocol, since there is no server to talk to in CI.

local source = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(repo .. "/common/.config/nvim")

local vcs = require("util.vcs")

local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")

local passed, failed = 0, 0
local failures = {}

local function check(name, ok, detail)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    table.insert(failures, name .. (detail and ("\n    " .. detail) or ""))
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

local function truthy(name, value, detail)
  check(name, value ~= nil and value ~= false, detail)
end

---Statuses keyed by path, so assertions do not depend on listing order.
local function status_map(files)
  local out = {}
  for _, f in ipairs(files) do
    out[f.path] = f.status
  end
  return out
end

local function run(cmd, cwd)
  local res = vim.system(cmd, { cwd = cwd, text = true }):wait()
  if res.code ~= 0 then
    error(string.format("%s failed in %s: %s", table.concat(cmd, " "), cwd, res.stderr or ""))
  end
  return res.stdout
end

local function write(path, text)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local fd = assert(io.open(path, "wb"))
  fd:write(text)
  fd:close()
end

--------------------------------------------------------------------------
-- git
--------------------------------------------------------------------------

local function git_env(dir)
  return { "git", "-c", "user.email=t@example.com", "-c", "user.name=Test", "-c", "commit.gpgsign=false" }, dir
end

local function git(dir, ...)
  local cmd = { "git", "-c", "user.email=t@example.com", "-c", "user.name=Test", "-c", "commit.gpgsign=false" }
  vim.list_extend(cmd, { ... })
  return run(cmd, dir)
end

local function build_git_repo()
  local root = temp .. "/git"
  vim.fn.mkdir(root, "p")
  git(root, "init", "-q", "-b", "main")
  write(root .. "/src/main.c", "int main(void) { return 0; }\n")
  write(root .. "/src/old name.c", "// a path with a space\n")
  write(root .. "/src/ünïcode.c", "// a path with non-ascii\n")
  write(root .. "/doomed.txt", "delete me\n")
  write(root .. "/deep/a/b/c/nested.txt", "nested\n")
  write(root .. "/renamed-from.txt", string.rep("stable content line\n", 20))
  write(root .. "/binary.bin", "\0\1\2\3\4binary\0")
  git(root, "add", "-A")
  git(root, "commit", "-qm", "initial")
  -- Stand in for a remote trunk so the fork-point logic has something to find.
  git(root, "update-ref", "refs/remotes/origin/main", "HEAD")
  git(root, "checkout", "-qb", "feature")

  -- One commit on the branch, so `branch` scope sees more than `working` does.
  write(root .. "/src/main.c", "int main(void) {\n  return 1;\n}\n")
  git(root, "add", "-A")
  git(root, "commit", "-qm", "branch commit")

  -- Uncommitted changes of every kind.
  write(root .. "/src/ünïcode.c", "// a path with non-ascii\n// edited\n")
  write(root .. "/src/old name.c", "// a path with a space\n// edited\n")
  vim.fn.delete(root .. "/doomed.txt")
  write(root .. "/added-staged.txt", "staged add\n")
  git(root, "add", "added-staged.txt")
  write(root .. "/untracked.txt", "untracked\n")
  git(root, "mv", "renamed-from.txt", "renamed-to.txt")
  return root
end

local git_root = build_git_repo()

do
  local b, root = vcs.detect(git_root)
  eq("git: detect from root", "git", b and b.name)
  eq("git: root path", vim.fn.resolve(git_root), vim.fn.resolve(root or ""))

  local nb = select(1, vcs.detect(git_root .. "/deep/a/b/c"))
  eq("git: detect from nested dir", "git", nb and nb.name)

  local none = select(1, vcs.detect(temp))
  eq("git: no backend outside a repo", nil, none and none.name)

  eq("git: rev(working)", "HEAD", b.rev(root, "working"))
  eq("git: rev(head)", "HEAD~1", b.rev(root, "head"))
  local fork = b.rev(root, "branch")
  truthy("git: rev(branch) resolves a sha", fork and fork:match("^%x%x%x%x%x%x%x"), tostring(fork))
  eq("git: rev(branch) is the merge base", vim.trim(git(git_root, "rev-parse", "origin/main")), fork)

  local working = status_map(b.changed(root, b.rev(root, "working")))
  eq("git: modified unicode path", "M", working["src/ünïcode.c"])
  eq("git: modified path with a space", "M", working["src/old name.c"])
  eq("git: deleted file", "D", working["doomed.txt"])
  eq("git: staged add", "A", working["added-staged.txt"])
  eq("git: untracked file", "?", working["untracked.txt"])
  eq("git: rename reports the new path", "R", working["renamed-to.txt"])
  eq("git: rename does not also report the old path", nil, working["renamed-from.txt"])

  -- The old path rides along on the record, so the diff UI can fetch the base
  -- content that actually existed instead of treating a rename as an add.
  local records = {}
  for _, f in ipairs(b.changed(root, b.rev(root, "working"))) do
    records[f.path] = f
  end
  eq("git: rename carries the old path", "renamed-from.txt", records["renamed-to.txt"] and records["renamed-to.txt"].orig)
  eq("git: a plain modification carries no old path", nil, records["src/ünïcode.c"] and records["src/ünïcode.c"].orig)
  local rename_patch = b.raw_diff(root, b.rev(root, "working"), "renamed-to.txt", "renamed-from.txt")
  truthy(
    "git: raw_diff given both paths reports a rename, not delete-plus-add",
    rename_patch:find("rename from renamed-from.txt", 1, true),
    rename_patch:sub(1, 200)
  )
  eq("git: unmodified file absent", nil, working["deep/a/b/c/nested.txt"])
  eq("git: working scope excludes the branch commit", nil, working["src/main.c"])

  local branch = status_map(b.changed(root, b.rev(root, "branch")))
  eq("git: branch scope includes the branch commit", "M", branch["src/main.c"])
  eq("git: branch scope still sees uncommitted work", "M", branch["src/ünïcode.c"])

  local show = b.show(root, b.rev(root, "branch"), "src/main.c")
  eq("git: show returns the base content", { "int main(void) { return 0; }" }, show)
  eq(
    "git: show handles a path with a space",
    { "// a path with a space" },
    b.show(root, b.rev(root, "branch"), "src/old name.c")
  )
  eq(
    "git: show handles a non-ascii path",
    { "// a path with non-ascii" },
    b.show(root, b.rev(root, "branch"), "src/ünïcode.c")
  )
  eq("git: show of an unknown path is nil", nil, b.show(root, "HEAD", "does/not/exist.c"))
  eq("git: show of a not-yet-committed file is nil", nil, b.show(root, b.rev(root, "branch"), "untracked.txt"))

  truthy("git: raw_diff produces a patch", #b.raw_diff(root, b.rev(root, "branch"), nil) > 0)
  local scoped = b.raw_diff(root, b.rev(root, "branch"), "src/main.c")
  truthy("git: raw_diff scoped to a path mentions it", scoped:find("src/main.c", 1, true))
  check("git: raw_diff scoped to a path excludes others", scoped:find("ünïcode", 1, true) == nil)

  local log = b.log(root, "src/main.c")
  eq("git: log has both commits", 2, #log)
  eq("git: log newest first", "branch commit", log[1] and log[1].subject)
  truthy("git: log parses a date", log[1] and log[1].date:match("^%d%d%d%d%-%d%d%-%d%d$"))
  eq("git: log parses the author", "Test", log[1] and log[1].author)
  -- An uncommitted rename has no commit containing the new path, so history is
  -- legitimately empty; --follow only helps once the rename is committed.
  eq("git: log of an uncommitted rename is empty", 0, #b.log(root, "renamed-to.txt"))
  git(git_root, "commit", "-qm", "commit the rename")
  local followed = b.log(root, "renamed-to.txt")
  truthy("git: log follows a committed rename back past it", #followed >= 2, vim.inspect(followed))

  -- rel_path is how every keymap turns the current buffer into a repo path.
  vim.cmd("edit " .. vim.fn.fnameescape(git_root .. "/src/main.c"))
  eq("git: rel_path of the current buffer", "src/main.c", vcs.rel_path(root))
  vim.cmd("enew")
  eq("git: rel_path of a nameless buffer is nil", nil, vcs.rel_path(root))
end

do
  -- A repository with no commits at all: HEAD does not resolve, and every call
  -- has to degrade instead of raising.
  local root = temp .. "/git-empty"
  vim.fn.mkdir(root, "p")
  git(root, "init", "-q", "-b", "main")
  write(root .. "/only.txt", "hello\n")
  local b = select(1, vcs.detect(root))
  eq("git empty: detected", "git", b and b.name)
  local ok_rev, rev = pcall(b.rev, root, "branch")
  check("git empty: rev does not raise", ok_rev, tostring(rev))
  local ok_changed, files = pcall(b.changed, root, rev or "HEAD")
  check("git empty: changed does not raise", ok_changed, tostring(files))
  eq("git empty: untracked file still listed", "?", ok_changed and status_map(files)["only.txt"])
  eq("git empty: show of a missing revision is nil", nil, b.show(root, "HEAD", "only.txt"))
end

do
  -- Detached HEAD: `git branch --show-current` is empty, which the fork-point
  -- candidate filter has to cope with.
  local root = temp .. "/git-detached"
  vim.fn.mkdir(root, "p")
  git(root, "init", "-q", "-b", "main")
  write(root .. "/a.txt", "one\n")
  git(root, "add", "-A")
  git(root, "commit", "-qm", "one")
  git(root, "update-ref", "refs/remotes/origin/main", "HEAD")
  write(root .. "/a.txt", "two\n")
  git(root, "add", "-A")
  git(root, "commit", "-qm", "two")
  git(root, "checkout", "-q", "--detach", "HEAD")
  local b = select(1, vcs.detect(root))
  local ok_rev, rev = pcall(b.rev, root, "branch")
  check("git detached: rev does not raise", ok_rev, tostring(rev))
  truthy("git detached: rev resolves", ok_rev and rev and #rev > 0)
end

--------------------------------------------------------------------------
-- jj
--------------------------------------------------------------------------

if vim.fn.executable("jj") == 1 then
  local root = temp .. "/jj"
  vim.fn.mkdir(root, "p")
  run({ "jj", "git", "init", "--quiet" }, root)
  write(root .. "/keep.txt", "base\n")
  write(root .. "/gone.txt", "will be deleted\n")
  write(root .. "/with space.txt", "spaced\n")
  run({ "jj", "--quiet", "describe", "-m", "initial" }, root)
  run({ "jj", "--quiet", "new", "-m", "wip" }, root)
  write(root .. "/keep.txt", "base\nedited\n")
  write(root .. "/fresh.txt", "added\n")
  vim.fn.delete(root .. "/gone.txt")

  local b, detected_root = vcs.detect(root)
  eq("jj: detected", "jj", b and b.name)
  eq("jj: root path", vim.fn.resolve(root), vim.fn.resolve(detected_root or ""))

  eq("jj: rev(working)", "@-", b.rev(detected_root, "working"))
  eq("jj: rev(head)", "@--", b.rev(detected_root, "head"))
  -- With no trunk configured, trunk() degrades to the root commit; falling back
  -- to @- is what keeps `branch` scope from reporting the whole repo as added.
  eq("jj: rev(branch) falls back to @- without a trunk", "@-", b.rev(detected_root, "branch"))

  local files = status_map(b.changed(detected_root, "@-"))
  eq("jj: modified", "M", files["keep.txt"])
  eq("jj: added", "A", files["fresh.txt"])
  eq("jj: deleted", "D", files["gone.txt"])
  eq("jj: untouched file absent", nil, files["with space.txt"])

  eq("jj: show returns base content", { "base" }, b.show(detected_root, "@-", "keep.txt"))
  eq("jj: show of a path with a space", { "spaced" }, b.show(detected_root, "@-", "with space.txt"))
  eq("jj: show of an unknown path is nil", nil, b.show(detected_root, "@-", "nope.txt"))

  local patch = b.raw_diff(detected_root, "@-", nil)
  truthy("jj: raw_diff is git-format", patch:find("diff --git", 1, true))
  truthy("jj: raw_diff scoped to a path", b.raw_diff(detected_root, "@-", "keep.txt"):find("keep.txt", 1, true))

  local log = b.log(detected_root, "keep.txt")
  truthy("jj: log returns revisions", #log >= 2)
  truthy("jj: log parses a date", log[1] and log[1].date:match("^%d%d%d%d%-%d%d%-%d%d$"))

  -- Regression: jj only sees the working copy after it snapshots, and passing
  -- --ignore-working-copy suppresses exactly that. An earlier version passed it
  -- on every call, so an edit made since the last jj command was invisible and
  -- the changed-files view reported "no changes" for work that was right there.
  -- Nothing below may run jj from the shell after the write.
  local fresh = temp .. "/jj-fresh"
  vim.fn.mkdir(fresh, "p")
  run({ "jj", "git", "init", "--quiet" }, fresh)
  write(fresh .. "/f.txt", "before\n")
  run({ "jj", "--quiet", "describe", "-m", "base" }, fresh)
  run({ "jj", "--quiet", "new", "-m", "wip" }, fresh)
  write(fresh .. "/f.txt", "before\nafter\n")
  local fb, froot = vcs.detect(fresh)
  eq("jj: an edit since the last jj command is visible", "M", status_map(fb.changed(froot, "@-"))["f.txt"])
  truthy("jj: that edit reaches the patch too", fb.raw_diff(froot, "@-", nil):find("after", 1, true))

  -- A colocated repo has both .jj and .git; jj is the one being driven.
  local colo = temp .. "/colocated"
  vim.fn.mkdir(colo, "p")
  run({ "jj", "git", "init", "--colocate", "--quiet" }, colo)
  eq("colocated: jj wins over git", "jj", (select(1, vcs.detect(colo)) or {}).name)
  vcs.clear_cache()
  vim.g.vcs_backend = "git"
  eq("colocated: vim.g.vcs_backend forces git", "git", (select(1, vcs.detect(colo)) or {}).name)
  vim.g.vcs_backend = nil
  vcs.clear_cache()
else
  print("SKIP jj backend (jj not installed)")
end

--------------------------------------------------------------------------
-- Perforce, against a stub server
--------------------------------------------------------------------------

do
  local bin = temp .. "/bin"
  vim.fn.mkdir(bin, "p")
  local client = temp .. "/p4client"
  vim.fn.mkdir(client .. "/sub", "p")
  write(client .. "/sub/edited.c", "local edited\n")
  write(client .. "/added.c", "local added\n")

  -- Emulates the subset of the p4 CLI the backend uses, in -ztag form.
  local calls = temp .. "/p4-calls.log"
  local stub = ([==[#!/usr/bin/env bash
set -euo pipefail
CLIENT=%s
echo "$@" >> %s
args=("$@")
ztag=0
if [[ "${1:-}" == "-ztag" ]]; then ztag=1; shift; fi
case "${1:-}" in
  info)
    echo "... clientRoot $CLIENT"
    echo "... clientName test-client"
    ;;
  opened)
    echo "... depotFile //depot/sub/edited.c"
    echo "... rev 7"
    echo "... action edit"
    echo ""
    echo "... depotFile //depot/added.c"
    echo "... rev 1"
    echo "... action add"
    echo ""
    echo "... depotFile //depot/removed.c"
    echo "... rev 3"
    echo "... action delete"
    ;;
  where)
    shift
    for d in "$@"; do
      echo "... depotFile $d"
      echo "... clientFile //test-client${d#//depot}"
      echo "... path $CLIENT${d#//depot}"
      echo ""
    done
    ;;
  print)
    # p4 print -q <path>#have
    target="${!#}"
    echo "depot contents of ${target}"
    ;;
  diff)
    echo "--- //depot/sub/edited.c"
    echo "+++ $CLIENT/sub/edited.c"
    echo "+local edited"
    ;;
  filelog)
    echo "... depotFile //depot/sub/edited.c"
    echo "... rev0 7"
    echo "... time0 1700000000"
    echo "... user0 alice"
    echo "... desc0 newest change"
    echo "... rev1 6"
    echo "... time1 1600000000"
    echo "... user1 bob"
    echo "... desc1 older change"
    ;;
  *) exit 2 ;;
esac
]==]):format(vim.fn.shellescape(client), vim.fn.shellescape(calls))

  for _, name in ipairs({ "p4", "g4" }) do
    write(bin .. "/" .. name, stub)
    vim.fn.setfperm(bin .. "/" .. name, "rwx------")
  end
  vim.env.PATH = bin .. ":" .. vim.env.PATH
  vcs.clear_cache()

  local b = vcs.backends.p4
  eq("p4: root from `p4 info` clientRoot", client, b.root(client))

  vim.fn.delete(calls)
  local files = b.changed(client, "#have")
  local map = status_map(files)

  -- `where` has to be asked once for the whole changelist. One call per file
  -- means a server round trip each, which is seconds on a real changelist.
  local where_calls = 0
  for _, line in ipairs(vim.fn.filereadable(calls) == 1 and vim.fn.readfile(calls) or {}) do
    if line:find("where", 1, true) then
      where_calls = where_calls + 1
    end
  end
  eq("p4: `where` is batched into a single call", 1, where_calls)
  eq("p4: edit maps to modified", "M", map["sub/edited.c"])
  eq("p4: add maps to added", "A", map["added.c"])
  eq("p4: delete maps to deleted", "D", map["removed.c"])
  eq("p4: paths are repo-relative", 3, #files)
  eq("p4: depot path carried through", "//depot/sub/edited.c", files[1] and files[1].depot)

  eq(
    "p4: show asks for the synced revision",
    { "depot contents of sub/edited.c#have" },
    b.show(client, "#have", "sub/edited.c")
  )
  truthy("p4: raw_diff returns a patch", b.raw_diff(client, "#have", "sub/edited.c"):find("local edited", 1, true))

  local log = b.log(client, "sub/edited.c")
  eq("p4: filelog returns every revision", 2, #log)
  eq("p4: filelog newest first", "#7", log[1] and log[1].rev)
  eq("p4: filelog parses the user", "alice", log[1] and log[1].author)
  eq("p4: filelog parses the description", "newest change", log[1] and log[1].desc or log[1] and log[1].subject)
  eq("p4: filelog second revision", "#6", log[2] and log[2].rev)

  eq("p4: rev is the synced revision", "#have", b.rev(client, "working"))
  eq("p4: head scope asks the server", "#head", b.rev(client, "head"))

  -- P4CONFIG short-circuits the server round trip.
  write(client .. "/.p4config", "P4CLIENT=test-client\n")
  vim.env.P4CONFIG = ".p4config"
  eq("p4: root from P4CONFIG marker", client, b.root(client .. "/sub"))
  vim.env.P4CONFIG = nil

  eq("g4: shares the p4 implementation", "M", status_map(vcs.backends.g4.changed(client, "#have"))["sub/edited.c"])
end

--------------------------------------------------------------------------
-- mercurial
--------------------------------------------------------------------------

if vim.fn.executable("hg") == 1 then
  local root = temp .. "/hg"
  vim.fn.mkdir(root, "p")
  run({ "hg", "init" }, root)
  write(root .. "/a.txt", "one\n")
  run({ "hg", "add", "a.txt" }, root)
  run({ "hg", "--config", "ui.username=Test <t@example.com>", "commit", "-m", "initial" }, root)
  write(root .. "/a.txt", "one\ntwo\n")
  write(root .. "/b.txt", "new\n")

  local b, detected = vcs.detect(root)
  eq("hg: detected", "hg", b and b.name)
  local map = status_map(b.changed(detected, b.rev(detected, "working")))
  eq("hg: modified", "M", map["a.txt"])
  eq("hg: untracked", "?", map["b.txt"])
  eq("hg: show returns base content", { "one" }, b.show(detected, ".", "a.txt"))
  truthy("hg: raw_diff produces a patch", #b.raw_diff(detected, ".", nil) > 0)
  truthy("hg: log returns revisions", #b.log(detected, "a.txt") >= 1)
else
  print("SKIP hg backend (hg not installed)")
end

--------------------------------------------------------------------------

vim.fn.delete(temp, "rf")

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  error("\n" .. table.concat(failures, "\n"))
end
