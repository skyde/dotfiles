return {
  {
    "olimorris/codecompanion.nvim",
    version = "^19.0.0",
    cmd = {
      "CodeCompanion",
      "CodeCompanionActions",
      "CodeCompanionChat",
      "CodeCompanionCLI",
      "CodeCompanionCmd",
    },
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    keys = {
      { "<leader>a", "", desc = "+ai", mode = { "n", "x" } },
      {
        "<leader>aa",
        "<cmd>CodeCompanionActions<cr>",
        desc = "AI actions",
        mode = { "n", "x" },
      },
      {
        "<leader>ac",
        "<cmd>CodeCompanionChat Toggle<cr>",
        desc = "Gemini chat",
        mode = { "n", "x" },
      },
      {
        "<leader>ai",
        "<cmd>CodeCompanion<cr>",
        desc = "Gemini inline prompt",
        mode = { "n", "x" },
      },
      {
        "<leader>aA",
        "<cmd>CodeCompanionChat adapter=gemini_cli<cr>",
        desc = "Gemini agent (CLI)",
      },
      {
        "<leader>ae",
        ":CodeCompanion /explain<cr>",
        desc = "AI explain selection",
        mode = "x",
      },
      {
        "<leader>af",
        ":CodeCompanion /fix<cr>",
        desc = "AI fix selection",
        mode = "x",
      },
      {
        "<leader>at",
        ":CodeCompanion /tests<cr>",
        desc = "AI generate tests",
        mode = "x",
      },
    },
    opts = {
      adapters = {
        http = {
          gemini = function()
            return require("codecompanion.adapters").extend("gemini", {
              env = {
                api_key = "GEMINI_API_KEY",
              },
            })
          end,
        },
        acp = {
          gemini_cli = function()
            return require("codecompanion.adapters").extend("gemini_cli", {
              commands = {
                default = { "gemini", "--acp" },
                yolo = { "gemini", "--yolo", "--acp" },
              },
              defaults = {
                auth_method = "gemini-api-key",
              },
              env = {
                GEMINI_API_KEY = "GEMINI_API_KEY",
              },
            })
          end,
        },
      },
      interactions = {
        chat = {
          adapter = {
            name = "gemini",
            model = "gemini-2.5-pro",
          },
          opts = {
            completion_provider = "blink",
            context_management = {
              enabled = true,
            },
          },
        },
        inline = {
          adapter = {
            name = "gemini",
            model = "gemini-2.5-pro",
          },
        },
        cmd = {
          adapter = {
            name = "gemini",
            model = "gemini-2.5-flash",
          },
        },
        background = {
          adapter = {
            name = "gemini",
            model = "gemini-2.5-flash",
          },
        },
      },
      display = {
        action_palette = {
          provider = "snacks",
        },
        chat = {
          window = {
            layout = "vertical",
            position = "right",
            width = 0.42,
          },
        },
      },
    },
  },
}
