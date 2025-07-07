local M = {}

local ns = vim.api.nvim_create_namespace("print-keys")
local enabled = false
local print_file = vim.fn.stdpath("state") .. "/key-press.log"

local function handler(char)
  local f = io.open(print_file, "a")
  if f then
    f:write(string.format("%s [%s] %s\n", os.date("%F %T"), vim.fn.mode(), vim.inspect(char)))
    f:close()
  end
end

function M.enable()
  if enabled then
    return
  end
  vim.on_key(handler, ns)
  enabled = true
  vim.notify("Key print enabled", vim.log.levels.INFO)
end

function M.disable()
  if not enabled then
    return
  end
  vim.on_key(nil, ns)
  enabled = false
  vim.notify("Key print disabled", vim.log.levels.INFO)
end

function M.toggle()
  if enabled then
    M.disable()
  else
    M.enable()
  end
end

return M
