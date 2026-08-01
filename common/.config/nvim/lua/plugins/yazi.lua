return {
  {
    "mikavilpas/yazi.nvim",
    -- Load on the command itself, not VeryLazy. VeryLazy still ran the whole
    -- plugin during the batch right after the UI appears; `cmd` defers it to
    -- the first <leader>e. That keymap probes `exists(":Yazi")` before falling
    -- back to lf/mini.files, and lazy.nvim registers a stub user command for
    -- every `cmd` entry at startup, so the probe still answers yes and the
    -- fallback chain is unaffected.
    cmd = "Yazi",
    opts = {
      -- Keep defaults; this just registers the :Yazi command
    },
  },
}
