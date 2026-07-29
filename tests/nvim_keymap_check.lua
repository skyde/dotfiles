-- Run with: tests/check-nvim-keymaps.sh
--
-- Unlike the *_spec.lua files this needs the real config loaded, because the
-- point is to check the bindings as they actually end up after LazyVim, the
-- plugin specs and config/keymaps.lua have all had their say.
--
-- Every binding is invoked. Callback maps are called and must not raise, even
-- with no language server and no debug session attached — degrading with a
-- message is fine, throwing is not. String-rhs maps are checked structurally,
-- since feeding their keys would change mode mid-run.

local report = vim.env.NVIM_KEYMAP_REPORT or "/tmp/nvim-keymap-check.txt"
local results, errors, spawned = {}, {}, {}

local function flush(note)
  local out = { ("invoked %d, errors %d%s"):format(#results, #errors, note or "") }
  for _, e in ipairs(errors) do
    table.insert(out, "ERROR " .. tostring(e):gsub("\n", " | "))
  end
  table.insert(out, "-- external commands --")
  for _, s in ipairs(spawned) do
    table.insert(out, "  " .. s)
  end
  vim.fn.writefile(out, report)
end

-- Let git and jj actually run; stop anything that would take over the desktop
-- or spawn a long-lived process.
local real_system, real_jobstart = vim.system, vim.fn.jobstart
local blocked = { open = true, ["xdg-open"] = true, explorer = true, kitty = true }
vim.system = function(cmd, ...)
  if type(cmd) == "table" and blocked[cmd[1]] then
    table.insert(spawned, "blocked " .. table.concat(cmd, " "))
    return real_system({ "true" })
  end
  return real_system(cmd, ...)
end
vim.fn.jobstart = function(cmd, ...)
  table.insert(spawned, "jobstart " .. (type(cmd) == "table" and table.concat(cmd, " ") or tostring(cmd)))
  return real_jobstart({ "true" })
end
vim.ui.select = function(_, _, cb)
  cb(nil)
end
vim.ui.input = function(_, cb)
  cb(nil)
end

local function cleanup()
  pcall(vim.cmd, "silent! stopinsert")
  -- Closing one float can take others with it, so re-check validity as we go.
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(w) and vim.api.nvim_win_get_config(w).relative ~= "" then
      pcall(vim.api.nvim_win_close, w, true)
    end
  end
  for _ = 1, 8 do
    if #vim.api.nvim_list_tabpages() <= 1 then
      break
    end
    local before = #vim.api.nvim_list_tabpages()
    pcall(vim.cmd, "tabclose!")
    if #vim.api.nvim_list_tabpages() == before then
      table.insert(errors, "cleanup could not close a tab")
      break
    end
  end
  pcall(vim.cmd, "silent! only")
end

local function invoke(lhs, mode)
  local found
  for _, m in ipairs(vim.api.nvim_get_keymap(mode or "n")) do
    if m.lhs == lhs then
      found = m
      break
    end
  end
  if not found then
    table.insert(errors, (mode or "n") .. " " .. lhs .. " is not mapped")
    return
  end
  if not found.callback then
    if found.rhs and #found.rhs > 0 then
      table.insert(results, lhs)
    else
      table.insert(errors, lhs .. " has an empty rhs")
    end
    return
  end
  local ok, err = pcall(found.callback)
  if ok then
    table.insert(results, lhs)
  else
    table.insert(errors, lhs .. " -> " .. tostring(err))
  end
  cleanup()
  flush(("  (last: %s)"):format(lhs))
end

-- Leader is <space>, which nvim_get_keymap reports literally.
local keys = {
  -- source control
  " gc",
  " gd",
  " gD",
  " ga",
  " gA",
  " gp",
  " gy",
  " gl",
  " gw",
  " gR",
  " gC",
  -- diffs and conflicts
  " cn",
  " cp",
  " co",
  " cO",
  " ct",
  " cT",
  " cb",
  " cB",
  " c0",
  " cm",
  " cq",
  " cc",
  " cd",
  " ci",
  " cv",
  " ce",
  " cI",
  "]c",
  "[c",
  "]x",
  "[x",
  -- goto
  "gi",
  "gp",
  "gu",
  "gn",
  "gh",
  -- palette, files, search
  " p",
  " E",
  " sb",
  " sr",
  " sz",
  " si",
  -- ui
  " up",
  " um",
  " ur",
  -- debug stepping, then debug actions, with nothing running
  " tn",
  " ti",
  " to",
  " tu",
  " td",
  " tc",
  " tl",
  " tw",
  " tb",
  " th",
  " dp",
  " dS",
  " dR",
  " dg",
  " dL",
  " dw",
  " dx",
  " db",
  -- hover cluster
  "<BS><BS>",
  "<BS> ",
  " <BS>",
}

local ok, err = xpcall(function()
  for _, k in ipairs(keys) do
    invoke(k)
  end
  for _, k in ipairs({ " cV", " ce" }) do
    invoke(k, "x")
  end
  invoke("ig", "o")
  invoke("ig", "x")
end, debug.traceback)

vim.system, vim.fn.jobstart = real_system, real_jobstart
if not ok then
  table.insert(errors, "driver: " .. tostring(err))
end
flush("  (complete)")

print(("keymap check: invoked %d, errors %d"):format(#results, #errors))
for _, e in ipairs(errors) do
  print("  ERROR " .. tostring(e):gsub("\n", " | "))
end
if #errors > 0 then
  vim.cmd("cquit 1")
end
