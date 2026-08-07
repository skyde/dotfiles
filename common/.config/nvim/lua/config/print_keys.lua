-- `<leader>uk` — print every key as it arrives.
--
-- This exists for one job: working out what a terminal actually sends. The
-- footpedal macro keys reach Neovim as `<F13>`..`<F24>` from bare kitty and as
-- `<S-F1>`..`<S-F12>` through tmux (see the map_shift_f note in
-- config/keymaps.lua), and when a pedal press does nothing the first question is
-- always which of the two — if either — arrived.
--
-- So it reports the key by name. The raw bytes are what `vim.on_key` hands over,
-- and `<80><fd>\b` is not an answer to "which key was that"; `keytrans` turns
-- the same bytes into `<S-F3>`.

local M = {}

local ns = vim.api.nvim_create_namespace("log-keys")
local enabled = false

---What arrived, as a name. `typed` is the key as the terminal sent it and `key`
---is what it became after mapping; they differ exactly when a mapping fired,
---which is the other half of the question this tool answers.
---@param key string
---@param typed string|nil
local function describe(key, typed)
  local name = vim.fn.keytrans(key)
  if typed and typed ~= "" and typed ~= key then
    return ("%s  (typed %s)"):format(name, vim.fn.keytrans(typed))
  end
  return name
end

M.describe = describe

function M.enable()
  if enabled then
    return
  end
  enabled = true
  -- Registered here rather than at load, and torn down again in disable(): an
  -- always-installed callback runs on every keystroke of every session to
  -- decide it has nothing to do.
  vim.on_key(function(key, typed)
    -- on_key runs inside key processing, where the docs say not to change
    -- editor state — and vim.notify under a notifier plugin opens a window.
    local text = describe(key, typed)
    vim.schedule(function()
      vim.notify(text)
    end)
  end, ns)
  vim.notify("Key print enabled", vim.log.levels.INFO)
end

function M.disable()
  if not enabled then
    return
  end
  enabled = false
  vim.on_key(nil, ns)
  vim.notify("Key print disabled", vim.log.levels.INFO)
end

function M.toggle()
  if enabled then
    M.disable()
  else
    M.enable()
  end
end

---Whether key printing is on. For the specs, and for anything that wants to
---report the state without toggling it.
function M.enabled()
  return enabled
end

return M
