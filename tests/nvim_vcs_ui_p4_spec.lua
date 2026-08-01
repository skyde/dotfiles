-- Run with: nvim --headless -u NONE -i NONE -l tests/nvim_vcs_ui_p4_spec.lua
--
-- Drives the diff UI end-to-end against a stub Perforce server — the backend
-- the git-driven nvim_vcs_ui_spec.lua never exercises. The stub keeps its
-- opened list and depot contents in mutable files, so the tests can simulate
-- the things only Perforce does: a sync moving a file's haveRev while the set
-- of opened files stays identical.

local source = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(repo .. "/common/.config/nvim")

vim.o.columns = 200
vim.o.lines = 50

local vcs = require("util.vcs")
local ui = require("util.vcs_ui")

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

local function write(path, text)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local fd = assert(io.open(path, "wb"))
  fd:write(text)
  fd:close()
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

local function scrub(keys)
  feed(keys)
  vim.wait(400, function()
    return false
  end)
end

local function open_settled(opts)
  ui.open(opts)
  vim.wait(3000, function()
    return not ui.busy()
  end)
end

local function layout()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  table.sort(wins, function(a, b)
    return vim.api.nvim_win_get_position(a)[2] < vim.api.nvim_win_get_position(b)[2]
  end)
  return wins
end

local function win_lines(w)
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false)
end

local function panel_lines()
  return win_lines(layout()[1])
end

--------------------------------------------------------------------------
-- the stub server
--------------------------------------------------------------------------

local client = temp .. "/client"
local state = temp .. "/state"
vim.fn.mkdir(client .. "/sub/dir", "p")
vim.fn.mkdir(state .. "/print", "p")

-- Working-copy contents.
write(client .. "/sub/dir/edited.c", "local\nEDITED\ncontent\n")
write(client .. "/added.c", "brand new\n")

---One `p4 opened` record.
local function opened_record(depot, action, have)
  local out = { "... depotFile " .. depot, "... action " .. action }
  if have then
    table.insert(out, "... haveRev " .. have)
  end
  table.insert(out, "")
  return table.concat(out, "\n")
end

---What the depot serves for `p4 print -q <path>#<rev>`.
local function set_depot(path_with_rev, text)
  write(state .. "/print/" .. path_with_rev:gsub("[/#]", "_"), text)
end

write(
  state .. "/opened",
  opened_record("//depot/sub/dir/edited.c", "edit", "4")
    .. "\n"
    .. opened_record("//depot/added.c", "add")
    .. "\n"
    .. opened_record("//depot/removed.c", "delete", "2")
)
set_depot("sub/dir/edited.c#4", "local\nedited\ncontent\n")
set_depot("removed.c#2", "was here\n")

local stub = ([==[#!/usr/bin/env bash
set -euo pipefail
STATE=%s
CLIENT=%s
if [[ "${1:-}" == "-ztag" ]]; then shift; fi
case "${1:-}" in
  info)
    echo "... clientRoot $CLIENT"
    ;;
  opened)
    cat "$STATE/opened"
    ;;
  where)
    shift
    for d in "$@"; do
      echo "... depotFile $d"
      echo "... path $CLIENT${d#//depot}"
      echo ""
    done
    ;;
  print)
    target="${!#}"
    key="${target//\//_}"
    key="${key//#/_}"
    if [[ -f "$STATE/print/$key" ]]; then
      cat "$STATE/print/$key"
    else
      exit 1
    fi
    ;;
  diff)
    echo "stub diff"
    ;;
  *) exit 2 ;;
esac
]==]):format(vim.fn.shellescape(state), vim.fn.shellescape(client))

local bin = temp .. "/bin"
vim.fn.mkdir(bin, "p")
write(bin .. "/p4", stub)
vim.fn.setfperm(bin .. "/p4", "rwx------")
vim.env.PATH = bin .. ":" .. vim.env.PATH

vim.g.vcs_backend = "p4"
vim.cmd("cd " .. vim.fn.fnameescape(client))

--------------------------------------------------------------------------
-- opening against the stub
--------------------------------------------------------------------------

do
  ui.open({ scope = "working" })
  -- The default rendering is inline; the assertions below want the two-pane
  -- layout where the base is its own buffer.
  ui.toggle_inline()
  vim.wait(3000, function()
    return not ui.busy()
  end)

  local lines = panel_lines()
  check("p4: header names the backend", lines[1]:find("p4", 1, true) ~= nil, lines[1])
  check("p4: header shows the synced revision", lines[2]:find("#have", 1, true) ~= nil, lines[2])

  local listed = {}
  for i = 4, #lines do
    table.insert(listed, lines[i])
  end
  eq("p4: the changelist renders as a tree with status letters", {
    "    sub/dir/",
    " M    edited.c",
    " A  added.c",
    " D  removed.c",
  }, listed)

  eq("p4: cursor starts on the first file, past the directory", 5, vim.api.nvim_win_get_cursor(layout()[1])[1])

  local wins = layout()
  eq("p4: base pane holds the depot content at the haveRev", { "local", "edited", "content" }, win_lines(wins[2]))
  eq("p4: working pane holds the client file", { "local", "EDITED", "content" }, win_lines(wins[3]))
  check("p4: both panes in diff mode", vim.wo[wins[2]].diff and vim.wo[wins[3]].diff)
  check(
    "p4: base pane is named after the haveRev",
    vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(wins[2])):find("edited.c", 1, true) ~= nil
  )

  -- An added file has no depot side.
  scrub("j")
  eq("p4: an added file diffs against nothing", { "" }, win_lines(layout()[2]))
  eq("p4: the added file's working copy shows", { "brand new" }, win_lines(layout()[3]))

  -- A deleted file has no client side.
  scrub("j")
  eq("p4: a deleted file shows the depot content", { "was here" }, win_lines(layout()[2]))
  eq("p4: a deleted file's right pane is empty", { "" }, win_lines(layout()[3]))
end

--------------------------------------------------------------------------
-- a sync moves haveRev without changing the opened list
--------------------------------------------------------------------------

do
  -- Same three opened files, but edited.c is now synced to #5 with different
  -- depot content. The listing *set* is identical; only the revision moved.
  write(
    state .. "/opened",
    opened_record("//depot/sub/dir/edited.c", "edit", "5")
      .. "\n"
      .. opened_record("//depot/added.c", "add")
      .. "\n"
      .. opened_record("//depot/removed.c", "delete", "2")
  )
  set_depot("sub/dir/edited.c#5", "local\nsynced to five\ncontent\n")

  ui.close()
  ui.open({ scope = "working" })
  -- The cached paint still shows the old base; nothing has revalidated yet.
  vim.api.nvim_win_set_cursor(layout()[1], { 5, 0 })
  scrub("")
  vim.wait(3000, function()
    return not ui.busy()
  end)
  -- The background revalidation saw the haveRev move, dropped the stale
  -- bases, and re-rendered against the new depot content.
  eq(
    "p4 sync: the revalidation replaces the stale base with the synced one",
    { "local", "synced to five", "content" },
    win_lines(layout()[2])
  )
end

--------------------------------------------------------------------------
-- hard refresh distrusts the depot content outright
--------------------------------------------------------------------------

do
  set_depot("sub/dir/edited.c#5", "local\nchanged again\ncontent\n")
  feed("R")
  vim.wait(3000, function()
    return not ui.busy()
  end)
  vim.api.nvim_win_set_cursor(layout()[1], { 5, 0 })
  scrub("")
  eq(
    "p4 R: a hard refresh refetches the base even with no rev change",
    { "local", "changed again", "content" },
    win_lines(layout()[2])
  )
  ui.close()
end

--------------------------------------------------------------------------
-- inline mode against p4
--------------------------------------------------------------------------

do
  ui.open({ scope = "working" })
  -- Block 1 left the remembered rendering side-by-side; flip back to inline.
  ui.toggle_inline()
  vim.wait(3000, function()
    return not ui.busy()
  end)
  eq("p4 inline: panel plus one pane", 2, #layout())
  local buf = vim.api.nvim_win_get_buf(layout()[2])
  eq("p4 inline: the pane is the real client file", client .. "/sub/dir/edited.c", vim.api.nvim_buf_get_name(buf))
  check("p4 inline: the overlay is attached", require("util.inline_diff").has(buf))
  ui.close()
end

--------------------------------------------------------------------------

vim.g.vcs_backend = nil
vim.fn.delete(temp, "rf")

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  error("\n" .. table.concat(failures, "\n"))
end
