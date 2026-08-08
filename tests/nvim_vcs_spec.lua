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
  -- Names git cannot print literally. It wraps each of these in double quotes
  -- and C-escapes the inside, and `core.quotepath=false` does not turn that off
  -- — it only governs the octal escaping of non-ASCII bytes. Parsed from the
  -- line output, the quotes and backslashes end up in the path and the file
  -- cannot be opened; the backend asks for -z instead.
  write(root .. '/has"quote.c', "// a quote in the name\n")
  write(root .. "/has\\backslash.c", "// a backslash in the name\n")
  write(root .. "/has\ttab.c", "// a tab in the name\n")
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
  write(root .. '/has"quote.c', "// a quote in the name\n// edited\n")
  write(root .. "/has\\backslash.c", "// a backslash in the name\n// edited\n")
  write(root .. "/has\ttab.c", "// a tab in the name\n// edited\n")
  -- Untracked too, so the ls-files half is covered as well.
  write(root .. '/untracked"quote.c', "// untracked, with a quote\n")
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

  -- Revisions come back resolved to hashes, never symbolic: cached base
  -- content is keyed by these, and "HEAD" would keep meaning the old content
  -- after a commit moved it.
  eq("git: rev(working) resolves the HEAD hash", vim.trim(git(git_root, "rev-parse", "HEAD")), b.rev(root, "working"))
  eq("git: rev(head) resolves the parent hash", vim.trim(git(git_root, "rev-parse", "HEAD~1")), b.rev(root, "head"))
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
  -- The names git has to quote. Each must come back as the real path, or the
  -- file simply cannot be opened from the changed-files view.
  eq("git: a name containing a double quote", "M", working['has"quote.c'])
  eq("git: a name containing a backslash", "M", working["has\\backslash.c"])
  eq("git: a name containing a tab", "M", working["has\ttab.c"])
  eq("git: an untracked name containing a double quote", "?", working['untracked"quote.c'])
  for _, name in ipairs({ 'has"quote.c', "has\\backslash.c", "has\ttab.c", 'untracked"quote.c' }) do
    eq(("git: %q names a file that exists"):format(name), 1, vim.fn.filereadable(root .. "/" .. name))
  end

  -- The old path rides along on the record, so the diff UI can fetch the base
  -- content that actually existed instead of treating a rename as an add.
  local records = {}
  for _, f in ipairs(b.changed(root, b.rev(root, "working"))) do
    records[f.path] = f
  end
  eq(
    "git: rename carries the old path",
    "renamed-from.txt",
    records["renamed-to.txt"] and records["renamed-to.txt"].orig
  )
  eq(
    "git: a plain modification carries no old path",
    nil,
    records["src/ünïcode.c"] and records["src/ünïcode.c"].orig
  )
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

  -- Revisions come back as commit ids, never symbolic, for the same reason
  -- git's resolve to hashes: "@-" moves, a cached base keyed by it must not.
  local wrev = b.rev(detected_root, "working")
  truthy("jj: rev(working) resolves a commit id", wrev and wrev:match("^%x+$"), tostring(wrev))
  local hrev = b.rev(detected_root, "head")
  truthy("jj: rev(head) resolves a commit id", hrev and hrev:match("^%x+$"), tostring(hrev))
  check("jj: rev(head) is not rev(working)", hrev ~= wrev)
  -- With no trunk configured, trunk() degrades to the root commit; falling back
  -- to @- is what keeps `branch` scope from reporting the whole repo as added.
  eq("jj: rev(branch) falls back to the working base without a trunk", wrev, b.rev(detected_root, "branch"))

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

  -- Renames. `jj diff --summary` fuses the pair into one `{old => new}` string;
  -- an earlier version took that whole string as the path, so a renamed file
  -- named nothing on disk, could not be opened, and had no old path to read
  -- base content from. Every shape jj compacts is covered here, including the
  -- one the brace form cannot represent unambiguously.
  local ren = temp .. "/jj-rename"
  vim.fn.mkdir(ren, "p")
  run({ "jj", "git", "init", "--quiet" }, ren)
  write(ren .. "/src/alpha.txt", "same dir\n")
  write(ren .. "/deep/a/file.txt", "shared suffix\n")
  write(ren .. "/at-root.txt", "nothing in common\n")
  write(ren .. "/w{x => y}.txt", "pathological\n")
  run({ "jj", "--quiet", "describe", "-m", "base" }, ren)
  run({ "jj", "--quiet", "new", "-m", "wip" }, ren)
  vim.fn.rename(ren .. "/src/alpha.txt", ren .. "/src/beta.txt")
  vim.fn.mkdir(ren .. "/deep/b", "p")
  vim.fn.rename(ren .. "/deep/a/file.txt", ren .. "/deep/b/file.txt")
  vim.fn.mkdir(ren .. "/moved", "p")
  vim.fn.rename(ren .. "/at-root.txt", ren .. "/moved/elsewhere.md")
  vim.fn.rename(ren .. "/w{x => y}.txt", ren .. "/w{p => q}.txt")

  local rb, rroot = vcs.detect(ren)
  local renamed = {}
  for _, f in ipairs(rb.changed(rroot, "@-")) do
    renamed[f.path] = f
  end
  local pairs_expected = {
    ["src/beta.txt"] = "src/alpha.txt", -- shared prefix: src/{alpha.txt => beta.txt}
    ["deep/b/file.txt"] = "deep/a/file.txt", -- shared suffix: deep/{a => b}/file.txt
    ["moved/elsewhere.md"] = "at-root.txt", -- nothing shared
    ["w{p => q}.txt"] = "w{x => y}.txt", -- braces the summary form cannot escape
  }
  for path, orig in pairs(pairs_expected) do
    eq(("jj: rename %q names the real path"):format(path), 1, vim.fn.filereadable(rroot .. "/" .. path))
    eq(("jj: rename %q is status R"):format(path), "R", renamed[path] and renamed[path].status)
    eq(("jj: rename %q carries the old path"):format(path), orig, renamed[path] and renamed[path].orig)
    -- Base content is fetched under the old name; the new one does not exist there.
    truthy(("jj: base content readable at %q"):format(orig), rb.show(rroot, "@-", orig))
  end
  eq("jj: the brace form is not left in the listing", nil, renamed["{at-root.txt => moved/elsewhere.md}"])

  write(ren .. "/src/beta.txt", "same dir\nedited\n")
  local edited = {}
  for _, f in ipairs(rb.changed(rroot, "@-")) do
    edited[f.path] = f
  end
  eq("jj: an edited rename is still a rename", "R", edited["src/beta.txt"] and edited["src/beta.txt"].status)
  truthy(
    "jj: raw_diff of a rename reports the pair",
    rb.raw_diff(rroot, "@-", "src/beta.txt", "src/alpha.txt"):find("rename from src/alpha.txt", 1, true)
  )

  -- Reverting a rename has to put both halves back: dropping only the new path
  -- leaves the old one deleted, which is a second unwanted change, not a revert.
  rb.revert(rroot, "@-", renamed["src/beta.txt"])
  eq("jj: reverting a rename restores the old path", 1, vim.fn.filereadable(rroot .. "/src/alpha.txt"))
  eq("jj: reverting a rename removes the new path", 0, vim.fn.filereadable(rroot .. "/src/beta.txt"))
  eq("jj: reverting a rename leaves the other renames alone", 1, vim.fn.filereadable(rroot .. "/deep/b/file.txt"))

  -- jj takes path arguments as fileset expressions, so these characters are
  -- syntax unless the path is passed as a quoted literal. `report (1).pdf` is
  -- an ordinary name a browser produces, and it used to be a parse error.
  local fs = temp .. "/jj-fileset"
  vim.fn.mkdir(fs, "p")
  run({ "jj", "git", "init", "--quiet" }, fs)
  local awkward = {
    "report (1).pdf",
    "colon:name.txt",
    "brace{x}.txt",
    'quo"te.txt',
    "back\\slash.txt",
    "sp ace.txt",
  }
  for i, name in ipairs(awkward) do
    write(fs .. "/" .. name, "base " .. i .. "\n")
  end
  run({ "jj", "--quiet", "describe", "-m", "base" }, fs)
  run({ "jj", "--quiet", "new", "-m", "wip" }, fs)
  local fsb, fsroot = vcs.detect(fs)
  for i, name in ipairs(awkward) do
    write(fs .. "/" .. name, "base " .. i .. "\nedited\n")
    eq(("jj: show of %q returns base content"):format(name), { "base " .. i }, fsb.show(fsroot, "@-", name))
    truthy(
      ("jj: raw_diff scoped to %q"):format(name),
      fsb.raw_diff(fsroot, "@-", name):find("edited", 1, true),
      fsb.raw_diff(fsroot, "@-", name)
    )
    truthy(("jj: log of %q returns a revision"):format(name), #fsb.log(fsroot, name) >= 1)
  end
  eq(
    "jj: revert of an awkward name restores the base",
    true,
    fsb.revert(fsroot, "@-", { path = awkward[1], status = "M" })
  )
  eq("jj: reverted content is the base content", { "base 1" }, vim.fn.readfile(fsroot .. "/" .. awkward[1]))
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
    # rev and haveRev are different fields and p4 prints both: rev is the
    # revision the file was opened at, haveRev the one synced into the
    # workspace. Base content has to come from haveRev, so they differ here.
    echo "... depotFile //depot/sub/edited.c"
    echo "... rev 8"
    echo "... haveRev 7"
    echo "... action edit"
    echo ""
    echo "... depotFile //depot/added.c"
    echo "... rev 1"
    echo "... haveRev none"
    echo "... action add"
    echo ""
    echo "... depotFile //depot/removed.c"
    echo "... rev 3"
    echo "... haveRev 3"
    echo "... action delete"
    echo ""
    # `p4 move` opens the pair as move/add and move/delete, with a slash.
    echo "... depotFile //depot/moved-to.c"
    echo "... rev 1"
    echo "... haveRev none"
    echo "... action move/add"
    echo ""
    echo "... depotFile //depot/moved-from.c"
    echo "... rev 5"
    echo "... haveRev 5"
    echo "... action move/delete"
    echo ""
    echo "... depotFile //depot/branched.c"
    echo "... rev 1"
    echo "... haveRev none"
    echo "... action branch"
    echo ""
    echo "... depotFile //depot/integrated.c"
    echo "... rev 2"
    echo "... haveRev 2"
    echo "... action integrate"
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
  -- The map used to spell these `move_add`, which p4 never prints, so both
  -- halves of a move arrived as "modified" — including the half that is not on
  -- disk any more and therefore cannot be opened.
  eq("p4: move/add maps to renamed", "R", map["moved-to.c"])
  eq("p4: move/delete maps to deleted", "D", map["moved-from.c"])
  eq("p4: branch maps to added", "A", map["branched.c"])
  eq("p4: integrate maps to modified", "M", map["integrated.c"])
  eq("p4: paths are repo-relative", 7, #files)
  eq("p4: depot path carried through", "//depot/sub/edited.c", files[1] and files[1].depot)
  -- haveRev, not rev: base content has to come from what is synced into the
  -- workspace, and "#have" as a cache key would keep meaning the old content
  -- after a sync moved it.
  eq("p4: the per-file revision is the synced one", "#7", files[1] and files[1].rev)
  local by_path = {}
  for _, f in ipairs(files) do
    by_path[f.path] = f
  end
  eq("p4: a file with nothing synced carries no revision", nil, by_path["added.c"] and by_path["added.c"].rev)

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
  -- One file per status hg can report against a revision, so the mapping onto
  -- this interface's letters is covered rather than assumed. `R` and `!` are
  -- the two that matter: hg's R is *removed*, which reads as "renamed" in the
  -- panel if it is passed through, and `!` is a tracked file deleted without
  -- telling hg.
  write(root .. "/removed.txt", "gone\n")
  write(root .. "/missing.txt", "vanished\n")
  run({ "hg", "add", "removed.txt", "missing.txt" }, root)
  run({ "hg", "--config", "ui.username=Test <t@example.com>", "commit", "-m", "second" }, root)
  write(root .. "/a.txt", "one\ntwo\n")
  write(root .. "/b.txt", "new\n")
  run({ "hg", "rm", "removed.txt" }, root)
  assert(os.remove(root .. "/missing.txt"))

  local b, detected = vcs.detect(root)
  eq("hg: detected", "hg", b and b.name)
  local map = status_map(b.changed(detected, b.rev(detected, "working")))
  eq("hg: modified", "M", map["a.txt"])
  -- `?` is not a letter, and a letters-only pattern dropped these silently.
  eq("hg: untracked", "?", map["b.txt"])
  eq("hg: removed reads as a deletion, not a rename", "D", map["removed.txt"])
  eq("hg: a file deleted behind hg's back reads as a deletion", "D", map["missing.txt"])
  eq("hg: show returns base content", { "one" }, b.show(detected, ".", "a.txt"))
  truthy("hg: raw_diff produces a patch", #b.raw_diff(detected, ".", nil) > 0)
  truthy("hg: log returns revisions", #b.log(detected, "a.txt") >= 1)

  -- Renames and copies. hg reports a rename as an unrelated add plus a delete
  -- unless asked for the source, which left the added half with no base content
  -- and diffing as a wholly new file. Reported the way git and jj report it:
  -- one row on the new path, carrying the old one.
  local hgr = temp .. "/hg-rename"
  vim.fn.mkdir(hgr, "p")
  run({ "hg", "init" }, hgr)
  write(hgr .. "/orig.txt", "original\n")
  write(hgr .. "/source.txt", "copy me\n")
  write(hgr .. "/plain.txt", "untouched by moves\n")
  -- hg reads a path argument as a pattern, and these prefixes name a pattern
  -- *type*: `set:notes.txt` resolved to a fileset expression, not a file.
  write(hgr .. "/set:notes.txt", "prefixed\n")
  write(hgr .. "/glob:x.txt", "globbed\n")
  -- A leading space is the one thing that makes hg's status line ambiguous: the
  -- code and the path are separated by exactly one space, so a greedy match
  -- swallows the name's own leading spaces and reports a path that is not there.
  write(hgr .. "/  indented.txt", "spaces in front\n")
  -- `hg add set:notes.txt` adds nothing at all — it reads as a fileset — which
  -- is the same trap the backend had to stop falling into.
  run({
    "hg",
    "add",
    "orig.txt",
    "source.txt",
    "plain.txt",
    "path:set:notes.txt",
    "path:glob:x.txt",
    "path:  indented.txt",
  }, hgr)
  run({ "hg", "--config", "ui.username=Test <t@example.com>", "commit", "-m", "base" }, hgr)
  run({ "hg", "mv", "orig.txt", "renamed.txt" }, hgr)
  run({ "hg", "cp", "source.txt", "duplicate.txt" }, hgr)
  write(hgr .. "/plain.txt", "untouched by moves\nedited\n")
  write(hgr .. "/  indented.txt", "spaces in front\nedited\n")
  write(hgr .. "/two\nlines.txt", "untracked, and awkward about it\n")

  local hb, hroot = vcs.detect(hgr)
  local hrecords = {}
  for _, f in ipairs(hb.changed(hroot, hb.rev(hroot, "working"))) do
    hrecords[f.path] = f
  end
  eq("hg: a rename is one row on the new path", "R", hrecords["renamed.txt"] and hrecords["renamed.txt"].status)
  eq("hg: a rename carries the old path", "orig.txt", hrecords["renamed.txt"] and hrecords["renamed.txt"].orig)
  eq("hg: the old path is not also listed as deleted", nil, hrecords["orig.txt"])
  eq("hg: a copy is a copy, not a rename", "C", hrecords["duplicate.txt"] and hrecords["duplicate.txt"].status)
  eq("hg: a copy carries its source", "source.txt", hrecords["duplicate.txt"] and hrecords["duplicate.txt"].orig)
  eq("hg: the copy source stays where it is", nil, hrecords["source.txt"])
  eq("hg: a plain edit is unaffected", "M", hrecords["plain.txt"] and hrecords["plain.txt"].status)
  eq("hg: a plain edit carries no source", nil, hrecords["plain.txt"] and hrecords["plain.txt"].orig)
  eq(
    "hg: a leading space survives the status line",
    "M",
    hrecords["  indented.txt"] and hrecords["  indented.txt"].status
  )
  -- hg refuses to *track* a newline in a filename but happily reports one as
  -- untracked, and line-oriented output splits it into two rows naming files
  -- that do not exist. -0 keeps it one record.
  eq("hg: a newline in a name stays one row", "?", hrecords["two\nlines.txt"] and hrecords["two\nlines.txt"].status)
  eq("hg: neither half of it is listed on its own", nil, hrecords["two"])
  eq("hg: the name is not trimmed to something that does not exist", nil, hrecords["indented.txt"])
  eq("hg: base content of the renamed file comes from the old path", { "original" }, hb.show(hroot, ".", "orig.txt"))

  for _, name in ipairs({ "set:notes.txt", "glob:x.txt" }) do
    eq(("hg: show of %q reads the file, not a pattern"):format(name), 1, #(hb.show(hroot, ".", name) or {}))
    truthy(("hg: log of %q returns a revision"):format(name), #hb.log(hroot, name) >= 1)
  end
  write(hgr .. "/set:notes.txt", "prefixed\nedited\n")
  truthy(
    "hg: raw_diff scoped to a pattern-prefixed name",
    hb.raw_diff(hroot, ".", "set:notes.txt"):find("edited", 1, true)
  )
  eq(
    "hg: revert of a pattern-prefixed name succeeds",
    true,
    hb.revert(hroot, ".", { path = "set:notes.txt", status = "M" })
  )
  eq("hg: the reverted file is back to its base", { "prefixed" }, vim.fn.readfile(hroot .. "/set:notes.txt"))

  hb.revert(hroot, ".", hrecords["renamed.txt"])
  eq("hg: reverting a rename restores the old path", 1, vim.fn.filereadable(hroot .. "/orig.txt"))

  -- Branch scope. It used to resolve to `.`, the same as uncommitted, so
  -- cycling to it in the panel showed none of the branch's committed work.
  local hgb = temp .. "/hg-branch"
  vim.fn.mkdir(hgb, "p")
  run({ "hg", "init" }, hgb)
  local function hg_commit(dir, message)
    run({ "hg", "--config", "ui.username=Test <t@example.com>", "commit", "-m", message }, dir)
  end
  write(hgb .. "/f.txt", "trunk one\n")
  run({ "hg", "add", "f.txt" }, hgb)
  hg_commit(hgb, "trunk one")
  write(hgb .. "/f.txt", "trunk two\n")
  hg_commit(hgb, "trunk two")
  local fork = vim.trim(run({ "hg", "log", "-r", ".", "--template", "{node}" }, hgb))
  run({ "hg", "branch", "-q", "feature" }, hgb)
  write(hgb .. "/f.txt", "on the branch\n")
  hg_commit(hgb, "branch work")
  write(hgb .. "/f.txt", "on the branch\nand uncommitted\n")

  local bb, broot = vcs.detect(hgb)
  eq("hg: rev(branch) is the fork point, not the working parent", fork, bb.rev(broot, "branch"))
  truthy("hg: rev(working) is a node", (bb.rev(broot, "working") or ""):match("^%x+$"))
  check("hg: rev(branch) is not rev(working)", bb.rev(broot, "branch") ~= bb.rev(broot, "working"))
  eq(
    "hg: branch scope sees the committed branch work",
    "M",
    status_map(bb.changed(broot, bb.rev(broot, "branch")))["f.txt"]
  )
  eq(
    "hg: base content at the fork point is trunk's, not the branch's",
    { "trunk two" },
    bb.show(broot, bb.rev(broot, "branch"), "f.txt")
  )
  -- -C, or hg tries to merge the uncommitted edit into trunk and drops into an
  -- interactive merge tool, which in a headless spec means hanging forever.
  run({ "hg", "update", "-q", "-C", "default" }, hgb)
  eq(
    "hg: on trunk itself, branch scope falls back to the working parent",
    bb.rev(broot, "working"),
    bb.rev(broot, "branch")
  )
else
  print("SKIP hg backend (hg not installed)")
end

--------------------------------------------------------------------------
-- async: the same backends, off the UI thread
--------------------------------------------------------------------------

do
  local done, async_files, async_base
  vcs.async(function()
    local backend = vcs.backends.git
    local rev = backend.rev(git_root, "working")
    async_files = backend.changed(git_root, rev)
    async_base = backend.show(git_root, rev, "src/main.c")
    done = true
  end)
  check(
    "async: the coroutine completes",
    vim.wait(4000, function()
      return done == true
    end)
  )
  local backend = vcs.backends.git
  local rev = backend.rev(git_root, "working")
  eq(
    "async: changed() answers the same as the blocking path",
    status_map(backend.changed(git_root, rev)),
    status_map(async_files or {})
  )
  eq("async: show() answers the same as the blocking path", backend.show(git_root, rev, "src/main.c"), async_base)
end

--------------------------------------------------------------------------
-- jj too old for `jj diff -T`, against a stub binary
--------------------------------------------------------------------------

-- Must stay last in the file: the backend remembers that templates are
-- unavailable, so anything real running after this would take the fallback.
do
  local bin = temp .. "/oldjj"
  vim.fn.mkdir(bin, "p")
  write(
    bin .. "/jj",
    [==[#!/usr/bin/env bash
for a in "$@"; do
  if [[ "$a" == "-T" ]]; then
    echo "Error: unexpected argument '-T' found" >&2
    exit 2
  fi
done
cat <<'OUT'
M plain.txt
A added.txt
R src/{alpha.txt => beta.txt}
R deep/{a => b}/file.txt
R {at-root.txt => moved/elsewhere.md}
OUT
]==]
  )
  vim.fn.setfperm(bin .. "/jj", "rwx------")
  vim.env.PATH = bin .. ":" .. vim.env.PATH
  vcs.clear_cache()

  local records = {}
  for _, f in ipairs(vcs.backends.jj.changed(temp, "@-")) do
    records[f.path] = f
  end
  eq("old jj: falls back to --summary", "M", records["plain.txt"] and records["plain.txt"].status)
  eq("old jj: a plain entry has no old path", nil, records["added.txt"] and records["added.txt"].orig)
  eq("old jj: shared-prefix rename splits", "src/alpha.txt", records["src/beta.txt"] and records["src/beta.txt"].orig)
  eq(
    "old jj: shared-suffix rename splits",
    "deep/a/file.txt",
    records["deep/b/file.txt"] and records["deep/b/file.txt"].orig
  )
  eq(
    "old jj: rename with nothing in common splits",
    "at-root.txt",
    records["moved/elsewhere.md"] and records["moved/elsewhere.md"].orig
  )
  eq("old jj: no brace form survives", nil, records["src/{alpha.txt => beta.txt}"])
end

--------------------------------------------------------------------------

vim.fn.delete(temp, "rf")

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  error("\n" .. table.concat(failures, "\n"))
end
