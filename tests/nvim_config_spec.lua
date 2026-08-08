-- Run with: nvim --headless -u NONE -i NONE -l tests/nvim_config_spec.lua
--
-- The two modules under lua/config/ that are logic rather than wiring:
--
--   config.print_keys     what a key press is reported as, and whether the
--                         on_key hook is installed at all
--   config.vscode_debug   the stop chain — debug session, then the CMake
--                         build, then an Overseer task, then say so
--
-- Everything else in lua/config/ is keymaps and autocmds, covered by
-- tests/check-nvim-keymaps.sh against the real config. These two are pure
-- enough to drive without plugins, by putting stubs in package.loaded, which is
-- exactly what `pcall(require, ...)` will find.

local source = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fn.fnamemodify(source, ":p:h:h")
vim.opt.runtimepath:prepend(repo .. "/common/.config/nvim")

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

local function keys(spec)
  return vim.api.nvim_replace_termcodes(spec, true, false, true)
end

--------------------------------------------------------------------------
-- config.print_keys
--------------------------------------------------------------------------

do
  local print_keys = require("config.print_keys")

  -- The whole reason this exists: a footpedal press has to be identifiable.
  -- vim.inspect of what on_key hands over reads "<80><fd>\b", which answers
  -- nothing; keytrans says <S-F3>.
  eq("describe: a shifted function key by name", "<S-F3>", print_keys.describe(keys("<S-F3>")))
  eq("describe: the terminal's spelling of the same key", "<F15>", print_keys.describe(keys("<F15>")))
  eq("describe: an ordinary key is itself", "j", print_keys.describe("j"))
  eq("describe: control keys are named", "<C-D>", print_keys.describe(keys("<C-d>")))
  eq("describe: escape", "<Esc>", print_keys.describe(keys("<Esc>")))

  -- The other half of the question: did a mapping fire, and what did the
  -- terminal actually send? Reported only when they differ, so an unmapped key
  -- stays a single unambiguous name.
  eq(
    "describe: names the typed key when a mapping changed it",
    "gk  (typed <Up>)",
    print_keys.describe("gk", keys("<Up>"))
  )
  eq("describe: says nothing extra when they match", "j", print_keys.describe("j", "j"))
  eq("describe: nor when there is no typed key", "j", print_keys.describe("j", ""))

  -- Installed only while printing is on. An always-registered callback runs on
  -- every keystroke of every session to decide it has nothing to do, so the
  -- state flag is not the interesting part — whether a callback is actually
  -- hooked is. vim.on_key() with no arguments counts them.
  local function hooks()
    return vim.on_key()
  end
  local base = hooks()

  eq("enabled: off to begin with", false, print_keys.enabled())
  eq("enabled: and nothing hooked into on_key", base, hooks())
  print_keys.enable()
  eq("enable: turns it on", true, print_keys.enabled())
  eq("enable: and hooks a callback", base + 1, hooks())
  print_keys.enable()
  eq("enable: is idempotent", true, print_keys.enabled())
  eq("enable: without hooking a second callback", base + 1, hooks())
  print_keys.disable()
  eq("disable: turns it off", false, print_keys.enabled())
  eq("disable: and unhooks it, so no per-keystroke cost remains", base, hooks())
  print_keys.disable()
  eq("disable: is idempotent too", false, print_keys.enabled())
  eq("disable: still unhooked", base, hooks())
  print_keys.toggle()
  eq("toggle: on", true, print_keys.enabled())
  eq("toggle: hooked", base + 1, hooks())
  print_keys.toggle()
  eq("toggle: and off again", false, print_keys.enabled())
  eq("toggle: unhooked", base, hooks())
end

--------------------------------------------------------------------------
-- config.vscode_debug
--------------------------------------------------------------------------

---Run `fn` with `mods` in package.loaded, then put things back.
local function with_modules(mods, fn)
  local saved = {}
  for name, value in pairs(mods) do
    saved[name] = package.loaded[name]
    package.loaded[name] = value
  end
  local ok, err = pcall(fn)
  for name in pairs(mods) do
    package.loaded[name] = saved[name]
  end
  assert(ok, err)
end

---Capture what vim.notify was told.
local function with_notify(fn)
  local said = {}
  local real = vim.notify
  vim.notify = function(msg)
    table.insert(said, tostring(msg))
  end
  local ok, err = pcall(fn)
  vim.notify = real
  assert(ok, err)
  return table.concat(said, " | ")
end

do
  -- Reloaded per case: it caches nothing, but the stubs it sees have to be the
  -- ones each case installed.
  local function debug_module()
    package.loaded["config.vscode_debug"] = nil
    return require("config.vscode_debug")
  end

  -- 1. A debug session is running: terminate it and stop there.
  with_modules({
    dap = {
      session = function()
        return { id = 1 }
      end,
      terminate = function()
        _G.__terminated = true
      end,
      adapters = {},
    },
  }, function()
    _G.__terminated = nil
    pcall(vim.api.nvim_del_user_command, "CMakeStop")
    debug_module().stop()
    eq("stop: terminates a running debug session", true, _G.__terminated)
  end)

  -- 2. No session, but cmake-tools has loaded: stop the build.
  with_modules({
    dap = {
      session = function()
        return nil
      end,
      adapters = {},
    },
  }, function()
    _G.__cmake_stopped = nil
    vim.api.nvim_create_user_command("CMakeStop", function()
      _G.__cmake_stopped = true
    end, {})
    debug_module().stop()
    vim.api.nvim_del_user_command("CMakeStop")
    eq("stop: falls through to stopping the build", true, _G.__cmake_stopped)
  end)

  -- 3. Neither, but Overseer is around: stop the task.
  with_modules({
    dap = {
      session = function()
        return nil
      end,
      adapters = {},
    },
    overseer = {},
  }, function()
    _G.__overseer_stopped = nil
    pcall(vim.api.nvim_del_user_command, "CMakeStop")
    vim.api.nvim_create_user_command("OverseerQuickAction", function()
      _G.__overseer_stopped = true
    end, { nargs = "*" })
    debug_module().stop()
    vim.api.nvim_del_user_command("OverseerQuickAction")
    eq("stop: falls through to stopping an Overseer task", true, _G.__overseer_stopped)
  end)

  -- 3b. A build is actually running under Overseer *and* cmake-tools has
  -- loaded. :CMakeStop exists in any C/C++ buffer whether or not it is running
  -- anything, so probing it first answered the key with a no-op and left the
  -- build running.
  with_modules({
    dap = {
      session = function()
        return nil
      end,
      adapters = {},
    },
    overseer = {
      STATUS = { RUNNING = "RUNNING" },
      list_tasks = function(opts)
        _G.__listed_status = opts and opts.status
        return { { name = "build" } }
      end,
    },
  }, function()
    _G.__overseer_stopped, _G.__cmake_stopped, _G.__listed_status = nil, nil, nil
    vim.api.nvim_create_user_command("CMakeStop", function()
      _G.__cmake_stopped = true
    end, {})
    vim.api.nvim_create_user_command("OverseerQuickAction", function()
      _G.__overseer_stopped = true
    end, { nargs = "*" })
    debug_module().stop()
    vim.api.nvim_del_user_command("CMakeStop")
    vim.api.nvim_del_user_command("OverseerQuickAction")
    eq("stop: a running Overseer task beats :CMakeStop", true, _G.__overseer_stopped)
    eq("stop: and the build is not asked to stop as well", nil, _G.__cmake_stopped)
    eq("stop: only running tasks are looked for", "RUNNING", _G.__listed_status)
  end)

  -- 3c. Overseer is loaded but idle: the CMake build is the thing to stop.
  with_modules({
    dap = {
      session = function()
        return nil
      end,
      adapters = {},
    },
    overseer = {
      STATUS = { RUNNING = "RUNNING" },
      list_tasks = function()
        return {}
      end,
    },
  }, function()
    _G.__overseer_stopped, _G.__cmake_stopped = nil, nil
    vim.api.nvim_create_user_command("CMakeStop", function()
      _G.__cmake_stopped = true
    end, {})
    debug_module().stop()
    vim.api.nvim_del_user_command("CMakeStop")
    eq("stop: with no task running the build is stopped", true, _G.__cmake_stopped)
    eq("stop: and Overseer is left alone", nil, _G.__overseer_stopped)
  end)

  -- 4. Nothing to stop: say so rather than failing silently. The Shift+F7 key
  -- is labelled "stop build" and gets pressed when nothing is running.
  with_modules({
    dap = {
      session = function()
        return nil
      end,
      adapters = {},
    },
  }, function()
    pcall(vim.api.nvim_del_user_command, "CMakeStop")
    local said = with_notify(function()
      debug_module().stop()
    end)
    check("stop: with nothing running it says so", said:find("Nothing to stop", 1, true) ~= nil, said)
  end)

  -- nvim-dap absent entirely — a bare Neovim, or a session where it failed to
  -- load. Both entry points must report rather than raise.
  with_modules({ dap = nil }, function()
    package.loaded["dap"] = nil
    local mod = debug_module()
    local said = with_notify(function()
      mod.start()
    end)
    check("start: without nvim-dap it reports", said:find("nvim-dap is not available", 1, true) ~= nil, said)
    said = with_notify(function()
      mod.select_and_start()
    end)
    check("select_and_start: likewise", said:find("nvim-dap is not available", 1, true) ~= nil, said)
    eq("load_launch_json: answers nil without nvim-dap", nil, mod.load_launch_json())
  end)

  -- With dap present but no configurations for this filetype, the picker must
  -- not be opened on an empty list.
  with_modules({
    dap = {
      session = function()
        return nil
      end,
      adapters = {},
      configurations = {},
    },
  }, function()
    local offered = false
    local real_select = vim.ui.select
    vim.ui.select = function()
      offered = true
    end
    local said = with_notify(function()
      debug_module().select_and_start()
    end)
    vim.ui.select = real_select
    check("select_and_start: no configurations reports instead of picking", not offered, "a picker was opened")
    check("select_and_start: and says why", said:find("No DAP configurations", 1, true) ~= nil, said)
  end)

  -- A launch.json that does not parse. dap.ext.vscode raises, and swallowing
  -- that left the debug key doing nothing for a reason nothing on screen
  -- explained.
  do
    local ws = vim.fn.tempname()
    vim.fn.mkdir(ws .. "/.vscode", "p")
    vim.fn.writefile({ '{ "configurations": [ }' }, ws .. "/.vscode/launch.json")
    local cwd = vim.uv.cwd()
    vim.cmd("cd " .. vim.fn.fnameescape(ws))

    with_modules({
      dap = {
        session = function()
          return nil
        end,
        adapters = {},
        configurations = {},
      },
      ["dap.ext.vscode"] = {
        getconfigs = function()
          error("Expected value but found invalid token at character 22")
        end,
      },
    }, function()
      local said = with_notify(function()
        debug_module().load_launch_json()
      end)
      check("launch.json: a parse failure is reported", said:find("Could not read", 1, true) ~= nil, said)
      check("launch.json: the report names the file", said:find(".vscode/launch.json", 1, true) ~= nil, said)
      check("launch.json: and carries the parser's complaint", said:find("invalid token", 1, true) ~= nil, said)
    end)

    -- One that parses says nothing at all.
    vim.fn.writefile({ '{ "version": "0.2.0", "configurations": [] }' }, ws .. "/.vscode/launch.json")
    with_modules({
      dap = {
        session = function()
          return nil
        end,
        adapters = {},
        configurations = {},
      },
      ["dap.ext.vscode"] = {
        getconfigs = function()
          return {}
        end,
      },
    }, function()
      local said = with_notify(function()
        debug_module().load_launch_json()
      end)
      eq("launch.json: a readable one is reported on not at all", "", said)
    end)

    -- The attach fix-up: VS Code writes ${command:pickProcess}, nvim-dap wants
    -- a function on `pid`. dap.utils is reached only when one is there to fix.
    vim.fn.writefile({ '{ "version": "0.2.0", "configurations": [] }' }, ws .. "/.vscode/launch.json")
    local attach = { name = "attach", request = "attach", processId = "${command:pickProcess}" }
    local plain = { name = "launch", request = "launch", program = "a.out" }
    local picked = false
    with_modules({
      dap = {
        session = function()
          return nil
        end,
        adapters = {},
        configurations = { cpp = { attach, plain } },
      },
      ["dap.ext.vscode"] = {
        getconfigs = function()
          return {}
        end,
      },
      ["dap.utils"] = {
        pick_process = function()
          picked = true
          return 4242
        end,
      },
    }, function()
      local said = with_notify(function()
        debug_module().load_launch_json()
      end)
      eq("attach: normalising is not reported as a failure", "", said)
      eq("attach: the VS Code placeholder is cleared", nil, attach.processId)
      eq("attach: pid becomes callable", "function", type(attach.pid))
      eq("attach: dap.utils is not touched until the pid is asked for", false, picked)
      eq("attach: and calling it picks a process", 4242, attach.pid and attach.pid())
      eq("attach: a launch config is left alone", nil, plain.pid)
    end)

    -- The configurations themselves: merged under every filetype the type maps
    -- to, and no duplicate when the same file is read twice.
    local providers = {
      configs = {
        ["dap.launch.json"] = function()
          return { { name = "upstream", type = "codelldb" } }
        end,
      },
    }
    local dap_stub = {
      session = function()
        return nil
      end,
      adapters = {},
      configurations = {},
      providers = providers,
    }
    with_modules({
      dap = dap_stub,
      ["dap.ext.vscode"] = {
        getconfigs = function()
          return {
            { name = "Launch", type = "codelldb", request = "launch" },
            { name = "Python", type = "python", request = "launch" },
          }
        end,
      },
    }, function()
      local mod = debug_module()
      mod.load_launch_json()
      local names = {}
      for ft, list in pairs(dap_stub.configurations) do
        names[ft] = vim.tbl_map(function(c)
          return c.name
        end, list)
      end
      eq("configs: a codelldb type lands on every language it drives", { "Launch" }, names.cpp)
      eq("configs: including C", { "Launch" }, names.c)
      eq("configs: and Rust", { "Launch" }, names.rust)
      eq("configs: an unmapped type lands on its own filetype", { "Python" }, names.python)

      -- Reading the same file again must not stack copies: the panel calls this
      -- on every debug key.
      mod.load_launch_json()
      eq("configs: reading twice does not duplicate", 1, #dap_stub.configurations.cpp)

      -- nvim-dap's own provider reads .vscode in the working directory only.
      -- Left in place beside this one, every configuration is offered twice.
      eq("configs: the built-in launch.json provider is superseded", {}, providers.configs["dap.launch.json"]())
    end)

    vim.cmd("cd " .. vim.fn.fnameescape(cwd or "."))
    vim.fn.delete(ws, "rf")
  end

  package.loaded["config.vscode_debug"] = nil
end

--------------------------------------------------------------------------

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
  error("\n" .. table.concat(failures, "\n"))
end
