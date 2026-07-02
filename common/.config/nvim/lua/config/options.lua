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
local win32yank_available = false

if is_windows then
  local executable_ok, executable = pcall(vim.fn.executable, win32yank_path)
  win32yank_available = executable_ok and executable == 1
end
local function inside_tmux_client()
  if not (vim.env.TMUX and vim.env.TMUX ~= "") then
    return false
  end

  local executable_ok, executable = pcall(vim.fn.executable, "tmux")
  if not (executable_ok and executable == 1) then
    return false
  end

  local ok, pane_id = pcall(vim.fn.system, { "tmux", "display-message", "-p", "#{pane_id}" })
  return ok and vim.v.shell_error == 0 and vim.trim(pane_id or "") ~= ""
end

local function env_nonempty(name)
  local value = vim.env[name]
  return value ~= nil and value ~= ""
end

local use_osc52 = env_nonempty("SSH_CLIENT")
  or env_nonempty("SSH_TTY")
  or env_nonempty("SSH_CONNECTION")
  or inside_tmux_client()

local function executable_path(name)
  for _, candidate in ipairs({
    "~/.local/bin/" .. name,
    "~/dotfiles/common/.local/bin/" .. name,
  }) do
    local path = vim.fn.expand(candidate)
    local executable_ok, executable = pcall(vim.fn.executable, path)
    if executable_ok and executable == 1 then
      return path
    end
  end

  local exepath_ok, path = pcall(vim.fn.exepath, name)
  if exepath_ok and path ~= "" then
    return path
  end

  return nil
end

-- Clipboard provider (works in native Windows, MSYS2 and WSL)
if is_windows and win32yank_available then
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
elseif use_osc52 then
  local copy_helper = executable_path("osc-copy")
  local paste_helper = executable_path("osc-paste")

  if copy_helper and paste_helper then
    vim.g.clipboard = {
      name = "osc-copy/osc-paste",
      copy = {
        ["+"] = { copy_helper },
        ["*"] = { copy_helper },
      },
      paste = {
        ["+"] = { paste_helper },
        ["*"] = { paste_helper },
      },
      cache_enabled = 0,
    }
  else
    local ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")

    if ok then
      vim.g.clipboard = {
        name = "OSC 52",
        copy = {
          ["+"] = osc52.copy("+"),
          ["*"] = osc52.copy("*"),
        },
        paste = {
          ["+"] = osc52.paste("+"),
          ["*"] = osc52.paste("*"),
        },
      }
    end
  end
end

vim.opt.clipboard:append("unnamedplus")

vim.diagnostic.config({ underline = false })

-- Do not highlight the current line
vim.opt.cursorline = false

-- Hide the sign gutter until diagnostics, breakpoints, or other signs exist.
vim.opt.signcolumn = "auto:1"

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
