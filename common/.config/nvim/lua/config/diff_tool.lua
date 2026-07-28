local M = {}

local methods = {
  dirs = "dir_diff",
  files = "diff_files",
  merge = "merge_files",
}

local function fail(message)
  vim.api.nvim_err_writeln("Neovim diff tool: " .. tostring(message))
  vim.cmd("cquit 1")
end

function M.open(kind, paths)
  local method = methods[kind]
  if not method then
    return fail("unknown mode: " .. tostring(kind))
  end

  local ok, err = xpcall(function()
    local escaped = {}
    for index, path in ipairs(paths or {}) do
      if type(path) ~= "string" or path == "" then
        error(("path %d is missing"):format(index))
      end
      escaped[index] = vim.fn.fnameescape(vim.fs.normalize(path))
    end

    local has_lazy, lazy = pcall(require, "lazy")
    if has_lazy then
      lazy.load({ plugins = { "diffview-plus.nvim" } })
    end

    require("diffview")[method](escaped)
    if not require("diffview.lib").get_current_view() then
      error("Diffview rejected the supplied paths")
    end
  end, debug.traceback)

  if not ok then
    fail(err)
  end
end

return M
