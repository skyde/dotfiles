# VSCode Keybindings Cheat Sheet

This document lists all custom shortcuts defined in [`dot_config/Code/User/keybindings.json`](../dot_config/Code/User/keybindings.json). The same file is symlinked for the Cursor editor.

## Navigation
- `PageDown` – scroll one page down and move the cursor to the top of the viewport (matches Vim behavior).
- `PageUp` – scroll one page up and move the cursor to the bottom of the viewport (matches Vim behavior).
- `Shift+F4` – scroll up 16 lines.
- `Shift+F6` – scroll down 16 lines.
- `Ctrl+Tab` – switch to the next tab (Windows only).
- `Ctrl+Shift+Tab` – switch to the previous tab (Windows only).

## Build and Search
- `Shift+F2` – run the build task.
- `Shift+F3` – quick open file or symbol.
- `Shift+F7` – stop build or debugging.
- `Shift+F8` – go to definition.
- `Shift+F11` – toggle comment for the current line.

## Terminal
- `Ctrl+/` – toggle the integrated terminal.
- `Ctrl+S` – send Ctrl+S to the integrated terminal when focused.
- `Cmd+T` – toggle the terminal visibility and exit fullscreen if needed.

## Explorer
- `Escape` – toggle the sidebar when focus is in the explorer.
- `o` – create a new file.
- `c` – rename the selected file.
- `Shift+O` – create a new folder.
- `d` – delete the selected file.

## Copilot Chat
- `Escape` – close Copilot Chat when focused.
- `Ctrl+N` – start a new conversation in Copilot Chat when the chat window is open.

## Merge Conflicts
- `Alt+K` – accept current change.
- `Shift+Alt+K` – accept all current changes.
- `Alt+J` – accept incoming change.
- `Shift+Alt+J` – accept all incoming changes.
- `Alt+H` – go to next unhandled conflict.
- `Shift+Alt+H` – go to next conflict.
- `Shift+Alt+L` – go to previous conflict.
- `Alt+L` – go to previous unhandled conflict.

`<leader> c o` – accept current change.
`<leader> c t` – accept incoming change.
`<leader> c b` – accept both changes.
 `<leader> c 0` – accept selection.
 `] x` – next conflict.
 `[ x` – previous conflict.
 `] c` – next change in diff.
 `[ c` – previous change in diff.


## Vim Extension Mappings

The following shortcuts are configured through the VS Code Vim extension via [`settings.json`](../dot_config/Code/User/settings.json).

### Normal Mode
- `<leader> v` – <C-v>
- `<tab>` – indent lines
- `<S-tab>` – outdent lines
- `<C-u>` – 16k
- `<C-d>` – 16j
- `<D-Left>` – go back
- `<D-Right>` – go forward
- `<C-o>` – go back
- `<C-i>` – go forward
- `<C-h>` – focus left pane
- `<C-j>` – focus pane below
- `<C-k>` – focus pane above
- `<Esc>` – <Esc>
- `u` – undo
- `<C-r>` – redo
- `<C-l>` – focus right pane
- `<leader> <leader>` – quick open
- `<leader> a` – open chat
- `<leader> f m` – focus file explorer
- `<leader> f n` – new file
- `<leader> e` – open explorer
- `] b` – next tab
- `[ b` – previous tab
- `<leader> b d` – close tab
- `<leader> b o` – close other tabs
- `<leader> b b` – <C-6>
- `<leader> b u` – unpin tab
- `<leader> b p` – pin tab
- `<leader> b P` – close other tabs
- `<leader> b h` – move tab left
- `<leader> b l` – move tab right
- `<S-h>` – :bprevious
- `<S-l>` – :bnext
- `<leader> w f` – toggle Zen mode
- `<leader> w F` – toggle fullscreen
- `leader w v` – :vsplit
- `leader w s` – :split
- `leader w d` – close tab
- `leader w h` – focus left pane
- `leader w j` – focus pane below
- `leader w k` – focus pane above
- `leader w l` – focus right pane
- `<leader> s g` – search within files
- `<leader> s f` – search files
- `<leader> s t` – search files by type
- `<leader> s r` – resume search
- `s` – <leader> <leader> 2 s
- `S` – <leader> <leader> 2 S
- `g d` – go to definition
- `g p` – peek definition
- `g i` – go to implementation
- `g r` – find references
- `g h` – switch header/source
- `g u` – find usages
- `g n` – show definition preview
- `v i g` – g g V G
- `y i g` – g g V G y
- `d i g` – g g V G d
- `<leader> c r` – rename symbol
- `<leader> c i` – show parameter hints
- `<leader> c e` – show completions
- `<leader> e e` – open problems view
- `<leader> e n` – next problem
- `<leader> e p` – previous problem
- `<leader> d b` – toggle breakpoint
- `<leader> d d` – disable all breakpoints
- `<leader> d e` – enable all breakpoints
- `<leader> d r` – remove all breakpoints
- `<leader> d a` – focus breakpoints view
- `<leader> d c` – continue debugging
- `<leader> g d` – view file diff
- `<leader> g s` – stage changes
- `<leader> g u` – unstage changes
- `<leader> g d` – view file diff
- `<leader> g w` – open file in repo
- `<leader> g r` – revert selected ranges
- `<leader> g h` – show commit details
- `<leader> g l` – open timeline
- `<leader> g n` – rename file
- `Alt+K` – accept current change during merge.
- `Shift+Alt+K` – accept all current changes.
- `Alt+J` – accept incoming change.
- `Shift+Alt+J` – accept all incoming changes.
- `Alt+H` – go to next unhandled conflict.
- `Shift+Alt+H` – go to next conflict region.
- `Alt+L` – go to previous unhandled conflict.
- `Shift+Alt+L` – go to previous conflict region.
- `<leader> c o` – accept current change.
- `<leader> c t` – accept incoming change.
- `<leader> c b` – accept both changes.
- `<leader> c 0` – accept selection.
- `] x` – next conflict.
- `[ x` – previous conflict.
- `<leader> t r` – run current test
- `<leader> t d` – debug current test
- `<leader> t a` – run all tests
- `<leader> t R` – rerun last tests
- `<leader> t o` – show test output
- `<leader> t f` – run tests in file
- `<leader> t e` – open test view
- `<leader> m b` – run build task
- `<leader> m c` – terminate task
- `<leader> m r` – start debugging
- `<leader> m s` – stop debugging
- `<leader> d g` – set next statement
- `Alt+H` – step over.
- `Alt+L` – step into.
- `Alt+K` – step out.
### Insert Mode

- `<Esc>` – <Esc> <C-g>u

### Visual Mode
- `<tab>` – indent lines
- `<S-tab>` – outdent lines
- `<` – outdent lines
- `>` – indent lines
- `H` – move line down
- `L` – move line up
