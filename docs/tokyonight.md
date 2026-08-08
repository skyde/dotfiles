# Tokyo Night theme

Every terminal-side tool in this repo is themed with **Tokyo Night — `night`**
variant (the darkest of the three, background `#1a1b26`). This file is the
source of truth: when you touch a colour in any config below, take the hex from
this table rather than eyeballing a new one.

Note that *syntax highlighting* is deliberately **not** Tokyo Night — `bat`,
`delta`, VS Code and yazi's preview pane all use `Visual Studio Dark+`. Tokyo
Night is the UI chrome (backgrounds, borders, status bars, selections); Dark+ is
the code itself.

`BAT_THEME` in `~/.zshenv` is the source of truth for that syntax theme. It is
read directly by `bat`, and indirectly by `delta` (which uses bat's theme set)
and by yazi (see below). Change it there and all three follow.

`~/.config/bat/config` names the same theme as a **fallback**, not a competing
source: bat prefers the environment variable, so that file only matters when
there is no environment to read — bat launched from an editor task, a GUI app
or a cron job, which would otherwise fall back to bat's own default and look
nothing like the rest of the setup. Same reasoning as vendoring btop's theme
instead of trusting the packaged copy.

The name is written out in four files by the time you count `~/.bashrc-custom`
and delta's `syntax-theme`, and two panes rendering the same file differently
is a subtle thing to notice, so `tests/check-theme.py` checks that all four say
the same thing.

## Palette

Taken from [`folke/tokyonight.nvim`](https://github.com/folke/tokyonight.nvim)
`extras/`, `night` style.

### Backgrounds and surfaces

| Name             | Hex       | Used for                                  |
| ---------------- | --------- | ----------------------------------------- |
| `bg`             | `#1a1b26` | default background                        |
| `bg_dark`        | `#16161e` | status lines, sidebars, floats, popups    |
| `black`          | `#15161e` | ANSI 0 background-ish, tab bar background  |
| `terminal_bg`    | `#1d202f` | ANSI 0 in every terminal                  |
| `bg_dark1`       | `#1f2335` | a fill that must read as inactive next to `bg_visual` |
| `bg_storm`       | `#24283b` | the third step of the blame stripe        |
| `bg_highlight`   | `#292e42` | inactive borders, boxes, subtle fills     |
| `bg_visual`      | `#283457` | visual selection                          |
| `selection`      | `#2e3c64` | terminal selection background             |
| `fg_gutter`      | `#3b4261` | gutter, inactive separators               |
| `blue7`          | `#394b70` | dim accents                               |

> **`fg_gutter` is not a text colour.** `#3b4261` is darker than the `#414868`
> called out below as unreadable, so anything you actually have to *read* —
> a hostname, a window index, a pane number — takes `comment` instead. Use
> `fg_gutter` for gutters, separators and scrollbars, which is what it is for.

The four near-background shades (`bg`, `bg_dark1`, `bg_storm`, `bg_highlight`)
exist as a sequence, and delta's `blame-palette` uses them as exactly that:
four steps close enough that a wall of blame does not turn into stripes, far
enough apart that adjacent commits separate.

### Foregrounds

| Name         | Hex       | Used for                             |
| ------------ | --------- | ------------------------------------ |
| `fg`         | `#c0caf5` | default foreground                   |
| `fg_dark`    | `#a9b1d6` | secondary text, ANSI 7               |
| `dark5`      | `#737aa2` | tertiary text                        |
| `comment`    | `#565f89` | comments, muted status text          |
| `dark3`      | `#545c7e` | inactive tabs, line numbers          |
| `terminal_black` | `#414868` | ANSI 8 (upstream value — see note) |

> **Note on ANSI 8.** Every terminal here uses `#85899c` instead of the
> upstream `#414868`. That is deliberate: `#414868` is close to unreadable for
> "bright black" text that CLI tools use for de-emphasised output. Keep all
> **four** terminals in sync — see below for who counts as one.
> `tests/check-theme.py` compares them.

### Four terminals, not two

Two of them are obvious. The other two get forgotten, and each was found
wearing upstream's `#414868` after the deviation above had already been
applied to the obvious ones:

- **VS Code's integrated terminal** is a terminal like kitty and wezterm,
  running the same tools, and it is easy to file under "editor".
- **Neovim's `:terminal`** is the same trap one level further in. `<leader>ft`,
  the lazygit and yazi windows and the vcs diff view all run real programs
  inside one, and those programs pick their colours out of sixteen ANSI slots
  exactly as they would under kitty.

Neovim's sixteen come from `terminal_ansi` in `plugins/tokyonight.lua`, which
is kitty's table copied out rather than the theme's own palette. Two reasons it
is spelled out instead of nudged:

- The theme derives ANSI 9–14 by running `Util.brighten()` over the accents,
  and the vendored kitty file that has to match them is a static copy of one
  past result of that function. Left implicit, an upstream change to `brighten`
  moves Neovim's terminal alone, silently.
- A table the test can read is a table the test can check. `check-theme.py`
  compares all sixteen against kitty, the same way it does for wezterm and VS
  Code, and separately checks the wiring — `terminal_colors = true` and an
  `on_colors` that actually hands the table over — because a palette nobody
  reads is the failure mode described under "dead keys" below.

Only `colors.terminal` is replaced, not the palette the editor's own highlight
groups are built from: `#85899c` is a colour for reading text against a dark
background, not for the borders and fills `terminal_black` draws elsewhere.

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

### Diff tints

Diff backgrounds are their own family, not palette accents. They have to be
dark enough that syntax-highlighted code stays readable on top — every one of
these is a *background* under an unchanged foreground — and they have to come
in three strengths, because both delta and Neovim's inline diff distinguish
the changed part of a line from the rest of it.

|            | non-emph  | body      | emph      |
| ---------- | --------- | --------- | --------- |
| added      | `#17311f` | `#20432b` | `#2c5a3a` |
| removed    | `#3f1f1f` | `#532727` | `#683131` |

Moved code (git's `diff.colorMoved`) sits between unchanged and changed, so it
gets its own quieter pair: violet-indigo for "left from here", cyan-teal for
"landed here".

| Direction        | delta's `map-styles` key | Hex       |
| ---------------- | ------------------------ | --------- |
| moved from, body | `bold purple`            | `#2e2547` |
| moved from, alt  | `bold blue`              | `#203356` |
| moved to, body   | `bold cyan`              | `#12384a` |
| moved to, alt    | `bold yellow`            | `#15423d` |

`tests/check-theme.py` asserts that Neovim's `InlineDiff*` groups use these
same values, because the inline diff exists to look like delta.

The inline diff needs more shades than delta does — it renders several move
pairs on screen at once and has to keep them apart, which delta never has to
do — so it extends the family with subtler tints of the same two hues, plus
two muted foregrounds for ghosted text and line numbers. Those live in
`lua/util/inline_diff.lua` beside the code that uses them:

| Role                          | Hex       |
| ----------------------------- | --------- |
| moved-from, subtler steps     | `#3a212b` `#352337` `#4a2139` |
| moved-to, subtler steps       | `#16332c` `#143539` `#175035` |
| ghosted moved-from foreground | `#8a7080` |
| folded region marker          | `#2f334d` |
| added line number             | `#6f9157` |
| moved-added line number       | `#5a7f9c` |
| whitespace error              | `#db4b4b` |

### Dark+ on the command line

The zsh line editor is the one piece of chrome that is also *code*, and it is
coloured as code — from `BAT_THEME`'s Visual Studio Dark+, set on
`FAST_HIGHLIGHT_STYLES` / `ZSH_HIGHLIGHT_STYLES` in `~/.zshrc`. PSReadLine
gets the same table on Windows, so a pipeline reads the same on both.

The reason is Ctrl-R. That picker pipes history through `bat`, so the same
command is already being painted in Dark+ one keystroke before it lands on the
prompt; anything else would mean accepting a history entry recoloured it.

| Role                                        | Hex       |
| ------------------------------------------- | --------- |
| plain text, redirections, `;` and `\|`       | `#d4d4d4` |
| comments                                    | `#6a9955` |
| strings                                     | `#ce9178` |
| commands, functions, aliases, `$(…)`        | `#dcdcaa` |
| control words, and precommands like `sudo`  | `#c586c0` |
| variables, assignments, interpolation       | `#9cdcfe` |
| type names                                  | `#4ec9b0` |
| globs, history expansion, escapes           | `#d7ba7d` |
| options                                     | `#569cd6` |
| numbers and file descriptors                | `#b5cea8` |

Two things stay Tokyo Night, because they are facts about the machine rather
than about syntax and Dark+ has no vocabulary for either: a word that resolves
to no command is `red`, and a path that has not resolved to anything yet is
`comment`. A path that *does* exist gets an underline instead of a hue.

> **Three Dark+ ports are in play, and this table is one of them.** The hexes
> above are VS Code's *published* Dark+ token colours. The editor side —
> Neovim's `lua/util/vscode_syntax.lua` — mirrors `Visual Studio Dark - C++`
> plus the token overrides in the VS Code settings, which resolves some of the
> same roles to different hexes (strings are `#dfa67c` there, comments
> `#7a987a`). Each side matches the thing it sits next to: the buffer matches
> VS Code, the prompt matches the picker above it. See
> `docs/vscode-syntax-parity.md`.

The third port is the one bat compiles in, and it is worth knowing it is not
quite this table. Rendering shell, Python, C++ and JSON through
`bat --theme="Visual Studio Dark+"` — identically on 0.24.0, 0.25.0 and 0.26.1
— gives ten colours, and five of them are the five above:

| Role                    | This table | What bat emits |
| ----------------------- | ---------- | -------------- |
| plain text              | `#d4d4d4`  | `#dcdcdc`      |
| comments                | `#6a9955`  | `#608b4e`      |
| strings                 | `#ce9178`  | `#d69d85`      |
| escapes                 | `#d7ba7d`  | `#e3bbab`      |
| type names              | `#4ec9b0`  | — (bat gives types the variable blue) |
| commands and functions  | `#dcdcaa`  | `#dcdcaa`      |
| control words           | `#c586c0`  | `#c586c0`      |
| variables               | `#9cdcfe`  | `#9cdcfe`      |
| options and keywords    | `#569cd6`  | `#569cd6`      |
| numbers                 | `#b5cea8`  | `#b5cea8`      |

So a history entry containing a quoted string does shift a little on its way
from the Ctrl-R picker to the prompt. That is accepted rather than chased,
because an exact match was never available: bat and zsh's highlighter divide a
command line into different tokens in the first place. bat's Bash grammar
paints `grep` as a variable and `echo` as plain text, scopes `;` and `|` as
control words, and has no notion at all of "this word resolves to no command" —
the distinctions the prompt exists to draw. Aligning the palette to bat's port
would move three shades and fix none of that.

What the table buys is the part that does survive: the same *roles* in the same
*family of colours*, so nothing changes category on the way down. Reach for
these values, not bat's, when adding a surface here.

### Why `jq` is not themed

`jq` is in `packages.txt` and prints JSON to the same terminal as everything
else, so it looks like an obvious gap. It is a gap, and it has to stay one.

By the rule above it is code, not chrome — `jq . x.json` and `bat x.json` are
the same bytes — so it should take bat's Dark+: `#dcdcdc` for the punctuation,
`#d69d85` for strings and object keys, `#b5cea8` for numbers, `#569cd6` for
`true`/`false`/`null`. That is what bat renders a `.json` file as, measured the
same way as the table above.

`JQ_COLORS` cannot say it. Before 1.8, jq parses each field into a fixed
`char[16]`, which leaves twelve characters for the escape body — enough for
`38;5;NNN`, four short of the fifteen `38;2;R;G;B` needs. And it is not a
per-field fallback: one over-long field and `jq_set_colors` returns 0, jq keeps
its own defaults, and it prints `Failed to set $JQ_COLORS` **on every
invocation**, including plain `jq -r .name` with no colour involved. Setting
truecolor here would put a warning line in the stderr of every script on the
box that pipes through jq, in exchange for no colour at all on any machine
running the jq Debian and Ubuntu ship (1.7.1).

The two things that do fit are both worse than nothing:

- **256-colour.** The cube's nearest entries miss `#d69d85` by 18 and `#569cd6`
  by 19 in a channel — the salmon goes tan, the blue goes cyan. That is the
  failure mode `doctor-theme.sh`'s first check exists to catch, chosen on
  purpose rather than suffered by accident.
- **ANSI 16.** Works everywhere, and lands on Tokyo Night by way of the
  terminal palette — which is the wrong palette. It would make jq the one
  surface in the setup rendering code in the chrome colours.

jq's own defaults are ANSI-indexed too, so today's output is already Tokyo
Night with the roles muddled (strings green, keys bold blue, `null` bright
black). Revisit when jq 1.8 is what these machines actually install: 1.8
allocates the colour buffer instead, and the truecolor values above become
sayable.

### One file-type table, four listings

`ls`, `eza`, `fd`, zsh's completion menu, `lf` and `yazi` all list files, and
all six now agree on what a `.zip` or a broken symlink looks like. The table
is written three times because the tools speak three dialects:

- `common/.config/shell/theme.sh` builds `LS_COLORS`, which GNU `ls`, `eza`,
  `fd` and — through a `list-colors` zstyle in `~/.zshrc` — zsh's completion
  menu all read;
- `common/.config/lf/colors` says it again, because lf reads `LS_COLORS` from
  the environment but needs its own copy when launched without one;
- yazi's `[filetype]` rules say it a third time, in yazi's schema.

Check 3 of `tests/check-theme.py` is what keeps the three honest.

One thing not to chase: a broken symlink's *name* is cyan in `eza` and red in
`ls`. `or` is set, and setting it again in `EZA_COLORS` changes nothing —
eza 0.18 colours the name as a link and shows the breakage on the arrow and
the target instead, which `bO` paints red and underlined. It is unmistakable
either way, just not identical.

`eza` also draws columns `LS_COLORS` has no vocabulary for, so `EZA_COLORS`
covers those with eza's own keys (`man eza_colors`). The permission bits
deliberately take yazi's per-column meanings — read yellow, write red, execute
green, separators in the gutter grey — so `drwxr-xr-x` reads the same in
`ls -l` as in yazi's footer. It is applied *on top of* `LS_COLORS` rather than
replacing it: there is no leading `reset`, so an extension the table does not
name keeps eza's built-in colour, which is ANSI-indexed and therefore already
Tokyo Night by way of the terminal palette.

### Man pages

`less` renders man's bold, underline and standout with the terminal's
defaults. `LESS_TERMCAP_*` in `theme.sh` replaces those three, each mapped to
a documented role: bold is headings and command names, so `blue`; underline
marks the argument you substitute, so `cyan`.

Standout is the interesting one. `less` uses it for **search matches**, not
only for the status line — verified by running `less -p` under a pty and
reading back what it wrapped the match in — so it takes `bg_search`, the blue
of an in-buffer match, per "Two kinds of match" above. The bottom status line
is drawn in standout too and comes along with it, which reads fine and is
quieter than the reverse video it gets by default.

`GROFF_NO_SGR=1` is set alongside them and is not optional: without it groff
emits its own SGR sequences and `less` never consults termcap at all, so the
variables have no effect. It is still supported in groff 1.24 (it is the
documented equivalent of `grotty -c`).

### Gotcha: yazi ignores unknown keys

Yazi validates colour *values* but silently ignores unknown section and key
names, so "it loaded without an error" does not mean a key is doing anything.
To check a key is really wired up, break its colour on purpose and confirm yazi
reports `invalid color`:

```bash
YAZI_CONFIG_HOME=/tmp/probe yazi --debug 2>&1 | grep "invalid color"
```

Silence there means the key name is wrong. The same trick enumerates the real
schema.

**Renames are the dangerous case**, because nothing about the config looks
wrong afterwards — the setting is still there, still spelled correctly, and
has simply stopped being read. yazi v25.12.29 moved `[mgr] hovered` and
`preview_hovered` into `[indicator]` as `current` and `preview`, and renamed
`[confirm] content` to `body`; until this was noticed, the hovered row had
silently gone back to `reversed` and the preview row to `underline` — the two
defaults those settings exist to override.

`tests/check-theme.py` cannot catch that: a colour that is never read is still
a valid colour. Re-audit by diffing against the version of upstream's preset
your yazi actually ships, which lists every key it reads:

```bash
curl -fsSL https://raw.githubusercontent.com/sxyazi/yazi/main/yazi-config/preset/theme-dark.toml \
  | grep -oE '^\[[a-z]+\]|^[a-z_]+ *=' | tr -d ' ='
```

Compare that against the section and key names here, and check anything that
differs against yazi's CHANGELOG — the preset on `main` includes unreleased
renames, so the CHANGELOG is what says whether a difference applies to the
release you are running. (`[help]`'s `on`/`run`/`desc`/`footer` are the current
example: superseded on `main`, not in any release yet, so they stay as they
are here.) For `[filetype]` rules, `is` accepts exactly `none`, `hidden`, `link`,
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

### One selected row

`bg_visual` `#283457` is *the* "this is the row you are on" fill, and it is
worth checking a new tool against: fzf's `bg+`, tmux's `mode-style`, zsh's
completion menu, yazi's `hovered`, btop's `selected_bg`, and Neovim's `Visual`,
`WildMenu` and `PmenuSel` are all the same colour. Neovim's completion menu was
the exception until it was overridden — the theme blends a shade of its own for
`PmenuSel` — which mattered because blink.cmp is disabled here, so that native
menu is the one on screen.

### Two kinds of match

Highlighted matches come in two flavours here, and they deliberately look
different, because they answer different questions.

**A match inside text you are reading** — `/` in Neovim, tmux copy mode,
wezterm copy mode, a search in `less` — is `blue0` `#3d59a1` behind the normal
foreground, and where the tool has a notion of a *current* match, that one is
`orange` `#ff9e64`. You are moving through a body of text and the colour says
"here is one of them, and here is the one you are on".

**The query you typed into a filter** — fzf, ripgrep, `delta --grep` — is an
inverted yellow block. Nothing is "current"; every visible line already
matched, and the highlight is showing you *which characters* earned it.

Reach for the right one when theming something new. `less` is the case that
looks ambiguous and is not: it is a pager, you search *within* it, so it takes
the blue. It has only one standout attribute and no concept of a current
match, so it gets the first half of that convention and not the second.

### Why matches are inverted, not just recoloured

Every search surface paints a match as an inverted yellow block, never as
recoloured text: fzf's `hl`/`hl+`, delta's `grep-match-word-style`, and
ripgrep's `match` (which has no `reverse` style, so `.ripgreprc` inverts by
hand — `bg` as the foreground, `yellow` as the background).

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

### Gotcha: do not colour git's diff

Delta paints diffs; git paints everything else it prints, and the
`[color "status"]`, `[color "branch"]` and `[color "decorate"]` sections give
those the palette's roles — green added, yellow modified, teal untracked,
magenta branch, cyan remote, and `orange` for HEAD, which is the same "you are
here" colour as the cursor and the current search match.

There is deliberately **no `[color "diff"]` section**, and there must not be
one. `delta.map-styles` recognises moved code by matching the exact colours
git emits for it — `bold purple`, `bold cyan` and friends — so overriding
git's diff colours would quietly stop delta from recognising a move, and
relocated code would go back to reading as a plain add plus a plain remove.
The failure is silent: diffs still render, they just stop being as useful.

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

The cursor is **`#ff5000`** (a hot orange) everywhere — kitty, wezterm, VS
Code's editor and terminal, Neovim, and the fzf pointer. It is not part of
Tokyo Night; it is a deliberate personal accent chosen to be instantly
findable against the blue-violet palette. Keep it.

"Everywhere" takes some doing in Neovim. `options.lua` points guicursor at the
`Cursor` group for the modes it lists, but terminal mode is not one of them and
falls back to Neovim's default `t:block-TermCursor` — and tokyonight defines no
`TermCursor`, so the cursor in a `:terminal` buffer was plain reverse video.
`lCursor` and `CursorIM`, the cursor under `:lmap` or an IME, are the theme's
own fg-on-bg for the same sort of reason. All three are set alongside `Cursor`
in `plugins/tokyonight.lua`.

## Where the theme lives

`tests/check-theme.py` reads this table, so a themed file that is missing from
it fails the test.

| Tool     | File                                                 |
| -------- | ---------------------------------------------------- |
| kitty    | `common/.config/kitty/themes/tokyonight_night.conf`   |
| kitty    | `common/.config/kitty/kitty.conf` (dim opacity, includes the theme) |
| wezterm  | `common/.config/wezterm/wezterm.lua`                  |
| VS Code terminal | `common/.config/Code/User/settings.json` (the `terminal.*` keys) |
| tmux     | `common/.tmux.conf` (the `# Theme` section)           |
| Neovim   | `common/.config/nvim/lua/plugins/tokyonight.lua` (chrome, and `:terminal`'s ANSI slots) |
| Neovim   | `common/.config/nvim/lua/util/inline_diff.lua` (the diff tints) |
| lazygit  | `common/.config/lazygit/config.yml` (`gui.theme`)     |
| delta, git | `common/.config/git/config` (`[delta]`, and git's own `[color "…"]`) |
| starship | `common/.config/starship.toml` (`[palettes.tokyonight]`) |
| fzf, ls, man | `common/.config/shell/theme.sh`                   |
| bat      | `common/.config/bat/config` (syntax theme fallback)   |
| zsh      | `common/.zshrc` (completion menu, command line, suggestions) |
| ripgrep  | `common/.ripgreprc`                                   |
| PowerShell | `windows/Documents/PowerShell/Microsoft.PowerShell_profile.ps1` (PSReadLine, rg) |
| search   | `common/.local/bin/st-rg`, `common/.local/bin/st-zoekt` |
| yazi     | `common/.config/yazi/theme.toml`, `plugins/bat-preview.yazi/` |
| lf       | `common/.config/lf/colors`                            |
| btop     | `common/.config/btop/themes/tokyo-night.theme`        |
| swatches | `doctor-theme.sh` (renders the palette, so it holds a copy) |

## Keeping it consistent

Half of these tools describe the same thing in a different dialect — hex here,
decimal SGR triples there, a TOML table somewhere else — so nothing but care
stops them drifting apart. `tests/check-theme.py` is that care, written down:

```bash
tests/check-theme.py            # report drift, exit non-zero
tests/check-theme.py --verbose  # and list what passed
```

It checks seven things:

1. **Every colour is documented here.** Any hex or `38;2;R;G;B` triple in a
   themed config has to appear somewhere in this file. That is what makes this
   document the registry rather than a description that rots.
2. **All four terminals agree**, slot for slot: background, foreground,
   cursor, selection and all sixteen ANSI colours, across kitty, wezterm,
   VS Code's integrated terminal and Neovim's `:terminal`.
3. **One file-type table, three dialects.** `LS_COLORS` (asked of a real shell,
   not reparsed), `lf/colors` and yazi's `[filetype]` rules must agree on every
   extension and file kind, colour *and* boldness — including where yazi says
   it by mime type and the other two by extension.
4. **The inline diff uses delta's tints**, exactly, since it exists to look
   like delta.
5. **One name for the syntax theme.** `~/.zshenv`, `~/.bashrc-custom`,
   delta's `syntax-theme` and `~/.config/bat/config` must all name the same
   one, or two panes render the same file differently.
6. **The roles that only work if they are one colour.** Some colours earn
   their keep by being identical everywhere: "you are here" is worthless if it
   is orange in one pane and white in the next, and a selected row that shifts
   shade between panes reads as two different kinds of selection. The cursor
   (11 settings), the selected row (7), an in-buffer search match (4) and the
   current match (2) are each compared across every tool that sets them.
7. **This file's table above points at files that exist**, and lists every
   file the test checks.

The checks are only as good as their scope: `CHROME_FILES` at the top of the
script is the list of files that get checked. Theme something new, add it
there and to the table above.

### The failure the test cannot see: dead keys

`check-theme.py` compares colours. It cannot tell you that a key stopped being
read — a colour nobody reads is still a valid colour, and most of these tools
ignore a key they do not recognise without a word. That failure looks like
nothing at all: the setting is there, spelled correctly, and simply does not
happen any more.

That audit is `tests/audit-theme-keys.py`. It asks each tool's upstream what
keys it actually reads — yazi's preset, delta's clap options, btop's
`Default_theme` map, lazygit's published JSON schema — and diffs ours against
the answer:

```bash
tests/audit-theme-keys.py            # report dead keys, exit non-zero
tests/audit-theme-keys.py --verbose  # and list keys upstream has that we do not set
```

It needs the network, which is why it is not part of `check-theme.py` and not
one of the checks to run on every change. Run it when a tool is upgraded.

It reports two things, and the difference between them is the whole reason it
fetches two refs:

- **DEAD** — the *release you run* does not read this key. The setting is doing
  nothing right now.
- **AHEAD** — the release still reads it, but upstream's default branch has
  renamed or dropped it. Not broken yet; it breaks on the next upgrade.

Diffing against `main` alone would cry wolf, because an upstream preset carries
renames that have not shipped; diffing against the release alone would give no
warning before an upgrade lands. yazi's `[help]` keys are the standing example
and are listed in the script's `ACCEPTED_AHEAD`, which is where a deliberate
"yes, we know, staying put until it ships" belongs.

What earlier runs of this found, by hand: yazi had moved two keys out from
under us (see the gotcha above), delta has no `blame-timestamp-style` and never
did, btop left six process-state colours at hardcoded off-palette fallbacks,
and lazygit's `lightTheme` is gone from both its config struct and its schema.

One kind of dead key the script cannot find by diffing names: an option
upstream advertises and then never applies. delta's `grep-header-file-style` is
one — it is in `--help`, delta parses it into an internal
`ripgrep-header-file-style`, and nothing ever reads that value; the file
heading in ripgrep-format output takes `grep-file-style`, the same key as the
classic format. Setting it would look correct and do nothing. Those live in the
script's `INERT` table, each with the probe that established it, so the next
person to notice the gap in the option list does not "fix" it.

### The other half: `./doctor-theme.sh`

The test checks that the configs in this repo agree with each other. It cannot
tell you whether they reached a particular machine, whether the shell there
exported them, or whether that terminal can render 24-bit colour at all —
which is the difference between "the theme is right" and "the theme looks
right in front of me".

`./doctor-theme.sh` is that half. It reports whether `COLORTERM` promises
truecolor (bat downgrades silently without it), whether each config file is
where the tool will look, and whether `LS_COLORS`, `EZA_COLORS`, `BAT_THEME`,
`FZF_DEFAULT_OPTS`, `LESS_TERMCAP_*`, `GROFF_NO_SGR` and
`RIPGREP_CONFIG_PATH` actually made it into the environment — then prints
swatches, because only your eye can confirm the last step.

The 16 ANSI blocks it prints come from the terminal rather than from any file
here, so they are what tells you whether kitty, wezterm or VS Code picked the
theme up. Look at slot 8: legible grey means the deviation above took, and
near-invisible means that terminal is still on upstream's `#414868`.
