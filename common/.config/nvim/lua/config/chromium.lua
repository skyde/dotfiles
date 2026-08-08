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

vim.api.nvim_create_user_command("ChromiumClangd", function()
  chromium.install_bundled_clangd()
end, { desc = "Install the bundled clangd (checkout_clangd in .gclient + gclient sync)" })

vim.api.nvim_create_user_command("ChromiumHealth", function()
  vim.cmd("checkhealth chromium")
end, { desc = "Diagnose Chromium clangd: binary, compdb, index, client" })

local group = vim.api.nvim_create_augroup("chromium_compdb", { clear = true })

local CPP_FILETYPES = { "c", "cpp", "objc", "objcpp" }
local cpp = {} ---@type table<string, true>
for _, ft in ipairs(CPP_FILETYPES) do
  cpp[ft] = true
end

-- Every touch of a C++ buffer inside a checkout: make sure clangd is the
-- bundled one, re-check the database's freshness (throttled — builds and
-- gn runs happen outside the editor, and a session outlives one compdb),
-- and check once per file that the file is actually in the database.
-- Everything in here dedupes itself, so calling it often is cheap.
local function check_buf(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local root = chromium.src_root(name)
  if not root then
    return
  end
  chromium.ensure_clangd(root)
  chromium.offer_bundled_clangd(root)
  chromium.refresh(root)
  chromium.compdb_probe(root, name)
end

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = CPP_FILETYPES,
  callback = function(ev)
    check_buf(ev.buf)
  end,
})

-- Re-entering a buffer or refocusing the editor is when out-of-editor
-- changes (a build, a gn run, a git pull) become visible — re-check then,
-- not once per session.
vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained" }, {
  group = group,
  callback = function(ev)
    if cpp[vim.bo[ev.buf].filetype] then
      check_buf(ev.buf)
    end
  end,
})

-- This module is pulled in from config/keymaps.lua, which LazyVim loads on
-- VeryLazy — after startup, so the FileType event for any buffer named on
-- the command line (`nvim foo.cc`) has already fired and the autocmd above
-- missed it. Catch those buffers up now.
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
