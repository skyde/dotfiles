-- Run with: nvim --headless -u NONE -i NONE -l tests/nvim_plugins_spec.lua
--
-- The `opts` / `keys` / `event` functions in common/.config/nvim/lua/plugins
-- are the places where an upstream change silently turns a customisation into
-- a no-op: they reach into the shape LazyVim happens to pass them, and when
-- that shape moves the function keeps running and quietly does nothing.
--
-- So each one is driven here with the structure it actually receives, and the
-- result is asserted. Deliberately plugin-free: the specs are plain Lua
-- tables, and nothing below needs the plugins themselves installed.

local source = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fn.fnamemodify(source, ":p:h:h")
local cfg = repo .. "/common/.config/nvim"
vim.opt.runtimepath:prepend(cfg)

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

---Load one plugin spec file by path, without lazy.nvim.
local function load_spec(name)
  local path = ("%s/lua/plugins/%s.lua"):format(cfg, name)
  local chunk, err = loadfile(path)
  if not chunk then
    error(("could not load %s: %s"):format(path, err))
  end
  return chunk()
end

---A spec file may return a single spec or a list of them; find the one for
---`plugin`, matching lazy.nvim's own "the string at [1] is the repo" rule.
local function spec_for(spec, plugin)
  if spec[1] == plugin then
    return spec
  end
  for _, entry in ipairs(spec) do
    if type(entry) == "table" and entry[1] == plugin then
      return entry
    end
  end
  return nil
end

--------------------------------------------------------------------------
-- every spec file loads and is shaped like a lazy.nvim spec
--------------------------------------------------------------------------

do
  local files = vim.fn.glob(cfg .. "/lua/plugins/*.lua", false, true)
  check("plugins: the directory is not empty", #files > 0)
  for _, path in ipairs(files) do
    local name = vim.fn.fnamemodify(path, ":t:r")
    local ok, spec = pcall(load_spec, name)
    check("plugins: " .. name .. " loads", ok, not ok and tostring(spec) or nil)
    if ok then
      check("plugins: " .. name .. " returns a table", type(spec) == "table", type(spec))
      -- Either { "repo", ... } or a list of those. Anything else is a spec
      -- lazy.nvim would quietly ignore.
      local named = type(spec[1]) == "string"
      local listed = type(spec[1]) == "table"
      check("plugins: " .. name .. " is a spec or a list of specs", named or listed, vim.inspect(spec[1]))
    end
  end
end

--------------------------------------------------------------------------
-- treesitter-textobjects: the ]c / [c rescue
--------------------------------------------------------------------------

do
  local spec = load_spec("treesitter-textobjects")
  local entry = spec_for(spec, "nvim-treesitter/nvim-treesitter-textobjects")
  check("textobjects: the spec targets the textobjects plugin", entry ~= nil)

  -- Exactly the table LazyVim passes in (lua/lazyvim/plugins/treesitter.lua).
  local opts = {
    move = {
      enable = true,
      set_jumps = true,
      keys = {
        goto_next_start = { ["]f"] = "@function.outer", ["]c"] = "@class.outer", ["]a"] = "@parameter.inner" },
        goto_next_end = { ["]F"] = "@function.outer", ["]C"] = "@class.outer", ["]A"] = "@parameter.inner" },
        goto_previous_start = { ["[f"] = "@function.outer", ["[c"] = "@class.outer", ["[a"] = "@parameter.inner" },
        goto_previous_end = { ["[F"] = "@function.outer", ["[C"] = "@class.outer", ["[A"] = "@parameter.inner" },
      },
    },
  }
  entry.opts(nil, opts)
  local keys = opts.move.keys

  -- `]c` / `[c` are "next / previous change" everywhere in this config. The
  -- textobjects plugin binds them buffer-locally, which shadows the global
  -- mapping in every treesitter buffer unless they are moved aside.
  eq("textobjects: ]c is freed", nil, keys.goto_next_start["]c"])
  eq("textobjects: [c is freed", nil, keys.goto_previous_start["[c"])
  eq("textobjects: ]C is freed", nil, keys.goto_next_end["]C"])
  eq("textobjects: [C is freed", nil, keys.goto_previous_end["[C"])
  eq("textobjects: class motion lands on ]k", "@class.outer", keys.goto_next_start["]k"])
  eq("textobjects: and on [k", "@class.outer", keys.goto_previous_start["[k"])
  eq("textobjects: end motions land on ]K / [K", "@class.outer", keys.goto_next_end["]K"])
  eq("textobjects: and [K", "@class.outer", keys.goto_previous_end["[K"])
  -- Everything else is left exactly as LazyVim had it.
  eq("textobjects: function motions untouched", "@function.outer", keys.goto_next_start["]f"])
  eq("textobjects: parameter motions untouched", "@parameter.inner", keys.goto_next_start["]a"])

  -- If upstream ever moves the keys somewhere else the hook must degrade
  -- rather than raise — but the assertions above are what notices.
  local moved = { move = { enable = true } }
  check("textobjects: tolerates a missing keys table", pcall(entry.opts, nil, moved))
  check("textobjects: tolerates no move table at all", pcall(entry.opts, nil, {}))
end

--------------------------------------------------------------------------
-- telescope: the ignore list and the ripgrep globs
--------------------------------------------------------------------------

do
  local spec = load_spec("telescope-ignore")
  local opts = { defaults = { file_ignore_patterns = { "^%.git/" } } }
  spec.opts(nil, opts)

  local patterns = opts.defaults.file_ignore_patterns
  check("telescope: keeps what LazyVim already ignored", vim.tbl_contains(patterns, "^%.git/"))
  check("telescope: adds the build directories", vim.tbl_contains(patterns, "^build/"))
  check("telescope: adds the object files", vim.tbl_contains(patterns, "%.o$"))
  -- Every entry is a Lua pattern telescope will run; a malformed one throws
  -- from inside the picker, where it reads as "search is broken".
  for _, p in ipairs(patterns) do
    check("telescope: `" .. p .. "` is a valid Lua pattern", pcall(string.find, "probe/path.txt", p))
  end

  for _, picker in ipairs({ "live_grep", "grep_string", "find_files" }) do
    local p = opts.pickers and opts.pickers[picker]
    check("telescope: " .. picker .. " is configured", p ~= nil)
    check("telescope: " .. picker .. " passes ripgrep globs", type(p.additional_args) == "function")
    if type(p.additional_args) == "function" then
      local args = p.additional_args()
      check("telescope: " .. picker .. " searches hidden files", vim.tbl_contains(args, "--hidden"))
      check("telescope: " .. picker .. " skips node_modules", vim.tbl_contains(args, "--glob=!node_modules/**"))
    end
  end
  eq("telescope: find_files shows hidden files", true, opts.pickers.find_files.hidden)

  -- The keys call into the live_grep_args extension, so it has to be a
  -- declared dependency or they raise on first press.
  check(
    "telescope: live_grep_args is a dependency",
    vim.tbl_contains(spec.dependencies or {}, "nvim-telescope/telescope-live-grep-args.nvim"),
    vim.inspect(spec.dependencies)
  )
  -- `config` suppresses lazy.nvim's automatic setup(), so it has to hand the
  -- opts over itself or every pattern above is silently dropped.
  check("telescope: config exists to pass opts through", type(spec.config) == "function")
end

--------------------------------------------------------------------------
-- lazy-loading triggers that have to *replace* LazyVim's, not add to it
--------------------------------------------------------------------------

do
  -- List-valued spec properties are merged with the parent, so returning the
  -- table from a function is the only way to drop the inherited trigger.
  local pairs_spec = load_spec("mini-pairs")
  check("mini.pairs: event is a function, so VeryLazy is replaced", type(pairs_spec.event) == "function")
  eq("mini.pairs: loads on InsertEnter", { "InsertEnter" }, pairs_spec.event())
  eq("mini.pairs: backtick pairing is off", false, pairs_spec.opts.mappings["`"])

  local autotag = load_spec("autotag")
  check("autotag: event is a function", type(autotag.event) == "function")
  eq("autotag: no event trigger at all", {}, autotag.event())
  check("autotag: loads by filetype instead", type(autotag.ft) == "table" and #autotag.ft > 0)
  check("autotag: markup filetypes are covered", vim.tbl_contains(autotag.ft, "html"))

  local comment = load_spec("comment")
  local lhs = {}
  for _, k in ipairs(comment.keys) do
    lhs[k[1]] = true
  end
  for _, want in ipairs({ "gcc", "gbc", "gc", "gb", "gcO", "gco", "gcA" }) do
    check("comment: " .. want .. " is a load trigger", lhs[want] == true)
  end
  -- `gc` and `gb` are operators; without visual mode the selection form is
  -- dead and lazy.nvim never replays the key.
  for _, k in ipairs(comment.keys) do
    if k[1] == "gc" or k[1] == "gb" then
      check("comment: " .. k[1] .. " triggers in visual mode too", vim.tbl_contains(k.mode, "x"), vim.inspect(k.mode))
    end
  end
end

--------------------------------------------------------------------------
-- neotest: <leader>T, never <leader>t
--------------------------------------------------------------------------

do
  local spec = load_spec("neotest")
  local entry = spec_for(spec, "nvim-neotest/neotest")
  check("neotest: the spec targets neotest", entry ~= nil)
  check("neotest: keys is a function, so LazyVim's <leader>t set is replaced", type(entry.keys) == "function")
  local keys = entry.keys()
  check("neotest: declares keys", #keys > 0)
  for _, k in ipairs(keys) do
    -- <leader>t is the debugger stepping cluster; a test key landing there
    -- would shadow it, which is the whole reason this file exists.
    check("neotest: " .. k[1] .. " stays out of the <leader>t cluster", not k[1]:match("^<leader>t"), k[1])
    check("neotest: " .. k[1] .. " is under <leader>T", k[1]:match("^<leader>T") ~= nil, k[1])
    check("neotest: " .. k[1] .. " has a description", type(k.desc) == "string" and #k.desc > 0)
  end
end

--------------------------------------------------------------------------
-- keys declared by plugin specs: unique, described, and callable
--------------------------------------------------------------------------

do
  local owner = {}
  local files = vim.fn.glob(cfg .. "/lua/plugins/*.lua", false, true)
  for _, path in ipairs(files) do
    local name = vim.fn.fnamemodify(path, ":t:r")
    local spec = load_spec(name)
    local entries = type(spec[1]) == "table" and spec or { spec }
    for _, entry in ipairs(entries) do
      local keys = entry.keys
      if type(keys) == "function" then
        keys = keys()
      end
      for _, k in ipairs(type(keys) == "table" and keys or {}) do
        local key = type(k) == "table" and k[1] or k
        if type(key) == "string" then
          -- Two plugin specs claiming the same key means one of them silently
          -- does nothing, depending on load order.
          check(
            ("plugin keys: %s is claimed once (%s)"):format(key, name),
            owner[key] == nil or owner[key] == name,
            "also claimed by " .. tostring(owner[key])
          )
          owner[key] = name
          if type(k) == "table" then
            check(("plugin keys: %s has a description"):format(key), type(k.desc) == "string" and #k.desc > 0)
          end
        end
      end
    end
  end
end

--------------------------------------------------------------------------
-- clangd: the Chromium cmd must not overwrite an explicit one
--------------------------------------------------------------------------

do
  local spec = load_spec("chromium-clangd")
  local entry = spec_for(spec, "neovim/nvim-lspconfig")
  check("clangd: the spec targets lspconfig", entry ~= nil)

  local opts = {}
  entry.opts(nil, opts)
  check("clangd: a cmd is provided", type(opts.servers.clangd.cmd) == "table")
  eq("clangd: the cmd starts with clangd", "clangd", opts.servers.clangd.cmd[1])

  -- tbl_deep_extend("keep"): anything already set wins, so a user override
  -- (or another spec) is not clobbered.
  local explicit = { servers = { clangd = { cmd = { "/opt/clangd" } } } }
  entry.opts(nil, explicit)
  eq("clangd: an explicit cmd is left alone", { "/opt/clangd" }, explicit.servers.clangd.cmd)
end

--------------------------------------------------------------------------
-- the "turn this off" specs really do turn things off
--------------------------------------------------------------------------

do
  local blink = load_spec("disable-blink")
  eq("disable: blink.cmp is off", false, spec_for(blink, "saghen/blink.cmp").enabled)

  local indent = load_spec("disable-indent-guides")
  eq("disable: indent-blankline is off", false, spec_for(indent, "lukas-reineke/indent-blankline.nvim").enabled)
  eq("disable: mini.indentscope is off", false, spec_for(indent, "nvim-mini/mini.indentscope").enabled)
  eq("disable: snacks indent is off", false, spec_for(indent, "folke/snacks.nvim").opts.indent.enabled)

  local scroll = load_spec("disable-smooth-scroll")
  eq("disable: snacks scroll is off", false, scroll.opts.scroll.enabled)

  local words = load_spec("no-cursorword")
  eq("disable: snacks words is off", false, spec_for(words, "folke/snacks.nvim").opts.words.enabled)

  local context = load_spec("treesitter-context")
  eq("disable: treesitter-context is off", false, spec_for(context, "nvim-treesitter/nvim-treesitter-context").enabled)
end

--------------------------------------------------------------------------
-- gitsigns: the signcolumn is off, so the cue has to be the line number
--------------------------------------------------------------------------

do
  local spec = load_spec("gitsigns")
  eq("gitsigns: no sign column", false, spec.opts.signcolumn)
  eq("gitsigns: line numbers are highlighted instead", true, spec.opts.numhl)
end

--------------------------------------------------------------------------
-- alpha: the ASCII banner is replaced, not left as LazyVim's
--------------------------------------------------------------------------

do
  local spec = load_spec("alpha")
  local entry = spec_for(spec, "goolord/alpha-nvim")
  local opts = { section = { header = { val = { "LAZYVIM", "BANNER" } } } }
  local out = entry.opts(nil, opts)
  eq("alpha: the banner is blanked", { "" }, out.section.header.val)
end

--------------------------------------------------------------------------

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  error("\n" .. table.concat(failures, "\n"))
end
