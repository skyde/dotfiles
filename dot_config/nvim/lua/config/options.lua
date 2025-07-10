-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Prevent 'edge hugging'
vim.o.scrolloff = 8

-- Adjust increment of a half page up / down command size
vim.o.scroll = 16

vim.opt.fileformats = { "unix", "dos" }

vim.g.neovide_cursor_vfx_mode = "none"
vim.g.neovide_cursor_animation_length = 0
vim.g.neovide_cursor_trail_length = 0
-- enable mouse in all modes (normal, visual, insert, command-line)
vim.opt.mouse = "a"

local win32yank_path = "win32yank.exe"
-- Clipboard provider (works in native Windows, MSYS2 and WSL)
if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 or vim.fn.has("win32unix") == 1 then
  vim.g.clipboard = {
    name = "win32yank-lf",
    copy = {
      ["+"] = { win32yank_path, "-i", "--crlf" },
      ["*"] = { win32yank_path, "-i", "--crlf" },
    },
    paste = {
      ["+"] = { win32yank_path, "-o", "--lf" },
      ["*"] = { win32yank_path, "-o", "--lf" },
    },
    cache_enabled = 0, -- 1 if you want selections cached for speed
  }
end

vim.opt.clipboard:append("unnamedplus")

-- Force a black background
vim.opt.background = "dark"

local function set_black_background()
  for _, group in ipairs({ "Normal", "NormalNC", "NormalFloat", "SignColumn", "MsgArea" }) do
    vim.api.nvim_set_hl(0, group, { bg = "#000000" })
  end
end

vim.api.nvim_create_autocmd("ColorScheme", {
  pattern = "*",
  callback = set_black_background,
})

set_black_background()
