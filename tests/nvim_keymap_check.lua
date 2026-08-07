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
  " cz",
  " cv",
  " cI",
  -- Code actions are on <leader>ca, which LazyVim registers buffer-locally on
  -- LspAttach with `has = "codeAction"`. Nothing here attaches a language
  -- server, so there is no such buffer to invoke it in and this harness cannot
  -- cover it; the key itself is LazyVim's own default, not config of ours.
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
  -- <leader>ms is the only <leader>m key safe to invoke here: the others start
  -- a build or a debug session, which would hang waiting on a picker. Stopping
  -- with nothing running just says so.
  " ms",
  -- hover cluster
  "<BS><BS>",
  "<BS> ",
  " <BS>",
  -- footpedal macro keys. A terminal delivers Shift+Fn as <F(n+12)>, so that is
  -- the half that has to work; tests/check-footpedal-keys.py covers the
  -- transport, this just makes sure the callbacks do not throw.
  "<F14>", -- Shift+F2, build and run
  "<F15>", -- Shift+F3, find class / file
  "<F19>", -- Shift+F7, stop build
  "<F20>", -- Shift+F8, goto definition
  "<F21>", -- Shift+F9, jump forward
}

--------------------------------------------------------------------------
-- docs/nvim-vscode-parity.md promises these keys exist
--------------------------------------------------------------------------

-- That document is the config's contract — it is what the README points at and
-- what the VS Code side was built to match — so a key listed there and bound
-- nowhere is a broken promise, not a stale comment. Checked here because it
-- needs the config as actually assembled: LazyVim's defaults, the lazy `keys`
-- triggers and config/*.lua all have a say in what ends up mapped.
--
-- Only table rows count. The prose names key *families* (`<leader>g`,
-- `<leader>t`) and, in "Deliberate differences", keys it explains are
-- deliberately absent — neither is a claim that a mapping exists.
local function check_documented_keys()
  local doc = vim.fn.fnamemodify(vim.env.NVIM_KEYMAP_REPO or ".", ":p") .. "docs/nvim-vscode-parity.md"
  local fd = io.open(doc)
  if not fd then
    table.insert(errors, "parity doc not found at " .. doc)
    return
  end

  -- One key, three spellings: the document says Backspace, the dap spec writes
  -- <backspace>, and nvim_get_keymap reports <BS>. Normalize all of them onto
  -- the last, so neither direction of this check reads them as different keys.
  local ALIASES = {
    ["<leader>Backspace"] = "<leader><BS>",
    ["<leader><backspace>"] = "<leader><BS>",
  }
  -- LazyVim registers these on LspAttach with a `has` capability guard, so they
  -- exist only in a buffer with a language server attached — which this harness
  -- deliberately does not have.
  local LSP_BUFFER_LOCAL = { ["<leader>ca"] = true, ["<leader>cr"] = true }

  local documented = {}
  for line in fd:lines() do
    if line:match("^%s*|") then
      for key in line:gmatch("`(<leader>[^`]+)`") do
        documented[ALIASES[key] or key] = true
      end
    end
  end
  fd:close()

  local mapped = {}
  for _, mode in ipairs({ "n", "x", "v", "o", "i" }) do
    for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
      mapped[m.lhs] = true
    end
  end

  local missing, total = {}, 0
  for key in pairs(documented) do
    total = total + 1
    if not LSP_BUFFER_LOCAL[key] then
      -- Leader is <space>, which nvim_get_keymap reports literally — including
      -- in <leader><leader>, hence a global substitution.
      local lhs = key:gsub("<leader>", " ")
      if not mapped[lhs] then
        table.insert(missing, key)
      end
    end
  end
  table.sort(missing)
  table.insert(results, ("parity doc: %d documented keys"):format(total))
  for _, key in ipairs(missing) do
    table.insert(errors, ("%s is in docs/nvim-vscode-parity.md but mapped nowhere"):format(key))
  end

  -- The other direction: a binding this config adds and never documents is the
  -- same drift seen from the other side, and the likelier one — the document is
  -- edited deliberately, a keymap gets added in passing.
  --
  -- Read from the source rather than from nvim_get_keymap, because that reports
  -- LazyVim's ~100 defaults too and this is only about the keys this config
  -- introduces. Only config/ and plugins/ — util/ and dotfiles/ mention keys in
  -- user-facing messages, not as bindings.
  local repo = vim.fn.fnamemodify(vim.env.NVIM_KEYMAP_REPO or ".", ":p")
  local undocumented = {}
  for _, dir in ipairs({ "config", "plugins" }) do
    local path = repo .. "common/.config/nvim/lua/" .. dir
    for name, kind in vim.fs.dir(path) do
      if kind == "file" and name:match("%.lua$") then
        local lnum = 0
        for line in io.lines(path .. "/" .. name) do
          lnum = lnum + 1
          -- A which-key group label declares a prefix, not a binding.
          if not line:find("group%s*=") then
            for key in line:gmatch('"(<leader>[^"%s]*)"') do
              -- A bare "<leader>" is a prefix being concatenated (the tab-number
              -- loop), not a key in its own right.
              if key ~= "<leader>" and not documented[ALIASES[key] or key] then
                table.insert(undocumented, ("%s (%s/%s:%d)"):format(key, dir, name, lnum))
              end
            end
          end
        end
      end
    end
  end
  table.sort(undocumented)
  for _, entry in ipairs(undocumented) do
    table.insert(errors, ("%s is mapped but absent from docs/nvim-vscode-parity.md"):format(entry))
  end
end

local ok, err = xpcall(function()
  for _, k in ipairs(keys) do
    invoke(k)
  end
  for _, k in ipairs({ " cV" }) do
    invoke(k, "x")
  end
  invoke("ig", "o")
  invoke("ig", "x")
  check_documented_keys()
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
