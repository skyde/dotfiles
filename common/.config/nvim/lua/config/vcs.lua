local M = {}

local compare_bases = {}

local function cwd()
  return vim.uv.cwd() or vim.fn.getcwd()
end

local function run(command, directory)
  local result = vim
    .system(command, {
      cwd = directory or cwd(),
      text = true,
    })
    :wait()

  return result.code == 0, vim.trim(result.stdout or ""), vim.trim(result.stderr or "")
end

local function current_file()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    vim.notify("The current buffer is not a file", vim.log.levels.WARN)
    return nil
  end
  return vim.fs.normalize(path)
end

local function p4_command()
  local configured = vim.env.NVIM_PERFORCE_CMD
  if configured and configured ~= "" then
    return configured
  end

  local shim = vim.fn.exepath("vcs-p4")
  if shim ~= "" then
    return shim
  end
  if vim.fn.executable("g4") == 1 then
    return "g4"
  end
  return "p4"
end

local function preferred_adapter()
  local ok, config = pcall(require, "diffview.config")
  if not ok then
    local configured = vim.env.NVIM_VCS
    if configured == "g4" then
      return "p4"
    end
    if vim.tbl_contains({ "git", "hg", "jj", "p4" }, configured) then
      return configured
    end
    return "jj"
  end
  return config.get_config().preferred_adapter
end

local function provider()
  local preferred = preferred_adapter()

  if preferred == "jj" then
    local ok = run({ "jj", "root" })
    if ok then
      return "jj"
    end
  elseif preferred == "p4" then
    local ok = run({ p4_command(), "info" })
    if ok then
      return "p4"
    end
  elseif preferred == "git" then
    local ok = run({ "git", "rev-parse", "--show-toplevel" })
    if ok then
      return "git"
    end
  end

  local is_git = run({ "git", "rev-parse", "--show-toplevel" })
  if is_git then
    return "git"
  end

  local is_jj = run({ "jj", "root" })
  if is_jj then
    return "jj"
  end

  if vim.fn.executable(p4_command()) == 1 then
    local is_p4 = run({ p4_command(), "info" })
    if is_p4 then
      return "p4"
    end
  end

  return nil
end

local function root_for(kind)
  if kind == "git" then
    local ok, root = run({ "git", "rev-parse", "--show-toplevel" })
    return ok and root or cwd()
  elseif kind == "jj" then
    local ok, root = run({ "jj", "root" })
    return ok and root or cwd()
  elseif kind == "p4" then
    local ok, output = run({ p4_command(), "info" })
    if ok then
      local root = output:match("Client root:%s*([^\n]+)")
      if root then
        return vim.trim(root)
      end
    end
  end
  return cwd()
end

local function git_upstream()
  local ok, upstream = run({ "git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}" })
  if ok and upstream ~= "" then
    return upstream
  end

  return nil
end

local function git_base()
  local ok, remote_head = run({ "git", "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD" })
  if ok and remote_head ~= "" then
    return remote_head
  end

  for _, candidate in ipairs({ "origin/main", "origin/master", "main", "master" }) do
    local exists = run({ "git", "rev-parse", "--verify", "--quiet", candidate })
    if exists then
      return candidate
    end
  end

  return "HEAD"
end

local function default_base(kind)
  if kind == "git" then
    return git_base()
  elseif kind == "jj" then
    return "trunk()"
  end
  return nil
end

local function remembered_base(kind)
  local root = root_for(kind)
  return compare_bases[root] or default_base(kind), root
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

local function open_diff(range, path)
  local args = {}
  if range and range ~= "" then
    table.insert(args, vim.fn.fnameescape(range))
  end
  if path then
    vim.list_extend(args, { "--", vim.fn.fnameescape(path) })
  end
  vim.api.nvim_cmd({ cmd = "DiffviewOpen", args = args }, {})
end

function M.changes()
  local ok, lib = pcall(require, "diffview.lib")
  if ok and lib.get_current_view() then
    require("diffview.actions").focus_files()
    return
  end
  open_diff()
end

function M.current_file()
  local path = current_file()
  if path then
    open_diff(nil, path)
  end
end

function M.current_change()
  local path = current_file()
  if not path then
    return
  end

  local kind = provider()
  local base = kind == "git" and "HEAD" or kind == "jj" and "@-" or nil
  open_diff(base, path)
end

function M.branch_diff()
  local kind = provider()
  if not kind then
    vim.notify("No Git, JJ, P4, or G4 workspace found", vim.log.levels.WARN)
    return
  end

  local base = remembered_base(kind)
  open_diff(revision_range(kind, base))
end

function M.upstream_patch()
  local kind = provider()
  if not kind then
    vim.notify("No Git, JJ, P4, or G4 workspace found", vim.log.levels.WARN)
    return
  end

  if kind == "git" then
    open_diff(revision_range(kind, git_upstream() or git_base()))
  elseif kind == "jj" then
    open_diff("@-...@")
  else
    open_diff()
  end
end

function M.choose_base()
  local kind = provider()
  if not kind then
    vim.notify("No Git, JJ, P4, or G4 workspace found", vim.log.levels.WARN)
    return
  end

  local base, root = remembered_base(kind)
  local default = revision_range(kind, base) or ""
  vim.ui.input({
    prompt = ("%s compare revision/range: "):format(kind:upper()),
    default = default,
  }, function(choice)
    if not choice or vim.trim(choice) == "" then
      return
    end
    choice = vim.trim(choice)
    compare_bases[root] = choice
    open_diff(choice)
  end)
end

function M.choose_adapter()
  require("lazy").load({ plugins = { "diffview-plus.nvim" } })

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
    vim.notify("Diffview adapter: " .. (choice.label or "Auto detect"))
  end)
end

function M.file_history()
  local path = current_file()
  if path then
    vim.api.nvim_cmd({ cmd = "DiffviewFileHistory", args = { vim.fn.fnameescape(path) } }, {})
  end
end

function M.repo_history()
  vim.cmd("DiffviewFileHistory")
end

function M.refresh()
  vim.cmd("DiffviewRefresh!")
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
  vim.cmd("DiffviewClose")
end

local function base_from_range(value)
  if not value then
    return nil
  end
  return value:match("^(.-)%.%.%.") or value:match("^(.-)%.%.") or value
end

function M.copy_diff()
  local kind = provider()
  if not kind then
    vim.notify("No Git, JJ, P4, or G4 workspace found", vim.log.levels.WARN)
    return
  end

  local base = base_from_range(remembered_base(kind))
  local command
  if kind == "git" then
    command = { "git", "diff", base or "HEAD", "--" }
  elseif kind == "jj" then
    command = { "jj", "diff", "--git", "--color=never", "--from", base or "@-", "--to", "@" }
  else
    command = { p4_command(), "diff", "-du" }
  end

  local ok, output, err = run(command, root_for(kind))
  if not ok then
    vim.notify(err ~= "" and err or "Unable to create diff", vim.log.levels.ERROR)
    return
  end
  if output == "" then
    vim.notify("There are no changes to copy", vim.log.levels.INFO)
    return
  end

  vim.fn.setreg("+", output .. "\n")
  vim.notify(("Copied %s diff (%d lines)"):format(kind:upper(), #vim.split(output, "\n")))
end

function M.info()
  local kind = provider()
  if not kind then
    vim.notify("VCS: none detected")
    return
  end

  local base = remembered_base(kind)
  local details = { "VCS: " .. kind:upper(), "root: " .. root_for(kind) }
  if base then
    table.insert(details, "compare base: " .. base)
  end
  if kind == "p4" then
    table.insert(details, "command: " .. p4_command())
  end
  vim.notify(table.concat(details, "\n"))
end

return M
