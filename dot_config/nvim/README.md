# My Neovim Setup

My personal Neovim configuration, built on top of [LazyVim](https://github.com/LazyVim/LazyVim). I've set it up for my C++ and Python projects.

## What's Inside?

*   **Full IDE Feel**: Comes with LSP, debugging, linting, and formatting ready to go.
*   **Super Fast**: Everything is lazy-loaded, so it starts up quick.
*   **Keyboard First**: Made for navigating with the keyboard, with `which-key` to help you find your way.
*   **My Tools**: I've added my favorite setups for C++ (`clangd`, `gtest`) and Python (`pyright`, `pytest`).

## How to Install

You'll need Neovim v0.9.0+ to run this.

1.  Clone this repo into your config folder.

    -   **macOS / Linux:**
        ```bash
        git clone <YOUR_REPO_URL> ~/.config/nvim
        ```
    -   **Windows (PowerShell):**
        ```powershell
        git clone <YOUR_REPO_URL> $env:LOCALAPPDATA\\nvim
        ```

2.  Open Neovim. It'll automatically install all the plugins the first time you run it.

### Automated Setup

Inside the `setup` folder you'll find helper scripts that can install the required
packages and copy this configuration in one go.

For macOS or Linux run:

```bash
./setup/install.sh
```

Windows users can run the PowerShell version from an elevated prompt:

```powershell
./setup/install.ps1
```

The Windows script installs **WezTerm** and launches it in the *MSYS2 UCRT64*
environment. On macOS and Linux the script uses **kitty** as the terminal.

If Git is not detected, the installer will use **winget** to install it before
copying the configuration files.

If your Linux distribution does not provide a `lazygit` package, the installer will download it from GitHub automatically.

## Dependencies

Some of the plugins in this configuration require external command-line tools to be installed on your system. Make sure you have the following available on both your macOS and Windows machines:

*   [**fd**](https://github.com/sharkdp/fd): A simple, fast and user-friendly alternative to `find`. Required by `venv-selector.nvim`.
*   [**lazygit**](https://github.com/jesseduffield/lazygit): A simple terminal UI for git commands.

## Plugins

Here are some of the key plugins that make this setup work:

*   [lazy.nvim](https://github.com/folke/lazy.nvim): The magic behind the plugin management.
*   [mason.nvim](https://github.com/williamboman/mason.nvim): For handling all the LSPs, debuggers, and linters.
*   [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim): For finding files, text, and pretty much anything else.
*   [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter): For smart, accurate syntax highlighting.
*   [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui): A nice UI for debugging.
*   [neotest](https://github.com/nvim-neotest/neotest): A great way to run tests.

## Debugging

Debug adapters for both **Python** and **C++** come preconfigured. `mason-nvim-dap`
will automatically install [debugpy](https://github.com/microsoft/debugpy) and
[codelldb](https://github.com/vadimcn/codelldb) so you can start using
`nvim-dap` right away.

### C++ Example

1. Build your program with `-g`.
2. Open the executable or source file in Neovim.
3. Start the debugger with `:DapContinue` (or `<leader>dL` using LazyVim defaults).
4. Toggle breakpoints with `:DapToggleBreakpoint` and watch the `nvim-dap-ui` panels for variables and stack information.

You can find the full list of plugins in the `lua/plugins/` folder.

## License

Feel free to use and share this under the [MIT License](LICENSE).
