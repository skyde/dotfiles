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
-- root_dir pins every buffer inside a checkout to the src root. Without
-- that, clangd's stock root markers (.clang-format, .git, …) split the
-- checkout at every vendored subproject that carries one — v8, blink,
-- webrtc, skia — and each split spawns its own clangd instance with its
-- own background indexer: multiplied memory, a raced index, and
-- find-usages answers that depend on which instance answered. One
-- checkout, one clangd.
--
-- cmd is a function, not a static argv: vim.lsp.config holds one cmd for
-- every clangd client, and a static argv would leak one checkout's
-- --compile-commands-dir and bundled binary into other checkouts and
-- non-Chromium projects in the same session. Neovim resolves root_dir
-- before spawning and passes the config in, so each client computes the
-- argv its own root wants (see util.chromium.spawn_cmd).
return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      local chromium = require("util.chromium")
      opts.servers = opts.servers or {}
      -- LazyVim hands every server mason knows about to mason-lspconfig: it
      -- calls vim.lsp.config for the server but leaves vim.lsp.enable to
      -- mason, which only fires once the package is installed. For clangd
      -- that is backwards here. cmd below always chooses the binary itself —
      -- the checkout's bundled clangd, or PATH's — so mason's copy is
      -- downloaded and then never executed; and when mason cannot install it
      -- (offline, a proxy, a failed download) clangd is never enabled at
      -- all, leaving C++ with no language server while a perfectly good
      -- clangd sits on PATH. That is exactly the silent degradation this
      -- file exists to prevent, so mason is asked only when there is
      -- genuinely no clangd to use.
      local root = chromium.src_root(vim.api.nvim_buf_get_name(0))
      local have_clangd = chromium.clangd_path(root) ~= "clangd" or vim.fn.executable("clangd") == 1
      opts.servers.clangd = vim.tbl_deep_extend("force", opts.servers.clangd or {}, {
        mason = not have_clangd,
        cmd = function(dispatchers, config)
          return vim.lsp.rpc.start(chromium.spawn_cmd(config), dispatchers, {
            cwd = config and config.cmd_cwd or nil,
            env = config and config.cmd_env or nil,
            detached = config and config.detached or nil,
          })
        end,
        ---@param bufnr integer
        ---@param on_dir fun(root_dir?: string)
        root_dir = function(bufnr, on_dir)
          -- nil outside a checkout: vim.lsp.start then falls back to the
          -- config's stock root_markers, so non-Chromium C++ is untouched.
          on_dir(chromium.src_root(vim.api.nvim_buf_get_name(bufnr)))
        end,
      })
    end,
  },
}
