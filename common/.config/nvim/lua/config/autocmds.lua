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

-- The VS Code setup highlights a yank briefly instead of leaving a persistent
-- selection highlight behind.
pcall(vim.api.nvim_del_augroup_by_name, "lazyvim_highlight_yank")
local yank_group = vim.api.nvim_create_augroup("dotfiles_highlight_yank", { clear = true })
vim.api.nvim_create_autocmd("TextYankPost", {
  group = yank_group,
  callback = function()
    vim.highlight.on_yank({ higroup = "IncSearch", timeout = 125 })
  end,
})

-- Chromium's mojom extension has no direct Neovim equivalent. Treat the IDL
-- as C++ so it still gets useful syntax, motions, comments, and completion.
vim.filetype.add({
  extension = {
    mojom = "cpp",
  },
})

-- VS Code deliberately disables format-on-save for JSON/JSONC while keeping
-- explicit formatting available.
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "json", "jsonc" },
  callback = function(args)
    vim.b[args.buf].autoformat = false
  end,
})

-- Be robust if the group changes or is missing
pcall(vim.api.nvim_del_augroup_by_name, "lazyvim_wrap_spell")
