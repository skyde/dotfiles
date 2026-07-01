-- Cross-VCS diffing.
--
-- diffview.nvim is the rich diff viewer (git and colocated jj repos):
--   <leader>gd   Diffview of working tree changes (toggle)
--   <leader>gD   Diffview of all changes vs upstream (merge-base, includes uncommitted)
--   <leader>gH   Diffview history of the current file
--
-- mini.diff is the hunk engine (replaces gitsigns) with sources for git,
-- Jujutsu (diff vs @-) and Perforce (diff vs #have), so signs, hunk
-- navigation and hunk revert work the same in all three:
--   ]h / [h            next / previous hunk (]H / [H last / first)
--   gh / gH            apply (stage) / reset hunk operator or visual selection
--   <leader>ghs/ghr    stage / reset hunk under cursor
--   <leader>ghS/ghR    stage / reset whole buffer
--   <leader>go         toggle inline diff overlay (any VCS)
--   <leader>gv         vertical split diff of buffer vs its VCS base (any VCS)

local function buf_path(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" or vim.fn.filereadable(path) == 0 then
    return nil
  end
  return path
end

-- Build a mini.diff source that fills reference text from a CLI command.
-- Attach is async: reference text is set (or attach failed) when the command
-- finishes, and the base is re-fetched on write/re-enter so external changes
-- (jj new, p4 sync, ...) are picked up.
local function make_cli_source(spec)
  local augroups = {}

  local function update(buf, is_attach)
    local path = buf_path(buf)
    if path == nil then
      return false
    end
    local argv, cwd = spec.ref_cmd(path)
    vim.system(argv, { cwd = cwd, text = true }, function(res)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        local MiniDiff = require("mini.diff")
        if res.code ~= 0 or not pcall(MiniDiff.set_ref_text, buf, res.stdout or "") then
          if is_attach then
            MiniDiff.fail_attach(buf)
          end
          return
        end
        if is_attach and augroups[buf] == nil then
          local group = vim.api.nvim_create_augroup("vcs_diff_" .. spec.name .. "_" .. buf, { clear = true })
          augroups[buf] = group
          vim.api.nvim_create_autocmd({ "BufWritePost", "BufEnter", "FocusGained" }, {
            group = group,
            buffer = buf,
            callback = function()
              update(buf, false)
            end,
          })
        end
      end)
    end)
  end

  return {
    name = spec.name,
    attach = function(buf)
      local path = buf_path(buf)
      if path == nil or vim.fn.executable(spec.exe) == 0 or not spec.is_usable(path) then
        return false
      end
      return update(buf, true)
    end,
    detach = function(buf)
      if augroups[buf] then
        pcall(vim.api.nvim_del_augroup_by_id, augroups[buf])
        augroups[buf] = nil
      end
    end,
    apply_hunks = function()
      vim.notify("Staging hunks is not supported for " .. spec.name .. "; use reset (gH) instead", vim.log.levels.WARN)
    end,
  }
end

-- Jujutsu: diff against the working copy's parent (@-). Only used for
-- non-colocated repos; colocated ones have .git and use the git source.
local function jj_source()
  return make_cli_source({
    name = "jj",
    exe = "jj",
    is_usable = function(path)
      return vim.fs.root(path, ".jj") ~= nil
    end,
    ref_cmd = function(path)
      -- quote as a fileset string literal so spaces etc. don't break parsing
      local name = '"' .. (vim.fs.basename(path):gsub("\\", "\\\\"):gsub('"', '\\"')) .. '"'
      return { "jj", "file", "show", "-r", "@-", name }, vim.fs.dirname(path)
    end,
  })
end

-- Perforce: diff against the synced revision (#have). Only attempted when a
-- p4 context is configured, to avoid pointless server round-trips.
local function p4_source()
  return make_cli_source({
    name = "p4",
    exe = "p4",
    is_usable = function(path)
      if vim.env.P4CLIENT or vim.env.P4CONFIG or vim.env.P4PORT then
        return true
      end
      return vim.fs.root(path, { ".p4config" }) ~= nil
    end,
    ref_cmd = function(path)
      return { "p4", "print", "-q", path .. "#have" }, vim.fs.dirname(path)
    end,
  })
end

-- Side-by-side diff of the current buffer against whatever base mini.diff
-- attached (git index, jj @-, p4 #have). Works where diffview can't (p4, jj).
local function diff_split_vs_base()
  local MiniDiff = require("mini.diff")
  local data = MiniDiff.get_buf_data(0)
  if data == nil or data.ref_text == nil then
    return vim.notify("No VCS base available for this buffer", vim.log.levels.WARN)
  end
  local ft = vim.bo.filetype
  local title = vim.fn.expand("%:t") .. " (base)"
  local ref_lines = vim.split(data.ref_text, "\n")
  if ref_lines[#ref_lines] == "" then
    table.remove(ref_lines)
  end
  vim.cmd("leftabove vertical new")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, ref_lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = ft
  vim.bo[buf].modifiable = false
  pcall(vim.api.nvim_buf_set_name, buf, title)
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(function()
        pcall(vim.cmd, "diffoff!")
      end)
    end,
  })
  vim.cmd("diffthis")
  vim.cmd("wincmd p")
  vim.cmd("diffthis")
end

local function git_out(args, cwd)
  local res = vim.system(vim.list_extend({ "git" }, args), { cwd = cwd, text = true }):wait()
  if res.code ~= 0 then
    return nil
  end
  local out = vim.trim(res.stdout or "")
  return out ~= "" and out or nil
end

-- Diff everything (committed + uncommitted) since diverging from upstream:
-- open diffview against merge-base(upstream, HEAD).
local function diffview_vs_upstream()
  local cwd = vim.fn.expand("%:p:h")
  if cwd == "" or vim.fn.isdirectory(cwd) == 0 then
    cwd = vim.uv.cwd()
  end
  local upstream = git_out({ "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}" }, cwd)
  if upstream == nil then
    for _, rev in ipairs({ "origin/HEAD", "origin/main", "origin/master", "main", "master" }) do
      if git_out({ "rev-parse", "--verify", "--quiet", rev }, cwd) then
        upstream = rev
        break
      end
    end
  end
  local base = upstream and git_out({ "merge-base", upstream, "HEAD" }, cwd)
  if base == nil then
    return vim.notify("Could not determine an upstream to diff against", vim.log.levels.WARN)
  end
  vim.notify("Diff vs " .. upstream .. " (merge-base " .. base:sub(1, 8) .. ")")
  vim.cmd("DiffviewOpen " .. base)
end

local function diffview_toggle()
  if require("diffview.lib").get_current_view() then
    vim.cmd("DiffviewClose")
  else
    vim.cmd("DiffviewOpen")
  end
end

return {
  -- mini.diff takes over hunk signs/operations for all VCSes
  { "lewis6991/gitsigns.nvim", enabled = false },

  {
    "echasnovski/mini.diff",
    event = "LazyFile",
    keys = {
      {
        "<leader>go",
        function()
          require("mini.diff").toggle_overlay(0)
        end,
        desc = "Toggle Diff Overlay",
      },
      { "<leader>gv", diff_split_vs_base, desc = "Diff Split vs Base" },
      { "<leader>ghs", "ghgh", remap = true, desc = "Stage Hunk" },
      { "<leader>ghr", "gHgh", remap = true, desc = "Reset (Revert) Hunk" },
      { "<leader>ghs", "gh", mode = "v", remap = true, desc = "Stage Selection" },
      { "<leader>ghr", "gH", mode = "v", remap = true, desc = "Reset (Revert) Selection" },
      {
        "<leader>ghS",
        function()
          require("mini.diff").do_hunks(0, "apply")
        end,
        desc = "Stage Buffer",
      },
      {
        "<leader>ghR",
        function()
          require("mini.diff").do_hunks(0, "reset")
        end,
        desc = "Reset (Revert) Buffer",
      },
    },
    opts = function()
      return {
        -- tried in order: git index, then jj, then p4
        source = { require("mini.diff").gen_source.git(), jj_source(), p4_source() },
        view = {
          style = "sign",
          signs = { add = "▎", change = "▎", delete = "" },
        },
        options = { wrap_goto = true },
      }
    end,
    config = function(_, opts)
      require("mini.diff").setup(opts)
      -- LazyVim's lualine diff component reads gitsigns' buffer dict; feed it
      -- from mini.diff so the statusline keeps working with gitsigns disabled
      vim.api.nvim_create_autocmd("User", {
        pattern = "MiniDiffUpdated",
        callback = function(ev)
          local summary = vim.b[ev.buf].minidiff_summary
          if summary == nil then
            return
          end
          vim.b[ev.buf].gitsigns_status_dict = {
            added = summary.add,
            changed = summary.change,
            removed = summary.delete,
          }
        end,
      })
    end,
  },

  {
    "sindrets/diffview.nvim",
    cmd = {
      "DiffviewOpen",
      "DiffviewClose",
      "DiffviewFileHistory",
      "DiffviewToggleFiles",
      "DiffviewFocusFiles",
      "DiffviewRefresh",
      "DiffviewLog",
    },
    keys = {
      { "<leader>gd", diffview_toggle, desc = "Diffview: Working Changes (toggle)" },
      { "<leader>gD", diffview_vs_upstream, desc = "Diffview: Diff vs Upstream" },
      { "<leader>gH", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: File History" },
    },
    opts = {
      enhanced_diff_hl = true,
    },
  },

  {
    "folke/which-key.nvim",
    optional = true,
    opts = {
      spec = {
        { "<leader>gh", group = "hunks" },
      },
    },
  },
}
