return {
  {
    -- rustaceanvim 9.x requires Neovim 0.12. Keep the newest release line
    -- compatible with the Neovim 0.11 used by this setup.
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
        ["*"] = {
          keys = {
            { "gi", vim.lsp.buf.implementation, desc = "Goto Implementation", has = "implementation" },
            { "gu", vim.lsp.buf.references, desc = "Find Usages", has = "references" },
            { "gn", vim.lsp.buf.hover, desc = "Definition Preview", has = "hover" },
            {
              "<leader>ce",
              vim.lsp.buf.code_action,
              desc = "Code Action",
              mode = { "n", "x" },
              has = "codeAction",
            },
            { "<leader>cI", vim.lsp.buf.signature_help, desc = "Signature Help", has = "signatureHelp" },
          },
        },
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
