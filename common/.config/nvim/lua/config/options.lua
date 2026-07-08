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
  local home = vim.env.HOME

  if home and home ~= "" then
    for _, path in ipairs({
      home .. "/.local/bin/" .. name,
      home .. "/dotfiles/common/.local/bin/" .. name,
    }) do
      local executable_ok, executable = pcall(vim.fn.executable, path)
      if executable_ok and executable == 1 then
        return path
      end
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
  local osc52_ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")
  local copy_provider = copy_helper and { copy_helper } or (osc52_ok and osc52.copy("+") or nil)
  local copy_provider_star = copy_helper and { copy_helper } or (osc52_ok and osc52.copy("*") or nil)
  local paste_provider = paste_helper and { paste_helper } or (osc52_ok and osc52.paste("+") or nil)
  local paste_provider_star = paste_helper and { paste_helper } or (osc52_ok and osc52.paste("*") or nil)

  local provider_name = "OSC 52"
  if copy_helper and paste_helper then
    provider_name = "osc-copy/osc-paste"
  elseif copy_helper then
    provider_name = "osc-copy/OSC 52"
  elseif paste_helper then
    provider_name = "OSC 52/osc-paste"
  end

  if copy_provider and copy_provider_star and paste_provider and paste_provider_star then
    vim.g.clipboard = {
      name = provider_name,
      copy = {
        ["+"] = copy_provider,
        ["*"] = copy_provider_star,
      },
      paste = {
        ["+"] = paste_provider,
        ["*"] = paste_provider_star,
      },
      cache_enabled = (copy_helper or paste_helper) and 0 or nil,
    }
  end
end

vim.opt.clipboard:append("unnamedplus")

vim.diagnostic.config({ underline = false })

-- Preserve literal tabs when pasting into terminal buffers.
vim.opt.termpastefilter = "BS,ESC,DEL"

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
