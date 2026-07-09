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

local clipboard_regtypes = {}

local function clipboard_lines_to_text(lines)
  return table.concat(lines or {}, "\n")
end

local function clipboard_text_to_lines(text)
  return vim.split(text or "", "\n", { plain = true })
end

local function notify_clipboard_failure(action, provider, err)
  local name = type(provider) == "table" and table.concat(provider, " ") or tostring(provider)
  vim.schedule(function()
    vim.notify("Clipboard " .. action .. " failed for " .. name .. ": " .. tostring(err), vim.log.levels.WARN)
  end)
end

local function call_clipboard_copy_provider(provider, lines, regtype)
  if type(provider) == "function" then
    return pcall(provider, lines, regtype)
  end

  if type(provider) == "table" then
    local ok, result = pcall(vim.fn.system, provider, clipboard_lines_to_text(lines))
    if not ok then
      return false, result
    end

    if vim.v.shell_error ~= 0 then
      return false, "exit " .. vim.v.shell_error .. ": " .. tostring(result)
    end

    return true
  end

  return false, "unsupported provider"
end

local function call_clipboard_paste_provider(provider)
  if type(provider) == "function" then
    local ok, lines, regtype = pcall(provider)
    if not ok then
      return false, nil, nil, lines
    end

    if type(lines) == "string" then
      lines = clipboard_text_to_lines(lines)
    end

    return true, lines, regtype
  end

  if type(provider) == "table" then
    local ok, result = pcall(vim.fn.system, provider)
    if not ok then
      return false, nil, nil, result
    end

    if vim.v.shell_error ~= 0 then
      return false, nil, nil, "exit " .. vim.v.shell_error .. ": " .. tostring(result)
    end

    return true, clipboard_text_to_lines(result), "v"
  end

  return false, nil, nil, "unsupported provider"
end

local function cache_clipboard_regtype(register, lines, regtype)
  clipboard_regtypes[register] = {
    text = clipboard_lines_to_text(lines),
    regtype = regtype,
  }
end

local function cached_clipboard_regtype(register, lines, fallback)
  local cached = clipboard_regtypes[register]
  if cached and cached.text == clipboard_lines_to_text(lines) then
    return cached.regtype
  end

  return fallback or "v"
end

local function wrap_clipboard_copy_provider(provider, register)
  return function(lines, regtype)
    local ok, err = call_clipboard_copy_provider(provider, lines, regtype)
    if ok then
      cache_clipboard_regtype(register, lines, regtype)
      return
    end

    clipboard_regtypes[register] = nil
    notify_clipboard_failure("copy", provider, err)
  end
end

local function wrap_clipboard_paste_provider(provider, register)
  return function()
    local ok, lines, regtype, err = call_clipboard_paste_provider(provider)
    if not ok then
      notify_clipboard_failure("paste", provider, err)
      return { "" }, "v"
    end

    return lines, cached_clipboard_regtype(register, lines, regtype)
  end
end

-- Clipboard provider (works in native Windows, MSYS2 and WSL)
if is_windows and win32yank_available then
  local copy_provider = { win32yank_path, "-i", "--crlf" }
  local paste_provider = { win32yank_path, "-o", "--lf" }

  vim.g.clipboard = {
    name = "win32yank-lf",
    copy = {
      ["+"] = wrap_clipboard_copy_provider(copy_provider, "+"),
      ["*"] = wrap_clipboard_copy_provider(copy_provider, "*"),
    },
    paste = {
      ["+"] = wrap_clipboard_paste_provider(paste_provider, "+"),
      ["*"] = wrap_clipboard_paste_provider(paste_provider, "*"),
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
        ["+"] = wrap_clipboard_copy_provider(copy_provider, "+"),
        ["*"] = wrap_clipboard_copy_provider(copy_provider_star, "*"),
      },
      paste = {
        ["+"] = wrap_clipboard_paste_provider(paste_provider, "+"),
        ["*"] = wrap_clipboard_paste_provider(paste_provider_star, "*"),
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
