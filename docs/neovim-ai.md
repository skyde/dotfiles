# Neovim AI

Neovim uses [CodeCompanion](https://github.com/olimorris/codecompanion.nvim)
as its AI harness. Gemini is the default HTTP adapter for chat and inline
edits, and Gemini CLI is available as an optional ACP agent when its `gemini`
executable is installed. Chat and inline work use `gemini-3.1-pro-preview`;
command and background work use `gemini-3.6-flash`.

## API key

CodeCompanion reads `GEMINI_API_KEY` from Neovim's environment. Keep the value
in a password manager, OS keychain, or private shell configuration outside this
repository. Do not add it to these dotfiles.

For a single shell session:

```sh
read -rs GEMINI_API_KEY
export GEMINI_API_KEY
```

Start Neovim from that shell. Open any AI command once (for example,
`:CodeCompanionActions`) to lazy-load CodeCompanion, then run
`:checkhealth codecompanion` to verify its dependencies.

## Keymap

| Key | Action |
| --- | --- |
| `<leader>aa` | Open the AI action palette |
| `<leader>ac` | Toggle Gemini chat |
| `<leader>ai` | Start an inline Gemini edit |
| `<leader>aA` | Open the Gemini CLI agent (when installed) |
| `<leader>ae` | Explain the visual selection |
| `<leader>af` | Fix the visual selection |
| `<leader>at` | Generate tests for the visual selection |
| `<leader>aT` | Switch to the existing tmux AI window |

Inside a chat, `#` adds editor context, `/` exposes slash commands, and `@`
selects tools. Use `ga` in the chat buffer to change the adapter or model.
