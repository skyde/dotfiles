-- Run with: nvim --headless -u NONE -i NONE -l tests/nvim_ripgrep_spec.lua
--
-- util.ripgrep translates a Neovim filetype into ripgrep's name for it, which
-- <leader>st needs to scope a search to the current file's language. Getting it
-- wrong is not a near miss: `rg --type=typescriptreact` exits with
-- "unrecognized file type" and the search comes back empty.
--
-- The alias table is checked against the real `rg --type-list` when ripgrep is
-- installed, so it cannot rot silently; the rest runs anywhere.

local source = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(repo .. "/common/.config/nvim")

local rg = require("util.ripgrep")

local passed, failed = 0, 0
local failures = {}

local function check(name, ok, detail)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    table.insert(failures, name)
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

--------------------------------------------------------------------------
-- translation, against a stubbed type list
--------------------------------------------------------------------------

local real_system = vim.system
local real_executable = vim.fn.executable

---Pretend ripgrep is installed. util.ripgrep checks that before spawning
---anything, so a stub on vim.system alone is never reached on a machine without
---it — which is exactly the machine (a macOS CI runner) where this spec first
---went green locally and red in CI.
local function fake_rg_installed()
  vim.fn.executable = function(bin)
    if bin == "rg" then
      return 1
    end
    return real_executable(bin)
  end
end

local function restore_executable()
  vim.fn.executable = real_executable
end

---Run `fn` with `rg --type-list` answering `names`.
local function with_types(names, fn)
  rg.clear_cache()
  fake_rg_installed()
  vim.system = function(cmd, ...)
    if cmd[1] == "rg" and cmd[2] == "--type-list" then
      local lines = {}
      for _, name in ipairs(names) do
        table.insert(lines, name .. ": *." .. name)
      end
      return {
        wait = function()
          return { code = 0, stdout = table.concat(lines, "\n") .. "\n" }
        end,
      }
    end
    return real_system(cmd, ...)
  end
  local ok, err = pcall(fn)
  vim.system = real_system
  restore_executable()
  rg.clear_cache()
  assert(ok, err)
end

do
  with_types({ "c", "cpp", "python", "lua", "ts", "js", "sh", "md" }, function()
    eq("a filetype ripgrep knows passes through", "--type=cpp", rg.type_arg("cpp"))
    eq("an aliased filetype is translated", "--type=ts", rg.type_arg("typescriptreact"))
    eq("javascriptreact also lands on js", "--type=js", rg.type_arg("javascriptreact"))
    eq("bash is sh", "--type=sh", rg.type_arg("bash"))

    -- The whole point: an unknown name must become "search everything", not an
    -- argument ripgrep rejects.
    eq("an unknown filetype filters nothing", nil, rg.type_arg("nosuchfiletype"))
    eq("no filetype filters nothing", nil, rg.type_arg(""))
    eq("nil filetype filters nothing", nil, rg.type_arg(nil))

    -- An alias whose target this ripgrep lacks is still unknown.
    eq("an alias to a missing type filters nothing", nil, rg.type_arg("terraform"))
  end)

  -- The list is asked for once; <leader>st must not spawn a subprocess per
  -- keypress.
  local calls = 0
  rg.clear_cache()
  fake_rg_installed()
  vim.system = function(cmd, ...)
    if cmd[1] == "rg" and cmd[2] == "--type-list" then
      calls = calls + 1
      return {
        wait = function()
          return { code = 0, stdout = "cpp: *.cc\n" }
        end,
      }
    end
    return real_system(cmd, ...)
  end
  rg.type_arg("cpp")
  rg.type_arg("cpp")
  rg.type_arg("lua")
  vim.system = real_system
  restore_executable()
  eq("the type list is fetched once per session", 1, calls)
  rg.clear_cache()
end

do
  -- ripgrep missing, or `--type-list` failing, is not evidence that the
  -- filetype is wrong — dropping the filter there would silently widen every
  -- search instead.
  rg.clear_cache()
  fake_rg_installed()
  vim.system = function(cmd, ...)
    if cmd[1] == "rg" and cmd[2] == "--type-list" then
      return {
        wait = function()
          return { code = 2, stdout = "" }
        end,
      }
    end
    return real_system(cmd, ...)
  end
  eq("no type list: the filetype is trusted", "--type=cpp", rg.type_arg("cpp"))
  eq("no type list: aliases still apply", "--type=ts", rg.type_arg("typescriptreact"))
  vim.system = real_system
  restore_executable()
  rg.clear_cache()
end

--------------------------------------------------------------------------
-- the alias table against the ripgrep on this machine
--------------------------------------------------------------------------

if vim.fn.executable("rg") == 1 then
  rg.clear_cache()
  local types = rg.types()
  check("real rg: reports a type list", next(types) ~= nil)

  -- Every alias must name a type this ripgrep actually has, or the translation
  -- turns a working search into an empty one.
  local bad = {}
  for ft, name in pairs(rg.FT_TO_RG) do
    if not types[name] then
      table.insert(bad, ("%s -> %s"):format(ft, name))
    end
  end
  table.sort(bad)
  check("real rg: every alias names a type it knows", #bad == 0, table.concat(bad, ", "))

  -- Aliases ripgrep has since made unnecessary by learning the filetype's own
  -- name. Reported, not asserted: which of these are redundant depends on the
  -- ripgrep in front of you — Homebrew's has a `proto` type, the one in Debian
  -- does not — and an alias that is redundant here is still load-bearing on an
  -- older release. Pruning one is a decision about which ripgrep versions to
  -- support, not something CI should make by going red.
  local redundant = {}
  for ft in pairs(rg.FT_TO_RG) do
    if types[ft] then
      table.insert(redundant, ft)
    end
  end
  table.sort(redundant)
  if #redundant > 0 then
    print(
      ("NOTE this ripgrep (%s) knows these filetypes under their own names, so the aliases are redundant here: %s"):format(
        vim.trim(vim.system({ "rg", "--version" }, { text = true }):wait().stdout:match("^[^\n]*") or "?"),
        table.concat(redundant, ", ")
      )
    )
  end

  -- Spot-check the case that motivated all of this.
  eq("real rg: typescriptreact resolves", "--type=ts", rg.type_arg("typescriptreact"))
  check("real rg: does not know typescriptreact itself", not types["typescriptreact"])
  rg.clear_cache()
else
  print("SKIP alias table check (rg not installed)")
end

--------------------------------------------------------------------------

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  error("\n" .. table.concat(failures, "\n"))
end
