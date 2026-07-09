-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Enable true color support
vim.opt.termguicolors = true

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
local is_windows = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 or vim.fn.has("win32unix") == 1
local use_osc52 = vim.env.SSH_CLIENT ~= nil
  or vim.env.SSH_TTY ~= nil
  or vim.env.SSH_CONNECTION ~= nil
  or vim.env.TMUX ~= nil

-- Clipboard provider (works in native Windows, MSYS2 and WSL)
if is_windows then
  vim.g.clipboard = require("config.clipboard").provider(
    "win32yank-lf",
    { win32yank_path, "-i", "--crlf" },
    { win32yank_path, "-o", "--lf" }
  )
elseif use_osc52 and vim.fn.executable("osc-copy") == 1 and vim.fn.executable("osc-paste") == 1 then
  vim.g.clipboard = require("config.clipboard").provider(
    "osc-copy/osc-paste",
    { "osc-copy" },
    { "osc-paste" }
  )
end

vim.opt.clipboard:append("unnamedplus")

vim.diagnostic.config({ underline = false })

-- Do not highlight the current line
vim.opt.cursorline = false

-- Remove the sign column gutter
vim.opt.signcolumn = "no"

-- Use a bright orange block cursor in normal mode and a hollow block when inserting
vim.opt.guicursor = {
  "n-v-c:block-Cursor", -- Normal/Visual/Command
  "i-ci:ver25-Cursor", -- Insert & Cmd‑line insert
  "r-cr:hor20-Cursor", -- Replace
  "o:hor50-Cursor", -- Operator‑pending
}

-- Don't show whitespace characters like tabs by default
vim.opt.list = false

-- Enable word wrap by default
vim.opt.wrap = true

-- Use a blank space for deleted lines in diff mode
vim.opt.fillchars:append({
  diff = " ",
})
