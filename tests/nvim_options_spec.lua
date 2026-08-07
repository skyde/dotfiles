-- Run with: nvim --headless -u NONE -i NONE -l tests/nvim_options_spec.lua
--
-- config/options.lua is the one file whose whole job is side effects, so the
-- ways it can go wrong are quiet ones: an option that Neovim resets out from
-- under it, a setting that only makes sense together with another one, or a
-- value that has drifted away from the git config it is supposed to mirror.
--
-- Loaded here directly rather than through lazy.nvim: it touches nothing but
-- vim.opt / vim.g / vim.fn, which is exactly what makes this possible.

local source = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fn.fnamemodify(source, ":p:h:h")
local cfg = repo .. "/common/.config/nvim"

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

-- The clipboard branches key off SSH_* and TMUX, so the environment has to be
-- steerable. Listed rather than derived from the caller's table: an unset
-- variable cannot be a table key, and every one of them has to be *cleared*
-- between runs or a probe leaks into the next case.
local ENV_KEYS = { "SSH_CLIENT", "SSH_TTY", "SSH_CONNECTION", "TMUX" }

---Load config/options.lua into this session with exactly `env` set of the
---variables above, and nothing else.
local function load_options(env)
  env = env or {}
  local saved = {}
  for _, name in ipairs(ENV_KEYS) do
    saved[#saved + 1] = { name, vim.env[name] }
    vim.env[name] = env[name]
  end
  vim.g.clipboard = nil
  local ok, err = pcall(dofile, cfg .. "/lua/config/options.lua")
  for _, entry in ipairs(saved) do
    vim.env[entry[1]] = entry[2]
  end
  if not ok then
    error(err)
  end
end

-- A realistic terminal: 'scroll' is derived from the window height, so the
-- size has to be settled before anything looks at it. The tabline goes with
-- it — see the note in nvim_vcs_ui_spec.lua: headless Neovim keeps its 80x24
-- default grid while `draw_tabline` draws at the current 'columns', and the
-- overflow is an invalid write whether or not it happens to abort.
vim.o.columns = 200
vim.o.lines = 50
vim.o.showtabline = 0

load_options()

--------------------------------------------------------------------------
-- the options that carry a decision
--------------------------------------------------------------------------

do
  eq("options: scrolloff keeps the cursor off the edge", 8, vim.o.scrolloff)
  eq("options: true colour is on", true, vim.o.termguicolors)
  eq("options: the mouse works in every mode", "a", vim.o.mouse)
  eq("options: word wrap is on", true, vim.o.wrap)
  eq("options: whitespace is not drawn by default", false, vim.o.list)

  -- These three only make sense together: with the sign column off and
  -- CursorLine never drawn, the highlighted line *number* is the only
  -- remaining "you are here" cue, and it is what the theme paints orange.
  eq("options: the sign column is off", "no", vim.o.signcolumn)
  eq("options: cursorline is on", true, vim.o.cursorline)
  eq("options: but only the number is drawn", "number", vim.o.cursorlineopt)

  eq("options: unix line endings are preferred, dos tolerated", "unix,dos", vim.o.fileformats)
  check("options: the clipboard follows the unnamed register", vim.o.clipboard:find("unnamedplus", 1, true) ~= nil)

  -- Every guicursor mode points at the one Cursor group the theme paints the
  -- shared #ff5000; a mode left on the default would blink a different colour.
  for _, mode in ipairs({ "n%-v%-c", "i%-ci", "r%-cr", "o" }) do
    check(
      ("options: guicursor %s uses the Cursor group"):format((mode:gsub("%%", ""))),
      vim.o.guicursor:match(mode .. ":[%w%d]+%-Cursor") ~= nil,
      vim.o.guicursor
    )
  end
end

--------------------------------------------------------------------------
-- 'scroll' is not a setting this config can hold
--------------------------------------------------------------------------

do
  -- Neovim recomputes 'scroll' to half the window height on every split and
  -- resize, so anything assigned at startup is gone before the first key is
  -- pressed. The 16-line step belongs to the <C-u> / <C-d> mappings, and
  -- options.lua must not pretend otherwise.
  local text = table.concat(vim.fn.readfile(cfg .. "/lua/config/options.lua"), "\n")
  check(
    "options: 'scroll' is not assigned (Neovim resets it on every resize)",
    text:match("%.scroll%s*=") == nil,
    "options.lua assigns 'scroll', which never survives the first window resize"
  )

  local keymaps = table.concat(vim.fn.readfile(cfg .. "/lua/config/keymaps.lua"), "\n")
  check("options: <C-u> steps 16 lines from a mapping", keymaps:find('"<C%-u>", "16k"') ~= nil)
  check("options: <C-d> steps 16 lines from a mapping", keymaps:find('"<C%-d>", "16j"') ~= nil)
end

--------------------------------------------------------------------------
-- diffopt mirrors the git config
--------------------------------------------------------------------------

do
  -- The promise in docs/nvim-vscode-parity.md is that a diff reads the same
  -- in the editor as in the terminal. That only holds while these two files
  -- agree, and nothing but this check notices when one of them moves.
  local git_config = table.concat(vim.fn.readfile(repo .. "/common/.config/git/config"), "\n")
  local algorithm = git_config:match("\n%s*algorithm%s*=%s*(%S+)")
  local context = git_config:match("\n%s*context%s*=%s*(%d+)")
  check("diffopt: the git config names a diff algorithm", algorithm ~= nil)
  check("diffopt: the git config names a context size", context ~= nil)

  if algorithm then
    check(
      ("diffopt: uses the git config's algorithm (%s)"):format(algorithm),
      vim.o.diffopt:find("algorithm:" .. algorithm, 1, true) ~= nil,
      vim.o.diffopt
    )
  end
  if context then
    check(
      ("diffopt: uses the git config's context (%s)"):format(context),
      vim.o.diffopt:find("context:" .. context, 1, true) ~= nil,
      vim.o.diffopt
    )
  end

  -- linematch is what makes a side-by-side diff of real code readable: it
  -- pairs each removed line with the added line it resembles instead of
  -- showing two solid blocks. The inline overlay hard-codes the same value.
  check("diffopt: linematch is on", vim.o.diffopt:find("linematch:60", 1, true) ~= nil, vim.o.diffopt)
  check("diffopt: the indent heuristic is on", vim.o.diffopt:find("indent%-heuristic") ~= nil, vim.o.diffopt)
  check("diffopt: internal diff", vim.o.diffopt:find("internal", 1, true) ~= nil, vim.o.diffopt)
  check("diffopt: filler lines are drawn", vim.o.diffopt:find("filler", 1, true) ~= nil, vim.o.diffopt)
  if vim.fn.has("nvim-0.12") == 1 then
    check("diffopt: char-level emphasis on 0.12+", vim.o.diffopt:find("inline:char", 1, true) ~= nil, vim.o.diffopt)
  end

  -- Deleted lines are drawn as blank rows, not a wall of hyphens.
  check("diffopt: deleted rows fill with a space", vim.o.fillchars:find("diff: ", 1, true) ~= nil, vim.o.fillchars)

  -- The overlay slices hunks itself; if it disagreed with 'diffopt' the two
  -- renderings would tell different stories about the same file.
  local overlay = table.concat(vim.fn.readfile(cfg .. "/lua/util/inline_diff.lua"), "\n")
  check("diffopt: the overlay uses the histogram algorithm too", overlay:find('algorithm = "histogram"') ~= nil)
  check("diffopt: and the same linematch", overlay:find("linematch = 60") ~= nil)
  check("diffopt: and reads the context out of diffopt", overlay:find('diffopt:match%("context:') ~= nil)
end

--------------------------------------------------------------------------
-- remote-plugin providers stay off
--------------------------------------------------------------------------

do
  -- Each of these makes Neovim probe for an interpreter at startup, and
  -- nothing here uses one. lazy.lua also drops the rplugin runtime plugin on
  -- the strength of that, so the two have to stay in step.
  for _, provider in ipairs({ "python3", "ruby", "node", "perl" }) do
    eq(("providers: %s is off"):format(provider), 0, vim.g["loaded_" .. provider .. "_provider"])
  end
  local lazy = table.concat(vim.fn.readfile(cfg .. "/lua/config/lazy.lua"), "\n")
  check("providers: rplugin is dropped from the runtimepath", lazy:find('"rplugin"', 1, true) ~= nil)
end

--------------------------------------------------------------------------
-- the clipboard provider picks itself by environment
--------------------------------------------------------------------------

do
  -- A bare local terminal leaves vim.g.clipboard alone, so Neovim's own
  -- detection (wl-copy, xclip, ...) applies.
  load_options()
  eq("clipboard: no provider is forced on a local terminal", nil, vim.g.clipboard)

  -- Over SSH or inside tmux the terminal is the only route to the local
  -- clipboard, which is what osc-copy/osc-paste are for — but only if they
  -- are installed; forcing a provider that is not there breaks yank entirely.
  local has_osc = vim.fn.executable("osc-copy") == 1 and vim.fn.executable("osc-paste") == 1
  for _, var in ipairs({ "SSH_CLIENT", "SSH_TTY", "SSH_CONNECTION", "TMUX" }) do
    load_options({ [var] = "probe" })
    if has_osc then
      eq(("clipboard: %s selects the OSC 52 provider"):format(var), "osc-copy/osc-paste", (vim.g.clipboard or {}).name)
    else
      eq(("clipboard: %s does not force a provider that is missing"):format(var), nil, vim.g.clipboard)
    end
  end
  load_options()
end

--------------------------------------------------------------------------
-- autocmds.lua
--------------------------------------------------------------------------

do
  dofile(cfg .. "/lua/config/autocmds.lua")
  local temp = vim.fn.tempname()
  vim.fn.mkdir(temp, "p")
  local path = temp .. "/settings.json.tmpl"
  local fd = assert(io.open(path, "wb"))
  fd:write('{ "a": {{ .B }} }\n')
  fd:close()
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  eq("autocmds: a .json.tmpl file is JSON", "json", vim.bo.filetype)
  vim.cmd("bwipeout!")
  vim.fn.delete(temp, "rf")
end

--------------------------------------------------------------------------

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  error("\n" .. table.concat(failures, "\n"))
end
