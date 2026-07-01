# tmux session picker with AI agent status

The fuzzy session picker (`prefix + S`, script:
`common/.local/bin/tmux-fzf-switch-session`) lists every tmux session and,
for each one, the AI coding agents running inside it plus a busy/idle guess:

```
work|4 windows|attached|claude[busy] codex[idle]
notes|1 windows|detached|-
```

The preview pane shows the session's windows and one line per agent
instance (agent, status, window and pane it lives in). `ctrl-r` refreshes
the list, `enter` switches to the session.

All detection is done by `common/.local/bin/tmux-agent-status`, which can
also be used standalone.

## `tmux-agent-status` CLI

```sh
tmux-agent-status [list]                    # TSV: session window pane_id agent status
tmux-agent-status summary [--color]         # TSV: session "agent[status] ..."
tmux-agent-status session <name> [--color]  # readable lines for one session
```

## How agents are detected

A pane counts as running an agent when the pane's process or any of its
descendants has a process name that exactly matches one of the configured
agent names (case-insensitive). The built-in names are:

`claude`, `opencode`, `codex`, `aider`, `gemini`, `goose`, `amp`, `crush`,
`droid`, `cursor-agent`, `copilot`

An agent is reported as **busy** when the last visible lines of its pane
match its busy-regex — by default a pattern covering the common
"esc to interrupt" style hints these tools print while working.

## Extending the agent list

No script edits needed; add names externally in either of two ways:

1. **Config file** `~/.config/tmux-agents.conf` (path override:
   `$TMUX_AGENTS_CONF`). One agent per line, either just a process name or
   `name|busy-regex` to also customize busy detection for that agent.
   `#` comments and blank lines are ignored. An entry with the same name as
   a built-in overrides it.

   ```
   # ~/.config/tmux-agents.conf
   my-agent
   friday|Press Ctrl-C to stop
   ```

2. **Environment variable** `TMUX_AGENTS`: extra names, separated by
   commas, spaces, or colons, e.g. `TMUX_AGENTS="goose,my-agent"`.

## Tuning busy detection

- `TMUX_AGENTS_BUSY_REGEX`: replace the default busy-regex (case-insensitive
  ERE) used for agents without a per-agent regex.
- `TMUX_AGENTS_SCAN_LINES`: how many of the pane's last visible lines to
  scan (default 40).
