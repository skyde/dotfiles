-- `:checkhealth dotfiles` — what this configuration expects to find on the
-- machine, and what it actually found.
--
-- Most of this config degrades quietly by design: no delta and a patch renders
-- plain, no lazyjj and `<leader>gg` falls back to lazygit, no osc-copy over SSH
-- and yanking to `+` goes nowhere. Every one of those is the right behaviour and
-- the wrong thing to discover in the middle of doing something else. This is the
-- one place that says which ones are in effect.
--
-- Nothing here is a failure the config caused: an `error` means a documented
-- feature cannot work at all here, a `warn` means it is running on its fallback,
-- and `info` means the question does not apply on this machine.
--
-- Deliberately dependency-free — it requires the config's own modules and
-- nothing else — so it answers even when the thing being diagnosed is a plugin
-- that failed to load.

local M = {}

local health = vim.health

---Is `bin` on PATH?
local function has(bin)
  return vim.fn.executable(bin) == 1
end

---First of `bins` that exists, or nil.
local function first(bins)
  for _, bin in ipairs(bins) do
    if has(bin) then
      return bin
    end
  end
  return nil
end

---`bin --version`, first line, for the report. Falls back to the path when the
---binary has no version flag worth calling.
local function version_of(bin, args)
  -- Guarded: vim.system raises on a missing binary, and this is the module
  -- someone runs *because* something is missing. Every caller checks has()
  -- first today; that is not a reason for the diagnostic tool to depend on it.
  if not has(bin) then
    return "not found"
  end
  local res = vim.system(vim.list_extend({ bin }, args or { "--version" }), { text = true }):wait()
  local line = vim.split(res.stdout or "", "\n", { plain = true })[1]
  if res.code ~= 0 or not line or vim.trim(line) == "" then
    return vim.fn.exepath(bin)
  end
  return vim.trim(line)
end

--------------------------------------------------------------------------
-- Neovim itself
--------------------------------------------------------------------------

-- 0.10 is where vim.uv and the modern option API landed, both of which this
-- config uses unconditionally. Not a guess: .github/workflows/neovim.yml runs
-- the whole spec suite against this exact version, so the floor is tested. Bump
-- the two together or neither.
local MIN_VERSION = { 0, 10, 0 }

local function check_neovim()
  health.start("Neovim")

  local v = vim.version()
  local version = ("%d.%d.%d"):format(v.major, v.minor, v.patch)
  if vim.version.lt(v, MIN_VERSION) then
    health.error(
      ("Neovim %s is older than the %s this config needs"):format(version, table.concat(MIN_VERSION, ".")),
      { "./install-nvim.sh installs the current release into ~/.local/bin" }
    )
  else
    health.ok(("Neovim %s"):format(version))
  end

  -- options.lua turns every remote-plugin host off on purpose; say so, since
  -- `:checkhealth provider` reports the same thing as a problem.
  local off = {}
  for _, name in ipairs({ "python3", "ruby", "node", "perl" }) do
    if vim.g["loaded_" .. name .. "_provider"] == 0 then
      table.insert(off, name)
    end
  end
  if #off > 0 then
    health.info(
      ("remote-plugin providers disabled on purpose: %s"):format(table.concat(off, ", "))
        .. " — nothing here uses them, and probing for the interpreters costs startup time"
    )
  end

  -- The inline diff's char-level emphasis is a 0.12 option; the overlay works
  -- without it, native diff mode just highlights whole lines.
  if vim.o.diffopt:find("inline:char", 1, true) then
    health.ok("diffopt has inline:char — native diffs emphasize the characters that changed")
  else
    health.info("diffopt has no inline:char (Neovim 0.12+); native diffs highlight whole lines")
  end
end

--------------------------------------------------------------------------
-- source control
--------------------------------------------------------------------------

local function check_vcs()
  health.start("Source control")

  local vcs = require("util.vcs")
  local present = {}
  for _, name in ipairs({ "git", "jj", "hg", "p4", "g4" }) do
    if has(name) then
      table.insert(present, name)
    end
  end
  if #present == 0 then
    health.error("no version-control client found (tried git, jj, hg, p4, g4)", {
      "<leader>gc and the whole diff UI need one of these on PATH",
    })
  else
    health.ok(("backends available: %s"):format(table.concat(present, ", ")))
  end

  local backend, root = vcs.detect(vim.fn.getcwd())
  if backend and root then
    local rev = backend.rev(root, "working")
    health.ok(("this directory is %s · %s"):format(backend.name, root))
    health.info(("working base resolves to %s"):format(rev:sub(1, 12)))
  else
    -- Detection needs the client, not just the marker on disk: a repository
    -- whose client is not installed is indistinguishable from no repository at
    -- all, which is the most confusing answer to give someone standing in one.
    -- Same order as util.vcs detects in, so a colocated repo names jj.
    local orphaned
    for _, pair in ipairs({ { ".jj", "jj" }, { ".git", "git" }, { ".hg", "hg" } }) do
      local found = vim.fs.find({ pair[1] }, { path = vim.fn.getcwd(), upward = true, limit = 1 })[1]
      if found and not has(pair[2]) then
        orphaned = { marker = found, bin = pair[2] }
        break
      end
    end
    if orphaned then
      health.error(
        ("%s found here but %s is not on PATH — the diff UI cannot read this repository"):format(
          orphaned.marker,
          orphaned.bin
        ),
        { ("Install %s, or open the view from a checkout whose client is installed."):format(orphaned.bin) }
      )
    else
      health.info("this directory is not under version control — nothing to diff here")
    end
  end

  if has("delta") then
    health.ok(("delta %s — patches render the way `git diff` does in a terminal"):format(version_of("delta")))
  else
    health.warn("delta not found; <leader>gp and <leader>gA render as a plain diff buffer", {
      "The inline and side-by-side diffs are unaffected — they never shell out to delta.",
      "Install: brew install git-delta / cargo install git-delta",
    })
  end

  -- <leader>gg picks a TUI by backend and falls back to lazygit.
  local tui = backend and ({ jj = { "lazyjj", "jjui" }, p4 = { "p4v" }, g4 = { "p4v" } })[backend.name]
  local preferred = tui and first(tui)
  if preferred then
    health.ok(("<leader>gg opens %s"):format(preferred))
  elseif has("lazygit") then
    health.ok(
      tui and "<leader>gg falls back to lazygit (no " .. table.concat(tui, "/") .. " on PATH)"
        or "<leader>gg opens lazygit"
    )
  else
    health.warn("lazygit not found; <leader>gg has nothing to open", {
      "./install-lazygit.sh installs the current release into ~/.local/bin",
    })
  end
end

--------------------------------------------------------------------------
-- clipboard
--------------------------------------------------------------------------

local function check_clipboard()
  health.start("Clipboard")

  -- options.lua appends unnamedplus, so every yank goes through whatever
  -- provider is in effect; a missing one means yanking silently does nothing.
  local provider = vim.g.clipboard and vim.g.clipboard.name
  if provider then
    -- Naming a provider is not the same as having one. config/options.lua picks
    -- win32yank on Windows whether or not it is installed, and Neovim does not
    -- fall back once vim.g.clipboard is set: every yank becomes a silent no-op.
    local copy = vim.g.clipboard.copy and vim.g.clipboard.copy["+"]
    local bin = type(copy) == "table" and copy[1] or type(copy) == "string" and copy or nil
    if bin and not has(bin) then
      health.error(("provider: %s, but %s is not on PATH — yanking to + goes nowhere"):format(provider, bin), {
        ("Install %s, or unset vim.g.clipboard to let Neovim pick its own provider."):format(bin),
      })
    else
      health.ok(("provider: %s (set by config/options.lua)"):format(provider))
    end
  else
    local detected = first({ "pbcopy", "wl-copy", "xclip", "xsel", "win32yank.exe" })
    if detected then
      health.ok(("provider: Neovim's own, via %s"):format(detected))
    else
      health.error("no clipboard provider; yanking to + and the copy keys go nowhere", {
        "Over SSH or inside tmux this config uses osc-copy/osc-paste from common/.local/bin.",
        "On a Linux desktop install wl-clipboard or xclip.",
      })
    end
  end

  local remote = vim.env.SSH_TTY or vim.env.SSH_CLIENT or vim.env.SSH_CONNECTION or vim.env.TMUX
  if remote then
    local missing = {}
    for _, bin in ipairs({ "osc-copy", "osc-paste" }) do
      if not has(bin) then
        table.insert(missing, bin)
      end
    end
    if #missing > 0 then
      health.warn(
        ("over SSH/tmux but %s not on PATH"):format(
          #missing == 1 and (missing[1] .. " is") or (table.concat(missing, " and ") .. " are")
        ),
        {
          "They ship in common/.local/bin; ./apply.sh links them into ~/.local/bin.",
        }
      )
    else
      health.ok("osc-copy/osc-paste present — the clipboard reaches the local machine over OSC 52")
    end
  end
end

--------------------------------------------------------------------------
-- search and files
--------------------------------------------------------------------------

local function check_tools()
  health.start("Search and files")

  for _, tool in ipairs({
    { bin = "rg", what = "the pickers and <leader>sg grep", required = true },
    { bin = "fd", what = "file finding in the pickers" },
  }) do
    if has(tool.bin) then
      health.ok(("%s — %s"):format(version_of(tool.bin), tool.what))
    elseif tool.required then
      health.error(("%s not found; %s will not work"):format(tool.bin, tool.what))
    else
      health.warn(("%s not found; %s falls back to a slower path"):format(tool.bin, tool.what))
    end
  end

  -- <leader>sz / <leader>si run these two scripts in a terminal; st itself
  -- picks zoekt or ripgrep depending on whether the tree has been indexed.
  local zoekt = {}
  for _, bin in ipairs({ "st", "si" }) do
    if not has(bin) then
      table.insert(zoekt, bin)
    end
  end
  if #zoekt > 0 then
    health.warn(("<leader>sz / <leader>si need %s on PATH"):format(table.concat(zoekt, " and ")), {
      "They ship in common/.local/bin; ./apply.sh links them into ~/.local/bin.",
    })
  elseif has("zoekt-index") then
    health.ok("st / si present, with zoekt installed for indexed search")
  else
    health.ok("st / si present; without zoekt-index they fall through to ripgrep")
  end

  if has("yazi") then
    health.ok(("%s — <leader>e opens it"):format(version_of("yazi")))
  else
    health.info("yazi not found; <leader>e falls back to mini.files, then nvim-tree")
  end
end

--------------------------------------------------------------------------
-- C++ and Chromium
--------------------------------------------------------------------------

local function check_cpp()
  health.start("C++ / Chromium")

  local chromium = require("util.chromium")
  local root = chromium.src_root(vim.fn.getcwd())
  if not root then
    if has("clangd") then
      health.ok(("%s on PATH"):format(version_of("clangd")))
    else
      health.info("clangd not found; C and C++ get no language features")
    end
    health.info("not inside a Chromium checkout — nothing else to check here")
    return
  end

  health.ok(("Chromium checkout: %s"):format(root))

  -- clangd_path answers "clangd" when the checkout has no bundled one, which is
  -- exactly the case worth reporting.
  if chromium.clangd_path(root) ~= "clangd" then
    health.ok("using the checkout's bundled clangd, version-matched to the build")
  elseif has("clangd") then
    health.warn("using clangd from PATH, not the checkout's bundled one", {
      ':ChromiumClangd adds "checkout_clangd": True to .gclient and syncs it.',
    })
  else
    health.error("no clangd at all; C++ has no language features in this checkout", {
      ":ChromiumClangd installs the bundled one.",
    })
  end

  local out_dir = chromium.out_dir(root)
  if out_dir then
    health.ok(("build dir: %s"):format(out_dir))
  else
    health.warn("no build dir found under out/", { ":ChromiumOutDir picks one." })
  end

  local compdb = root .. "/compile_commands.json"
  if vim.uv.fs_stat(compdb) then
    if chromium.stale(root) then
      health.warn("compile_commands.json is older than build.ninja", {
        ":ChromiumCompdb regenerates it (opening a C++ buffer does this once per session).",
      })
    else
      health.ok("compile_commands.json is current")
    end
  else
    health.warn("no compile_commands.json; clangd will guess at flags", {
      ":ChromiumCompdb generates it.",
    })
  end
end

--------------------------------------------------------------------------
-- terminal integration
--------------------------------------------------------------------------

local function check_terminal()
  health.start("Terminal integration")

  -- The footpedal macro keys arrive as <F13>..<F24> from a bare terminal and as
  -- <S-Fn> through tmux; keymaps.lua binds both halves. Report which spelling
  -- this terminal can actually deliver, since a terminal that sends neither is
  -- the usual reason a pedal press does nothing.
  local encodings = {}
  if vim.fn.has("gui_running") == 1 or vim.g.neovide then
    table.insert(encodings, "<S-Fn> (GUI)")
  end
  if vim.env.TMUX then
    table.insert(encodings, "<S-Fn> (tmux extended-keys)")
  end
  if vim.fn.has("terminfo") == 1 then
    table.insert(encodings, "<F13>..<F24> (terminfo kf13..kf24)")
  end
  health.info(
    ("Shift+Fn is bound in both spellings; this session can receive: %s"):format(
      #encodings > 0 and table.concat(encodings, ", ") or "unknown"
    )
  )
  health.info("tests/check-footpedal-keys.py verifies the transport end to end")

  if vim.g.neovide then
    health.ok("Neovide: <leader>up / <leader>um / <leader>ur resize the font")
  elseif vim.env.KITTY_LISTEN_ON then
    health.ok("kitty remote control: <leader>up / <leader>um / <leader>ur resize the font")
  else
    health.info("font size is the terminal's to control here; the zoom keys say so and do nothing")
  end
end

--------------------------------------------------------------------------

-- Ordered, not a map: the report reads top to bottom and pairs() would shuffle
-- the sections between runs.
M.sections = {
  { "Neovim", check_neovim },
  { "Source control", check_vcs },
  { "Clipboard", check_clipboard },
  { "Search and files", check_tools },
  { "C++ / Chromium", check_cpp },
  { "Terminal integration", check_terminal },
}

function M.check()
  -- One failing section must not hide the rest: this is a diagnostic, and the
  -- likeliest reason a section throws is the very breakage being chased.
  for _, section in ipairs(M.sections) do
    local ok, err = pcall(section[2])
    if not ok then
      health.start(section[1])
      health.error(("this check itself failed: %s"):format(err))
    end
  end
end

return M
