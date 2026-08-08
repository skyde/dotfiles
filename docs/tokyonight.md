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
schema. For `[filetype]` rules, `is` accepts exactly `none`, `hidden`, `link`,
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
| git      | `common/.config/git/config` (the `[color "..."]` sections) |
| starship | `common/.config/starship.toml` (`[palettes.tokyonight]`) |
| fzf      | `common/.config/shell/theme.sh`                       |
| ls, eza, grep, man | `common/.config/shell/theme.sh` (`LS_COLORS`, `EZA_COLORS`, `GREP_COLORS`, `LESS_TERMCAP_*`) |
| zsh      | `common/.config/shell/theme.sh` (autosuggestions), `common/.zshrc` (completion menu) |
| zsh syntax | `common/.config/fsh/tokyonight.ini` (fast-syntax-highlighting) |
| PowerShell | `windows/Documents/PowerShell/Microsoft.PowerShell_profile.ps1` (PSReadLine) |
| Hammerspoon | `mac/.hammerspoon/init.lua` (`hs.alert.defaultStyle`) |
| ripgrep  | `common/.ripgreprc`                                   |
| search pickers | `common/.local/bin/st-rg`, `common/.local/bin/st-zoekt` (the awk prefix) |
| yazi     | `common/.config/yazi/theme.toml`, `plugins/bat-preview.yazi/` |
| lf       | `common/.config/lf/colors` (file names), `common/.config/lf/lfrc` (the `# Theme` section), `common/.config/lf/icons` (deliberately colourless) |
| btop     | `common/.config/btop/themes/tokyo-night.theme`        |

`tests/check-theme.py` reads this table to decide what to scan, so a tool is
covered from the moment its row lands here.

**VS Code is the one exception**, and deliberately so. Its chrome lives in
`workbench.colorCustomizations` in `common/.config/Code/User/settings.json` and
follows this palette, but the same file also carries the Dark+ token colours,
the debug inline-value colours and a handful of long-standing personal choices
that are not Tokyo Night — the orange-brown active tab border, the inlay hint
greys. Scanning it whole would report all of those forever, so it is not in the
table. What *must* agree is checked directly instead: the 16 ANSI slots of its
integrated terminal, and its title bar, are compared against kitty and wezterm
by `tests/check-theme.py parity`.

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
  | git | `--get-color` on every `color.*` key | an attribute typo the hex scan cannot see, e.g. `#7aa2f7 blod` |
  | wezterm | `ls-fonts`, which evaluates the config | any colour it cannot parse, by key name — the strictest of them |

  Each of these was added because the one before it found something real.

  Three tools are deliberately absent, so nobody repeats the experiment. **btop**
  loads a theme containing an unknown key without a word — it is not an oracle,
  and the only way to check its theme is to diff the keys against
  `Default_theme` in its `src/btop_theme.cpp`. **lazygit** looks like one
  because it prints `--config`, but that output omits every field with an empty
  default, so real keys appear missing; its schema is the reference, and the
  command for it is in a comment beside the theme block in its config. **eza**
  discards a malformed `EZA_COLORS` code without a word; its key names were
  checked against `man eza_colors` instead.
- **contrast** — every foreground/background pair clears the floor for the job
  it does, and every focused fill stands off the page behind it. The tiers, and
  why they are not simply WCAG AA, are in the script.
