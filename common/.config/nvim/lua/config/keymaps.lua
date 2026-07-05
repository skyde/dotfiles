local map = vim.keymap.set
local print_keys = require("config.print_keys")
local project = require("config.project")

-- Use screen-line motions for arrow keys in Normal, Visual & Operator-Pending modes
for _, mode in ipairs({ "n", "v", "o" }) do
  map(mode, "<Up>", "gk", { noremap = true, desc = "Move up screen-line" })
  map(mode, "<Down>", "gj", { noremap = true, desc = "Move down screen-line" })
end

-- And in Insert mode, use <C-o> to invoke a single Normal-mode command
map("i", "<Up>", "<C-o>gk", { noremap = true, desc = "Move up screen-line (insert)" })
map("i", "<Down>", "<C-o>gj", { noremap = true, desc = "Move down screen-line (insert)" })

vim.keymap.set("n", "<C-u>", "16k", { noremap = true, desc = "Move Up 16 lines" })
vim.keymap.set("n", "<C-d>", "16j", { noremap = true, desc = "Move Down 16 lines" })

-- Enter block visual mode with <leader>v
vim.keymap.set("n", "<leader>v", "<C-v>", { noremap = true, desc = "Block Visual Mode" })

-- Redo with Shift+U, matching redo keybindings from other editors
map("n", "U", "<C-r>", { desc = "Redo" })

-- Move by words with the same Ctrl+Left/Right convention used by shells
-- and GUI editors.
local function move_previous_word()
  vim.cmd("normal! b")
end

local function move_previous_word_insert()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local search_start = 1
  local target_col = 0

  while true do
    local word_start, word_end = line:find("[%w_]+", search_start)
    if not word_start or (word_start - 1) >= col then
      break
    end

    target_col = word_start - 1
    search_start = word_end + 1
  end

  vim.api.nvim_win_set_cursor(0, { row, target_col })
  vim.cmd("startinsert")
end

local function move_next_word()
  vim.cmd("normal! e")
end

local function move_next_word_insert()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local word_start, word_end = line:find("[%w_]+", math.min(col + 1, #line + 1))

  if word_start and word_end then
    vim.api.nvim_win_set_cursor(0, { row, word_end })
  else
    vim.api.nvim_win_set_cursor(0, { row, #line })
  end

  vim.cmd("startinsert")
end

for _, lhs in ipairs({ "<C-Left>", "\27[1;5D" }) do
  map("n", lhs, move_previous_word, { desc = "Move to previous word" })
  map("i", lhs, move_previous_word_insert, { desc = "Move to previous word" })
end

for _, lhs in ipairs({ "<C-Right>", "\27[1;5C" }) do
  map("n", lhs, move_next_word, { desc = "Move to next word" })
  map("i", lhs, move_next_word_insert, { desc = "Move to next word" })
end

local function previous_word_start(line, boundary)
  if boundary <= 0 then
    return nil
  end

  local trimmed_boundary = boundary
  while trimmed_boundary > 0 and line:sub(trimmed_boundary, trimmed_boundary):match("%s") do
    trimmed_boundary = trimmed_boundary - 1
  end

  local search_start = 1
  local target_start = nil

  while true do
    local word_start, word_end = line:find("[%w_]+", search_start)
    if not word_start or word_start > trimmed_boundary then
      break
    end

    if word_end >= trimmed_boundary then
      target_start = word_start
      break
    end

    target_start = word_start
    search_start = word_end + 1
  end

  return target_start
end

local function delete_previous_word_at(boundary, insert_mode)
  local row = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local target_start = previous_word_start(line, boundary)

  if not target_start then
    if insert_mode then
      vim.cmd("startinsert")
    end
    return
  end

  local new_line = line:sub(1, target_start - 1) .. line:sub(boundary + 1)
  local new_col = target_start - 1

  vim.api.nvim_set_current_line(new_line)
  if not insert_mode and #new_line > 0 then
    new_col = math.min(new_col, #new_line - 1)
  end
  vim.api.nvim_win_set_cursor(0, { row, new_col })

  if insert_mode then
    vim.cmd("startinsert")
  end
end

local function delete_previous_word()
  local _, col = unpack(vim.api.nvim_win_get_cursor(0))
  delete_previous_word_at(col + 1, false)
end

local function delete_previous_word_insert()
  local _, col = unpack(vim.api.nvim_win_get_cursor(0))
  local boundary = col
  if vim.fn.mode():sub(1, 1) ~= "i" and col < #vim.api.nvim_get_current_line() then
    boundary = col + 1
  end

  delete_previous_word_at(boundary, true)
end

for _, lhs in ipairs({ "<C-BS>", "\27[127;5u" }) do
  map("n", lhs, delete_previous_word, { desc = "Delete previous word" })
  map("i", lhs, delete_previous_word_insert, { desc = "Delete previous word" })
end

-- Delete the next word with the same Ctrl+Delete convention used by shells
-- and GUI editors.
local function delete_next_word()
  vim.cmd([[normal! "_dw]])
end

for _, lhs in ipairs({ "<C-Del>", "\27[3;5~" }) do
  map({ "n", "i" }, lhs, delete_next_word, { desc = "Delete next word" })
end

-- disable horizontal scroll with mouse/trackpad
for _, mode in ipairs({ "n", "i", "v", "o", "t" }) do
  map(mode, "<ScrollWheelLeft>", "<Nop>", { silent = true, desc = "Disable ← scroll" })
  map(mode, "<ScrollWheelRight>", "<Nop>", { silent = true, desc = "Disable → scroll" })
end

--------------------------------------------------------------------------
-- Shift+Function key helpers -------------------------------------------
--------------------------------------------------------------------------

---Map a command to both <S-Fn> and <F(n+12)> so the binding works across
---different terminal/OS combinations.
---@param n integer Function key number (1..12)
---@param rhs string|function Command or callback
---@param opts table|nil Additional options for `vim.keymap.set`
local function map_shift_f(n, rhs, opts)
  opts = opts or {}
  local modes = opts.mode or "n"
  opts.mode = nil
  map(modes, "<S-F" .. n .. ">", rhs, opts)
  map(modes, "<F" .. (n + 12) .. ">", rhs, opts)
end

local function load_plugin(name)
  local ok, lazy = pcall(require, "lazy")
  if ok then
    pcall(lazy.load, { plugins = { name } })
  end
end

local function run_user_command(command, failure_message)
  local ok, err = pcall(vim.cmd, command)
  if not ok then
    vim.notify(failure_message .. ": " .. tostring(err), vim.log.levels.WARN)
    return false
  end

  return true
end

local function task_workspace_dir()
  local start = project.buffer_start(0)
  local _, workspace_dir = project.vscode_file("tasks.json", start)
  return workspace_dir or project.root(start)
end

local function run_project_task(overseer, opts)
  local dir = task_workspace_dir()
  local run_opts = vim.tbl_extend("force", opts or {}, {
    cwd = dir,
    search_params = {
      dir = dir,
      filetype = vim.bo.filetype,
    },
  })
  local ok, err = pcall(overseer.run_task, run_opts)
  if not ok then
    vim.notify("Unable to run task: " .. tostring(err), vim.log.levels.WARN)
    return false
  end

  return true
end

local function run_default_build()
  load_plugin("overseer.nvim")

  local ok, overseer = pcall(require, "overseer")
  if ok then
    if run_project_task(overseer, { tags = { overseer.TAG.BUILD } }) then
      return
    end
  end

  if vim.fn.exists(":CMakeBuild") == 2 then
    run_user_command("CMakeBuild", "Unable to run CMakeBuild")
    return
  end

  vim.notify("No build task runner is available", vim.log.levels.WARN)
end

local function find_type_symbol()
  load_plugin("telescope.nvim")

  local ok, builtin = pcall(require, "telescope.builtin")
  if ok then
    local symbols_ok, err = pcall(builtin.lsp_workspace_symbols, {
      symbols = { "class", "struct", "interface", "enum" },
    })
    if symbols_ok then
      return
    end

    vim.notify("Unable to find type symbols: " .. tostring(err), vim.log.levels.WARN)
  end

  if vim.fn.exists(":Telescope") == 2 then
    run_user_command("Telescope lsp_workspace_symbols", "Unable to run Telescope")
    return
  end

  vim.notify("Telescope is unavailable", vim.log.levels.WARN)
end

local function stop_current_task()
  load_plugin("overseer.nvim")

  local ok, overseer = pcall(require, "overseer")
  if ok then
    local list_ok, tasks = pcall(overseer.list_tasks, { unique = true, status = "RUNNING" })
    if list_ok then
      local task = tasks[1]
      if task then
        local stop_ok, err = pcall(overseer.run_action, task, "stop")
        if stop_ok then
          return
        end

        vim.notify("Unable to stop task: " .. tostring(err), vim.log.levels.WARN)
      end
    else
      vim.notify("Unable to list running tasks: " .. tostring(tasks), vim.log.levels.WARN)
    end
  end

  if vim.fn.exists(":CMakeStop") == 2 then
    run_user_command("CMakeStop", "Unable to run CMakeStop")
    return
  end

  if vim.fn.exists(":OverseerTaskAction") == 2 then
    run_user_command("OverseerTaskAction", "Unable to run OverseerTaskAction")
    return
  end

  vim.notify("No running task command is available", vim.log.levels.WARN)
end

local function get_lsp_clients(bufnr)
  if vim.lsp.get_clients then
    return vim.lsp.get_clients({ bufnr = bufnr })
  end

  return vim.lsp.get_active_clients({ bufnr = bufnr })
end

local function goto_definition()
  if #get_lsp_clients(0) == 0 then
    vim.notify("No LSP client attached", vim.log.levels.INFO)
    return
  end

  local ok, err = pcall(vim.lsp.buf.definition)
  if not ok then
    vim.notify("Unable to go to definition: " .. tostring(err), vim.log.levels.WARN)
  end
end

local function toggle_search_highlight()
  vim.o.hlsearch = not vim.o.hlsearch
end

local function switch_source_header()
  if vim.fn.exists(":ClangdSwitchSourceHeader") ~= 2 then
    vim.notify("ClangdSwitchSourceHeader is unavailable", vim.log.levels.INFO)
    return
  end

  local ok, err = pcall(vim.cmd, "ClangdSwitchSourceHeader")
  if not ok then
    vim.notify("Unable to switch source/header: " .. tostring(err), vim.log.levels.WARN)
  end
end

-- Build and navigation macros from the shared keyboard layer.
map_shift_f(2, run_default_build, { mode = { "n", "i" }, desc = "Run Build" })
map_shift_f(3, find_type_symbol, { mode = { "n", "i" }, desc = "Find Type Symbol" })

-- Move up/down 16 lines.
map_shift_f(4, "16k", { mode = { "n", "v" }, desc = "Move Up 16 lines", noremap = true })
map_shift_f(4, "<C-o>16k", { mode = "i", desc = "Move Up 16 lines", noremap = true })
map_shift_f(6, "16j", { mode = { "n", "v" }, desc = "Move Down 16 lines", noremap = true })
map_shift_f(6, "<C-o>16j", { mode = "i", desc = "Move Down 16 lines", noremap = true })

-- Stop current build
map_shift_f(7, stop_current_task, { mode = { "n", "i" }, desc = "Stop Build" })

-- Go to LSP definition
map_shift_f(8, goto_definition, { mode = { "n", "i" }, desc = "Goto Definition" })

-- Toggle persistent search highlighting. Shift+F10 is reserved by tmux as a
-- terminal-level secondary prefix, so the search toggle intentionally uses F9.
map_shift_f(9, toggle_search_highlight, { mode = { "n", "i" }, desc = "Toggle Search Highlight" })

-- Leader-based toggle for key print debugging
vim.keymap.set("n", "<leader>uk", print_keys.toggle, {
  desc = "Toggle Key Print",
})

map_shift_f(11, "gcc", { remap = true, silent = true, desc = "Toggle Comment (line)" })
map_shift_f(11, "<C-o>gcc", { mode = "i", remap = true, silent = true, desc = "Toggle Comment (line)" })

map_shift_f(11, "gc", { mode = "x", remap = true, silent = true, desc = "Toggle Comment (block)" })

-- Reload the current buffer, smart-handling Lua files
local function source_current_file()
  if vim.bo.filetype == "lua" then
    run_user_command("luafile %", "Unable to source current file")
  else
    run_user_command("source %", "Unable to source current file")
  end
end

vim.keymap.set("n", "zl", source_current_file, { desc = "Source current file" })

-- Reload the entire Neovim configuration and plugins
local function reload_config()
  if not run_user_command("source $MYVIMRC", "Unable to reload config") then
    return
  end

  run_user_command("Lazy sync", "Unable to sync plugins")
end

vim.keymap.set("n", "<leader>rr", reload_config, { desc = "Reload config" })

local function diagnostic_jump(count, severity)
  return function()
    local ok, err = pcall(function()
      if vim.diagnostic.jump then
        vim.diagnostic.jump({ count = count, severity = severity, float = true })
      elseif count > 0 then
        vim.diagnostic.goto_next({ severity = severity, float = true })
      else
        vim.diagnostic.goto_prev({ severity = severity, float = true })
      end
    end)

    if not ok then
      vim.notify("Unable to jump diagnostics: " .. tostring(err), vim.log.levels.INFO)
    end
  end
end

local function diagnostic_list(kind)
  return function()
    local ok, err = pcall(function()
      if kind == "quickfix" then
        vim.diagnostic.setqflist({ open = true })
      else
        vim.diagnostic.setloclist({ open = true })
      end
    end)

    if not ok then
      vim.notify("Unable to populate diagnostics list: " .. tostring(err), vim.log.levels.INFO)
    end
  end
end

local function line_diagnostics()
  local ok, err = pcall(vim.diagnostic.open_float)
  if not ok then
    vim.notify("Unable to open line diagnostics: " .. tostring(err), vim.log.levels.INFO)
  end
end

local function list_jump(command, empty_message)
  return function()
    local ok, err = pcall(vim.cmd, command)
    if not ok then
      vim.notify(empty_message .. ": " .. err, vim.log.levels.INFO)
    end
  end
end

local function list_open(command, empty_message)
  return function()
    local ok, err = pcall(vim.cmd, command)
    if not ok then
      vim.notify(empty_message .. ": " .. err, vim.log.levels.INFO)
    end
  end
end

map("n", "]d", diagnostic_jump(1), { desc = "Next diagnostic" })
map("n", "[d", diagnostic_jump(-1), { desc = "Previous diagnostic" })
map("n", "]e", diagnostic_jump(1, vim.diagnostic.severity.ERROR), { desc = "Next error" })
map("n", "[e", diagnostic_jump(-1, vim.diagnostic.severity.ERROR), { desc = "Previous error" })
map("n", "]w", diagnostic_jump(1, vim.diagnostic.severity.WARN), { desc = "Next warning" })
map("n", "[w", diagnostic_jump(-1, vim.diagnostic.severity.WARN), { desc = "Previous warning" })
map("n", "]q", list_jump("cnext", "No next quickfix item"), { desc = "Next quickfix item" })
map("n", "[q", list_jump("cprevious", "No previous quickfix item"), { desc = "Previous quickfix item" })
map("n", "]l", list_jump("lnext", "No next location item"), { desc = "Next location item" })
map("n", "[l", list_jump("lprevious", "No previous location item"), { desc = "Previous location item" })
map("n", "<leader>cd", line_diagnostics, { desc = "Line diagnostics" })
map("n", "<leader>cq", diagnostic_list("quickfix"), { desc = "Diagnostics to quickfix" })
map("n", "<leader>cl", diagnostic_list("loclist"), { desc = "Diagnostics to location list" })
map("n", "<leader>co", list_open("copen", "No quickfix list"), { desc = "Open quickfix" })
map("n", "<leader>cO", list_open("lopen", "No location list"), { desc = "Open location list" })

--------------------------------------------------------------------------
-- Map normal shortcut (used by macros to NVim) -----------------------------------------------------
--------------------------------------------------------------------------

-- Save file with Cmd+S in normal, insert, and visual mode.
map({ "n", "i", "v" }, "<D-s>", "<cmd>w<CR>", { desc = "Save file" })

-- Same action via Shift+F5 (sent by kitty Cmd+S)
map_shift_f(5, "<cmd>w<CR>", { mode = { "n", "i", "v" }, desc = "Save file" })

-- Toggle between source and header files (requires clangd)
map("n", "<A-o>", switch_source_header, { desc = "Switch header/source" })

-- Navigate jump list with Alt+Left/Right
map("n", "<D-Left>", "<C-o>", { desc = "Jump backward" })
map("n", "<D-Right>", "<C-i>", { desc = "Jump forward" })

-- macOS clipboard shortcuts
local function copy_clipboard_normal()
  vim.cmd([[normal! "+yy]])
end

local function copy_clipboard_visual()
  vim.api.nvim_feedkeys(vim.keycode([["+y]]), "nx", false)
end

local function cut_clipboard_normal()
  if vim.bo.buftype == "terminal" then
    copy_clipboard_normal()
    return
  end

  vim.cmd([[normal! "+dd]])
end

local function cut_clipboard_visual()
  if vim.bo.buftype == "terminal" then
    copy_clipboard_visual()
    return
  end

  vim.api.nvim_feedkeys(vim.keycode([["+d]]), "nx", false)
end

local function copy_clipboard_terminal()
  vim.fn.setreg("+", vim.api.nvim_get_current_line(), "V")
end

local function cut_clipboard_terminal()
  copy_clipboard_terminal()
end

local function paste_clipboard_to_terminal()
  local ok, job_id = pcall(vim.api.nvim_buf_get_var, 0, "terminal_job_id")
  if not ok or type(job_id) ~= "number" then
    vim.notify("Unable to paste: no terminal job", vim.log.levels.WARN)
    return
  end

  local get_ok, lines = pcall(vim.fn.getreg, "+", 1, true)
  if not get_ok then
    vim.notify("Unable to paste: + register failed (" .. tostring(lines) .. ")", vim.log.levels.WARN)
    return
  end

  local text = type(lines) == "table" and table.concat(lines, "\n") or tostring(lines)
  if text == "" then
    return
  end

  local type_ok, regtype = pcall(vim.fn.getregtype, "+")
  if type_ok and type(regtype) == "string" and regtype:sub(1, 1) == "V" then
    text = text .. "\n"
  end

  local paste_ok, paste_result = pcall(vim.api.nvim_paste, text, false, -1)
  if paste_ok and paste_result ~= false then
    return
  end

  local chan_ok, chan_err = pcall(vim.api.nvim_chan_send, job_id, text)
  if chan_ok then
    return
  end

  vim.notify(
    "Unable to paste into terminal: paste failed ("
      .. tostring(paste_result)
      .. "); channel send failed ("
      .. tostring(chan_err)
      .. ")",
    vim.log.levels.WARN
  )
end

local function paste_clipboard_normal()
  if vim.bo.buftype == "terminal" then
    paste_clipboard_to_terminal()
    return
  end

  for _ = 1, vim.v.count1 do
    vim.cmd([[normal! "+p]])
  end
end

local function paste_clipboard_visual()
  if vim.bo.buftype == "terminal" then
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
    paste_clipboard_to_terminal()
    return
  end

  vim.api.nvim_feedkeys(vim.keycode([["+P]]), "n", false)
end

local function delete_to_line_start()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  if col <= 0 then
    return
  end

  local line = vim.api.nvim_get_current_line()
  vim.api.nvim_set_current_line(line:sub(col + 1))
  vim.api.nvim_win_set_cursor(0, { row, 0 })
end

local function terminal_delete_to_line_start()
  local ok, job_id = pcall(vim.api.nvim_buf_get_var, 0, "terminal_job_id")
  if ok and type(job_id) == "number" then
    vim.api.nvim_chan_send(job_id, "\21")
  end
end

map("n", "<D-c>", copy_clipboard_normal, { desc = "Copy line" })
map("v", "<D-c>", copy_clipboard_visual, { desc = "Copy selection" })
map("i", "<D-c>", '<C-o>"+yy', { desc = "Copy line" })
map("t", "<D-c>", copy_clipboard_terminal, { desc = "Copy line" })
map("n", "<D-x>", cut_clipboard_normal, { desc = "Cut line" })
map("v", "<D-x>", cut_clipboard_visual, { desc = "Cut selection" })
map("i", "<D-x>", '<C-o>"+dd', { desc = "Cut line" })
map("t", "<D-x>", cut_clipboard_terminal, { desc = "Cut line" })
for _, lhs in ipairs({ "<C-Insert>", "\27[2;5~" }) do
  map("n", lhs, copy_clipboard_normal, { desc = "Copy line" })
  map("v", lhs, copy_clipboard_visual, { desc = "Copy selection" })
  map("i", lhs, '<C-o>"+yy', { desc = "Copy line" })
  map("t", lhs, copy_clipboard_terminal, { desc = "Copy line" })
end
for _, lhs in ipairs({ "<S-Del>", "\27[3;2~" }) do
  map("n", lhs, cut_clipboard_normal, { desc = "Cut line" })
  map("v", lhs, cut_clipboard_visual, { desc = "Cut selection" })
  map("i", lhs, '<C-o>"+dd', { desc = "Cut line" })
  map("t", lhs, cut_clipboard_terminal, { desc = "Cut line" })
end
map("n", "<D-v>", paste_clipboard_normal, { desc = "Paste" })
-- Visual P replaces the selection without clobbering the unnamed register.
map("v", "<D-v>", paste_clipboard_visual, { desc = "Paste over selection" })
map("i", "<D-v>", "<C-r>+", { desc = "Paste" })
map("c", "<D-v>", "<C-r>+", { desc = "Paste" })
map("t", "<D-v>", paste_clipboard_to_terminal, { desc = "Paste" })
for _, lhs in ipairs({ "<S-Insert>", "\27[2;2~" }) do
  map("n", lhs, paste_clipboard_normal, { desc = "Paste" })
  map("v", lhs, paste_clipboard_visual, { desc = "Paste over selection" })
  map("i", lhs, "<C-r>+", { desc = "Paste" })
  map("c", lhs, "<C-r>+", { desc = "Paste" })
  map("t", lhs, paste_clipboard_to_terminal, { desc = "Paste" })
end
map({ "n", "i" }, "<D-BS>", delete_to_line_start, { desc = "Delete to line start" })
map("c", "<D-BS>", "<C-u>", { desc = "Delete to line start" })
map("t", "<D-BS>", terminal_delete_to_line_start, { desc = "Delete to line start" })
map({ "n", "v" }, "<D-a>", "ggVG", { desc = "Select all" })
map("i", "<D-a>", "<Esc>ggVG", { desc = "Select all" })

pcall(vim.keymap.del, "n", "<S-h>")
pcall(vim.keymap.del, "n", "<S-l>")

-- Buffer navigation via GUI Cmd+Shift keys where supported.
map("n", "<D-S-]>", ":bnext<CR>", { desc = "Next buffer" })
map("n", "<D-S-[>", ":bprevious<CR>", { desc = "Previous buffer" })

-- Same actions via Shift+F1/F12 or F13/F24 terminal encodings.
map_shift_f(1, "<cmd>bprevious<CR>", { mode = { "n", "i" }, desc = "Previous buffer" })
map_shift_f(12, "<cmd>bnext<CR>", { mode = { "n", "i" }, desc = "Next buffer" })

-- Open new tab
map("n", "<leader>bn", "<cmd>tabnew<CR>", { desc = "New tab" })

-- Move tab left/right
map("n", "<leader>bh", "<cmd>tabmove -1<CR>", { desc = "Move tab left" })
map("n", "<leader>bl", "<cmd>tabmove +1<CR>", { desc = "Move tab right" })

-- Jump to tab by number
for i = 1, 9 do
  map("n", "<leader>" .. i, "<cmd>tabnext " .. i .. "<CR>", {
    desc = "Go to tab " .. i,
  })
end
map("n", "<leader>0", "<cmd>tablast<CR>", { desc = "Go to last tab" })

local function project_dir()
  return project.root_for_buffer(0)
end

local function file_dir()
  return project.file_dir_for_buffer(0)
end

-- Indent with Tab and unindent with Shift+Tab
map("n", "<Tab>", ">>", { desc = "Indent line" })
map("n", "<S-Tab>", "<<", { desc = "Unindent line" })
map("v", "<Tab>", ">gv", { desc = "Indent selection" })
map("v", "<S-Tab>", "<gv", { desc = "Unindent selection" })

local function open_yazi_at(dir)
  load_plugin("yazi.nvim")

  local ok, yazi = pcall(require, "yazi")
  if not (ok and yazi and type(yazi.yazi) == "function") then
    return false
  end

  local path = project.buffer_path(0)
  local args = path and { reveal_path = path } or nil
  local open_ok, err = pcall(yazi.yazi, nil, dir, args)
  if not open_ok then
    vim.notify("Unable to open Yazi: " .. tostring(err), vim.log.levels.WARN)
    return false
  end

  return true
end

local function open_lf_at(dir)
  load_plugin("fm-nvim")

  local ok, fm = pcall(require, "fm-nvim")
  if ok and fm and type(fm.Lf) == "function" then
    local lf_ok, err = pcall(fm.Lf, vim.fn.shellescape(dir))
    if not lf_ok then
      vim.notify("Unable to open LF: " .. tostring(err), vim.log.levels.WARN)
      return false
    end

    return true
  end

  if vim.fn.exists(":Lf") == 2 then
    return run_user_command("Lf " .. vim.fn.fnameescape(dir), "Unable to open LF")
  end

  return false
end

local function open_nvim_tree_at(dir)
  if vim.fn.exists(":NvimTreeToggle") ~= 2 then
    return false
  end

  run_user_command("NvimTreeToggle " .. vim.fn.fnameescape(dir), "Unable to open NvimTree")
  return true
end

local function open_file_manager()
  local dir = project_dir()

  if open_yazi_at(dir) or open_lf_at(dir) then
    return
  end

  local ok, mini = pcall(require, "mini.files")
  if ok and mini and type(mini.open) == "function" then
    local mini_ok, err = pcall(mini.open, dir)
    if not mini_ok then
      vim.notify("Unable to open mini.files: " .. tostring(err), vim.log.levels.WARN)
    else
      return
    end
  end

  if open_nvim_tree_at(dir) then
    return
  end

  vim.notify("No file manager is available", vim.log.levels.WARN)
end

vim.keymap.set({ "n", "v" }, "<leader>e", open_file_manager, {
  silent = true,
  desc = "File manager at project root",
})

local terminals_by_dir = {}

local function set_local_dir(dir, label)
  dir = project.normalize_dir(dir)
  if not run_user_command("lcd " .. vim.fn.fnameescape(dir), "Unable to set " .. label) then
    return
  end

  vim.notify(label .. ": " .. dir)
end

local function terminal_is_running(bufnr)
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    return false
  end

  if vim.bo[bufnr].buftype ~= "terminal" then
    return false
  end

  local ok, job_id = pcall(vim.api.nvim_buf_get_var, bufnr, "terminal_job_id")
  if not (ok and type(job_id) == "number") then
    return false
  end

  local wait_ok, status = pcall(vim.fn.jobwait, { job_id }, 0)
  return wait_ok and type(status) == "table" and status[1] == -1
end

local function terminal_buffer_exists(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype == "terminal"
end

local function terminal_split_height()
  local preferred = math.max(8, math.min(15, math.floor(vim.o.lines * 0.30)))
  local available = math.max(1, vim.o.lines - vim.o.cmdheight - 6)
  return math.max(1, math.min(preferred, available))
end

local function cached_terminal(dir)
  local bufnr = terminals_by_dir[dir]
  if bufnr and not terminal_buffer_exists(bufnr) then
    terminals_by_dir[dir] = nil
    return nil
  end

  return bufnr
end

local function focus_visible_buffer(bufnr)
  local current_tab = vim.api.nvim_get_current_tabpage()

  for _, win_id in ipairs(vim.fn.win_findbuf(bufnr)) do
    if vim.api.nvim_win_is_valid(win_id) and vim.api.nvim_win_get_tabpage(win_id) == current_tab then
      local ok, err = pcall(vim.api.nvim_set_current_win, win_id)
      if ok then
        return true
      end

      vim.notify("Unable to focus terminal: " .. tostring(err), vim.log.levels.WARN)
    end
  end

  return false
end

local function hide_visible_buffer(bufnr)
  local hidden = false
  local current_tab = vim.api.nvim_get_current_tabpage()

  for _, win_id in ipairs(vim.fn.win_findbuf(bufnr)) do
    if vim.api.nvim_win_is_valid(win_id) and vim.api.nvim_win_get_tabpage(win_id) == current_tab then
      if #vim.api.nvim_tabpage_list_wins(current_tab) == 1 then
        local ok, err = pcall(vim.api.nvim_set_current_win, win_id)
        if ok and run_user_command("hide enew", "Unable to hide terminal") then
          hidden = true
        elseif not ok then
          vim.notify("Unable to hide terminal: " .. tostring(err), vim.log.levels.WARN)
        end
      else
        local ok, err = pcall(vim.api.nvim_win_close, win_id, false)
        if ok then
          hidden = true
        else
          vim.notify("Unable to hide terminal: " .. tostring(err), vim.log.levels.WARN)
        end
      end
    end
  end

  return hidden
end

local function close_failed_terminal_window(win_id)
  if not (win_id and vim.api.nvim_win_is_valid(win_id)) then
    return
  end

  local ok, err = pcall(vim.api.nvim_win_close, win_id, true)
  if ok and not vim.api.nvim_win_is_valid(win_id) then
    return
  end

  local hide_ok, hide_err = pcall(vim.api.nvim_win_call, win_id, function()
    vim.cmd("hide")
  end)
  if hide_ok and not vim.api.nvim_win_is_valid(win_id) then
    return
  end

  vim.notify("Unable to close failed terminal split: " .. tostring(hide_ok and err or hide_err), vim.log.levels.WARN)
end

local function open_terminal(dir)
  dir = project.normalize_dir(dir)

  local bufnr = cached_terminal(dir)
  if terminal_is_running(bufnr) and focus_visible_buffer(bufnr) then
    run_user_command("startinsert", "Unable to enter terminal insert mode")
    return
  end

  local height = terminal_split_height()
  if not run_user_command("botright " .. height .. "split", "Unable to open terminal split") then
    return
  end
  local terminal_win = vim.api.nvim_get_current_win()
  if not run_user_command("lcd " .. vim.fn.fnameescape(dir), "Unable to set terminal directory") then
    close_failed_terminal_window(terminal_win)
    return
  end
  if not run_user_command("resize " .. height, "Unable to resize terminal split") then
    close_failed_terminal_window(terminal_win)
    return
  end

  if terminal_is_running(bufnr) then
    local ok, err = pcall(vim.api.nvim_win_set_buf, 0, bufnr)
    if not ok then
      vim.notify("Unable to reuse terminal buffer: " .. tostring(err), vim.log.levels.WARN)
      close_failed_terminal_window(terminal_win)
      return
    end
  else
    if not run_user_command("terminal", "Unable to open terminal") then
      close_failed_terminal_window(terminal_win)
      return
    end
    terminals_by_dir[dir] = vim.api.nvim_get_current_buf()
  end

  run_user_command("startinsert", "Unable to enter terminal insert mode")
end

local function hide_terminal(dir)
  dir = project.normalize_dir(dir)

  local current_bufnr = vim.api.nvim_get_current_buf()
  if terminal_buffer_exists(current_bufnr) and hide_visible_buffer(current_bufnr) then
    return
  end

  local bufnr = cached_terminal(dir)
  if terminal_buffer_exists(bufnr) and hide_visible_buffer(bufnr) then
    return
  end

  for cached_dir, cached_bufnr in pairs(terminals_by_dir) do
    if terminal_buffer_exists(cached_bufnr) then
      if hide_visible_buffer(cached_bufnr) then
        return
      end
    else
      terminals_by_dir[cached_dir] = nil
    end
  end

  vim.notify("No visible terminal", vim.log.levels.INFO)
end

local function tmux_session_command()
  local function is_executable(command)
    local ok, result = pcall(vim.fn.executable, command)
    return ok and result == 1
  end

  local function exepath(name)
    local ok, command = pcall(vim.fn.exepath, name)
    if ok and command ~= "" then
      return command
    end

    return nil
  end

  for _, name in ipairs({ "tmux-session-notify", "tmux-session" }) do
    local home = vim.env.HOME
    if home and home ~= "" then
      for _, home_command in ipairs({
        home .. "/.local/bin/" .. name,
        home .. "/dotfiles/common/.local/bin/" .. name,
      }) do
        if is_executable(home_command) then
          return home_command
        end
      end
    end

    local command = exepath(name)
    if command then
      return command
    end
  end

  return nil
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

local function switch_tmux_project_session(window)
  return function()
    if not inside_tmux_client() then
      vim.notify("Not inside tmux", vim.log.levels.INFO)
      return
    end

    local command = tmux_session_command()
    if not command then
      vim.notify("tmux-session is unavailable", vim.log.levels.WARN)
      return
    end

    local dir = project_dir()
    local args = { command }
    local target = "session"
    if window then
      vim.list_extend(args, { "--window", window })
      target = ({
        agent = "AI window",
        resume = "resume window",
        terminal = "terminal window",
      })[window] or (window .. " window")
    end
    vim.list_extend(args, { "--start-dir", dir })

    local stderr_lines = {}
    local job_ok, job_id = pcall(vim.fn.jobstart, args, {
      stderr_buffered = true,
      on_stderr = function(_, data)
        for _, line in ipairs(data or {}) do
          if line ~= "" then
            table.insert(stderr_lines, line)
          end
        end
      end,
      on_exit = function(_, code)
        vim.schedule(function()
          if code == 0 then
            vim.notify("Tmux project " .. target .. ": " .. dir)
            return
          end

          local message = table.concat(stderr_lines, "\n")
          if message == "" then
            message = "exit " .. tostring(code)
          end
          vim.notify("tmux-session failed: " .. message, vim.log.levels.WARN)
        end)
      end,
    })
    if not job_ok then
      vim.notify("Unable to start tmux-session: " .. tostring(job_id), vim.log.levels.WARN)
      return
    end
    if type(job_id) ~= "number" or job_id <= 0 then
      vim.notify("Unable to start tmux-session", vim.log.levels.WARN)
      return
    end
  end
end

map("n", "<leader>ft", function()
  open_terminal(project_dir())
end, { desc = "Terminal at project root" })

map("n", "<leader>fT", function()
  open_terminal(file_dir())
end, { desc = "Terminal at file directory" })

map("n", "<leader>fX", function()
  hide_terminal(project_dir())
end, { desc = "Hide terminal" })

map("n", "<leader>fc", function()
  set_local_dir(project_dir(), "Project cwd")
end, { desc = "Set cwd to project root" })

map("n", "<leader>fC", function()
  set_local_dir(file_dir(), "File cwd")
end, { desc = "Set cwd to file directory" })

map("n", "<leader>ws", switch_tmux_project_session(), { desc = "Tmux project session" })
map("n", "<leader>wr", switch_tmux_project_session("resume"), { desc = "Tmux project resume window" })
map("n", "<leader>wa", switch_tmux_project_session("agent"), { desc = "Tmux project AI window" })
map("n", "<leader>wt", switch_tmux_project_session("terminal"), { desc = "Tmux project terminal window" })

map("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

-- Move selection up / down
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selection down", silent = true })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selection up", silent = true })

local function path_relative_to_cwd(path)
  return project.relative_path(path, vim.fn.getcwd())
end

local function path_relative_to_project(path)
  return project.relative_path(path, project.root_for_path(path))
end

local function set_register(register, value)
  local ok, err = pcall(vim.fn.setreg, register, value)
  if ok then
    return true
  end

  return false, tostring(err)
end

local function copy_active_file_path(include_line, path_kind)
  local absolute_path = project.buffer_path(0)
  if not absolute_path then
    return vim.notify("No file", vim.log.levels.WARN)
  end

  local p = absolute_path

  if path_kind == "cwd" then
    p = path_relative_to_cwd(absolute_path)
  elseif path_kind == "project" then
    p = path_relative_to_project(absolute_path)
  end

  if include_line then
    p = p .. ":" .. vim.fn.line(".")
  end

  local register = "+"
  local ok, err = set_register(register, p)
  if not ok then
    register = '"'
    local fallback_ok, fallback_err = set_register(register, p)
    if not fallback_ok then
      vim.notify(
        "Unable to copy path: + register failed (" .. err .. '); " register failed (' .. fallback_err .. ")",
        vim.log.levels.WARN
      )
      return
    end
  end

  vim.notify("Copied path to " .. register .. ": " .. p)
end

map({ "n", "v" }, "<leader>fl", function()
  copy_active_file_path(false, "absolute")
end, { desc = "Copy path of active file" })

map({ "n", "v" }, "<leader>fL", function()
  copy_active_file_path(true, "absolute")
end, { desc = "Copy path and line of active file" })

map({ "n", "v" }, "<leader>fr", function()
  copy_active_file_path(false, "cwd")
end, { desc = "Copy relative path of active file" })

map({ "n", "v" }, "<leader>fR", function()
  copy_active_file_path(true, "cwd")
end, { desc = "Copy relative path and line of active file" })

map({ "n", "v" }, "<leader>fP", function()
  copy_active_file_path(false, "project")
end, { desc = "Copy project path of active file" })

map({ "n", "v" }, "<leader>fY", function()
  copy_active_file_path(true, "project")
end, { desc = "Copy project path and line of active file" })
