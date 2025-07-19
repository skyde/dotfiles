local map = vim.keymap.set
local print_keys = require("config.print_keys")

-- Use screen-line motions for arrow keys in Normal, Visual & Operator-Pending modes
for _, mode in ipairs({ "n", "v", "o" }) do
  map(mode, "<Up>", "gk", { noremap = true, desc = "Move up screen-line" })
  map(mode, "<Down>", "gj", { noremap = true, desc = "Move down screen-line" })
end

-- And in Insert mode, use <C-o> to invoke a single Normal-mode command
map("i", "<Up>", "<C-o>gk", { noremap = true, desc = "Move up screen-line (insert)" })
map("i", "<Down>", "<C-o>gj", { noremap = true, desc = "Move down screen-line (insert)" })

vim.keymap.set("n", "<C-u>", "16k", { noremap = true, desc = "Scroll Up 16 lines" })
vim.keymap.set("n", "<C-d>", "16j", { noremap = true, desc = "Scroll Down 16 lines" })

-- Enter block visual mode with <leader>v
vim.keymap.set("n", "<leader>v", "<C-v>", { noremap = true, desc = "Block Visual Mode" })

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

-- TODO: Use the vim.keymap.set style remap for all of these instead of this function call style

-- Scroll up/down 16 lines
map_shift_f(4, "<C-u>", { desc = "Scroll Up 16 lines", noremap = true })
map_shift_f(6, "<C-d>", { desc = "Scroll Down 16 lines", noremap = true })

-- Stop current build
map_shift_f(7, "<cmd>CMakeStop<CR>", { desc = "Stop Build" })

-- Go to LSP definition
map_shift_f(8, vim.lsp.buf.definition, { desc = "Goto Definition" })

-- Leader-based toggle for key print debugging
vim.keymap.set("n", "<leader>uk", print_keys.toggle, {
  desc = "Toggle Key Print",
})

map_shift_f(11, "gcc", { remap = true, silent = true, desc = "Toggle Comment (line)" })

map_shift_f(11, "gc", { mode = "x", remap = true, silent = true, desc = "Toggle Comment (block)" })

-- Reload the current buffer, smart-handling Lua files
vim.keymap.set("n", "zl", function()
  if vim.bo.filetype == "lua" then
    vim.cmd("luafile %") -- executes Lua buffers correctly
  else
    vim.cmd("source %") -- everything else
  end
end, { desc = "Source current file" })

--------------------------------------------------------------------------
-- Map normal shortcut (used by macros to NVim) -----------------------------------------------------
--------------------------------------------------------------------------

-- Save file with Ctrl+S in normal and insert mode
map({ "n", "i" }, "<D-s>", "<cmd>w<CR>", { desc = "Save file" })

-- Toggle between source and header files (requires clangd)
map("n", "<A-o>", "<cmd>ClangdSwitchSourceHeader<CR>", { desc = "Switch header/source" })

-- Navigate jump list with Alt+Left/Right
map("n", "<D-Left>", "<C-o>", { desc = "Jump backward" })
map("n", "<D-Right>", "<C-i>", { desc = "Jump forward" })

-- macOS clipboard shortcuts
map("v", "<D-c>", '"+y', { desc = "Copy selection" })
map("v", "<D-x>", '"+d', { desc = "Cut selection" })
map("n", "<D-v>", '"+p', { desc = "Paste" })
map("v", "<D-v>", '"+p', { desc = "Paste over selection" })
map("i", "<D-v>", "<C-r>+", { desc = "Paste" })
map("n", "<D-a>", "ggVG", { desc = "Select all" })

vim.keymap.del("n", "<S-h>")
vim.keymap.del("n", "<S-l>")

-- These are commented out for now as they are not working. Maybe kitty on Mac does not pick up the event?
-- Next buffer: Cmd+Shift+]
-- map("n", "<D-S-]>", ":bnext<CR>", { desc = "Next buffer" })
-- Previous buffer: Cmd+Shift+[
-- map("n", "<D-S-[>", ":bprevious<CR>", { desc = "Previous buffer" })

-- Move tab left/right
map("n", "<leader>bh", "<cmd>tabmove -1<CR>", { desc = "Move tab left" })
map("n", "<leader>bl", "<cmd>tabmove +1<CR>", { desc = "Move tab right" })
