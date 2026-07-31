-- Source-control and diff keymaps, matching the VS Code bindings they replace.
-- See docs/nvim-vscode-parity.md for the side-by-side table.
--
-- Everything here goes through util.vcs, so the same keys work in git, jj,
-- Perforce (p4 / g4) and Mercurial repositories.

local ui = require("util.vcs_ui")
local conflict = require("util.conflict")
local map = vim.keymap.set

conflict.setup()

--------------------------------------------------------------------------
-- commands, so the same actions are reachable without the leader keys
--------------------------------------------------------------------------

local function cmd(name, fn, opts)
  vim.api.nvim_create_user_command(name, fn, opts or {})
end

cmd("VcsChanges", function(a)
  ui.open({ scope = a.args ~= "" and a.args or "working" })
end, {
  nargs = "?",
  complete = function()
    return { "working", "branch", "head" }
  end,
})
cmd("VcsDiff", function(a)
  ui.file_diff(a.args ~= "" and a.args or "working")
end, {
  nargs = "?",
  complete = function()
    return { "working", "branch", "head" }
  end,
})
cmd("VcsPatch", function(a)
  ui.patch(a.args ~= "" and a.args or "branch")
end, {
  nargs = "?",
  complete = function()
    return { "working", "branch", "head" }
  end,
})
cmd("VcsHistory", ui.history)
cmd("VcsInfo", function()
  local vcs = require("util.vcs")
  local backend, root = vcs.detect()
  if not backend then
    return vim.notify("No version control detected here", vim.log.levels.WARN)
  end
  vim.notify(
    ("%s · %s\nworking base: %s\nbranch base:  %s"):format(
      backend.name,
      root,
      backend.rev(root, "working") or "?",
      backend.rev(root, "branch") or "?"
    )
  )
end)

--------------------------------------------------------------------------
-- source control (<leader>g)
--------------------------------------------------------------------------

-- The one that gets used constantly: the changed-file list with a live diff,
-- standing in for focusing the VS Code SCM view.
map("n", "<leader>gc", function()
  ui.open({ scope = "working" })
end, { desc = "Changed files (uncommitted)" })
map("n", "<leader>gD", function()
  ui.open({ scope = "branch" })
end, { desc = "Changed files (since fork point)" })
map("n", "<leader>gC", function()
  vim.ui.input({ prompt = "Compare against revision: " }, function(rev)
    if rev and rev ~= "" then
      ui.open({ rev = rev })
    end
  end)
end, { desc = "Changed files (pick base)" })
map("n", "<leader>gR", ui.refresh, { desc = "Refresh changed files" })

map("n", "<leader>gd", function()
  ui.file_diff("working")
end, { desc = "Diff this file (uncommitted)" })
map("n", "<leader>ga", function()
  ui.file_diff("branch")
end, { desc = "Diff this file (since fork point)" })

map("n", "<leader>gp", function()
  ui.patch("working")
end, { desc = "Patch: uncommitted" })
map("n", "<leader>gA", function()
  ui.patch("branch")
end, { desc = "Patch: everything since fork point" })
map("n", "<leader>gy", function()
  ui.copy_patch("branch")
end, { desc = "Copy patch (since fork point)" })

map("n", "<leader>gl", ui.history, { desc = "File history" })
map("n", "<leader>gw", ui.goto_file, { desc = "Open the real file from a diff" })
map("n", "<leader>gg", ui.tui, { desc = "Source control TUI" })

--------------------------------------------------------------------------
-- diffs and conflicts (<leader>c)
--------------------------------------------------------------------------

---`]c` / `[c` should always mean "next change", whatever kind of change the
---buffer actually has: diff-mode hunks in a diff, the overlay's hunks in the
---inline view, conflict markers in a conflicted file, gitsigns hunks in an
---ordinary buffer.
---@param dir 1|-1
local function next_change(dir)
  local inline = require("util.inline_diff")
  if vim.wo.diff then
    vim.cmd("normal! " .. (dir > 0 and "]c" or "[c"))
  elseif inline.has(0) then
    inline.goto_hunk(0, dir)
  elseif conflict.has_conflicts(0) then
    conflict.goto_conflict(dir)
  else
    local ok, gs = pcall(require, "gitsigns")
    if ok then
      gs.nav_hunk(dir > 0 and "next" or "prev")
    end
    return
  end
  -- Say where that landed — "Change 2 of 5" — the way the VS Code diff editor
  -- numbers its changes, so a walk through a big file keeps its bearings.
  local index, total
  if vim.wo.diff then
    index, total = ui.change_position()
  elseif inline.has(0) then
    index, total = inline.hunk_position(0)
  end
  if total and total > 0 then
    vim.api.nvim_echo({ { ("Change %d of %d"):format(index, total), "None" } }, false, {})
  end
end

map("n", "]c", function()
  next_change(1)
end, { desc = "Next change" })
map("n", "[c", function()
  next_change(-1)
end, { desc = "Previous change" })
map("n", "<leader>cn", function()
  next_change(1)
end, { desc = "Next change" })
map("n", "<leader>cp", function()
  next_change(-1)
end, { desc = "Previous change" })
map("n", "]x", function()
  conflict.goto_conflict(1)
end, { desc = "Next conflict" })
map("n", "[x", function()
  conflict.goto_conflict(-1)
end, { desc = "Previous conflict" })

-- Conflict resolution. Lower case takes one side of the conflict under the
-- cursor; upper case takes that side for the whole file.
map("n", "<leader>co", function()
  conflict.choose("ours")
end, { desc = "Conflict: take ours" })
map("n", "<leader>cO", function()
  conflict.choose_all("ours")
end, { desc = "Conflict: take ours (all)" })
map("n", "<leader>ct", function()
  conflict.choose("theirs")
end, { desc = "Conflict: take theirs" })
map("n", "<leader>cT", function()
  conflict.choose_all("theirs")
end, { desc = "Conflict: take theirs (all)" })
map("n", "<leader>cb", function()
  conflict.choose("both")
end, { desc = "Conflict: take both" })
map("n", "<leader>cB", function()
  conflict.choose_all("both")
end, { desc = "Conflict: take both (all)" })
map("n", "<leader>c0", function()
  conflict.choose("none")
end, { desc = "Conflict: take neither" })
map("n", "<leader>cm", conflict.merge_view, { desc = "Conflict: open merge view" })
map("n", "<leader>cq", conflict.finish, { desc = "Conflict: save and close merge view" })

-- Move between the two halves of a diff, or the panes of the merge view.
map("n", "<leader>cc", ui.switch_side, { desc = "Diff: other side" })

-- `<leader>cd` is Line Diagnostics in LazyVim and "switch diff side" in the
-- VS Code config. Inside a diff there are no diagnostics worth reading, so
-- letting context pick keeps both bindings honest.
map("n", "<leader>cd", function()
  if vim.wo.diff then
    ui.switch_side()
  else
    vim.diagnostic.open_float()
  end
end, { desc = "Diff: other side / Line diagnostics" })

map("n", "<leader>ci", ui.toggle_inline, { desc = "Diff: toggle inline / side-by-side" })

-- Revert. In diff mode `do` already pulls the other side's hunk in, which is
-- exactly `diffEditor.revert`; these just give it the VS Code names. The
-- inline overlay has its own revert, since there is no second window there.
map("n", "<leader>cv", function()
  local inline = require("util.inline_diff")
  if vim.wo.diff then
    vim.cmd("normal! do")
  elseif inline.has(0) then
    if not inline.revert_hunk(0) then
      vim.notify("Cursor is not on a change", vim.log.levels.INFO)
    end
  else
    local ok, gs = pcall(require, "gitsigns")
    if ok then
      gs.reset_hunk()
    end
  end
end, { desc = "Revert this change" })
map({ "n", "x" }, "<leader>cV", function()
  if vim.wo.diff then
    vim.cmd([['<,'>diffget]])
  else
    local ok, gs = pcall(require, "gitsigns")
    if ok then
      gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
    end
  end
end, { desc = "Revert selected range" })

--------------------------------------------------------------------------
-- which-key group labels
--------------------------------------------------------------------------

local ok, wk = pcall(require, "which-key")
if ok then
  wk.add({
    { "<leader>g", group = "source control" },
    { "<leader>c", group = "code / conflicts" },
  })
end
