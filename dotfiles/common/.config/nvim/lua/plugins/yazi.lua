return {
  {
    "mikavilpas/yazi.nvim",
    -- Load lazily; the keymap in config/keymaps.lua calls :Yazi
    event = "VeryLazy",
    opts = {
      -- Keep defaults; this just registers the :Yazi command
    },
  },
}
