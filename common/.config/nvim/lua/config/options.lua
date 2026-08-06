-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Nothing here uses remote-plugin hosts, and leaving them enabled makes
-- Neovim probe for python3/ruby/node/perl interpreters at startup.
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0

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
    cache_enabled = 0,
  }
elseif use_osc52 and vim.fn.executable("osc-copy") == 1 and vim.fn.executable("osc-paste") == 1 then
  vim.g.clipboard = {
    name = "osc-copy/osc-paste",
    copy = {
      ["+"] = { "osc-copy" },
      ["*"] = { "osc-copy" },
    },
    paste = {
      ["+"] = { "osc-paste" },
      ["*"] = { "osc-paste" },
    },
    cache_enabled = 0,
  }
end

vim.opt.clipboard:append("unnamedplus")

vim.diagnostic.config({ underline = false })

-- Do not highlight the current line itself, but do highlight its line number.
-- 'cursorlineopt = number' means CursorLine (the row background) is never drawn;
-- only CursorLineNr is, which the theme paints in the cursor orange. Without
-- 'cursorline' at all, CursorLineNr is dead config and there is no position cue
-- left, since signcolumn is off below.
vim.opt.cursorline = true
vim.opt.cursorlineopt = "number"

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

-- Diff behaviour, matched to the git config in common/.config/git/config so a
-- diff looks the same in Neovim as it does in the terminal:
--   histogram    same algorithm as diff.algorithm
--   context:10   same as diff.context
--   linematch    lines up moved/edited pairs inside a hunk instead of showing
--                two solid blocks, which is what makes a side-by-side diff
--                readable on real code
vim.opt.diffopt = {
  "internal",
  "filler",
  "closeoff",
  "algorithm:histogram",
  "indent-heuristic",
  "linematch:60",
  "context:10",
}

-- Highlight the characters that changed inside a modified line, not just the
-- line — what delta does in the terminal. Only exists on nvim 0.12+, hence
-- the pcall rather than a version check.
pcall(function()
  vim.opt.diffopt:append("inline:char")
end)
