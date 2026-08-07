-- Run with: nvim --headless -u NONE -i NONE -l tests/nvim_text_spec.lua
--
-- Two jobs. First, util.text — the shim that keeps this config's diff engine
-- working across the vim.diff -> vim.text.diff rename (`:h deprecated`).
-- Second, a sweep of the whole Lua tree for APIs Neovim has already deprecated,
-- so a new call site cannot quietly reintroduce one: the config is meant to run
-- on the current release, and "it still works today" is exactly how a config
-- breaks on the release that finally drops them.

local source = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fn.fnamemodify(source, ":p:h:h")
local nvim_dir = repo .. "/common/.config/nvim"
vim.opt.runtimepath:prepend(nvim_dir)

local text = require("util.text")

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
-- util.text.diff / util.text.hunks
--------------------------------------------------------------------------

do
  check("diff: bound to something callable", type(text.diff) == "function")
  -- Whichever name this build has, it must be the real one. On 0.12+ that is
  -- vim.text.diff; on 0.11 only vim.diff exists.
  check(
    "diff: prefers vim.text.diff when the build has it",
    (vim.text and vim.text.diff) and text.diff == vim.text.diff or text.diff == vim.diff
  )

  eq("hunks: identical input has no hunks", {}, text.hunks("a\nb\n", "a\nb\n"))
  eq("hunks: a changed line is one hunk", { { 2, 1, 2, 1 } }, text.hunks("a\nb\n", "a\nB\n"))
  eq("hunks: an appended line counts as zero old lines", { { 2, 0, 3, 1 } }, text.hunks("a\nb\n", "a\nb\nc\n"))
  eq("hunks: a deleted line counts as zero new lines", { { 2, 1, 1, 0 } }, text.hunks("a\nb\n", "a\n"))
  eq("hunks: empty against empty", {}, text.hunks("", ""))
  eq("hunks: everything added", { { 0, 0, 1, 2 } }, text.hunks("", "a\nb\n"))
  eq("hunks: everything deleted", { { 1, 2, 0, 0 } }, text.hunks("a\nb\n", ""))

  -- The callers pass algorithm/linematch through; the wrapper must not eat them.
  local opts_hunks = text.hunks("a\nb\nc\n", "a\nB\nc\n", { algorithm = "histogram", indent_heuristic = true })
  eq("hunks: passes options through", { { 2, 1, 2, 1 } }, opts_hunks)

  -- result_type is the wrapper's own; a caller must not be able to ask for the
  -- unified-text form and get a shape the hunk loops cannot walk.
  local forced = text.hunks("a\n", "b\n", { result_type = "unified" })
  check("hunks: always returns indices", type(forced[1]) == "table", vim.inspect(forced))

  -- An options table handed in by a caller must come back unmodified: several
  -- call sites build theirs once and reuse it.
  local reused = { algorithm = "histogram" }
  text.hunks("a\n", "b\n", reused)
  eq("hunks: leaves the caller's options alone", { algorithm = "histogram" }, reused)
end

--------------------------------------------------------------------------
-- no deprecated Neovim APIs anywhere in the config
--------------------------------------------------------------------------

-- Each entry is a Lua pattern matched against source text, with what to use
-- instead. Keep the list to things Neovim has actually deprecated, and cite the
-- release, so this stays a fact about upstream rather than a style opinion.
local DEPRECATED = {
  { "vim%.diff%s*%(", "vim.text.diff (0.12) — use util.text.diff/hunks" },
  { "vim%.tbl_islist%s*%(", "vim.islist (0.10)" },
  { "vim%.tbl_flatten%s*%(", "vim.iter():flatten():totable() (0.10)" },
  { "vim%.tbl_add_reverse_lookup%s*%(", "hand-rolled reverse lookup (0.10)" },
  { "vim%.validate%s*%(%s*{", "the (name, value, type) form of vim.validate (0.11)" },
  { "vim%.highlight%.", "vim.hl. (0.11)" },
  { "vim%.health%.report_", "the unprefixed vim.health.start/ok/warn/error/info (0.10)" },
  { "vim%.lsp%.buf_get_clients%s*%(", "vim.lsp.get_clients (0.10)" },
  { "vim%.lsp%.get_active_clients%s*%(", "vim.lsp.get_clients (0.10)" },
  { "vim%.lsp%.util%.jump_to_location%s*%(", "vim.lsp.util.show_document (0.11)" },
  { "nvim_buf_set_option%s*%(", "vim.bo / nvim_set_option_value (0.10)" },
  { "nvim_buf_get_option%s*%(", "vim.bo / nvim_get_option_value (0.10)" },
  { "nvim_win_set_option%s*%(", "vim.wo / nvim_set_option_value (0.10)" },
  { "nvim_win_get_option%s*%(", "vim.wo / nvim_get_option_value (0.10)" },
  { "nvim_exec%s*%(", "nvim_exec2 (0.9)" },
}

-- vim.loop is deprecated in favour of vim.uv, but the lazy.nvim bootstrap
-- legitimately probes `vim.uv or vim.loop`: it runs before anything else and
-- has to work on a Neovim too old to have vim.uv at all.
local LOOP_FALLBACK = "%(vim%.uv or vim%.loop%)"

-- BufModifiedSet, which 0.13 removed in favour of OptionSet with pattern
-- "modified". nvim_create_autocmd raises on an unknown event, so naming it is
-- only safe behind an exists() probe — which is what util.vcs_ui does, and what
-- this allows. Checked per file rather than per line: the probe and the uses it
-- guards are necessarily several lines apart.
local EVENT_PROBE = 'vim%.fn%.exists%("##'

local function lua_files()
  local out = {}
  local function walk(dir)
    for name, kind in vim.fs.dir(dir) do
      local full = dir .. "/" .. name
      if kind == "directory" then
        walk(full)
      elseif name:match("%.lua$") then
        table.insert(out, full)
      end
    end
  end
  walk(nvim_dir .. "/lua")
  table.insert(out, nvim_dir .. "/init.lua")
  return out
end

do
  local files = lua_files()
  check("sweep: found the config's Lua files", #files > 20, tostring(#files))

  local hits = {}
  for _, path in ipairs(files) do
    local rel = path:sub(#nvim_dir + 2)
    local probes_events = io.open(path):read("*a"):find(EVENT_PROBE) ~= nil
    local lnum = 0
    for line in io.lines(path) do
      lnum = lnum + 1
      -- Comments discuss these names on purpose (util.text documents the
      -- rename it exists for); only code counts.
      local code = line:gsub("%-%-.*$", "")
      for _, entry in ipairs(DEPRECATED) do
        if code:find(entry[1]) then
          table.insert(hits, ("%s:%d uses a deprecated API; use %s"):format(rel, lnum, entry[2]))
        end
      end
      if code:find("vim%.loop%.") and not code:find(LOOP_FALLBACK) then
        table.insert(hits, ("%s:%d uses vim.loop; use vim.uv (0.10)"):format(rel, lnum))
      end
      if code:find("BufModifiedSet") and not probes_events then
        table.insert(
          hits,
          ('%s:%d names BufModifiedSet, removed in 0.13, without an exists() probe; use OptionSet with pattern "modified"'):format(
            rel,
            lnum
          )
        )
      end
    end
  end
  check("sweep: no deprecated Neovim APIs in the config", #hits == 0, table.concat(hits, "\n           "))
end

--------------------------------------------------------------------------

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  error("\n" .. table.concat(failures, "\n"))
end
