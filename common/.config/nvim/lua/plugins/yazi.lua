return {
  {
    "mikavilpas/yazi.nvim",
    -- Load on the command itself, not VeryLazy. VeryLazy still ran the whole
    -- plugin during the batch right after the UI appears; `cmd` defers it to
    -- the first <leader>e. That keymap checks for the yazi *binary* before
    -- reaching for this command, because lazy.nvim registers a stub for every
    -- `cmd` entry at startup — so `exists(":Yazi")` alone would answer yes
    -- everywhere and the mapping's mini.files fallback could never run.
    cmd = "Yazi",
    opts = {
      -- Keep defaults; this just registers the :Yazi command
    },
  },
}
