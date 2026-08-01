-- Load on the comment keys instead of VeryLazy: nothing here matters until you
-- actually comment something, and VeryLazy ran it in the batch right after the
-- UI appears. The list below is Comment.nvim's full default mapping set
-- (Comment/config.lua): toggler gcc/gbc, operators gc/gb, and the extras
-- gcO/gco/gcA. `gc` and `gb` need visual mode too, and normal mode for their
-- operator-pending form (`gc` + a motion) — lazy.nvim loads the plugin and
-- replays the key, so the operator still waits for its motion as normal.
return {
  "numToStr/Comment.nvim",
  keys = {
    { "gcc", mode = "n", desc = "Comment toggle line" },
    { "gbc", mode = "n", desc = "Comment toggle block" },
    { "gc", mode = { "n", "x" }, desc = "Comment toggle linewise" },
    { "gb", mode = { "n", "x" }, desc = "Comment toggle blockwise" },
    { "gcO", mode = "n", desc = "Comment insert above" },
    { "gco", mode = "n", desc = "Comment insert below" },
    { "gcA", mode = "n", desc = "Comment insert end of line" },
  },
  opts = {},
}
