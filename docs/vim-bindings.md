# VSVim Bindings Cheat Sheet

This guide lists all custom key mappings defined in [`dot_vsvimrc`](../dot_vsvimrc).
The `Space` key is the leader and `,` is the local leader.
Equivalent mappings are configured for the VSCodeVim extension via
[`dot_config/Code/User/settings.json`](../dot_config/Code/User/settings.json),
which is also symlinked for use by the Cursor editor.

## General
- `zl` – reload `.vsvimrc`.
- `<Esc>` – clear search highlights.
- Arrow keys act as `h`, `j`, `k`, `l`.
- `vig` – select entire buffer.
- `yig` – yank entire buffer.
- `<C-u>` – scroll up 16 lines.
- `<C-d>` – scroll down 16 lines.
- `<S-F4>` – scroll up 16 lines (macro).
- `<S-F6>` – scroll down 16 lines (macro).
- `<C-O>` / `<C-I>` – jump backward/forward through edits.
- `<C-h/j/k/l>` – move between windows.
- `<` / `>` in visual mode keep selection when indenting.
- `<leader><leader>` – ReSharper goto file.
- `<C-s>` – format document and save (works in all modes).
- `<leader>uh` – toggle Hard Mode.

## File Operations
- `<leader>fm` – open containing folder.
- `<leader>r` – open terminal window.
- `<leader>e` – show Solution Explorer.

## Navigation and Code
- `gd` – go to definition.
- `gp` – peek definition.
- `gi` – go to implementation.
- `gr` – find all references.
- `gk` / `gj` – previous/next method.
- `gu` – go to usage.
- `gc` – toggle comment.
- `gh` – toggle header/source file.
- `<leader>cr` – ReSharper rename symbol.
- `<leader>cR` – rename file.
- `<leader>ci` – show parameter info.

## Version Control
- `<leader>gd` – diff against depot.
- `<leader>go` – open in P4V.
- `<leader>gr` – revert if unchanged.
- `<leader>gR` – revert file.
- `<leader>ga` – mark for add.
- `<leader>gD` – mark for delete.
- `<leader>gh` – file history.
- `<leader>gt` – timelapse view.

## Merge Conflicts
- `Alt+K` – accept current change.
- `Shift+Alt+K` – accept all current changes.
- `Alt+J` – accept incoming change.
- `Shift+Alt+J` – accept all incoming changes.
- `Alt+H` – go to next unhandled conflict.
- `Shift+Alt+H` – go to next conflict region.
- `Alt+L` – go to previous unhandled conflict.
- `Shift+Alt+L` – go to previous conflict region.

## Refactoring and Errors
- `<leader>ce` – Resharper quick fix.
- `<leader>.` – quick actions for position.
- `<leader>ee` – show error list.
- `<leader>en` – next error.
- `<leader>ep` – previous error.

## Tabs and Windows
- `]b` / `[b` – next/previous tab.
- `<S-Left>` / `<S-Right>` – previous/next tab.
- `<leader>bd` – close current document.
- `<leader>bp` – pin tab.
- `<leader>bP` – close all but pinned.
- `<leader>bo` – close other tabs.
- `s` – Peasy Motion two‑char jump.
- `S` – Peasy Motion jump to tab.

## Unit Testing
- `<leader>tr` – run tests from context.
- `<leader>td` – debug tests from context.
- `<leader>ta` – run all tests in solution.
- `<leader>tl` – repeat last test run.
- `<leader>tt` – open unit test sessions.
- `<leader>e` – next error in solution.
- `<leader>E` – previous error in solution.

## Build and Search
- `<leader>mb` – build solution.
- `<leader>mc` – cancel build.
- `<leader>mr` – start debugging.
- `<leader>ms` – stop debugging.
- `<leader>sg` – open ReSharper Fast Find.

## Window Management
- `<leader>wf` – toggle fullscreen (via Minimal VS Plugin).
- `<leader>wp` – pin current window.
- `<leader>wP` – close all but pinned.

## Debugging
- `<leader>db` – toggle breakpoint.
- `<leader>dd` – disable all breakpoints.
- `<leader>de` – enable all breakpoints.
- `<leader>dr` – delete all breakpoints.
- `<leader>da` – list breakpoints.
- `<leader>dc` – continue debugging.
- `<leader>dw` – QuickWatch dialog.
- `<leader>dg` – run to cursor.
- `Alt+H` – step over.
- `Alt+L` – step into.
- `Alt+K` – step out.

## Hardware Macro Keys
These key combinations are implemented via keyboard macros rather than in `dot_vsvimrc`:

```
build and run   – Shift+F2
find class      – Shift+F3
scroll up       – Shift+F4
scroll down     – Shift+F6
stop build      – Shift+F7
goto definition – Shift+F8
toggle search   – Shift+F9
toggle eye      – Shift+F10
toggle comment  – Shift+F11
```
