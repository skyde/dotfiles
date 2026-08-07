# Tokyo Night theme

Every terminal-side tool in this repo is themed with **Tokyo Night — `night`**
variant (the darkest of the three, background `#1a1b26`). This file is the
source of truth: when you touch a colour in any config below, take the hex from
this table rather than eyeballing a new one.

Note that *syntax highlighting* is deliberately **not** Tokyo Night — `bat`,
`delta`, VS Code and yazi's preview pane all use `Visual Studio Dark+`. Tokyo
Night is the UI chrome (backgrounds, borders, status bars, selections); Dark+ is
the code itself.

`BAT_THEME` in `~/.zshenv` is the single source of truth for that syntax theme.
It is read directly by `bat`, and indirectly by `delta` (which uses bat's theme
set) and by yazi (see below). Change it there and all three follow.

## Palette

Taken from [`folke/tokyonight.nvim`](https://github.com/folke/tokyonight.nvim)
`extras/`, `night` style.

### Backgrounds and surfaces

| Name             | Hex       | Used for                                  |
| ---------------- | --------- | ----------------------------------------- |
| `bg`             | `#1a1b26` | default background                        |
| `bg_dark`        | `#16161e` | status lines, sidebars, floats, popups    |
| `black`          | `#15161e` | ANSI 0 background-ish, tab bar background  |
| `bg_highlight`   | `#292e42` | inactive borders, boxes, subtle fills     |
| `bg_visual`      | `#283457` | visual selection                          |
| `selection`      | `#2e3c64` | terminal selection background             |
| `fg_gutter`      | `#3b4261` | gutter, inactive separators               |
| `blue7`          | `#394b70` | dim accents                               |

### Foregrounds

| Name         | Hex       | Used for                             |
| ------------ | --------- | ------------------------------------ |
| `fg`         | `#c0caf5` | default foreground                   |
| `fg_dark`    | `#a9b1d6` | secondary text, ANSI 7               |
| `dark5`      | `#737aa2` | tertiary text                        |
| `comment`    | `#565f89` | comments, muted status text          |
| `dark3`      | `#545c7e` | inactive tabs, line numbers          |
| `terminal_black` | `#414868` | ANSI 8 (upstream value — see note) |

> **Note on ANSI 8.** kitty and wezterm here use `#85899c` instead of the
> upstream `#414868`. That is deliberate: `#414868` is close to unreadable for
> "bright black" text that CLI tools use for de-emphasised output. Keep the two
> terminals in sync.

### Accents

| Name       | Hex       | ANSI  | Used for                                   |
| ---------- | --------- | ----- | ------------------------------------------ |
| `red`      | `#f7768e` | 1     | deletions, errors                          |
| `green`    | `#9ece6a` | 2     | additions, success                         |
| `yellow`   | `#e0af68` | 3     | warnings, modified                         |
| `blue`     | `#7aa2f7` | 4     | primary accent, active borders, headers    |
| `magenta`  | `#bb9af7` | 5     | branches, keywords                         |
| `cyan`     | `#7dcfff` | 6     | links, info                                |
| `orange`   | `#ff9e64` | 16    | session name, numbers, prompts             |
| `red1`     | `#db4b4b` | 17    | hard errors, whitespace errors             |
| `teal`     | `#1abc9c` | —     | untracked / new                            |
| `purple`   | `#9d7cd8` | —     | secondary magenta                          |
| `green1`   | `#73daca` | —     | URLs                                       |
| `blue0`    | `#3d59a1` | —     | search background                          |
| `blue5`    | `#89ddff` | —     | punctuation, bright cyan accents           |

Bright ANSI variants (9–15) are the accents lightened:
`#ff899d` `#9fe044` `#faba4a` `#8db0ff` `#c7a9ff` `#a4daff` `#c0caf5`.

### Git colours

| Name      | Hex       |
| --------- | --------- |
| `add`     | `#449dab` |
| `change`  | `#6183bb` |
| `delete`  | `#914c54` |

### Gotcha: lazygit ignores unknown keys too

Same failure as yazi's below, without yazi's probe: lazygit accepts any key it
does not recognise and does nothing with it, and there is no debug output that
names the offender. Keys move between releases (0.64 renamed `git.pagers` to
`git.diffRenderers`), so a config that worked last year can be half-inert now,
looking exactly like one that works. `./tests/check-lazygit-config.sh` is the
substitute for a probe: it validates the file against the schema published for
the installed lazygit version. Details in [`lazygit.md`](lazygit.md).

### Gotcha: lazygit reads `COLORTERM`, not terminfo

tmux advertising `RGB` in `terminal-overrides` is not enough for it. Measured
in tmux without `COLORTERM` set, lazygit paints its entire UI out of the
256-colour cube — `#9ece6a` arrives as colour 149 — and every hex in
`common/.config/lazygit/config.yml` is an approximation. `.tmux.conf` therefore
sets `COLORTERM=truecolor` for every pane, since a pane otherwise only inherits
it if the client that started the tmux server happened to export it.

### Gotcha: yazi ignores unknown keys

Yazi validates colour *values* but silently ignores unknown section and key
names, so "it loaded without an error" does not mean a key is doing anything.
To check a key is really wired up, break its colour on purpose and confirm yazi
reports `invalid color`:

```bash
YAZI_CONFIG_HOME=/tmp/probe yazi --debug 2>&1 | grep "invalid color"
```

Silence there means the key name is wrong. The same trick enumerates the real
schema. For `[filetype]` rules, `is` accepts exactly `none`, `hidden`, `link`,
`orphan`, `dummy`, `block`, `char`, `fifo`, `sock`, `exec`, `sticky` — there is
no `dir`; directories are matched with the name glob `*/`.

### Why yazi previews through bat, not `syntect_theme`

Yazi has a `mgr.syntect_theme` setting, but it wants a path to a `.tmTheme`
file, and `Visual Studio Dark+` only exists compiled inside bat — there is no
such file on disk to point at. Vendoring one would also mean yazi's preview
drifts from bat the next time `BAT_THEME` changes.

So `plugins/bat-preview.yazi` shells out to `bat` instead. The preview then
inherits both things that are already maintained elsewhere:

- **`BAT_THEME`**, so yazi, bat, delta and VS Code agree on what code looks
  like, from one setting.
- **The custom syntaxes in `~/.config/bat/syntaxes`** (C#, C++, JSON, TOML,
  YAML), compiled into bat's cache. Yazi's built-in previewer carries its own
  syntax set and has no idea those exist.

The plugin forces `COLORTERM=truecolor` on the bat subprocess. Without it bat
silently downgrades to the 256-colour cube — the preview still looks
*plausible*, just not the same colours as VS Code.

If bat is missing the plugin falls back to uncoloured plain text rather than
erroring.

The same `BAT_THEME` highlighting is applied to the Ctrl-R history picker, via
`fzf_history_highlight` in `common/.config/shell/theme.sh`. Two constraints
there are load-bearing: bat must run with `--wrap=never` (a wrapped long
command would reach fzf as several separate, unrunnable candidates), and fzf
must get `--ansi` explicitly (that is what makes it hand back the plain command
instead of one full of escape sequences).

### Why matches are inverted, not just recoloured

`hl`/`hl+` are `#e0af68`/`#faba4a` with `bold:reverse`, so what you typed shows
up as a solid yellow block. This is not a style preference, it is the only thing
that survives the picker above: fzf replaces just the *foreground* of the
matched characters, and in the history list those characters are already
syntax-coloured by bat, so the old `hl:#7aa2f7` was a blue fg dropped into a
line that was already blue, grey and cyan. Inverting fg and bg gives a match
that reads the same whatever the syntax theme did underneath, and the two
different yellows keep the contrast even on the current line, which sits on
`bg+` (`#283457`) instead of the terminal background.

### Scrolling the yazi preview

`skip` counts **screen rows**, not source lines, because bat does the wrapping.
That is what lets J/K scroll a file that is only a handful of lines long but
wraps into a tall block — counting source lines would let one very long line
swallow the pane with nothing left to scroll. Note `job.skip` exists only on
the peek job; in `seek` the live offset is `cx.active.preview.skip`, and
reading the wrong one throws silently, which looks exactly like J/K doing
nothing.

### Gotcha: delta feature sections

Delta's colours must sit in the plain `[delta]` section, **not** in a named
`[delta "..."]` feature. As of delta 0.18, `commit-style`, `file-style` and
every `*-decoration-style` key is read only from the plain section; setting them
in a feature is silently ignored, which leaves diff headers un-themed while the
diff body looks correct.

It is worse than that, though: on delta 0.18 a feature section in git config is
not applied **at all** — not via `DELTA_FEATURES`, and not via `--features`
either (verified with a probe feature whose format change never rendered). The
working escape hatch for an occasional toggle is a `git -c delta.<option>=<value>`
alias: git exports `-c` settings to its pager through `GIT_CONFIG_PARAMETERS`,
and delta reads that like any other git config. That is how the `sbs`
side-by-side alias in `common/.config/git/config` works.

### Local deviation: the cursor

The cursor is **`#ff5000`** (a hot orange) everywhere — kitty, wezterm, Neovim,
and the fzf pointer. It is not part of Tokyo Night; it is a deliberate personal
accent chosen to be instantly findable against the blue-violet palette. Keep it.

## Where the theme lives

| Tool     | File                                                 |
| -------- | ---------------------------------------------------- |
| kitty    | `common/.config/kitty/themes/tokyonight_night.conf`   |
| wezterm  | `common/.config/wezterm/wezterm.lua`                  |
| tmux     | `common/.tmux.conf` (the `# Theme` section)           |
| Neovim   | `common/.config/nvim/lua/plugins/tokyonight.lua`      |
| lazygit  | `common/.config/lazygit/config.yml` (`gui.theme`)     |
| delta    | `common/.config/git/config` (`[delta]`)               |
| starship | `common/.config/starship.toml` (`[palettes.tokyonight]`) |
| fzf      | `common/.config/shell/theme.sh`                       |
| yazi     | `common/.config/yazi/theme.toml`, `plugins/bat-preview.yazi/` |
| lf       | `common/.config/lf/colors`                            |
| btop     | `common/.config/btop/themes/tokyo-night.theme`        |
