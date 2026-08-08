-- Diagnostic underlines stay off.
--
-- `vim.diagnostic.config({ underline = false })` in config/options.lua does
-- not survive on its own. LazyVim carries a whole `vim.diagnostic.Opts` in
-- its nvim-lspconfig spec and applies it wholesale — `underline = true`
-- included — when that plugin loads, which is the first file opened. So the
-- option was on for every diagnostic anyone ever saw; only the seconds
-- before the first buffer had it off.
--
-- Set here, LazyVim merges it into the same table it later applies, and the
-- setting is the one that lands. Anything else meant to override
-- `opts.diagnostics` belongs here too, for the same reason.
return {
  {
    "neovim/nvim-lspconfig",
    opts = { diagnostics = { underline = false } },
  },
}
