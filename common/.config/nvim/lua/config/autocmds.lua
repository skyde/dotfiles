-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "*.json.tmpl",
  callback = function()
    vim.bo.filetype = "json"
  end,
})

-- Match VS Code's short highlighted-yank feedback without retaining a
-- selection/occurrence highlight.
pcall(vim.api.nvim_del_augroup_by_name, "lazyvim_highlight_yank")
local yank_group = vim.api.nvim_create_augroup("dotfiles_highlight_yank", { clear = true })
vim.api.nvim_create_autocmd("TextYankPost", {
  group = yank_group,
  callback = function()
    vim.highlight.on_yank({ higroup = "IncSearch", timeout = 125 })
  end,
})

-- Chromium's mojom extension has no dedicated parser here. C++ gives it
-- useful syntax, comments, motions, and language-aware editing.
vim.filetype.add({
  extension = {
    mojom = "cpp",
  },
})

-- VS Code keeps explicit formatting for JSON/JSONC, but disables format on
-- save for those filetypes.
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "json", "jsonc" },
  callback = function(args)
    vim.b[args.buf].autoformat = false
  end,
})

-- Keep a small, file-backed close history so <leader>bD mirrors VS Code's
-- reopen-closed-editor command.
local closed_buffers = {}
local close_history_group = vim.api.nvim_create_augroup("dotfiles_closed_buffers", { clear = true })
vim.api.nvim_create_autocmd("BufDelete", {
  group = close_history_group,
  callback = function(args)
    local path = vim.api.nvim_buf_get_name(args.buf)
    if path == "" or vim.bo[args.buf].buftype ~= "" then
      return
    end
    path = vim.fs.normalize(path)
    for index = #closed_buffers, 1, -1 do
      if closed_buffers[index] == path then
        table.remove(closed_buffers, index)
      end
    end
    table.insert(closed_buffers, path)
    if #closed_buffers > 20 then
      table.remove(closed_buffers, 1)
    end
  end,
})

vim.api.nvim_create_user_command("BufferReopenLast", function()
  while #closed_buffers > 0 do
    local path = table.remove(closed_buffers)
    if vim.fn.filereadable(path) == 1 then
      vim.cmd.edit(vim.fn.fnameescape(path))
      return
    end
  end
  vim.notify("No recently closed file", vim.log.levels.INFO)
end, { desc = "Reopen the most recently closed file buffer" })

-- Be robust if the group changes or is missing
pcall(vim.api.nvim_del_augroup_by_name, "lazyvim_wrap_spell")
