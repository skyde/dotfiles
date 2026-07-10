return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        c = { "clang_format" },
        cmake = { "cmake_format" },
        cpp = { "clang_format" },
        cuda = { "clang_format" },
        objc = { "clang_format" },
        objcpp = { "clang_format" },
        proto = { "buf" },
        python = { "ruff_format", "black", stop_after_first = true },
      },
    },
  },
}
