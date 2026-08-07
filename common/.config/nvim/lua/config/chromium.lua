-- Chromium checkout automation: the autocmds and commands around
-- util.chromium, mirroring what the ChromiumIDE VS Code extension does for
-- clangd (see that module's header for the full story). Nothing here runs
-- outside a Chromium checkout.

local chromium = require("util.chromium")

vim.api.nvim_create_user_command("ChromiumCompdb", function()
  chromium.generate({ force = true })
end, { desc = "Regenerate compile_commands.json and restart clangd" })

vim.api.nvim_create_user_command("ChromiumOutDir", function()
  chromium.pick_out_dir()
end, { desc = "Pick the Chromium build dir xrefs are generated against" })

local group = vim.api.nvim_create_augroup("chromium_compdb", { clear = true })

-- Opening C++ inside a checkout: make sure clangd is the bundled one, and
-- regenerate the compdb when it is missing or predates the current
-- build.ninja — ChromiumIDE's "InitOnly" generation, plus its staleness
-- check. Checked once per root per session; :ChromiumCompdb forces.
local checked = {} ---@type table<string, true>
local CPP_FILETYPES = { "c", "cpp", "objc", "objcpp" }

local function check_buf(buf)
  local root = chromium.src_root(vim.api.nvim_buf_get_name(buf))
  if not root then
    return
  end
  chromium.ensure_clangd(root)
  if not checked[root] then
    checked[root] = true
    if chromium.stale(root) then
      chromium.generate({ root = root, force = true })
    end
  end
end

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = CPP_FILETYPES,
  callback = function(ev)
    check_buf(ev.buf)
  end,
})

-- This module is pulled in from config/keymaps.lua, which LazyVim loads on
-- VeryLazy — after startup, so the FileType event for any buffer named on
-- the command line (`nvim foo.cc`) has already fired and the autocmd above
-- missed it. Catch those buffers up now.
local cpp = {} ---@type table<string, true>
for _, ft in ipairs(CPP_FILETYPES) do
  cpp[ft] = true
end
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_loaded(buf) and cpp[vim.bo[buf].filetype] then
    check_buf(buf)
  end
end

-- Saving a GN file means build rules may have changed; regenerate once the
-- writes settle — ChromiumIDE's "Always" generation scope for GN.
vim.api.nvim_create_autocmd("BufWritePost", {
  group = group,
  pattern = { "*.gn", "*.gni" },
  callback = function(ev)
    local root = chromium.src_root(vim.api.nvim_buf_get_name(ev.buf))
    if root then
      chromium.gn_changed(root)
    end
  end,
})
