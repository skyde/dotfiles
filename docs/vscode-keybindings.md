# VSCode Keybindings Cheat Sheet

This document lists all custom shortcuts defined in [`dot_config/Code/User/keybindings.json`](../dot_config/Code/User/keybindings.json). The same file is symlinked for the Cursor editor.

## Navigation
- `PageDown` – scroll one page down and move the cursor to the top of the viewport (matches Vim behavior).
- `PageUp` – scroll one page up and move the cursor to the bottom of the viewport (matches Vim behavior).
- `Shift+F4` – scroll up 16 lines.
- `Shift+F6` – scroll down 16 lines.

## Build and Search
- `Shift+F2` – run the build task.
- `Shift+F3` – quick open file or symbol.
- `Shift+F7` – stop build or debugging.
- `Shift+F8` – go to definition.
- `Shift+F11` – toggle comment for the current line.

## Terminal
- `Ctrl+/` – toggle the integrated terminal.

## Explorer
- `Escape` – toggle the sidebar when focus is in the explorer.
- `o` – create a new file.
- `c` – rename the selected file.
- `Shift+O` – create a new folder.
- `d` – delete the selected file.

## Vim Extension Mappings

The following shortcuts are configured through the VS Code Vim extension via [`settings.json`](../dot_config/Code/User/settings.json).

### Normal Mode
- `<leader> v` – <C-v>
- `<tab>` – editor.action.indentLines
- `<S-tab>` – editor.action.outdentLines
- `<C-u>` – 16k
- `<C-d>` – 16j
- `<D-Left>` – workbench.action.navigateBack
- `<D-Right>` – workbench.action.navigateForward
- `<C-o>` – workbench.action.navigateBack
- `<C-i>` – workbench.action.navigateForward
- `<C-h>` – workbench.action.focusLeftGroup
- `<C-j>` – workbench.action.focusBelowGroup
- `<C-k>` – workbench.action.focusAboveGroup
- `<Esc>` – <Esc>
- `u` – undo
- `<C-r>` – redo
- `<C-l>` – workbench.action.focusRightGroup
- `<leader> <leader>` – workbench.action.quickOpen
- `<leader> f m` – workbench.files.action.focusFilesExplorer
- `<leader> e` – workbench.view.explorer
- `] b` – workbench.action.nextEditor
- `[ b` – workbench.action.previousEditor
- `<leader> b d` – workbench.action.closeActiveEditor
- `<leader> b o` – workbench.action.closeOtherEditors
- `<leader> b b` – <C-6>
- `<leader> b u` – workbench.action.unpinEditor
- `<leader> b p` – workbench.action.pinEditor
- `<leader> b P` – workbench.action.closeOtherEditors
- `<S-h>` – :bprevious
- `<S-l>` – :bnext
- `<leader> w f` – workbench.action.toggleZenMode
- `<leader> w F` – workbench.action.toggleFullScreen
- `leader w v` – :vsplit
- `leader w s` – :split
- `leader w d` – workbench.action.closeActiveEditor
- `leader w h` – workbench.action.focusLeftGroup
- `leader w j` – workbench.action.focusBelowGroup
- `leader w k` – workbench.action.focusAboveGroup
- `leader w l` – workbench.action.focusRightGroup
- `<leader> s g` – find-it-faster.findWithinFiles
- `<leader> s f` – find-it-faster.findFiles
- `<leader> s t` – find-it-faster.findWithinFilesWithTypeFilter
- `<leader> s r` – find-it-faster.resumeSearch
- `s` – <leader> <leader> 2 s
- `S` – <leader> <leader> 2 S
- `g d` – editor.action.revealDefinition
- `g p` – editor.action.peekDefinition
- `g i` – editor.action.goToImplementation
- `g r` – editor.action.goToReferences
- `g h` – C_Cpp.SwitchHeaderSource
- `g u` – editor.action.referenceSearch.trigger
- `g n` – editor.action.showDefinitionPreviewHover
- `v i g` – g g V G
- `y i g` – g g V G y
- `d i g` – g g V G d
- `<leader> c r` – editor.action.rename
- `<leader> c i` – editor.action.triggerParameterHints
- `<leader> c e` – editor.action.quickFix
- `<leader> e e` – workbench.actions.view.problems
- `<leader> e n` – editor.action.marker.next
- `<leader> e p` – editor.action.marker.prev
- `<leader> d b` – editor.debug.action.toggleBreakpoint
- `<leader> d d` – workbench.debug.viewlet.action.disableAllBreakpoints
- `<leader> d e` – workbench.debug.viewlet.action.enableAllBreakpoints
- `<leader> d r` – workbench.debug.viewlet.action.removeAllBreakpoints
- `<leader> d a` – workbench.debug.viewlet.action.focusBreakpointsView
- `<leader> d c` – workbench.action.debug.continue
- `<leader> g d` – git.openChange
- `<leader> g s` – git.stage
- `<leader> g u` – git.unstage
- `<leader> g d` – git.openChange
- `<leader> g w` – git.openFile
- `<leader> g r` – git.revertSelectedRanges
- `<leader> g h` – gitlens.showQuickCommitFileDetails
- `<leader> g l` – files.openTimeline
- `<leader> g n` – renameFile
- `<leader> t r` – testing.runCurrentTest
- `<leader> t d` – testing.debugCurrentTest
- `<leader> t a` – testing.runAll
- `<leader> t R` – testing.reRunLastRun
- `<leader> t o` – testing.showMostRecentOutput
- `<leader> t f` – testing.runCurrentFile
- `<leader> t e` – testing.openTestView
- `<leader> m b` – workbench.action.tasks.build
- `<leader> m c` – workbench.action.tasks.terminate
- `<leader> m r` – workbench.action.debug.start
- `<leader> m s` – workbench.action.debug.stop
- `J` – debug.setNextStatement / merge-conflict.accept.incoming / cursorDown
- `H` – debug.stepOver / merge.goToNextUnhandledConflict / cursorLeft
- `L` – debug.stepInto / merge.goToPreviousUnhandledConflict / cursorRight
- `K` – debug.stepOut / merge-conflict.accept.current / cursorUp
### Insert Mode

- `<Esc>` – <Esc> <C-g>u

### Visual Mode
- `<tab>` – editor.action.indentLines
- `<S-tab>` – editor.action.outdentLines
- `<` – editor.action.outdentLines
- `>` – editor.action.indentLines
- `H` – editor.action.moveLinesDownAction
- `L` – editor.action.moveLinesUpAction
