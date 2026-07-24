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
        function()
          if vim.fn.executable("gemini") ~= 1 then
            vim.notify("Gemini CLI is not installed; use <leader>ac for API-key chat", vim.log.levels.WARN)
            return
          end
          vim.cmd("CodeCompanionChat adapter=gemini_cli")
        end,
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
            local adapter = require("codecompanion.adapters").extend("gemini", {
              env = {
                api_key = "GEMINI_API_KEY",
              },
            })
            -- The pinned CodeCompanion release predates Gemini 3.6. Register
            -- its current model metadata so model selection and capabilities
            -- behave like the built-in Gemini entries.
            adapter.schema.model.choices["gemini-3.6-flash"] = {
              formatted_name = "Gemini 3.6 Flash",
              meta = { context_window = 1048576 },
              opts = { can_form_structured_outputs = true, can_reason = true, has_vision = true },
            }
            return adapter
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
            model = "gemini-3.1-pro-preview",
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
            model = "gemini-3.1-pro-preview",
          },
        },
        cmd = {
          adapter = {
            name = "gemini",
            model = "gemini-3.6-flash",
          },
        },
        background = {
          adapter = {
            name = "gemini",
            model = "gemini-3.6-flash",
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
