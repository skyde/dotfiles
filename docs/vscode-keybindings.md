# VSCode Keybindings Cheat Sheet

This document lists the custom shortcuts I use in VS Code. The same keybindings can also be used in the Cursor editor.

## Navigation
- `Ctrl+Tab` – switch to the next tab (Windows only).
- `Ctrl+Shift+Tab` – switch to the previous tab (Windows only).
- `PageDown` – scroll one page down and move the cursor to the top of the viewport (matches Vim behavior).
- `PageUp` – scroll one page up and move the cursor to the bottom of the viewport (matches Vim behavior).
- `Shift+F4` – scroll up 16 lines outside the integrated terminal.
- `Shift+F6` – scroll down 16 lines outside the integrated terminal.
- `Ctrl+O` / `Ctrl+I` – jump backward/forward through editor history outside the integrated terminal.

## Editing
- `Alt+Up` – disabled to prevent moving the current line.
- `Alt+Down` – disabled to prevent moving the current line.

## Terminal
- `Ctrl+/` – toggle the integrated terminal.
- `Ctrl+T` – toggle the terminal visibility and exit fullscreen if needed.
- `Cmd+S` – when a terminal is focused, send Shift+F5 to the terminal (mapped in Neovim to save the file).
- `Ctrl+O` / `Ctrl+I` – passed through to terminal apps such as tmux and Neovim.
- `Shift+F1` / `Shift+F12` – passed through to terminal apps when the terminal is focused.
- `Shift+F2` / `Shift+F3` / `Shift+F7` – passed through to terminal apps when the terminal is focused.
- `Shift+F4` / `Shift+F5` / `Shift+F6` – passed through to terminal apps when the terminal is focused.
- `Shift+F8` / `Shift+F11` – passed through to terminal apps when the terminal is focused.
- `Shift+F9` – passed through to terminal Neovim to toggle search highlighting.
- `Shift+F10` – passed through to tmux as the secondary prefix key.

## Build and Search
- `Shift+F2` – start debugging outside the integrated terminal.
- `Shift+F3` – quick open file or symbol outside the integrated terminal.
- `Shift+F8` – go to definition.
- `Shift+F11` – toggle comment for the current line.
- `Shift+F7` – stop build or debugging outside the integrated terminal.

## Debugging
- `Alt+Down` – step over.
- `Alt+Up` – step into.
- `Alt+H` – step out.

## Explorer
- `Escape` – focus the editor when the Explorer has focus.
- `o` – create a new file.
- `Shift+O` – create a new folder.
- `c` – rename the selected file.
- `d` – delete the selected file.

## Copilot Chat
- `Escape` – focus the editor when Copilot Chat is active.

## Merge Conflicts
- `Alt+Down` – go to next unhandled conflict.
- `Alt+Up` – go to previous unhandled conflict.


## Vim Extension Mappings

The following shortcuts are configured through the VS Code Vim extension's settings.
Space is mapped as `<leader>`.

### Normal Mode
- `<leader> v` – <C-v>
- `<tab>` – indent lines
- `<S-tab>` – outdent lines
- `<C-u>` – move up 16 lines (`16k`)
- `<C-d>` – move down 16 lines (`16j`)
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
- `<leader> f m` – toggle Yazi file manager
- `<leader> f n` – new file
- `<leader> e` – open explorer
- `] b` – next tab
- `[ b` – previous tab
- `<leader> b d` – close tab
- `<leader> b o` – close other tabs and pin current
- `<leader> b b` – <C-6>
- `<leader> b u` – unpin tab
- `<leader> b p` – pin tab
- `<leader> b P` – close other tabs
- `<leader> b h` – move tab left
- `<leader> b l` – move tab right
- `<S-h>` – :bprevious
- `<S-l>` – :bnext
- `<leader> w f` – toggle fullscreen
- `<leader> w F` – toggle Zen mode
- `<leader> w v` – :vsplit
- `<leader> w s` – :split
- `<leader> w d` – close tab
- `<leader> w h` – focus left pane
- `<leader> w j` – focus pane below
- `<leader> w k` – focus pane above
- `<leader> w l` – focus right pane
- `<leader> u w` – toggle word wrap
- `<leader> u z` – toggle Zen mode
- `<leader> u c` – toggle render whitespace
- `<leader> u i` – toggle inline parameter name hints
- `<leader> s g` – search within files
- `<leader> s f` – search files
- `<leader> s t` – search files by type
- `<leader> s r` – resume search
- `g d` – go to definition
- `g p` – peek definition
- `g i` – go to implementation
- `g r` – find references
- `g h` – switch header/source
- `g u` – find usages
- `g n` – show definition preview
- `v i g` – g g V G
- `y i g` – yank entire buffer
- `d i g` – g g V G d
- `<leader> c r` – rename symbol
- `<leader> c i` – show parameter hints
- `<leader> c e` – Quick Fix / Code Actions
- `<leader> c s` – switch diff side
- `<leader> c v` – revert selected ranges
- `<leader> <BS>` – show hover
- `<BS> <leader>` – show parameter hints
- `<BS> <BS>` – show hover
- `<leader> e e` – open problems view
- `<leader> e n` – next problem
- `<leader> e p` – previous problem
- `<leader> d b` – toggle breakpoint
- `<leader> d <BS>` – show debug hover
- `<leader> d d` – disable all breakpoints
- `<leader> d e` – enable all breakpoints
- `<leader> d r` – remove all breakpoints
- `<leader> d a` – focus breakpoints view
- `<leader> d c` – continue debugging
- `<leader> g g` – open LazyGit in an editor terminal
- `<leader> g G` – open Source Control (SCM) view
- `<leader> g d` – view file diff
- `<leader> g w` – open file in repo
- `<leader> g h` – show commit details
- `<leader> g l` – open git log for current file
- `<leader> T r` – run current test
- `<leader> T d` – debug current test
- `<leader> T a` – run all tests
- `<leader> T R` – rerun last tests
- `<leader> T o` – show test output
- `<leader> T f` – run tests in file
- `<leader> T e` – open test view
- `<leader> m b` – run build task
- `<leader> m c` – terminate task
- `<leader> m r` – start debugging
- `<leader> m s` – stop debugging
- `<leader> d g` – set next statement
### Insert Mode

- `<Esc>` – <Esc> <C-g>u

### Visual Mode
- `<tab>` – indent lines
- `<S-tab>` – outdent lines
- `<` – outdent lines
- `>` – indent lines
- `J` – move line down
- `K` – move line up
