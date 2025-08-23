# VSVim Bindings Cheat Sheet

This guide lists my custom key mappings for the VSVim plugin in Visual Studio.
The `Space` key acts as the leader and `,` is the local leader.
Equivalent mappings can be configured for the VSCodeVim extension (and Cursor)
using that extension's settings.

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

## File Operations
- `<leader>fm` – open containing folder.
- `<leader>r` – open terminal window.
- `<leader>e` – show Solution Explorer.

## Tabs and Windows
- `]b` / `[b` – next/previous tab.
- `<S-Left>` / `<S-Right>` – previous/next tab.
- `<leader>bd` – close current document.
- `<leader>bp` – pin tab.
- `<leader>bP` – close all but pinned.
- `<leader>bo` – close other tabs.
- `s` – Peasy Motion two‑char jump.
- `S` – Peasy Motion jump to tab.

## Version Control
- `<leader>gd` – diff against depot.
- `<leader>go` – open in P4V.
- `<leader>gr` – revert if unchanged.
- `<leader>gR` – revert file.
- `<leader>ga` – mark for add.
- `<leader>gD` – mark for delete.
- `<leader>gh` – file history.
- `<leader>gt` – timelapse view.

## Refactoring and Errors
- `<leader>ce` – ReSharper quick fix.
- `<leader>.` – quick actions for position.
- `<leader>ee` – show error list.
- `<leader>en` – next error.
- `<leader>ep` – previous error.

## Build and Search
- `<leader>mb` – build solution.
- `<leader>mc` – cancel build.
- `<leader>mr` – start debugging.
- `<leader>ms` – stop debugging.
- `<leader>sg` – open ReSharper Fast Find.

## Unit Testing
- `<leader>tr` – run tests from context.
- `<leader>td` – debug tests from context.
- `<leader>ta` – run all tests in solution.
- `<leader>tl` – repeat last test run.
- `<leader>tt` – open unit test sessions.
- `<leader>e` – next error in solution.
- `<leader>E` – previous error in solution.

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

## Merge Conflicts
- `Alt+K` – accept current change (ours).
- `Shift+Alt+K` – accept all current changes (ours).
- `Alt+J` – accept incoming change (theirs).
- `Shift+Alt+J` – accept all incoming changes (theirs).
- `Alt+H` – go to next difference region.
- `Shift+Alt+H` – go to next difference region.
- `Alt+L` – go to previous difference region.
- `Shift+Alt+L` – go to previous difference region.

## Hardware Macro Keys
These key combinations are implemented via keyboard macros rather than the VSVim configuration:

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
