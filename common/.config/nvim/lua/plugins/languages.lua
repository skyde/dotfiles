return {
  {
    -- rustaceanvim 9.x requires Neovim 0.12. Keep the newest release line
    -- compatible with the Neovim 0.11 used by this setup.
    "mrcjkb/rustaceanvim",
    version = "8.0.5",
    opts = function(_, opts)
      opts.dap = opts.dap or {}
      -- LazyVim's pinned Rust extra still computes Mason's removed v1 `opt`
      -- path while specs are loading. Resolve codelldb only when debugging
      -- starts, after Mason has had a chance to install it.
      opts.dap.adapter = function()
        local command = vim.fn.exepath("codelldb")
        if command == "" then
          return false
        end
        return {
          type = "server",
          host = "127.0.0.1",
          port = "${port}",
          executable = {
            command = command,
            args = { "--port", "${port}" },
          },
        }
      end
    end,
  },
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      local requested = {
        "bash-language-server",
        "buf",
        "docker-compose-language-service",
        "dockerfile-language-server",
        "debugpy",
        "json-lsp",
        "marksman",
        "neocmakelsp",
        "rust-analyzer",
        "shellcheck",
        "shfmt",
        "taplo",
        "vtsls",
        "yaml-language-server",
      }

      local unique = {}
      local seen = {}
      for _, tool in ipairs(vim.list_extend(opts.ensure_installed or {}, requested)) do
        if not seen[tool] then
          seen[tool] = true
          table.insert(unique, tool)
        end
      end
      opts.ensure_installed = unique
    end,
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
