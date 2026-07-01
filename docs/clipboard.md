# Clipboard across VS Code → SSH → tmux → nvim

The usual setup is the VS Code integrated terminal on macOS, SSH into a Linux
box, tmux on the remote, and nvim (sometimes launched by another program, such
as an AI coding tool) inside that. Every layer has to cooperate for copy and
paste to work, and this repo wires them up as follows.

## How copy works

- **nvim inside tmux over SSH** uses a `tmux` clipboard provider
  (`common/.config/nvim/lua/config/options.lua`). Yanks run
  `tmux load-buffer -w -`, which talks to tmux over its socket instead of
  writing escape sequences to stdout. This is what makes yanking work even
  when nvim runs inside another program's embedded terminal — escape
  sequences would be swallowed there, but the tmux socket is always
  reachable. The `-w` flag makes tmux forward the copy to the outer terminal
  via OSC 52.
- **tmux** has `set-clipboard on` plus
  `terminal-features ',xterm*:clipboard'` (`common/.tmux.conf`), so anything
  that lands in a tmux buffer (nvim yanks, copy-mode `y`, mouse selections)
  is forwarded to the local terminal as an OSC 52 sequence.
- **VS Code's terminal** applies OSC 52 copies to the macOS clipboard
  (supported and enabled by default in any recent VS Code). kitty is
  covered too via `clipboard_control write-clipboard` in
  `common/.config/kitty/kitty.conf`.
- **nvim over SSH without tmux** copies with nvim's built-in OSC 52
  provider, writing straight to the terminal.
- **Shell scripts** (`osc-copy`, used by lazygit and the tmux helpers)
  follow the same order: tmux buffer first, then local clipboard tools,
  then a raw OSC 52 write.

So: yank in nvim → tmux buffer → OSC 52 → VS Code → macOS clipboard, with no
step depending on who owns the tty.

## How paste works

- **Terminal paste (Cmd+V) always works** and is the way to paste text
  copied on the Mac (from a browser, another app, …). VS Code sends it as a
  bracketed paste, which tmux and nvim pass through correctly.
- **`p` / `"+p` in nvim** pastes the tmux buffer (`tmux save-buffer -`),
  i.e. whatever was last yanked in nvim or copied in tmux copy-mode —
  including in other panes and windows of the same server.
- **Why `p` can't see the macOS clipboard:** reading the local clipboard
  from the remote side needs an OSC 52 *paste query*, and VS Code's
  terminal (like most) refuses to answer those for security reasons. Over
  SSH without tmux, nvim's paste therefore falls back to the unnamed
  register instead of sending a query that would hang.

## Requirements

- tmux ≥ 3.2 (for `load-buffer -w`); `set-clipboard on` must not be
  overridden in `~/.tmux.conf.local`.
- VS Code new enough to support OSC 52 (anything from late 2022 on).

## Verifying the whole chain

Run `verify-clipboard <ssh-host>` **on the local machine** (it's stowed into
`~/.local/bin` by these dotfiles) while VS Code or kitty has a terminal
attached to the remote tmux session. It pushes a unique token through the
remote tmux buffer with OSC 52 forwarding and checks that the token arrives
in the local clipboard — a PASS means every hop from the remote tmux to the
OS clipboard works.

## Troubleshooting

- `:checkhealth clipboard` in nvim should report the `tmux` provider when
  inside tmux over SSH.
- `tmux show-buffer` on the remote shows what `p` will paste.
- If copies stop reaching the Mac, check that the outer terminal advertises
  clipboard support to tmux: `tmux display -p '#{client_termfeatures}'`
  should include `clipboard`.
- After editing configs, restart tmux fully (`tmux kill-server`) — some
  clipboard options only apply to new sessions.
