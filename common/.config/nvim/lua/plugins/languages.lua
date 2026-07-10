return {
  {
    -- rustaceanvim 9.x requires Neovim 0.12. Keep the newest upstream line
    -- that explicitly supports the installed Neovim 0.11 release.
    "mrcjkb/rustaceanvim",
    version = "8.0.5",
  },
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = {
        "bash-language-server",
        "buf",
        "docker-compose-language-service",
        "dockerfile-language-server",
        "json-lsp",
        "marksman",
        "neocmakelsp",
        "rust-analyzer",
        "shellcheck",
        "shfmt",
        "taplo",
        "vtsls",
        "yaml-language-server",
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        bashls = {},
        buf_ls = {},
      },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = { "bash", "proto" },
    },
  },
}
