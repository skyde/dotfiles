# Footpedal keys in Neovim

The footpedal turns the whole keyboard into a macro layer, and the Kinesis sends
those macros as `Shift+F1`..`Shift+F12` (see "Macro Bindings" in the README).
This is what each one does in Neovim, and why the mappings are spelled the way
they are.

## Keyboard macros

Sent by the Kinesis macro layer, one key per pedal-modified key.

| Key | Macro | VS Code | Neovim |
| --- | --- | --- | --- |
| `Shift+F2` | build and run | `workbench.action.debug.start` | `config.vscode_debug.start()` |
| `Shift+F3` | find class / file | `workbench.action.quickOpen` | `Snacks.picker.smart()` |
| `Shift+F4` | scroll up | 16 × `scrollLineUp` + `cursorUp` | `16k` |
| `Shift+F6` | scroll down | 16 × `scrollLineDown` + `cursorDown` | `16j` |
| `Shift+F7` | stop build | `workbench.action.debug.stop` | `config.vscode_debug.stop()` |
| `Shift+F8` | goto definition | `editor.action.revealDefinition` | `vim.lsp.buf.definition` |
| `Shift+F10` | tmux prefix | — | consumed by tmux, never reaches Neovim |
| `Shift+F11` | toggle comment | `editor.action.commentLine` | `gcc` / `gc` |

`Shift+F9` ("toggle search" in the older Visual Studio cheat sheet) is not bound
in either editor.

## Terminal-translated Cmd shortcuts

Not pedal keys. These are Cmd shortcuts the terminal rewrites into the same
`Shift+F` space, so that a Mac shortcut reaches Neovim, which cannot see `Cmd`.

| Pressed | Rewritten to | Neovim | Rewritten by |
| --- | --- | --- | --- |
| `Cmd+S` | `Shift+F5` | `:w` | kitty (`send_key`) and VS Code (`sendSequence`) |
| `Cmd+Shift+[` | `Shift+F1` | `:bprevious` | kitty only |
| `Cmd+Shift+]` | `Shift+F12` | `:bnext` | kitty only |

In the VS Code terminal `Cmd+Shift+[` / `Cmd+Shift+]` still switch VS Code
editors rather than Neovim buffers, which is usually what you want there.

Everything except the scroll keys is mapped in insert mode too, since with the
pedal held these get pressed mid-typing.

## Why every mapping is made twice

`map_shift_f` in `config/keymaps.lua` maps both `<S-Fn>` and `<F(n+12)>`. Both
are needed, because which one Neovim actually sees depends on what is between
the keyboard and Neovim:

| Stack | Bytes on the wire | Neovim reports |
| --- | --- | --- |
| kitty | terminfo `kf13`..`kf24` | `<F13>`..`<F24>` |
| VS Code integrated terminal | terminfo `kf13`..`kf24` | `<F13>`..`<F24>` |
| anything, inside tmux (`extended-keys on`) | re-encoded by tmux | `<S-F1>`..`<S-F12>` |
| Neovide and other GUIs | n/a | `<S-F1>`..`<S-F12>` |

Note that kitty and xterm disagree on one key: xterm's `kf15` (Shift+F3) is
`CSI 1;2R`, but kitty sends `CSI 13;2~` instead, because `CSI 1;2R` collides
with a cursor-position report. Both decode to `<F15>`, so the mapping does not
have to care.

## The VS Code side

VS Code owns the keyboard before the integrated terminal does, so any of these
bound to a VS Code command needs `!terminalFocus` in its `when` clause or
Neovim never sees the key. In `keybindings.json` that is handled either
explicitly (`shift+f2`, `shift+f3`, `shift+f4`, `shift+f6`, `shift+f7`) or by a
context that is already false in a terminal (`editorTextFocus`, for `shift+f8`
and `shift+f11`).

## Checking it

```bash
tests/check-footpedal-keys.py
```

Drives the real keys into a real Neovim through all three transports — a pty
with the VS Code terminal's escape sequences, tmux, and a real kitty window
driven over its remote-control socket — and asserts the actual effect (cursor
moved 16 lines, buffer switched, line commented, file saved, picker opened).

`tests/check-nvim-keymaps.sh` additionally invokes the callbacks directly, which
is faster but does not cover the transport.
