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
local in_tmux = vim.env.TMUX ~= nil
local in_ssh = vim.env.SSH_CLIENT ~= nil or vim.env.SSH_TTY ~= nil or vim.env.SSH_CONNECTION ~= nil

-- Paste falls back to the unnamed register when there is no readable system
-- clipboard. Real system pastes still arrive through the terminal's own
-- Cmd/Ctrl+V (bracketed paste), which never touches this provider.
local function register_paste()
  return { vim.split(vim.fn.getreg('"'), "\n"), vim.fn.getregtype('"') }
end

-- Read the tmux paste buffer, inferring linewise yanks from the trailing
-- newline that the copy side appends for them.
local function tmux_paste()
  local out = vim.fn.system({ "tmux", "save-buffer", "-" })
  if vim.v.shell_error ~= 0 then
    return register_paste()
  end
  local regtype = out:sub(-1) == "\n" and "V" or "v"
  local lines = vim.split(out, "\n")
  if regtype == "V" then
    table.remove(lines)
  end
  return { lines, regtype }
end

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
    cache_enabled = 0, -- 1 if you want selections cached for speed
  }
elseif in_ssh and in_tmux then
  -- Copy through the tmux server socket rather than by writing OSC 52 to our
  -- own tty: with `set-clipboard on` tmux forwards the buffer to the outer
  -- terminal (VS Code, kitty, ...) itself, so yanks reach the OS clipboard
  -- even when nvim runs embedded inside another program whose terminal
  -- swallows escape sequences.
  vim.g.clipboard = {
    name = "tmux",
    copy = {
      ["+"] = { "tmux", "load-buffer", "-w", "-" },
      ["*"] = { "tmux", "load-buffer", "-w", "-" },
    },
    paste = {
      ["+"] = tmux_paste,
      ["*"] = tmux_paste,
    },
    cache_enabled = 0,
  }
elseif in_ssh then
  -- Plain SSH: emit OSC 52 for copy, but never *query* the terminal for
  -- paste — VS Code's terminal does not answer OSC 52 reads, so a query
  -- would stall every `p`.
  local ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")

  if ok then
    vim.g.clipboard = {
      name = "OSC 52",
      copy = {
        ["+"] = osc52.copy("+"),
        ["*"] = osc52.copy("*"),
      },
      paste = {
        ["+"] = register_paste,
        ["*"] = register_paste,
      },
    }
  end
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
