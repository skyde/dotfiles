-- Run with: nvim --headless -u NONE -i NONE -l tests/nvim_health_spec.lua
--
-- Exercises `:checkhealth dotfiles` (common/.config/nvim/lua/dotfiles/health.lua)
-- by swapping vim.health for a recorder and driving the check with a PATH built
-- for the case under test. That is the only way to assert on it: the real
-- vim.health writes into a checkhealth buffer, and what matters here is what the
-- report says, not how it is drawn.
--
-- The point of the module is to be right about a machine it did not expect, so
-- most of what follows is the unhappy paths: nothing installed, a VCS but no
-- TUI, SSH without the OSC helpers.

local source = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(repo .. "/common/.config/nvim")

local health = require("dotfiles.health")
local vcs = require("util.vcs")

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

local temp = vim.fn.tempname()
vim.fn.mkdir(temp .. "/bin", "p")

---An executable on PATH that answers --version and nothing else.
local function fake(name, output)
  local path = temp .. "/bin/" .. name
  vim.fn.writefile({ "#!/bin/sh", ("echo %q"):format(output or (name .. " 1.0")) }, path)
  assert(vim.uv.fs_chmod(path, 493))
end

--------------------------------------------------------------------------
-- the recorder
--------------------------------------------------------------------------

local real_health, real_path, real_env = vim.health, vim.env.PATH, {}

---Run the whole check with `path` as PATH and the given environment overrides,
---and return the report as a flat list of { level, message, advice } plus the
---section headings in order.
---@param opts { path?: string, env?: table<string, string|nil>, cwd?: string }
local function report(opts)
  opts = opts or {}
  local entries, sections = {}, {}
  local current
  vim.health = {
    start = function(name)
      current = name
      table.insert(sections, name)
    end,
    ok = function(msg)
      table.insert(entries, { level = "ok", section = current, msg = msg })
    end,
    info = function(msg)
      table.insert(entries, { level = "info", section = current, msg = msg })
    end,
    warn = function(msg, advice)
      table.insert(entries, { level = "warn", section = current, msg = msg, advice = advice })
    end,
    error = function(msg, advice)
      table.insert(entries, { level = "error", section = current, msg = msg, advice = advice })
    end,
  }
  -- The module binds vim.health at load, so it has to be re-required against
  -- the recorder rather than reused from the top of this file.
  package.loaded["dotfiles.health"] = nil

  vim.env.PATH = opts.path or (temp .. "/bin")
  for name, value in pairs(opts.env or {}) do
    real_env[name] = vim.env[name]
    vim.env[name] = value
  end
  -- Detection shells out and memoises per directory; a PATH change has to
  -- invalidate that or every case after the first sees the first one's answer.
  vcs.clear_cache()

  local ok, err = pcall(function()
    require("dotfiles.health").check()
  end)

  for name in pairs(opts.env or {}) do
    vim.env[name] = real_env[name]
  end
  vim.env.PATH = real_path
  vim.health = real_health
  package.loaded["dotfiles.health"] = health

  assert(ok, err)
  return entries, sections
end

---Every message at `level`, joined — enough to assert "the report says this".
local function text(entries, level)
  local out = {}
  for _, e in ipairs(entries) do
    if not level or e.level == level then
      table.insert(out, e.msg)
    end
  end
  return table.concat(out, "\n")
end

local function find(entries, level, needle)
  for _, e in ipairs(entries) do
    if e.level == level and e.msg:find(needle, 1, true) then
      return e
    end
  end
  return nil
end

--------------------------------------------------------------------------
-- structure
--------------------------------------------------------------------------

do
  local entries, sections = report({})
  eq("sections: all six, in a fixed order", {
    "Neovim",
    "Source control",
    "Clipboard",
    "Search and files",
    "C++ / Chromium",
    "Terminal integration",
  }, sections)

  -- check() wraps each section in pcall and reports a throw as an error naming
  -- itself; nothing should be reaching that path.
  check("structure: no section threw", not find(entries, "error", "this check itself failed"), text(entries, "error"))

  -- The order is fixed rather than incidental, so a second run must match.
  local _, again = report({})
  eq("sections: stable across runs", sections, again)

  check(
    "structure: every entry belongs to a section",
    (function()
      for _, e in ipairs(entries) do
        if not e.section then
          return false
        end
      end
      return true
    end)()
  )
end

--------------------------------------------------------------------------
-- Neovim
--------------------------------------------------------------------------

do
  local entries = report({})
  local v = vim.version()
  check(
    "neovim: reports the running version",
    find(entries, "ok", ("Neovim %d.%d.%d"):format(v.major, v.minor, v.patch)) ~= nil,
    text(entries)
  )

  -- The providers are off in config/options.lua on purpose, and :checkhealth
  -- provider calls that a problem; this has to say otherwise. The spec runs
  -- with -u NONE, so set the flags the way options.lua would.
  local saved = {}
  for _, name in ipairs({ "python3", "ruby", "node", "perl" }) do
    saved[name] = vim.g["loaded_" .. name .. "_provider"]
    vim.g["loaded_" .. name .. "_provider"] = 0
  end
  local with_providers_off = report({})
  for _, name in ipairs({ "python3", "ruby", "node", "perl" }) do
    vim.g["loaded_" .. name .. "_provider"] = saved[name]
  end
  local note = find(with_providers_off, "info", "remote-plugin providers disabled on purpose")
  check("neovim: disabled providers are stated as deliberate", note ~= nil, text(with_providers_off, "info"))
  check(
    "neovim: names every disabled provider",
    note ~= nil and note.msg:find("python3") and note.msg:find("perl"),
    note and note.msg
  )
end

--------------------------------------------------------------------------
-- source control: nothing installed
--------------------------------------------------------------------------

do
  -- An empty PATH is the sharpest version of the question this module exists to
  -- answer, and the case most likely to make it throw rather than report.
  local entries = report({ path = temp .. "/empty" })
  check(
    "bare machine: no VCS client is an error",
    find(entries, "error", "no version-control client found") ~= nil,
    text(entries, "error")
  )
  check("bare machine: ripgrep is an error", find(entries, "error", "rg not found") ~= nil, text(entries, "error"))
  check(
    "bare machine: no clipboard provider is an error",
    find(entries, "error", "no clipboard provider") ~= nil,
    text(entries, "error")
  )
  check(
    "bare machine: delta only warns, since the diffs do not need it",
    find(entries, "warn", "delta not found") ~= nil,
    text(entries, "warn")
  )
  local delta = find(entries, "warn", "delta not found")
  check(
    "bare machine: the delta warning says what still works",
    delta and delta.advice and table.concat(delta.advice, " "):find("never shell out to delta", 1, true) ~= nil,
    delta and vim.inspect(delta.advice)
  )
  check(
    "bare machine: yazi is only informational — there are two fallbacks",
    find(entries, "info", "yazi not found") ~= nil,
    text(entries, "info")
  )
  check(
    "bare machine: not a Chromium checkout, and it says so once",
    find(entries, "info", "not inside a Chromium checkout") ~= nil,
    text(entries, "info")
  )
end

--------------------------------------------------------------------------
-- source control: a git machine, with and without a TUI
--------------------------------------------------------------------------

do
  fake("git", "git version 2.99.0")
  fake("rg", "ripgrep 14.0.0")
  fake("delta", "delta 0.18.0")

  local entries = report({})
  check("git machine: lists the backends found", find(entries, "ok", "backends available: git") ~= nil, text(entries))
  check("git machine: delta is reported ok", find(entries, "ok", "delta 0.18.0") ~= nil, text(entries, "ok"))
  check(
    "git machine: no lazygit is a warning with the install script",
    (function()
      local e = find(entries, "warn", "lazygit not found")
      return e and e.advice and table.concat(e.advice, " "):find("install-lazygit.sh", 1, true) ~= nil
    end)(),
    text(entries, "warn")
  )

  fake("lazygit", "lazygit 0.44")
  local with_tui = report({})
  check(
    "git machine: lazygit present is reported as what <leader>gg opens",
    find(with_tui, "ok", "<leader>gg opens lazygit") ~= nil,
    text(with_tui, "ok")
  )
  check("git machine: and no longer warns about it", find(with_tui, "warn", "lazygit") == nil, text(with_tui, "warn"))
end

--------------------------------------------------------------------------
-- a configured clipboard provider that is not installed
--------------------------------------------------------------------------

do
  -- config/options.lua sets vim.g.clipboard to win32yank on Windows whether or
  -- not it is installed, and Neovim does not fall back once that is set — every
  -- yank becomes a silent no-op. Reporting the provider by name and calling it
  -- ok was the one way this check could be wrong and look right.
  local real_clipboard = vim.g.clipboard
  vim.g.clipboard = {
    name = "win32yank-lf",
    copy = { ["+"] = { "win32yank.exe", "-i", "--crlf" } },
    paste = { ["+"] = { "win32yank.exe", "-o", "--lf" } },
  }
  local entries = report({})
  local err = find(entries, "error", "win32yank.exe is not on PATH")
  check("configured provider: a missing binary is an error", err ~= nil, text(entries, "error") .. text(entries, "ok"))
  check(
    "configured provider: the advice says what to do",
    err and table.concat(err.advice or {}, " "):find("Install win32yank.exe", 1, true) ~= nil,
    err and vim.inspect(err.advice)
  )
  check(
    "configured provider: and it is not also reported ok",
    find(entries, "ok", "provider: win32yank-lf") == nil,
    text(entries, "ok")
  )

  fake("win32yank.exe")
  local installed = report({})
  check(
    "configured provider: present, it is reported ok",
    find(installed, "ok", "provider: win32yank-lf") ~= nil,
    text(installed, "ok")
  )
  check(
    "configured provider: and no longer an error",
    find(installed, "error", "win32yank.exe") == nil,
    text(installed, "error")
  )
  vim.g.clipboard = real_clipboard
end

--------------------------------------------------------------------------
-- clipboard over SSH
--------------------------------------------------------------------------

do
  -- Yanking over SSH goes through osc-copy/osc-paste; missing, the "+" register
  -- silently swallows everything, which is precisely the failure worth naming.
  local entries = report({ env = { SSH_TTY = "/dev/pts/9" } })
  local warn = find(entries, "warn", "over SSH/tmux but")
  check("ssh: missing OSC helpers are named", warn ~= nil, text(entries, "warn"))
  -- Plain find: "osc-copy" as a pattern is `osc` + a lazy quantifier + `copy`,
  -- which does not match the literal text.
  check(
    "ssh: names both helpers",
    warn and warn.msg:find("osc-copy", 1, true) and warn.msg:find("osc-paste", 1, true),
    warn and warn.msg
  )
  check(
    "ssh: says where they come from",
    warn and warn.advice and table.concat(warn.advice, " "):find("common/.local/bin", 1, true) ~= nil,
    warn and vim.inspect(warn.advice)
  )

  fake("osc-copy")
  local one_missing = report({ env = { SSH_TTY = "/dev/pts/9" } })
  local single = find(one_missing, "warn", "over SSH/tmux but")
  check(
    "ssh: one missing helper reads as one",
    single and single.msg:find("osc-paste is not on PATH", 1, true) ~= nil,
    single and single.msg
  )

  fake("osc-paste")
  local with_osc = report({ env = { SSH_TTY = "/dev/pts/9" } })
  check(
    "ssh: present helpers are reported ok",
    find(with_osc, "ok", "osc-copy/osc-paste present") ~= nil,
    text(with_osc, "ok")
  )

  -- Off SSH and outside tmux the question does not arise, and the report should
  -- not raise it.
  local local_session = report({ env = { SSH_TTY = nil, SSH_CLIENT = nil, SSH_CONNECTION = nil, TMUX = nil } })
  check(
    "local session: says nothing about OSC helpers",
    find(local_session, "warn", "over SSH/tmux") == nil,
    text(local_session, "warn")
  )
end

--------------------------------------------------------------------------
-- zoekt helpers
--------------------------------------------------------------------------

do
  local entries = report({})
  check(
    "zoekt: missing st/si is a warning naming both",
    (function()
      local e = find(entries, "warn", "<leader>sz / <leader>si need")
      return e and e.msg:find("st and si") ~= nil
    end)(),
    text(entries, "warn")
  )

  fake("st")
  fake("si")
  local with_scripts = report({})
  check(
    "zoekt: without zoekt-index it says the fallback is ripgrep",
    find(with_scripts, "ok", "fall through to ripgrep") ~= nil,
    text(with_scripts, "ok")
  )

  fake("zoekt-index")
  local with_zoekt = report({})
  check(
    "zoekt: with zoekt-index it says indexed search is available",
    find(with_zoekt, "ok", "with zoekt installed for indexed search") ~= nil,
    text(with_zoekt, "ok")
  )
end

--------------------------------------------------------------------------

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  error("\n" .. table.concat(failures, "\n"))
end
