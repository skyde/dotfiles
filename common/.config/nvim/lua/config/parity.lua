-- Keymaps that exist in the VS Code setup but have no LazyVim equivalent, or
-- whose LazyVim equivalent sits on a different key. Source-control and diff
-- keys live in config/vcs.lua; this file is everything else.
--
-- See docs/nvim-vscode-parity.md for the full table.

local map = vim.keymap.set

--------------------------------------------------------------------------
-- palette and panels
--------------------------------------------------------------------------

map("n", "<leader>p", function()
  Snacks.picker.commands()
end, { desc = "Command palette" })

--------------------------------------------------------------------------
-- goto (g)
--------------------------------------------------------------------------

-- LazyVim puts implementation on gI; the VS Code config uses gi, so support
-- both rather than moving anyone's fingers.
map("n", "gi", function()
  Snacks.picker.lsp_implementations()
end, { desc = "Goto Implementation" })
-- Peek: a picker with a preview pane is the closest thing to VS Code's peek
-- window, and unlike a float it is navigable.
map("n", "gp", function()
  Snacks.picker.lsp_definitions()
end, { desc = "Peek Definition" })
map("n", "gu", function()
  Snacks.picker.lsp_references()
end, { desc = "Find Usages" })
map("n", "gn", function()
  vim.lsp.buf.hover()
end, { desc = "Definition Preview (hover)" })
map("n", "gh", "<cmd>ClangdSwitchSourceHeader<cr>", { desc = "Switch Header/Source" })

-- Whole-buffer text object, so vig / yig / dig all work. The operator-pending
-- half has to go through :normal! rather than a motion, which is the standard
-- recipe for a text object that spans the file.
map("x", "ig", ":<C-u>normal! ggVG<cr>", { silent = true, desc = "Entire buffer" })
map("o", "ig", ":<C-u>normal! ggVG<cr>", { silent = true, desc = "Entire buffer" })

--------------------------------------------------------------------------
-- code (<leader>c)
--------------------------------------------------------------------------

-- Code actions are on LazyVim's default <leader>ca; the VS Code config now
-- uses the same key.
map("n", "<leader>cI", vim.lsp.buf.signature_help, { desc = "Signature Help" })

--------------------------------------------------------------------------
-- hover cluster: <BS> as a second leader, as in the VS Code config
--------------------------------------------------------------------------

map("n", "<BS><BS>", vim.lsp.buf.hover, { desc = "Hover" })
map("n", "<BS><leader>", vim.lsp.buf.signature_help, { desc = "Signature Help" })
map("n", "<BS>n", function()
  Snacks.terminal(nil, { cwd = LazyVim.root() })
end, { desc = "Terminal" })

--------------------------------------------------------------------------
-- files
--------------------------------------------------------------------------

map("n", "<leader>E", function()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    path = vim.fn.getcwd()
  end
  -- explorer.exe wants "/select,<path>" as a single argument; handed the flag
  -- and the path separately it ignores both and opens the default folder.
  local opener = vim.fn.has("mac") == 1 and { "open", "-R", path }
    or vim.fn.has("win32") == 1 and { "explorer", "/select," .. path }
    or { "xdg-open", vim.fn.fnamemodify(path, ":h") }
  vim.system(opener)
end, { desc = "Reveal in file manager" })

--------------------------------------------------------------------------
-- search
--------------------------------------------------------------------------

map("n", "<leader>sb", function()
  Snacks.picker.buffers()
end, { desc = "Search open buffers" })
map("n", "<leader>sr", function()
  Snacks.picker.resume()
end, { desc = "Resume last search" })

-- Zoekt, via the same `st` / `si` scripts the VS Code tasks called.
map("n", "<leader>sz", function()
  Snacks.terminal("st", { cwd = LazyVim.root(), win = { style = "terminal" } })
end, { desc = "Search (zoekt / ripgrep)" })
map("n", "<leader>si", function()
  Snacks.terminal("si", { cwd = LazyVim.root(), win = { style = "terminal" } })
end, { desc = "Index workspace (zoekt)" })

--------------------------------------------------------------------------
-- UI toggles
--------------------------------------------------------------------------

---Font size only has meaning where Neovim owns the rendering (Neovide) or
---where the terminal exposes remote control (kitty). Everywhere else say so
---once rather than failing silently.
---@param delta number|nil nil resets
local function zoom(delta)
  if vim.g.neovide then
    vim.g.neovide_scale_factor = delta and (vim.g.neovide_scale_factor or 1) + delta or 1
    return
  end
  if vim.env.KITTY_LISTEN_ON then
    local arg = delta and (delta > 0 and "+1" or "-1") or "0"
    vim.system({ "kitty", "@", "--to", vim.env.KITTY_LISTEN_ON, "set-font-size", arg })
    return
  end
  vim.notify("Font size is controlled by the terminal here", vim.log.levels.INFO)
end

map("n", "<leader>up", function()
  zoom(0.1)
end, { desc = "Zoom in" })
map("n", "<leader>um", function()
  zoom(-0.1)
end, { desc = "Zoom out" })
map("n", "<leader>ur", function()
  zoom(nil)
end, { desc = "Zoom reset" })

--------------------------------------------------------------------------
-- debug traversal (<leader>t), matching the VS Code layout where <leader>t is
-- stepping and <leader>T is the test runner
--------------------------------------------------------------------------

local function dap_do(fn)
  return function()
    local ok, dap = pcall(require, "dap")
    if ok then
      fn(dap)
    end
  end
end

local function dapui_view(name)
  return function()
    local ok, dapui = pcall(require, "dapui")
    if ok then
      dapui.float_element(name, { enter = true })
    end
  end
end

map(
  "n",
  "<leader>tn",
  dap_do(function(d)
    d.step_over()
  end),
  { desc = "Debug: Step Over" }
)
map(
  "n",
  "<leader>ti",
  dap_do(function(d)
    d.step_into()
  end),
  { desc = "Debug: Step Into" }
)
map(
  "n",
  "<leader>to",
  dap_do(function(d)
    d.step_out()
  end),
  { desc = "Debug: Step Out" }
)
map(
  "n",
  "<leader>tu",
  dap_do(function(d)
    d.up()
  end),
  { desc = "Debug: Up the call stack" }
)
map(
  "n",
  "<leader>td",
  dap_do(function(d)
    d.down()
  end),
  { desc = "Debug: Down the call stack" }
)
map("n", "<leader>tc", dapui_view("stacks"), { desc = "Debug: Call stack" })
map("n", "<leader>tl", dapui_view("scopes"), { desc = "Debug: Variables" })
map("n", "<leader>tw", dapui_view("watches"), { desc = "Debug: Watches" })
map("n", "<leader>tb", dapui_view("breakpoints"), { desc = "Debug: Breakpoints" })
map(
  "n",
  "<leader>th",
  dap_do(function(d)
    d.repl.toggle()
  end),
  { desc = "Debug: REPL" }
)

--------------------------------------------------------------------------
-- debug actions (<leader>d)
--------------------------------------------------------------------------

map(
  "n",
  "<leader>dp",
  dap_do(function(d)
    d.pause()
  end),
  { desc = "Debug: Pause" }
)
map(
  "n",
  "<leader>dS",
  dap_do(function(d)
    d.terminate()
  end),
  { desc = "Debug: Stop" }
)
map(
  "n",
  "<leader>dR",
  dap_do(function(d)
    d.restart()
  end),
  { desc = "Debug: Restart" }
)
map(
  "n",
  "<leader>dg",
  dap_do(function(d)
    d.goto_()
  end),
  { desc = "Debug: Set next statement" }
)
map(
  "n",
  "<leader>dL",
  dap_do(function(d)
    vim.ui.input({ prompt = "Log point message: " }, function(msg)
      if msg and msg ~= "" then
        d.set_breakpoint(nil, nil, msg)
      end
    end)
  end),
  { desc = "Debug: Log point" }
)
map({ "n", "x" }, "<leader>dw", function()
  local ok, widgets = pcall(require, "dap.ui.widgets")
  if ok then
    widgets.centered_float(widgets.expression)
  end
end, { desc = "Debug: Watch expression" })
map(
  { "n", "x" },
  "<leader>dx",
  dap_do(function(d)
    d.repl.toggle()
  end),
  { desc = "Debug: REPL / evaluate" }
)

--------------------------------------------------------------------------
-- which-key groups
--------------------------------------------------------------------------

local ok, wk = pcall(require, "which-key")
if ok then
  wk.add({
    { "<leader>t", group = "debug: step" },
    { "<leader>T", group = "test" },
    { "<leader>m", group = "make / tasks" },
    { "<leader>d", group = "debug" },
    { "<BS>", group = "hover" },
  })
end
