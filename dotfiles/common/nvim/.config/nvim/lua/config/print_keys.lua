local M = {}

local enabled = false

vim.on_key(function(char)
  if not enabled then
    return
  end
  vim.notify(vim.inspect(char))
end, vim.api.nvim_create_namespace("log-keys"))

function M.enable()
  if enabled then
    return
  end
  enabled = true
  vim.notify("Key print enabled", vim.log.levels.INFO)
end

function M.disable()
  if not enabled then
    return
  end
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
