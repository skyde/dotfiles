-- C/C++ LSP (goto definition, references, hover, rename, completion).
--
-- Configured here instead of via LazyVim's clangd extra so that a Chromium
-- checkout works on a fresh machine with no manual setup: the checkout's own
-- clangd and its out/ compilation database are discovered when the client
-- starts. See util.clangd for the discovery rules and docs/chromium-nvim-lsp.md
-- for the whole story.

local clangd = require("util.clangd")

-- Root resolved for the client that is about to start. vim.lsp.enable() calls
-- root_dir() and then spawns cmd() on the next tick, and cmd() is handed no
-- buffer, so stash the root here and prefer the current buffer's own root when
-- it has one.
local last_root = nil

-- Roots already warned about, so the notification fires once per session.
local warned = {}

local function warn_missing_db(root)
  if warned[root] then
    return
  end
  warned[root] = true
  local lines = {
    "clangd: no compile_commands.json under " .. root,
    "Run helpers/chrome/generate-compile-commands.sh (or",
    "`gn gen out/Default --export-compile-commands`) —",
    "goto-definition is guesswork until then.",
  }
  vim.notify(table.concat(lines, "\n"), vim.log.levels.WARN)
end

-- Defined here rather than in an `init` hook so that it cannot shadow one
-- LazyVim may add to the nvim-lspconfig spec later; lazy.nvim lets the last
-- spec win for plain function fields.
vim.api.nvim_create_user_command("ClangdStatus", function()
  vim.notify(clangd.describe(0), vim.log.levels.INFO)
end, { desc = "Show how clangd is configured for this buffer" })

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "c", "cpp" } },
  },

  -- A checkout-provided clangd is preferred, but keep one around for C/C++
  -- outside of a GN tree.
  {
    "mason-org/mason.nvim",
    optional = true,
    opts = { ensure_installed = { "clangd" } },
  },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        clangd = {
          -- Which binary to run is decided per root by util.clangd.binary, so
          -- don't let mason-lspconfig own the lifecycle.
          mason = false,
          cmd = function(dispatchers)
            local root = clangd.root_for(0) or last_root
            return vim.lsp.rpc.start(clangd.cmd(root), dispatchers)
          end,
          root_dir = function(bufnr, on_dir)
            local root = clangd.root_for(bufnr)
            last_root = root
            if root and not clangd.compile_commands_dir(root) then
              warn_missing_db(root)
            end
            -- nil lets Neovim fall back to clangd's usual root markers.
            on_dir(root)
          end,
          capabilities = {
            offsetEncoding = { "utf-16" },
          },
          -- stylua: ignore
          keys = {
            { "<leader>ch", function() clangd.switch_source_header() end, desc = "Switch Source/Header (C/C++)" },
          },
        },
      },
    },
  },
}
