# C++ DAP Demo (Neovim + nvim-dap + overseer.nvim)

Simple project to validate VS Code-style launch/tasks with Neovim.

Key configs:
- .vscode/tasks.json: build and run tasks
- .vscode/launch.json: lldb configs (launch + attach)

Steps (we will run these using your Neovim config bindings):
1. Open this folder in Neovim.
2. Press <leader>mr to run default debug config (Launch demo) which triggers preLaunchTask build.
3. Try <leader>mR to pick "Attach to process (lldb)" and confirm a process picker appears.
