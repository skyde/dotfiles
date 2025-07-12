return {
  "folke/persistence.nvim",
  event = "BufReadPre",
  opts = {
    -- always save sessions even when no buffers are open
    need = 0,
  },
  keys = {
    {
      "<leader>qs",
      function()
        require("persistence").load()
      end,
      desc = "Restore session",
    },
    {
      "<leader>ql",
      function()
        require("persistence").load({ last = true })
      end,
      desc = "Restore last session",
    },
    {
      "<leader>qd",
      function()
        require("persistence").stop()
      end,
      desc = "Don't save this session",
    },
  },
}
