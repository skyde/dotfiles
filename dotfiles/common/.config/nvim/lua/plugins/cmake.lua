return {
  {
    "Civitasv/cmake-tools.nvim",
    dependencies = { "nvim-lua/plenary.nvim", "mfussenegger/nvim-dap" },
    ft = { "c", "cpp", "objc", "objcpp", "cuda", "cmake" },
    opts = {},
    -- Note: We intentionally do not define <leader>m mappings here.
    -- Overseer owns the VS Code-style task keys.
  },
}
