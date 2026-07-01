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
local in_ssh = vim.env.SSH_CLIENT ~= nil or vim.env.SSH_TTY ~= nil or vim.env.SSH_CONNECTION ~= nil

-- True when a local clipboard tool nvim can auto-detect is available
-- (pbcopy on macOS, wl-copy/xclip/xsel on a Linux desktop). Mirrors the
-- detection order in the osc-copy script.
local has_local_clip = vim.fn.has("mac") == 1
  or (vim.env.WAYLAND_DISPLAY ~= nil and vim.fn.executable("wl-copy") == 1)
  or (vim.env.DISPLAY ~= nil and (vim.fn.executable("xclip") == 1 or vim.fn.executable("xsel") == 1))

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
elseif vim.env.TMUX ~= nil and (in_ssh or not has_local_clip) then
  -- SSH (or headless) + tmux: sync the clipboard through tmux's paste
  -- buffer over its socket rather than writing OSC 52 escape sequences to
  -- stdout. Escape sequences only reach the outer terminal when nvim owns
  -- the real tty, so they get swallowed when nvim runs inside another
  -- program's embedded terminal (e.g. an AI coding tool). The socket path
  -- always works, and
  -- with tmux's `set-clipboard on` the copy is still forwarded to the
  -- local terminal (and thus the OS clipboard) via OSC 52.
  -- Note: to paste text copied on the local machine, use the terminal's
  -- paste key (Cmd+V); `p` pastes what was last yanked in nvim or tmux.
  local tmux_paste = { "sh", "-c", "tmux save-buffer - 2>/dev/null || true" }
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
  -- Plain SSH session without tmux: copy with OSC 52. Paste falls back to
  -- the unnamed register because most terminals (VS Code included) refuse
  -- to answer OSC 52 paste queries, which would otherwise leave `p`
  -- waiting on a reply that never comes. Use the terminal's paste key
  -- (Cmd+V) to insert text copied on the local machine.
  local ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")

  if ok then
    local function reg_paste()
      return { vim.split(vim.fn.getreg('"'), "\n"), vim.fn.getregtype('"') }
    end
    vim.g.clipboard = {
      name = "OSC 52",
      copy = {
        ["+"] = osc52.copy("+"),
        ["*"] = osc52.copy("*"),
      },
      paste = {
        ["+"] = reg_paste,
        ["*"] = reg_paste,
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
