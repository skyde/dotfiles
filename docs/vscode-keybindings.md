# VSCode Keybindings Cheat Sheet

This document lists the custom shortcuts I use in VS Code. The same keybindings can also be used in the Cursor editor.

## Navigation
- `Ctrl+Tab` – switch to the next tab (Windows only).
- `Ctrl+Shift+Tab` – switch to the previous tab (Windows only).
- `PageDown` – scroll one page down and move the cursor to the top of the viewport (matches Vim behavior).
- `PageUp` – scroll one page up and move the cursor to the bottom of the viewport (matches Vim behavior).
- `Shift+F4` – scroll up 16 lines.
- `Shift+F6` – scroll down 16 lines.

## Editing
- `Alt+Up` – disabled to prevent moving the current line.
- `Alt+Down` – disabled to prevent moving the current line.

## Terminal
- `Ctrl+/` – toggle the integrated terminal.
- `Ctrl+T` / `Cmd+T` – toggle the terminal visibility and exit fullscreen if needed.
- `Ctrl+Alt+B` / `Cmd+;` – toggle the secondary side bar.
- `Ctrl+S` / `Cmd+S` – when a terminal is focused, send Shift+F5 to the terminal (mapped in Neovim to save the file).

## Build and Search
- `Shift+F2` – start debugging.
- `Shift+F3` – quick open file or symbol.
- `Shift+F8` – go to definition.
- `Shift+F11` – toggle comment for the current line.
- `Shift+F7` – stop build or debugging.

## Debugging
- `Alt+Down` – step over.
- `Alt+Up` – step into.
- `Alt+H` – step out.

## Explorer
- `Escape` – focus the editor when the Explorer has focus.
- `o` – create a new file.
- `Shift+I` – create a new folder.
- `i` / `r` – rename the selected file.
- `d` – delete the selected file.
- `j` / `k` – move the Explorer cursor without changing multi-selection.
- `v` – toggle multi-selection for the focused item.
- `y` / `x` / `p` – copy, cut, and paste selected items.
- `l` / `Enter` – open files or toggle folders; `h` collapses folders.

## Copilot Chat
- `Escape` – focus the editor when Copilot Chat is active.

## Merge Conflicts
- `Alt+Down` – go to next unhandled conflict.
- `Alt+Up` – go to previous unhandled conflict.

## Vim Extension Mappings

The following shortcuts are generated from `common/.config/Code/User/settings.json`.
Space is mapped as `<leader>`.

### Normal Mode

- `<leader> v` - Vim <C-v>
- `<tab>` - indent lines
- `<S-tab>` - outdent lines
- `<D-Left>` - go back
- `<D-Right>` - go forward
- `<C-o>` - go back
- `<C-i>` - go forward
- `<C-h>` - focus left editor group
- `<C-l>` - focus right editor group
- `<C-j>` - focus editor group below
- `<C-k>` - focus editor group above
- `<Esc>` - Vim <Esc>; clear search highlight; close parameter hints
- `u` - undo
- `<C-r>` - redo
- `<S-u>` - redo
- `Y` - Vim y $
- `<leader> p` - show command palette
- `<leader> r` - toggle side bar
- `<backspace> n` - prepare terminal context; run task "StandardTerminal"; return to Vim Normal mode
- `<leader> f t` - prepare terminal context; run task "StandardTerminal"; return to Vim Normal mode
- `<leader> a` - prepare terminal context; run task "Tmux: Switch to AI"; run task "StandardTerminal"; return to Vim Normal mode
- `<leader> i` - prepare terminal context; run task "Tmux: Switch to Terminal"; run task "StandardTerminal"; return to Vim Normal mode
- `<leader> f T` - prepare terminal context; run task "Tmux: Kill Sessions"; return to Vim Normal mode
- `<leader> u w` - toggle word wrap
- `<leader> u z` - toggle Zen mode
- `<leader> u c` - toggle render whitespace
- `<leader> u p` - zoom in
- `<leader> u m` - zoom out
- `<leader> u r` - reset zoom
- `<leader> u h` - toggle clangd inlay hints
- `<leader> e` - prepare terminal context; toggle Yazi file manager
- `<leader> E` - reveal file in OS
- `<leader> f e` - focus Explorer; reveal active file in Explorer
- `<leader> f r` - open recent
- `<leader> f l` - copy active file path
- `<leader> f n` - new untitled file
- `<leader> f p` - open recent
- `<leader> b n` - new untitled file
- `] b` - next editor tab
- `[ b` - previous editor tab
- `<leader> b h` - move editor tab left
- `<leader> b l` - move editor tab right
- `<leader> b d` - unpin editor; close active editor
- `<leader> b D` - reopen closed editor
- `<leader> b o` - close all editor groups; reopen closed editor; pin editor
- `<leader> b b` - Vim <C-6>
- `<leader> b u` - unpin editor
- `<leader> b p` - pin editor
- `<leader> b P` - close other editors
- `<leader> w f` - toggle fullscreen
- `<leader> w v` - vertical split
- `<leader> w s` - horizontal split
- `<leader> w L` - move editor to right group
- `<leader> w H` - move editor to left group
- `<leader> w K` - move editor to above group
- `<leader> w J` - move editor to below group
- `<leader> w h` - focus left editor group
- `<leader> w j` - focus editor group below
- `<leader> w k` - focus editor group above
- `<leader> w l` - focus right editor group
- `<leader> w d` - close active editor
- `<leader> <leader>` - quick open
- `<leader> f f` - prepare terminal context; set context closePanelOnEnter=true; run task "FZF Files"; return to Vim Normal mode
- `<leader> s g` - prepare terminal context; set context closePanelOnEnter=true; run task "FZF Ripgrep"; return to Vim Normal mode
- `<leader> s T` - Vim y i w; prepare terminal context; set context closePanelOnEnter=true; run task "FZF Ripgrep (No Cache)"; run multi-command task.custom.delayedPaste
- `<leader> s t` - Vim y i w; prepare terminal context; set context closePanelOnEnter=true; run task "FZF Ripgrep"; run multi-command task.custom.delayedPaste
- `<leader> /` - Vim y i w; prepare terminal context; set context closePanelOnEnter=true; run task "FZF Ripgrep"; run multi-command task.custom.delayedPaste
- `<leader> s z` - prepare terminal context; set context closePanelOnEnter=true; run task "Zoekt Search"; return to Vim Normal mode
- `<leader> s i` - run task "Zoekt Index"
- `<leader> s b` - workbench.action.showAllEditorsByMostRecentlyUsed
- `<leader> s r` - rerun last task
- `<leader> 1` - open editor tab 1
- `<leader> 2` - open editor tab 2
- `<leader> 3` - open editor tab 3
- `<leader> 4` - open editor tab 4
- `<leader> 5` - open editor tab 5
- `<leader> 6` - open editor tab 6
- `<leader> 7` - open editor tab 7
- `<leader> 8` - open editor tab 8
- `<leader> 9` - open editor tab 9
- `<leader> 0` - open last editor tab
- `g d` - go to definition
- `g y` - go to type definition
- `g Y` - peek type definition
- `g p` - peek definition
- `g i` - go to implementation
- `g r` - find references
- `g h` - switch header/source
- `g u` - find usages
- `g n` - show definition preview
- `v i g` - Vim g g V G
- `y i g` - Vim : % y <CR>
- `d i g` - Vim g g V G d
- `<leader> c r` - rename symbol
- `<leader> c I` - show parameter hints
- `<leader> c e` - quick fix / code actions
- `<leader> c f` - save file; run task "Run Git CL Format"
- `<leader> x x` - prepare terminal context; set context closePanelOnEnter=true; show Problems view; toggle maximized panel
- `] d` - next problem
- `[ d` - previous problem
- `<leader> d b` - toggle breakpoint
- `<leader> d B d` - disable all breakpoints
- `<leader> d B e` - enable all breakpoints
- `<leader> d B r` - remove all breakpoints
- `<leader> d B c` - conditional breakpoint
- `<leader> d c` - continue debugging
- `<leader> d p` - pause debugging
- `<leader> d S` - stop debugging
- `<leader> d R` / `<leader> d r` - restart debugging
- `<leader> d g` - jump debugger to cursor
- `<leader> d L` - add logpoint
- `<leader> Backspace` - show hover; show debug hover
- `Backspace <leader>` - show parameter hints
- `Backspace Backspace` - show hover
- `<leader> d w` - add selection to watch
- `<leader> d x` - evaluate selection in debug REPL
- `<leader> t n` - debug step over
- `<leader> t i` - debug step into
- `<leader> t I` - debug step into target
- `<leader> t o` - debug step out
- `<leader> t l` - focus Variables view
- `<leader> t w` - focus Watch view
- `<leader> t h` - focus Debug Console
- `<leader> t b` - focus Breakpoints view
- `<leader> t c` - focus Call Stack view
- `<leader> t u` - move up call stack
- `<leader> t d` - move down call stack
- `<leader> t U` - move to top call stack frame
- `<leader> t D` - move to bottom call stack frame
- `<leader> g g` - prepare terminal context; run task "LazyGit"; return to Vim Normal mode
- `<leader> g l` - prepare terminal context; new terminal; send terminal sequence; move terminal to editor; toggle terminal panel; toggle terminal panel
- `<leader> g D` - open aggregate Git changes editor
- `<leader> g d` - open file diff
- `<leader> g C` - open aggregate Git changes editor
- `<leader> g a` - view Git changes
- `<leader> g c` - focus Source Control; focus list up; focus list down
- `<leader> g r` - focus SCM repositories
- `<leader> g R` - refresh SCM graph
- `<leader> g T` - set SCM graph tree mode
- `<leader> g p` - prepare terminal context; run `diff-branch`; move terminal to editor; toggle terminal panel
- `<leader> g A` - prepare terminal context; new terminal; send terminal sequence; move terminal to editor; toggle terminal panel; toggle terminal panel
- `<leader> g y` - run task "Copy Git Diff"
- `<leader> g w` - open worktree file
- `<leader> c a` - accept both merge sides
- `<leader> c m` - open merge editor
- `d o` - revert selected diff range
- `<leader> c o` - accept current/ours in an inline conflict; toggle ours in the merge editor
- `<leader> c O` - accept all current/ours conflicts; accept all ours in the merge editor
- `<leader> c t` - accept incoming/theirs in an inline conflict; toggle theirs in the merge editor
- `<leader> c T` - accept all incoming/theirs conflicts; accept all theirs in the merge editor
- `<leader> c b` - accept both merge sides
- `<leader> c c` - toggle merge editor side
- `<leader> c q` - accept merge
- `<leader> c n` - next diff change; next unhandled conflict
- `<leader> c p` - previous diff change; previous unhandled conflict
- `] x` - next unhandled conflict
- `[ x` - previous unhandled conflict
- `] c` - next diff change
- `[ c` - previous diff change
- `<leader> c d` - switch diff side
- `<leader> c i` - toggle side-by-side diff
- `<leader> c v` - revert selected diff range
- `<leader> c V` - revert selected Git ranges
- `<leader> T r` - run test at cursor
- `<leader> T d` - debug test at cursor
- `<leader> T a` - run all tests
- `<leader> T R` - rerun last tests
- `<leader> T o` - show latest test output
- `<leader> T f` - run tests in current file
- `<leader> T e` - focus Test Explorer
- `<leader> m T` - run task picker
- `<leader> m t` - rerun last task
- `<leader> m b` - run build task
- `<leader> m B` - configure default build task
- `<leader> m c` - terminate task
- `<leader> m r` - start debugging
- `<leader> m R` - select and start debugging
- `<leader> m s` - stop debugging
- `Z Z` - unpin editor; save file; close active editor
- `Z Q` - unpin editor; revert and close active editor

### Insert Mode

- `<Esc>` - Vim <Esc> <C-g>u

### Visual Mode

- `<Enter>` - Vim <Escape>
- `<tab>` - indent lines
- `<S-tab>` - outdent lines
- `<` - outdent lines
- `>` - indent lines
- `J` - editor.action.moveLinesDownAction
- `K` - editor.action.moveLinesUpAction
