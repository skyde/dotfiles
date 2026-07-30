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

`Shift+F9` is listed as "toggle search" in the older Visual Studio cheat sheet
but was bound in neither editor, so it now carries jump-forward — see below. If
the Kinesis layer is ever given a real "toggle search" macro again, that
collides.

## Terminal-translated Cmd shortcuts

Not pedal keys. These are Cmd shortcuts the terminal rewrites into the same
`Shift+F` space, so that a Mac shortcut reaches Neovim, which cannot see `Cmd`.

| Pressed | Rewritten to | Neovim | Rewritten by |
| --- | --- | --- | --- |
| `Cmd+S` | `Shift+F5` | `:w` | kitty (`send_key`) and VS Code (`sendSequence`) |
| `Cmd+Left` | `Ctrl+O` | previous location | kitty and VS Code |
| `Cmd+Right` | `Shift+F9` | next location | kitty and VS Code |
| `Cmd+Shift+[` | `Shift+F1` | `:bprevious` | kitty only |
| `Cmd+Shift+]` | `Shift+F12` | `:bnext` | kitty only |

In the VS Code terminal `Cmd+Shift+[` / `Cmd+Shift+]` still switch VS Code
editors rather than Neovim buffers, which is usually what you want there.

### Why jump-forward is not on Ctrl+I

`Ctrl+O` carries jump-backward fine — it is a plain control byte that every
terminal and tmux pass straight through. Its pair does not work that way:

- `Ctrl+I` and `Tab` are the same byte, `0x09`.
- Neovim collapses them into one key. `vim.keycode("<C-i>") == vim.keycode("<Tab>")`,
  and this holds **even when the terminal disambiguates them** — sending kitty's
  `CSI 105;5u` form still arrives as `<Tab>`.
- `config/keymaps.lua` maps normal-mode `<Tab>` to `>>`, so `Ctrl+I` indents the
  line instead of jumping.

So there is no terminal-side encoding that fixes it, and the key has to be
something other than Tab. `Shift+F9` was the one unused slot in the Shift+F
space this repo already uses for exactly this purpose, and it survives kitty,
tmux and the VS Code terminal alike. Neovim maps it with `noremap` to `<C-i>`,
so the right-hand side reaches the builtin rather than the indent mapping.

Two things worth knowing about the `ctrl+o` / `ctrl+i` keys themselves: in VS
Code they are bound to `navigateBack`/`navigateForward` with `!terminalFocus`,
so pressing them in the integrated terminal reaches Neovim instead of moving
VS Code's editor history. And in kitty these were previously written as
`map cmd+left ctrl-o`, which looks plausible but is not a kitty action — kitty
drops unknown actions silently, so `Cmd+Left` did nothing at all until it was
changed to `send_key`.

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

Drives the real keys into a real Neovim through four transports — a pty with the
VS Code terminal's escape sequences, tmux, a real kitty window driven over its
remote-control socket, and kitty with tmux inside it — and asserts the actual
effect (cursor moved 16 lines, buffer switched, line commented, file saved,
picker opened, jumplist moved).

The four are genuinely different, which is the reason for testing all of them:
tmux delivers a different key spelling than bare kitty, and tmux picks its
`default-terminal` from the host terminal, so `kitty+tmux` and
`vscode-terminal+tmux` are not the same path either. Pass a name to run just
one: `kitty`, `kitty+tmux`, `tmux`, `vscode`.

`tests/check-nvim-keymaps.sh` additionally invokes the callbacks directly, which
is faster but does not cover the transport.
