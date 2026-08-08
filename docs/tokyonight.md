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
| `terminal_bg`    | `#1d202f` | ANSI 0 in kitty and wezterm               |
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

> **Note on ANSI 8.** kitty, wezterm and VS Code's integrated terminal all use
> `#85899c` instead of the upstream `#414868`. That is deliberate: `#414868` is
> close to unreadable for "bright black" text that CLI tools use for
> de-emphasised output. Keep all **three** terminals in sync — VS Code's is a
> terminal like the other two, running the same tools, and it is the one that
> gets forgotten. `tests/check-theme.py` compares them.

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
gets the same table on Windows, so a pipeline reads the same on both — with
one row that deliberately does not match, noted at the end of this section.

The reason is Ctrl-R. That picker pipes history through `bat`, so the same
command is already being painted in Dark+ one keystroke before it lands on the
prompt; anything else would mean accepting a history entry recoloured it.

| Role                                        | Hex       |
| ------------------------------------------- | --------- |
| plain text, arguments                       | `#d4d4d4` |
| comments                                    | `#6a9955` |
| strings                                     | `#ce9178` |
| commands, functions, aliases, `$(…)`        | `#dcdcaa` |
| subcommands — `git commit`, `docker run`    | `#4ec9b0` |
| control words, precommands, `[[ ]]` `(( ))` | `#c586c0` |
| variables, assignments, interpolation       | `#9cdcfe` |
| globs, case patterns, history expansion     | `#d7ba7d` |
| options                                     | `#569cd6` |
| option values — `--jobs=8`, `-m "msg"`      | string / number colour |
| numbers and file descriptors                | `#b5cea8` |
| redirections, `;` and `\|`                   | `#737aa2` |
| bracket pairs, by nesting depth             | `#ffd700` `#da70d6` `#179fff` |

Two things stay Tokyo Night, because they are facts about the machine rather
than about syntax and Dark+ has no vocabulary for either: a word that resolves
to no command is `red`, and a path that has not resolved to anything yet is
`comment`. A path that *does* exist gets an underline instead of a hue.

Three of those rows are about keeping the line from going flat. **Subcommands**
get the type colour because `git commit` and `docker run` are the most-typed
tokens on the line and had no colour of their own — `fast-syntax-highlighting`
knows them from its per-command grammars, and left unset they fell through to
the plugin's raw ANSI `fg=yellow`. The plugin's built-in grammar list froze
around 2019, so `~/.zshrc` also registers its generic subcommand grammar for
the tools that arrived since (`cargo`, `kubectl`, `gh`, `uv`, the Chromium
checkout's `gn` and `gclient`, …) — one hash entry each, pointing at the same
chroma the built-ins use. **Option values** are the long tail of a long
command — `--target=x86_64-…`, `--jobs=8`, the message after `git commit -m` —
and their two style keys (`optarg-string`, `optarg-number`) are defined by
neither the plugin's defaults nor its default theme, so every one of them
rendered in the terminal's raw foreground. They are literals, and take the
string orange or, when the whole value is digits, the number green. The `=`
form is styled for every command; the free-standing value after an option
only where a grammar declares which options take one. **Plumbing** dropped from `#d4d4d4` to dark5
so that it stops reading level with the words either side of it; that is the
same move the path separators make, and for the same reason. **Bracket pairs**
are VS Code's own bracket-pair-colourisation hues, since the prompt is code.

The rest of the shell's grammar — `case` arms, here-strings, `for` headers,
array subscripts — is named in the table too. Not because each one needs its
own hue, but because *unset is not neutral*: both highlighters ship defaults
for these, and those defaults are ANSI-indexed (`fg=green`, `fg=yellow,bold`)
or outright backgrounds (`bg=blue`, `bg=18`), so anything left out was painted
from a palette this repo does not otherwise use. `tests/check-theme.py` check 8
is what keeps a role from silently going back to one.

One role in that table is not a colour at all. `fast-syntax-highlighting`
keeps a *secondary* style table for anything it treats as an embedded shell —
most visibly the inside of `$(…)` — and ships `secondary` pointing at a theme
it downloads from `raw.githubusercontent.com` the first time a shell starts.
While that switch is armed, the words inside the parentheses are painted from
the downloaded file instead of from the table above — and that file speaks in
256-colour indices, so they land outside the palette entirely:

```
before   x=$(git rev-parse HEAD)     git fg=180 #d7af87 · rev-parse fg=150 #afd787
after    x=$(git rev-parse HEAD)     git #dcdcaa · rev-parse #4ec9b0 · HEAD #9cdcfe
```

Emptying `secondary` stops the switch, and a nested command reads exactly like
a top-level one. `~/.zshrc` also pins `FAST_WORK_DIR` and leaves an empty
`secondary_theme.zsh` in it, so the download — now never read — is not part of
opening a shell. On a cold cache the difference is a 3.4 KB fetch from GitHub
during startup versus none.

> Worth knowing when checking this by hand: if `secondary_theme.zsh` exists but
> is **empty** — which is exactly what `~/.zshrc` now leaves behind — the
> switch still happens but finds no `free*` keys, and the body comes out one
> flat run of `#9cdcfe` rather than in 256-colour indices. Two different wrong
> answers from the same mechanism, depending on cache state. Delete the whole
> work dir before measuring, or a warm cache will tell you a different story
> than a cold one.

One thing the table cannot reach, so as not to go looking for it later: the
awk program inside `awk '{print $1}'`. `→chroma/-awk.ch` is the only chroma
that builds a style by pasting two table entries together with a comma — it
joins `reserved-word` (or `mathnum`, for a number) to a second style chosen by
whether the program parses. Which of the two it picks decides whether the
result is legal:

- **program accepts** → the second style is `subtle-bg`, so `print` in
  `awk '{print 1}'` is asked for `fg=#c586c0,bg=#292e42`. A foreground and a
  background: perfectly valid, and it renders as intended, the program sitting
  on a slightly raised ground.
- **program rejects** → the second style is `incorrect-subtle`, so the same
  word is asked for `fg=#c586c0,fg=#f7768e`. Two foregrounds, and zsh resolves
  a doubled `fg=` to a colour that is neither — it lands near `#f7f6ce`.

**The row that does not cross to Windows.** Redirections and separators drop
to dark5 in zsh, and the obvious mirror in PSReadLine is `Operator` — but
PSReadLine spends `Operator` only on tokens the PowerShell parser flags as
unary, binary or assignment operators, and `|` and `>` are neither
(`TokenKind.Pipe`, `TokenKind.Redirection`); both fall to `Default`. Moving
`Operator` would therefore recolour `-eq`, `=` and `+` — which zsh paints from
other roles — without touching a pipeline at all. So it stays `#d4d4d4`, and
the Windows prompt keeps its joints level with its words until someone can
check the mapping against a real PSReadLine.

The catch with awk is what does the accepting: the chroma shells out to **`gawk`**
specifically. On a machine with only `mawk` or BSD awk the test can never
succeed, so *every* awk program takes the reject branch and the whole program
is painted as though it were malformed. That is the usual reason this looks
broken. Installing `gawk` is the actual fix; no value in this table reaches
it, and the shell *around* the string is unaffected either way.

> **Two Dark+ variants are in play, on purpose.** These are bat's built-in
> `Visual Studio Dark+`. The editor side — Neovim's `lua/util/vscode_syntax.lua`
> — mirrors `Visual Studio Dark - C++` plus the token overrides in the VS Code
> settings, which resolves some of the same roles to different hexes (strings
> are `#dfa67c` there, comments `#7a987a`). Each side matches the thing it sits
> next to: the prompt matches the picker above it, the buffer matches VS Code.
> See `docs/vscode-syntax-parity.md`.

### Markdown in the terminal: `glow`

`glow` is the one place where the chrome/code split happens *inside a single
document*, so it is worth being explicit about where the line falls.

Headings, links, block quotes, rules, tables and the inline-code chip are
chrome, and take Tokyo Night. `h1` is `bg_dark` on `blue`, which is the same
pair kitty gives its active tab; a link is `green1`, which is kitty's
`url_color`; the rule is `fg_gutter`, the separator colour.

A fenced block is code, so it takes Dark+ — and specifically **bat's** Dark+,
not the published values in the command-line table above. `bat README.md`
highlights the fence contents too, with the syntax it detects from the info
string, so glow and bat are two ways of looking at the same file in the same
terminal. That is the "two panes rendering the same file differently" case, and
it is the one place in the setup where bat's port is the right one to copy.

Two things about the result are worth knowing before you go looking for a bug:

- **Code blocks are 256-colour.** glamour hardcodes
  `chromaFormatter = "terminal256"` and glow never calls
  `WithChromaFormatter`, so the chroma table is rounded to the cube on the way
  out — `#569cd6` renders as `#5fafd7`. Nothing in the config can reach 24-bit
  there. The markdown chrome around it is true 24-bit. If glamour ever picks
  the formatter from the colour profile, these values become exact for free.
- **A few chrome colours come out one unit low.** Sweeping all 256 byte values
  through glow, 24 of them lose one: `33+4k`, `66+8k` and `132+16k` for
  `k = 0..7`. So `#7aa2f7` arrives as `#79a2f7` and `#292e42` as `#282e41`.
  It is a rounding artefact in glow's colour layer, it is invisible, and it is
  not the config drifting — do not "correct" the style file to chase it.

The style is pointed at by `GLOW_STYLE` in `theme.sh` rather than by `style` in
`glow.yml`, because a path in the config file does not work. `glow.yml` carries
the explanation.

Those Dark+ values are bat's, and four of them are not the ones the
command-line table above carries — that table is VS Code's *published* Dark+,
and bat's compiled port resolves some roles a few units away. Measured by
rendering shell, Python, C++ and JSON through
`bat --theme="Visual Studio Dark+"`, identically on 0.24.0, 0.25.0 and 0.26.1:

| Role                   | bat emits | the command-line table |
| ---------------------- | --------- | ---------------------- |
| plain text             | `#dcdcdc` | `#d4d4d4`              |
| comments               | `#608b4e` | `#6a9955`              |
| strings                | `#d69d85` | `#ce9178`              |
| string escapes         | `#e3bbab` | `#d7ba7d`              |
| commands and functions | `#dcdcaa` | `#dcdcaa`              |
| control words          | `#c586c0` | `#c586c0`              |
| variables              | `#9cdcfe` | `#9cdcfe`              |
| keywords and types     | `#569cd6` | `#569cd6`              |
| numbers                | `#b5cea8` | `#b5cea8`              |

Each side matches the thing it sits next to: the prompt matches the Ctrl-R
picker, the fence matches `bat`.

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
| Neovim   | `common/.config/nvim/lua/plugins/tokyonight.lua`      |
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
| glow     | `common/.config/glow/tokyonight.json`, `common/.config/glow/glow.yml` |
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

It checks eight things:

1. **Every colour is documented here.** Any hex or `38;2;R;G;B` triple in a
   themed config has to appear somewhere in this file. That is what makes this
   document the registry rather than a description that rots.
2. **All three terminals agree**, slot for slot: background, foreground,
   cursor, selection and all sixteen ANSI colours, across kitty, wezterm and
   VS Code's integrated terminal.
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
8. **The command line names every role a highlighter would otherwise colour
   itself.** `_tn_cli_styles` in `~/.zshrc` is compared against the list of
   roles that `fast-syntax-highlighting` and `zsh-syntax-highlighting` give a
   *coloured* default, and the check fails if the table stops naming one or
   names one with anything that is not a palette hex. Roles whose default is
   `none` are deliberately out of scope: they introduce no foreign colour.

The checks are only as good as their scope: `CHROME_FILES` at the top of the
script is the list of files that get checked. Theme something new, add it
there and to the table above.

### The failure the test cannot see: dead keys

`check-theme.py` compares colours. It cannot tell you that a key stopped being
read — a colour nobody reads is still a valid colour, and most of these tools
ignore a key they do not recognise without a word. That failure looks like
nothing at all: the setting is there, spelled correctly, and simply does not
happen any more.

It is worth re-running this audit when a tool is upgraded. Each of the three
below turned up something real:

```bash
# yazi — diff our sections and keys against upstream's preset
curl -fsSL https://raw.githubusercontent.com/sxyazi/yazi/main/yazi-config/preset/theme-dark.toml

# delta — every *-style key it actually defines
curl -fsSL https://raw.githubusercontent.com/dandavison/delta/main/src/cli.rs \
  | grep -oE 'long = "[a-z-]+"' | sort -u

# btop — the key list is its Default_theme map
curl -fsSL https://raw.githubusercontent.com/aristocratos/btop/main/src/btop_theme.cpp \
  | sed -n '/Default_theme/,/};/p' | grep -oE '"\w+"' | sort -u

# lazygit — its published JSON schema is the list
curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazygit/master/schema/config.json
```

What they found: yazi had moved two keys out from under us (see the gotcha
above), delta has no `blame-timestamp-style` and never did, btop left six
process-state colours at hardcoded off-palette fallbacks, and lazygit's
`lightTheme` is gone from both its config struct and its schema. Compare
against the CHANGELOG of the release you are running, not just `main` — an
upstream preset includes renames that have not shipped yet.

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
