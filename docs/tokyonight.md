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
| `black`          | `#15161e` | the strip the tabs sit on, in kitty and wezterm alike |
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

> **Note on ANSI 8.** kitty, wezterm and the VS Code integrated terminal all
> use `#85899c` instead of the upstream `#414868`. That is deliberate:
> `#414868` reads at 1.9:1 against `bg`, which is close to unreadable for the
> "bright black" that CLI tools use for de-emphasised output; `#85899c` gets it
> to 4.9:1 while still receding. There are **four** copies of the 16 ANSI
> slots, and the ones after the first are easy to forget: kitty, wezterm, the
> VS Code integrated terminal, and Neovim — which pushes tokyonight's own
> palette into `:terminal` when `terminal_colors = true`, putting upstream's
> values back for exactly the two slots this theme changes on purpose. Slot 0
> is the other one: upstream's `#15161e` is *darker* than the background, so
> plain black text is invisible, which is why the terminals use `#1d202f`.
> `tests/check-theme.py parity` compares all four.

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

Bright ANSI variants (9–15) are the accents lightened. ANSI 8 is the local
deviation noted above.

| Name             | Hex       | ANSI |
| ---------------- | --------- | ---- |
| `bright black`   | `#85899c` | 8    |
| `bright red`     | `#ff899d` | 9    |
| `bright green`   | `#9fe044` | 10   |
| `bright yellow`  | `#faba4a` | 11   |
| `bright blue`    | `#8db0ff` | 12   |
| `bright magenta` | `#c7a9ff` | 13   |
| `bright cyan`    | `#a4daff` | 14   |
| `bright white`   | `#c0caf5` | 15   |

### Git colours

| Name      | Hex       |
| --------- | --------- |
| `add`     | `#449dab` |
| `change`  | `#6183bb` |
| `delete`  | `#914c54` |

### Derived surfaces

Colours that are not in the upstream palette but are used deliberately. Each
one earns its place below by doing something no palette entry does; anything
not listed here is drift, and `tests/check-theme.py` says so.

| Hex       | Name             | Why it is not a palette colour                    |
| --------- | ---------------- | ------------------------------------------------- |
| `#1d202f` | ANSI 0           | Slot 0 is one notch above `bg` on purpose: a program printing "black" text against the terminal background would otherwise be invisible. |
| `#ff5000` | cursor           | The shared "you are here" accent: kitty, wezterm, Neovim and the fzf pointer. Not a Tokyo Night colour at all — see "Local deviation: the cursor" below. |
| `#000000` | cursor glyph     | True black under the `#ff5000` block cursor and nowhere else. Reads at 6.4:1 against the orange; `bg` would give 1.6:1. |
| `#1f2335` | `bg_dark1`       | One step above `bg`. The "present but not focused" fill — yazi's which-key mask, lazygit's selection in an unfocused panel. |
| `#24283b` | `bg` (storm)     | The storm variant's background, borrowed as the third step of delta's blame stripe. |

#### Tinted washes — an accent used as a background

An accent at full strength behind text is a highlighter pen: `green` under
syntax-highlighted code is unreadable. These are the accents mixed down into
`bg` until the text on top survives — every one clears 4.5:1 against both `fg`
and Dark+'s plain foreground, which is what `tests/check-theme.py contrast`
pins. (Dark+'s own colours are deliberately not written down here: a hex in
this document is a hex the checker will then permit anywhere in the tree, and
the syntax theme's palette is not the UI's to borrow.)

Mostly delta's diff body, which is what they were mixed for. btop borrows three
of them for its process states, on the same reasoning: a background with text
over it and no foreground key of its own to compensate.

| Hex       | Role                                            |
| --------- | ----------------------------------------------- |
| `#20432b` | added line                                      |
| `#2c5a3a` | added, emphasised token                         |
| `#17311f` | added, unchanged remainder                      |
| `#532727` | removed line; btop's paused process             |
| `#683131` | removed, emphasised token                       |
| `#3f1f1f` | removed, unchanged remainder                    |
| `#2e2547` | moved from here (violet); btop's process banner |
| `#203356` | moved from here (indigo); btop's followed process |
| `#12384a` | moved to here (cyan)                            |
| `#15423d` | moved to here (teal)                            |

#### These washes are what a colour-blind reader has

delta's added and removed backgrounds are 39.7 apart in Lab and **3.0** apart
to a deuteranope — the same colour. That is not a fault to repaint away: about
one man in twelve cannot separate those hues whatever green and red you pick,
so a diff carrying direction in hue alone is broken for them by construction.

This diff does not carry it in hue. Direction lives in the line-number gutter,
because `line-numbers-left-format` is empty and a removed line therefore has no
number at all, and *presence* lives in lightness, which colour-vision
deficiency leaves alone:

| | everyone | deuteranope |
| --- | --- | --- |
| added vs the page | 32.3 | **22.9** |
| removed vs the page | 27.2 | **24.2** |
| added vs removed | 39.7 | **3.0** |

Three states — blank gutter, numbered and tinted, numbered and plain — all
separable without hue.

So the thing worth pinning is not the hue difference, which cannot be fixed,
but the lightness difference, which a well-meaning tweak toward subtlety can
quietly remove. `tests/check-theme.py contrast` simulates deuteranopia on every
row of the table above and requires each to stand at least 10 from the page.

### Why the shell theme is interactive-only

`common/.config/shell/theme.sh` returns immediately unless the shell is
interactive. `.zshenv` is read by every zsh that any script or tool ever
spawns, and sourcing the file costs about a millisecond there — roughly 40% of
what `.zshenv` costs in total. Almost all of that is zsh *parsing* the lines
rather than running them, so the only way to make it cheaper without the guard
would be to delete the comments that explain the colours.

Nothing is lost. Every variable in the file configures either something only an
interactive session has (fzf's picker, the line editor) or a tool that colours
its output only when that output is a terminal — `ls --color=auto`, `grep
--color=auto`, bat, man. They are all exported, so a script started *from* an
interactive shell inherits every one of them; the shells that skip the file are
the ones with no terminal to paint.

The consequence for tooling: anything reading these values has to source the
file **interactively**, or it sees an empty file and checks nothing.
`tests/check-theme.py` uses `zsh -fic` and `bash --norc -ic`, and filters the
job-control warnings bash emits when forced interactive without a terminal.

### Gotcha: an unknown yazi *rule* key is fatal

This one is worth reading before the next one, because the two are opposites
and the difference is expensive.

An unknown **style** key (`hovered`, `content`, `on`) is ignored in silence —
that is the next section. An unknown **rule** key is not: yazi refuses the
entire file and falls back to its presets. So one stale key in one filetype
rule does not cost you that rule, it costs you the whole theme, while every
colour in the file still reads as perfectly correct.

That is exactly what had happened here. Yazi v25.12.29 renamed `name` to `url`
"for open, fetchers, spotters, preloaders, previewers, filetype, and `globs`
icon rules" (#3034), which meant:

- every `{ name = "*.zip", … }` in `theme.toml` → **the whole theme rejected**
- the previewer rules in `yazi.toml` → **the whole config rejected**, so
  `bat-preview` never ran and the ratios, sort and preview settings were the
  stock ones
- and separately, `"$schema"` at the top of `keymap.toml` is now refused as not
  kebab-cased → **the whole keymap rejected**

Three files, all silently on presets. Mime patterns moved too: yazi matches
them against a scheme-prefixed string now, so `image/*` matches nothing and
needs to be `**/image/*` — its own presets carry that prefix, and one of them
matches `vfs/{absent,stale}`.

The lesson is that yazi's configs must be *loaded*, not merely read. When yazi
is installed, `tests/check-theme.py parity` does exactly that:

```bash
YAZI_CONFIG_HOME=common/.config/yazi yazi --debug
```

which prints each config with a character count, or the reason it was refused.

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
`preview_hovered` into `[indicator]` as `current` and `preview`, renamed
`[confirm] content` to `body`, and renamed the rule pattern key `name` to
`url`; until this was noticed, the hovered row had silently gone back to
`reversed` and the preview row to `underline` — the two defaults those
settings exist to override.

**And a rename cuts both ways.** These dotfiles land on machines whose yazi
was installed at different times, and each side of a rename ignores the
other's spelling: chasing the new names alone broke every machine still on
an older binary — a url-only filetype table matches nothing there, so the
whole listing renders in plain foreground. The resolution is to say it both
ways: every filetype rule carries `url` and `name` with identical globs, the
hovered row is set in `[mgr]` and in `[indicator]`, and `[confirm]` has both
`content` and `body`. Whichever spelling a given yazi understands is the one
it reads; it ignores the other. Verified by running 25.5.31 and 26.5.6
against the same config and reading the rendered colours back, and
`tests/check-theme.py` fails if a rule loses a spelling or a pair drifts
apart.

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

This is not hypothetical, and the failure is worse than it sounds: yazi renames
theme keys between releases, and a renamed key does not warn, it just stops
applying and takes the default instead. Twice now the default has been the
exact thing the setting was written to avoid.

| Release     | Change                                                            |
| ----------- | ----------------------------------------------------------------- |
| `v25.12.29` | `[mgr] hovered` and `preview_hovered` → `[indicator] current` and `preview`. The defaults are `reversed = true` and `underline = true` — the reverse-video flip and the hard rule the settings exist to replace. |
| `v25.12.29` | `[confirm] content` → `body`.                                      |
| unreleased  | `[help] on` → `chord`, `run` and `desc` → `action`, `footer` removed. Both spellings are set in `theme.toml` until this lands. |

So when yazi is upgraded, diff its shipped `theme-dark.toml` against ours and
look at the key *names*, not just the colours:

```bash
curl -s https://raw.githubusercontent.com/sxyazi/yazi/main/yazi-config/preset/theme-dark.toml
```

A key we set that no longer appears there is doing nothing.

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

### Gotcha: delta options that do not exist

A `[delta]` section in git config is a dumping ground. Git stores whatever you
put there and delta reads the keys it knows, so a key with a name that is
subtly wrong is not an error — it is a setting that silently never applies.

This config carried `blame-timestamp-style` for a long time. It reads exactly
like the real options around it and delta has never had it: there is
`blame-timestamp-format` and `blame-timestamp-output-format`, but the
timestamp's colour is not separately settable — it comes from
`blame-code-style` with the rest of the line. Confirmed against the binary,
which rejects `--blame-timestamp-style` outright, and against delta's source
back to 0.16.

`tests/check-theme.py parity` now asks delta about every key in the section
whenever delta is installed. The binary is the only reliable oracle here:
`--help` summarises rather than listing.

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

> **Two Dark+ variants are in play, on purpose.** These are bat's built-in
> `Visual Studio Dark+`. The editor side — Neovim's `lua/util/vscode_syntax.lua`
> — mirrors `Visual Studio Dark - C++` plus the token overrides in the VS Code
> settings, which resolves some of the same roles to different hexes (strings
> are `#dfa67c` there, comments `#7a987a`). Each side matches the thing it sits
> next to: the prompt matches the picker above it, the buffer matches VS Code.
> See `docs/vscode-syntax-parity.md`.

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

### The failure the test cannot see: dead keys

`check-theme.py` compares colours. It cannot tell you that a key stopped being
read — a colour nobody reads is still a valid colour, and most of these tools
ignore a key they do not recognise without a word. That failure looks like
nothing at all: the setting is there, spelled correctly, and simply does not
happen any more.

It is worth re-running this audit when a tool is upgraded. Each of the three
below turned up something real:

```bash

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

### One selected row

`bg_visual` `#283457` is *the* "this is the row you are on" fill, and it is
worth checking a new tool against: fzf's `bg+`, tmux's `mode-style`, zsh's
completion menu, yazi's `hovered`, btop's `selected_bg`, and Neovim's `Visual`,
`WildMenu` and `PmenuSel` are all the same colour. Neovim's completion menu was
the exception until it was overridden — the theme blends a shade of its own for
`PmenuSel` — which mattered because blink.cmp is disabled here, so that native
menu is the one on screen.

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

## Where the theme lives

`tests/check-theme.py` reads this table, so a themed file that is missing from
it fails the test.

| Tool     | File                                                 |
| -------- | ---------------------------------------------------- |
| kitty    | `common/.config/kitty/themes/tokyonight_night.conf`   |
| kitty    | `common/.config/kitty/kitty.conf` (dim opacity, includes the theme) |
| wezterm  | `common/.config/wezterm/wezterm.lua`                  |
| tmux     | `common/.tmux.conf` (the `# Theme` section)           |
| Neovim   | `common/.config/nvim/lua/plugins/tokyonight.lua`      |
| Neovim   | `common/.config/nvim/lua/util/inline_diff.lua` (the diff tints) |
| lazygit  | `common/.config/lazygit/config.yml` (`gui.theme`)     |
| delta    | `common/.config/git/config` (`[delta]`)               |
| git      | `common/.config/git/config` (the `[color "..."]` sections) |
| starship | `common/.config/starship.toml` (`[palettes.tokyonight]`) |
| fzf      | `common/.config/shell/theme.sh`                       |
| ls, eza, grep, man | `common/.config/shell/theme.sh` (`LS_COLORS`, `EZA_COLORS`, `GREP_COLORS`, `LESS_TERMCAP_*`) |
| zsh      | `common/.config/shell/theme.sh` (autosuggestions), `common/.zshrc` (completion menu, and the Dark+ command line) |
| PowerShell | `windows/Documents/PowerShell/Microsoft.PowerShell_profile.ps1` (PSReadLine) |
| Hammerspoon | `mac/.hammerspoon/init.lua` (`hs.alert.defaultStyle`) |
| ripgrep  | `common/.ripgreprc`                                   |
| search pickers | `common/.local/bin/st-rg`, `common/.local/bin/st-zoekt` (the awk prefix) |
| yazi     | `common/.config/yazi/theme.toml`, `plugins/bat-preview.yazi/` |
| lf       | `common/.config/lf/colors` (file names), `common/.config/lf/lfrc` (the `# Theme` section), `common/.config/lf/icons` (deliberately colourless) |
| btop     | `common/.config/btop/themes/tokyo-night.theme`        |
| the doctor | `./doctor-theme.sh` (what it expects to find on the machine) |

`tests/check-theme.py` reads this table to decide what to scan, so a tool is
covered from the moment its row lands here.

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

### Carries colour, deliberately not palette-checked

Some files hold colours and are still kept out of the table above. Each has a
reason, and each is checked by something other than the palette scan — but
"not in the table" is invisible on its own, so they are named here and the
parity check requires this list to stay exactly true. A tracked file that grows
a colour without either a table row above or a row here is a failure; so is a
row here for a file that no longer carries colour. There is no third state in
which a colour goes unlooked-at.

| File | Why it is out | What checks it instead |
| --- | --- | --- |
| `common/.config/Code/User/settings.json` | `workbench.colorCustomizations` does follow this palette, but the same file carries the Dark+ token colours, the debug inline-value colours and some long-standing personal choices that are not Tokyo Night — the orange-brown active tab border, the inlay hint greys. Scanning it whole would report those forever. | the 16 ANSI slots of its integrated terminal and its title bar, compared against kitty and wezterm |
| `common/.config/nvim/lua/util/vscode_syntax.lua` | Deliberately not this palette. Every hex in it is what VS Code resolves for a construct, so that a buffer reads the same in both editors — see the syntax-parity doc next to this one. | the tables in that doc are read back and must match what the file maps, and the theme it resolves against must still be the one `settings.json` selects |

Documentation, the checkers themselves, and the per-platform symlinks into
`common/` are not tracked here — the first two only quote colours, and the
third is the same file seen twice.

## Checking it

```bash
tests/check-theme.py            # all three checks
tests/check-theme.py contrast   # just one
tests/check-theme.py --verbose  # and what passed
tests/check-theme.py swatch     # every colour, then the preview below
tests/check-theme.py preview    # just the preview
```

`preview` draws small mock-ups of the surfaces out of the real colours — a file
listing with a build artefact under the cursor, a diff with added, removed,
emphasised and moved lines, a search hit, a command line, a prompt and a status
bar. A column of swatches tells you the colours are right; it does not tell you
whether a diff is readable or whether build noise recedes far enough without
vanishing, and those are the questions the theme exists to answer.

And, if you change the checker itself:

```bash
tests/check-theme-selftest.py   # break one thing at a time, 13 times over
```

It copies the working tree, makes one specific thing wrong in it, and requires
the checker to fail *and* to say why in recognisable words — plus direct
assertions on the parts no config mutation can reach, like the contrast maths
and the fill floor. A checker that never fails is indistinguishable from one
that is broken.

`swatch` prints every colour in this document and every pair the contrast table
knows about, using real escape sequences. Passing checks prove the numbers are
right, which is not the same as the theme being right — and it is also the
quickest way to find out whether a terminal is genuinely doing 24-bit colour or
quietly approximating it.

- **palette** — every colour literal in every file above is one this document
  names, including the ones written as SGR escapes (lf) or decimal triplets
  (ripgrep), and including the values `theme.sh` builds at runtime rather than
  spelling out.
- **parity** — the copies agree: the 16 ANSI slots across kitty, wezterm and
  the VS Code integrated terminal; the tab bar across kitty and wezterm; the
  per-extension file colours across lf, yazi and the `LS_COLORS` the shell
  exports; and everything `theme.sh` exports, sourced in *both* bash and zsh
  and compared byte for byte — `$var:s` is a history modifier in zsh, so text
  that is unremarkable to bash can be a parse error there.

  It also checks the chain the *syntax* colours rest on. Neovim's hexes in
  `lua/util/vscode_syntax.lua` are the values VS Code resolves once a specific
  theme extension and the user's `textMateRules` combine, so three files have
  to agree and none of them mentions the others: `docs/vscode-syntax-parity.md`
  names the theme and its extension, `settings.json` selects the theme by name,
  and `vscode_extensions.txt` decides whether the extension is installed. Drop
  the extension and nothing breaks loudly — VS Code falls back to another dark
  theme, and Neovim keeps painting colours resolved against one that is gone.

  It also checks that Neovim's inline diff and delta paint the same diff:
  `lua/util/inline_diff.lua` maps each of its highlights to a delta style in
  its own header comment, and this is what holds the two files to it.

  And where a tool can be asked to read its own configuration back, it is —
  `delta`, `ripgrep`, `yazi`, `starship`, `bat` and `kitty`, each skipped when
  not installed. This is the part that has found the most, because a config
  file will hold a misspelled or renamed key indefinitely while looking
  entirely correct:

  | Tool | Asked | What it catches |
  | ---- | ----- | --------------- |
  | delta | every key under `[delta]` offered back as a flag | an option it does not have |
  | ripgrep | a real search against `/dev/null` | a colour spec it rejects |
  | yazi | `--debug`, which prints each config or the reason it refused it | a rule key that makes it discard the whole file |
  | starship | `explain`, then its session log under `STARSHIP_CACHE` | an unknown section or key |
  | bat | `--list-themes` | `BAT_THEME` naming a theme it does not carry |
  | kitty | its own config loader via `+runpy` | an unknown option key |
  | git | the real commands against a throwaway repository | a colour slot git does not have |
  | tmux | a server on its own socket, then `show-options` | an option name tmux drops on load |
  | lazygit | its own `--config` dump, for `gui.theme` only | a theme key lazygit has no field for |
  | the doctor | its swatches, against what `theme.sh` really exports | a demo colour the shell stopped producing |
  | the search pickers | their awk prefixes, against `~/.ripgreprc` | a result `rg` and its picker paint differently |
  | git | `--get-color` on every `color.*` key | an attribute typo the hex scan cannot see, e.g. `#7aa2f7 blod` |
  | wezterm | `ls-fonts`, which evaluates the config | any colour it cannot parse, by key name — the strictest of them |

  Each of these was added because the one before it found something real.

  Two tools are still absent, and the reason is now measured rather than
  asserted — this paragraph used to name three, and the third turned out to be
  wrong. None of them validates its config, but all three *render*, and
  rendered output is an oracle of a different kind: set one key to a colour
  nothing else uses and see whether it reaches the screen. That works. It just
  does not reach far enough.

  **btop** loads an unknown theme key without a word, and its debug log says
  nothing beyond "Loading theme file". Its output does carry 41 of the 48
  theme colours, but the seven it misses are the load- and state-dependent ones
  — gradient endpoints that only paint under load, process states that need a
  selection — so a check built on it would fail on a quiet machine and pass on
  a busy one. Rejected for flakiness, not for impossibility.

  **eza** discards a malformed `EZA_COLORS` code without a word. A per-key
  sentinel does work, and an unknown key correctly fails to reach the output,
  but only 18 of its 60 keys paint in a basic listing — and a much richer
  fixture (a git repo with staged, modified and untracked files, symlinks, hard
  links, extended attributes, `--git --extended --octal-permissions
  --total-size`) moved that to 20. Guarding 20 keys at the price of a 40-entry
  list of unreachable ones, which would itself go stale, is not worth it. Key
  names were checked against `man eza_colors` instead.

  Measured with eza 0.18.2 and btop 1.3.0. Both are worth re-testing when
  either gains a way to dump what it parsed.
  Media files are the case where the two tools genuinely describe the same
  thing in different languages: yazi matches images, video, audio and PDFs by
  mime (`**/image/*`), while `lf` and `LS_COLORS` have no notion of mime and
  spell out `*.png`. A rule-by-rule comparison never brings those together, so
  18 file types were described twice and compared never. The check bridges them
  through the standard library's extension-to-mime table, which is the one
  mapping here that is not itself part of the theme.

  A note on how these read their configs, because it went wrong four times.
  A check that asks "is this colour still in that file?" has to ask it of the
  lines the tool will read, not of the file as text — every config here
  explains its choices in comments, and changing a colour is exactly what
  leaves a commented-out copy of the old line behind. That copy satisfies the
  pattern perfectly while the live line says something else.

  Caught this way: the COLORTERM guard (which accepted the paragraph explaining
  an export as the export), the stale-pair guard, the shared-role check, and
  the doctor swatches. Whole-line comments are stripped first now, by the
  marker the file's syntax uses — `--` for Lua, `//` for JSON, `#` for the
  rest — and each has a mutation of its own.

  A related one, same audit: a reader that takes the *first* match in a file
  stops at the first. `st-rg` carries two awk prefixes and only one was being
  read, so the other could paint search results any colour it liked.

  That audit is no longer done by hand. `tests/check-theme-selftest.py`
  generates it: for every colour in every scanned config it changes the value
  and runs the checker, and if anything failed, changes it again with a
  commented-out copy of the original line above it. Something must still fail.
  A reader added next year is probed the day it lands, which is the point —
  four of these were found by hand, and the fifth was found by the generator
  on its first run, in a file the hand audit had already been through.

  The same machinery answers a blunter question: how much of the theme is
  actually pinned? `--report-unpinned` changes each colour to another
  *documented* colour and reports where nothing failed. 255 of 568 do not — which is not all wrong, a
  colour with no counterpart in another tool has nothing to be pinned to — but
  it is the honest number, and it is where the next check should come from.
  `.zshrc` was 32 of its 41 until the command line got tied to the table above;
  it is 1 now. `theme.sh`'s palette was 28 of 28 and is 8, the doctor's swatch
  block 13 of 13 and is 1, starship's `[palettes.tokyonight]` 11 of 16 and is 0.
  Those three and the shell palette are the same shape — a name the palette
  already defines, beside a hex — and one check reads all four.

  Every colour on a line is counted, not the first: fzf's options put four on
  one line, and testing only the leading one left the other three unmeasured —
  which is how `theme.sh` read as 8 of 8 loose while its fzf pointer was
  already pinned as a shared role. Only colours a tool will actually read are
  counted. An earlier version of the
  report included hexes sitting in trailing comments — `lf`'s colours file and
  both search pickers write their real values as decimal SGR and name the hex
  only in the comment beside it — which inflated both halves of the fraction by
  37. The probe and the report share one enumeration now, so they cannot
  disagree about what counts.

  The number does not always move when a check lands, and that is worth
  knowing before chasing it. Binding delta's diff tints to the tint tables
  changed nothing in the count, because Neovim's inline diff already held them
  — they were pinned to another config rather than to the decision. Anchoring
  them to the doc is still the better arrangement (two configs can drift
  together; the doc is where the choice was made), but it bought no new
  coverage, and the honest count says so.

  It samples one colour per file by default and sweeps every one under
  `--probe-comments` — worth running after adding a check, because the sample
  found one fooled reader and the full sweep found five more in a single file.
  It works on a copy of the tree, never the tree itself. `THEME_CHECK_NO_TOOLS=1` exists for it: the external
  oracles are 2.2 of the 2.3 seconds a run costs, and the probe needs only the
  readers.

- **contrast** — every foreground/background pair clears the floor for the job
  it does, and every focused fill stands off the page behind it. The tiers, and
  why they are not simply WCAG AA, are in the script.

  Two lists feed it. One is written by hand and says what each pair is *for*,
  which is the only way a deliberately quiet pair — an inactive tab label — can
  be held to a lower floor than body text. The other is derived: yazi, `lf`'s
  colours file and `.tmux.conf` each state a foreground against a background,
  so all 44 of those pairs are read off the files and held to 4.5:1 without
  anyone listing them. The hand-written tier wins wherever both apply.

  Each needs its own reader — a TOML table, a raw SGR sequence, tmux style
  segments — and tmux has to be read per segment rather than per line, because
  `window-status-current-format` sets three `#[...]` blocks in a row and pairing
  the first foreground with the first background would invent a combination that
  is never drawn.


  `btop` and `lazygit` state their pairs by *naming* rather than adjacency —
  `theme[selected_fg]` and `theme[selected_bg]` sit a dozen lines apart, and
  `cherryPickedCommitFgColor` has a matching `BgColor`. The shared key stem is
  what joins them, so a line-based reader saw none of those six.

  A further source has no file to read at all: `LS_COLORS`, `EZA_COLORS` and
  `GREP_COLORS` are assembled from palette variables, so a pair in them only
  exists once `theme.sh` has been sourced. Most of what is there is mirrored in
  `lf`'s colours file and kept honest by the parity check — which is why the
  sticky bug could not have hidden in the exports alone — but eza has keys `lf`
  has no equivalent for, and a pair written under one of those has nothing to
  disagree with. Those are sourced and measured too.

  The derived half exists because the hand-written half had covered 6 of yazi's
  16 real pairs, and sticky directories — `#c0caf5` on `#7aa2f7`, **1.56:1**,
  the least readable thing in the repository — were in the other ten. What hid
  it was agreement: yazi, `lf` and `LS_COLORS` all said the same unreadable
  thing, so the parity check was satisfied and nothing else had an opinion.
  Sticky now matches what `setuid`, `setgid` and `sticky+other-writable`
  already did — `#16161e` on the accent, 7.14:1 — which was the established
  pattern in this repo for a badge on a coloured fill, applied everywhere
  except the one place it was needed most.
