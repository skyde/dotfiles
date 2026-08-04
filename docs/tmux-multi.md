# tmux-multi — unified tmux across machines

`tmux-multi` makes several computers feel like one tmux. Every machine keeps
its own tmux server — sessions live where their processes run and survive
disconnects — but session management is unified: one picker lists every
session on every machine, Enter jumps to it wherever it lives, and new
sessions can be created on any machine from the same two keystrokes.

```text
        laptop (hub)                     desktop                devbox
┌───────────────────────────┐      ┌────────────────┐      ┌─────────────┐
│ local tmux                │      │ tmux server    │      │ tmux server │
│  ├─ window: notes         │ ssh  │  ├─ build      │      │  ├─ train   │
│  ├─ window: build@desktop ─────────▶ (attached)   │ ssh  │  └─ logs    │
│  └─ window: train@devbox ─────────────────────────────────▶ (attached) │
└───────────────────────────┘      └────────────────┘      └─────────────┘
```

Remote sessions open inside a local tmux window running
`ssh -t <host> tmux new-session -A`. The window is tagged, so picking the
same session again jumps to the existing window instead of opening a second
ssh. If the connection drops, the window offers to reconnect rather than
closing.

Because the hosts file lists *all* machines and each machine skips its own
name, the same dotfiles work everywhere — any machine can be the hub.

## Setup

1. **Key-based ssh** to each machine (background queries use `BatchMode`, so
   password prompts are treated as unreachable). Ideally give each machine a
   short alias in `~/.ssh/config`.

2. **List your machines** in `~/.config/tmux-multi/hosts`:

   ```sh
   mkdir -p ~/.config/tmux-multi
   cp ~/.config/tmux-multi/hosts.example ~/.config/tmux-multi/hosts
   $EDITOR ~/.config/tmux-multi/hosts
   ```

   One ssh destination per line; `#` comments allowed. List every machine —
   each one skips its own hostname. If an alias doesn't match that machine's
   `hostname -s`, export `TMUX_MULTI_SELF=<alias>` there so it knows itself.

3. **Enable ssh connection sharing** so the picker is instant instead of
   paying a full ssh handshake per host. In `~/.ssh/config`:

   ```ssh-config
   Host *
     ControlMaster auto
     ControlPath ~/.ssh/cm-%r@%h:%p
     ControlPersist 10m
   ```

4. **Check the wiring**:

   ```sh
   tmux-multi doctor
   ```

## Keys (inside tmux)

| Key | Action |
| --- | --- |
| `prefix s` | Fullscreen session picker across all machines: session name first, colourised columns, and a preview along the bottom showing a live capture of **every** window in the session (remote previews cached ~10s so hovering is instant). Vim-style: `j`/`k` move, `/` searches (`esc` back), `q` quits; `enter` open, `ctrl-n` new, `ctrl-x` kill, `ctrl-r` refresh. |
| `prefix S` | Same picker (alias). |
| `prefix N` | New session: pick the machine, then name the session (or pick an existing one). |
| `prefix M-s` | The native, local-only session tree that `prefix s` used to open. |
| `prefix prefix` | Send one prefix to the inner (remote) tmux — e.g. `M-a M-a c` makes a window on the remote machine. |
| `F12` | Hand **all** keys to the inner tmux (outer status dims and shows `NESTED`). `F12` again to take them back. |

A remote-session window technically holds a second tmux (the remote one),
but the view stays **flat**: while such a window is current, the local bar
hides itself, so the only status line on screen is the remote machine's —
green hostname, that machine's windows. Select a local window and the local
bar returns. At any moment exactly one bar describes the machine you are
looking at.

Keys follow the same rule: **window- and pane-level commands act on the
machine you are looking at**. In a remote window, `n`/`p`, the digits, `c`,
`x`, `z`, `w`, `,`, `[`, splits, `h`/`j`/`k`/`l`, `<`/`>` and `C` are
forwarded to the inner tmux, so the bar you see is the bar they drive; on a
local window they act locally as always. Session-level keys stay local
everywhere: `s`/`S`/`N` (picker), `d` (detach), `r` (reload), `M-s` — and
`]` pastes the local buffer into the remote pane, i.e. cross-machine paste.
Note the asymmetry: `n`/`p` can walk you *into* a remote window, but once
there they cycle that machine's windows — the picker (`prefix s`) is the way
back out. `F12` still hands over *every* key when you need something not in
the forwarded set.

`prefix s` deliberately *replaces* the native session tree: the key you already
reach for should show every machine's sessions, not just this one's. With no
hosts configured it lists local sessions only, so it degrades to the old
behaviour. The native tree is still on `prefix M-s`.

## Trying it without real machines

`tmux-multi-demo start` boots a sandbox: an `ssh` shim answers for two fake
hosts (devbox, buildbox — each a private tmux server on its own socket) plus
an always-unreachable `offline`, with a few seeded sessions. Attach with
`tmux-multi-demo attach` and use the normal keys; the status bar shows a red
DEMO. It is fully self-contained — own config, own sockets, nothing read from
`~/.tmux.conf` or `~/.ssh`, and the shim refuses unknown hosts. `stop` kills
the demo servers, `clean` also removes its directory (`~/.cache/tmux-multi-demo`).

## CLI

Everything also works outside tmux (e.g. straight from a terminal):

```sh
tmux-multi            # picker; attaches in this terminal
tmux-multi ls         # host<TAB>session<TAB>windows<TAB>attached
tmux-multi open desktop build
tmux-multi kill devbox train
tmux-multi doctor     # per-host connectivity / tmux report
```

New local sessions created through tmux-multi use `tmux-session`, so they get
the same default layout as ever; the same applies on remotes that have these
dotfiles (it falls back to plain `tmux new-session -A` otherwise).

## Troubleshooting

- **A host never shows sessions** — run `tmux-multi doctor`. Almost always
  ssh auth (BatchMode needs keys/agent) or tmux not installed there.
- **Picker is slow** — enable ControlMaster (above). Without it every refresh
  pays a full ssh handshake per host; unreachable hosts time out after 3 s.
- **After a reboot + tmux-resurrect restore** the remote windows re-run their
  ssh loop and reconnect; the remote sessions themselves were never gone.
- **Killed a remote session from its own machine?** The local window notices
  the ssh exit and closes (or offers reconnect if the link died instead).
- **Renamed a remote session?** The old local window still points at the old
  name; press Enter at its reconnect prompt to recreate/reattach, or just
  open it fresh from the picker.
