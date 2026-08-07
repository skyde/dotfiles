-- clangd, explicitly configured — previously nothing in this config set it
-- up, so C++ got whatever clangd happened to be on PATH with stock flags,
-- which inside a Chromium checkout degrades into "gd sometimes works".
--
-- Inside a Chromium checkout this uses the checkout's own bundled clangd
-- (version-matched to the clang that wrote the compile commands; add
-- `"checkout_clangd": True` to .gclient custom_vars to keep it synced) and
-- the flags //docs/clangd.md recommends. The compilation-database freshness
-- half of the story lives in util/chromium.lua + config/chromium.lua.
--
-- The cmd is computed from the cwd at startup; opening a Chromium buffer in
-- a session started elsewhere is caught by config/chromium.lua's FileType
-- autocmd, which reconfigures and restarts clangd.
return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      opts.servers.clangd = vim.tbl_deep_extend("keep", opts.servers.clangd or {}, {
        cmd = require("util.chromium").clangd_cmd(),
      })
    end,
  },
}
