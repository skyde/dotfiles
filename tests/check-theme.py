#!/usr/bin/env python3
"""Check that the Tokyo Night theme is consistent across every tool that wears it.

    tests/check-theme.py              # all checks
    tests/check-theme.py palette      # only one check
    tests/check-theme.py --verbose    # also print what passed

The theme is spread over a dozen config files in four different syntaxes, and
nothing in any of them refers to any other. Every "keep these in sync" comment
in the tree is a promise a human has to keep by hand, which is exactly the kind
of promise that quietly stops being true. These three checks turn those
comments into something that fails loudly instead.

  palette   Every colour literal in a themed config is one that
            docs/tokyonight.md names. A hex that appears nowhere in the doc is
            either drift or an undocumented deliberate choice; both want
            fixing, one in the config and one in the doc.

  parity    The mirrors actually mirror. kitty, wezterm and the VS Code
            integrated terminal each carry their own copy of the 16 ANSI
            slots; lf and yazi each carry their own copy of the per-extension
            file colours. Nothing but this check couples them.

  contrast  Every foreground/background pair the theme puts on screen clears
            the floor for what that pair is *for* (see TIERS). This is what
            stops "muted" from sliding into "invisible" one plausible shade at
            a time.

The file list is not hardcoded: it is read out of the "Where the theme lives"
table at the bottom of docs/tokyonight.md. Theme a new tool, add its row to
that table, and it is covered from then on.
"""

import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = os.path.join(REPO, "docs", "tokyonight.md")

HEX = re.compile(r"#[0-9a-fA-F]{6}\b")

# Short names for the configs the contrast table points at.
KITTY = "common/.config/kitty/themes/tokyonight_night.conf"
TMUX = "common/.tmux.conf"
STARSHIP = "common/.config/starship.toml"
SHELL = "common/.config/shell/theme.sh"
GIT = "common/.config/git/config"
LAZYGIT = "common/.config/lazygit/config.yml"
YAZI = "common/.config/yazi/theme.toml"
BTOP = "common/.config/btop/themes/tokyo-night.theme"


def norm(hexstr):
    """Lowercase a #rrggbb. kitty writes #FF5000 and wezterm writes #ff5000."""
    return hexstr.lower()


# --------------------------------------------------------------------------
# The documented palette
# --------------------------------------------------------------------------


def read_doc():
    with open(DOC, encoding="utf-8") as fh:
        return fh.read()


def documented_colours(doc):
    """Every hex the palette doc mentions, mapped to the names it gives them.

    Deliberately generous about *where* in the doc a colour appears: the
    palette tables, the bright-ANSI prose line, and the notes about local
    deviations are all equally binding. The rule being enforced is "a colour
    a config uses is a colour the doc accounts for", and a colour explained in
    a paragraph is accounted for just as well as one sitting in a table.
    """
    names = {}
    for line in doc.splitlines():
        # Table rows look like: | `yellow` | `#e0af68` | warnings, modified |
        cells = [c.strip().strip("`") for c in line.split("|")]
        row_name = cells[1] if len(cells) > 2 else ""
        for found in HEX.findall(line):
            key = norm(found)
            label = row_name if row_name and not HEX.match(row_name) else ""
            names.setdefault(key, set())
            if label:
                names[key].add(label)
    return names


def themed_files(doc):
    """The files listed in the doc's "Where the theme lives" table.

    Only rows whose path exists are returned: the table also documents files
    for tools that a given checkout may not carry.
    """
    files = []
    for line in doc.splitlines():
        cells = [c.strip() for c in line.split("|")]
        if len(cells) < 3:
            continue
        # The path cell may list two files ("theme.toml`, `plugins/...").
        for path in re.findall(r"`([^`]+)`", cells[2]):
            # Rows like "(the `# Theme` section)" carry parentheticals that are
            # not paths; a real row always names something under common/.
            if not path.startswith("common/"):
                continue
            full = os.path.join(REPO, path)
            if os.path.isfile(full) and full not in files:
                files.append(full)
    return files


# --------------------------------------------------------------------------
# check: palette
# --------------------------------------------------------------------------

# Colours that do not appear as #rrggbb. lf writes LS_COLORS truecolor escapes
# and ripgrep takes decimal triplets, so both would otherwise sail past a hex
# scanner untouched — which is how ripgrep's match colour drifted a full shade
# off the palette and stayed there.
DECIMAL_TRIPLE = re.compile(r"(?:38|48);2;(\d{1,3});(\d{1,3});(\d{1,3})")
RG_COLOR = re.compile(r"--colors=\w+:(?:fg|bg):(\d{1,3}),(\d{1,3}),(\d{1,3})")


def colours_in(path):
    """Yield (lineno, hex, raw) for every colour literal in a config file."""
    with open(path, encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            # Strip trailing comments before scanning: the configs annotate
            # their escape sequences with the hex they encode ("# yellow
            # #e0af68"), and counting those as uses would make every file
            # trivially self-consistent.
            code = line.split("#", 1)[0] if _comment_leads(path) else line
            for found in HEX.findall(line if not _comment_leads(path) else code):
                yield lineno, norm(found), found
            for r, g, b in DECIMAL_TRIPLE.findall(code):
                yield lineno, "#%02x%02x%02x" % (int(r), int(g), int(b)), \
                    "38;2;%s;%s;%s" % (r, g, b)
            for r, g, b in RG_COLOR.findall(code):
                yield lineno, "#%02x%02x%02x" % (int(r), int(g), int(b)), \
                    "%s,%s,%s" % (r, g, b)


def _comment_leads(path):
    """True for files where `#` starts a comment rather than a colour.

    Only matters for the decimal-escape formats, where a line's real colour is
    a run of digits and its comment names the equivalent hex. In hex-carrying
    files `#` is the colour, so nothing may be stripped.
    """
    return os.path.basename(path) in ("colors", ".ripgreprc")


def check_palette(doc, verbose):
    known = documented_colours(doc)
    problems = []
    for path in themed_files(doc):
        rel = os.path.relpath(path, REPO)
        seen = 0
        for lineno, hexval, raw in colours_in(path):
            seen += 1
            if hexval not in known:
                problems.append(
                    "%s:%d: %s is not a colour docs/tokyonight.md names%s"
                    % (rel, lineno, raw, _nearest(hexval, known))
                )
        if verbose:
            print("  %-58s %3d colours" % (rel, seen))

    problems.extend(_check_shell_exports(known, verbose))
    return problems


# The shell's colours are assembled from palette variables rather than written
# out, which is what makes them readable -- and what makes a plain text scan
# useless on them: the file says "38;2;$_tn_yellow", not a colour. So run it
# and look at what actually comes out the other side. This is the only check
# that sees the values ls, eza, grep and man are really handed.
SHELL_EXPORTS = [
    "LS_COLORS", "EZA_COLORS", "GREP_COLORS",
    "LESS_TERMCAP_md", "LESS_TERMCAP_mb", "LESS_TERMCAP_us", "LESS_TERMCAP_so",
    "ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE",
]


def _check_shell_exports(known, verbose):
    import subprocess

    path = os.path.join(REPO, "common/.config/shell/theme.sh")
    script = '. "$1"; for v in %s; do eval "printf \'%%s\\n\' \\"\\$$v\\""; done' \
        % " ".join(SHELL_EXPORTS)
    try:
        out = subprocess.run(["bash", "-c", script, "_", path],
                             capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as exc:
        return ["could not source theme.sh: %s" % exc]
    if out.returncode != 0:
        return ["theme.sh failed to source: %s" % out.stderr.strip()]

    problems = []
    seen = 0
    for name, value in zip(SHELL_EXPORTS, out.stdout.split("\n")):
        found = set()
        for r, g, b in DECIMAL_TRIPLE.findall(value):
            found.add("#%02x%02x%02x" % (int(r), int(g), int(b)))
        found.update(norm(h) for h in HEX.findall(value))
        seen += len(found)
        for colour in sorted(found):
            if colour not in known:
                problems.append(
                    "$%s exports %s, which docs/tokyonight.md does not name%s"
                    % (name, colour, _nearest(colour, known))
                )
    if verbose:
        print("  %-58s %3d colours" % ("(sourced) $LS_COLORS and friends", seen))
    return problems


def _nearest(hexval, known):
    """Suggest the closest documented colour, so the fix is obvious.

    Plain RGB distance. A perceptual metric would rank these better in theory,
    but every real case here is a near-miss of one specific palette entry, and
    for those the two agree.
    """

    def rgb(h):
        return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))

    target = rgb(hexval)
    best, dist = None, None
    for cand in known:
        d = sum((a - b) ** 2 for a, b in zip(target, rgb(cand)))
        if dist is None or d < dist:
            best, dist = cand, d
    if best is None or dist > 3000:
        return ""
    label = sorted(known[best])
    return " (did you mean %s%s?)" % (best, " / " + label[0] if label else "")


# --------------------------------------------------------------------------
# check: parity
# --------------------------------------------------------------------------

ANSI_NAMES = [
    "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
    "bright black", "bright red", "bright green", "bright yellow",
    "bright blue", "bright magenta", "bright cyan", "bright white",
]


def kitty_colours():
    path = os.path.join(REPO, "common/.config/kitty/themes/tokyonight_night.conf")
    out = {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            m = re.match(r"\s*(\w+)\s+(#[0-9a-fA-F]{6})", line)
            if m:
                out[m.group(1)] = norm(m.group(2))
    ansi = [out.get("color%d" % i) for i in range(16)]
    return ansi, out


def wezterm_colours():
    path = os.path.join(REPO, "common/.config/wezterm/wezterm.lua")
    raw = open(path, encoding="utf-8").read()
    # Strip Lua comments before reading the ANSI blocks. The comment above
    # `brights` names both the upstream bright-black and the one we use
    # instead, and counting those as entries shifts every slot after it by
    # two -- reported as eight separate mismatches that were really one
    # parser bug.
    text = re.sub(r"--[^\n]*", "", raw)

    def block(key):
        m = re.search(key + r"\s*=\s*\{(.*?)\}", text, re.S)
        return [norm(h) for h in HEX.findall(m.group(1))] if m else []

    ansi = block("ansi") + block("brights")
    scalars = dict(
        (k, norm(v))
        for k, v in re.findall(r"(\w+)\s*=\s*'(#[0-9a-fA-F]{6})'", text)
    )
    # The tab entries nest, and every one of them spells its keys the same
    # way, so a flat scan would have active_tab and inactive_tab overwrite
    # each other. Read each sub-table under its own name instead.
    for tab in ("active_tab", "inactive_tab"):
        m = re.search(tab + r"\s*=\s*\{(.*?)\}", text, re.S)
        if m:
            for k, v in re.findall(r"(\w+)\s*=\s*'(#[0-9a-fA-F]{6})'", m.group(1)):
                scalars["%s.%s" % (tab, k)] = norm(v)
    return ansi, scalars


def vscode_colours():
    path = os.path.join(REPO, "common/.config/Code/User/settings.json")
    text = open(path, encoding="utf-8").read()
    got = dict(
        (k, norm(v))
        for k, v in re.findall(r'"([\w.]+)"\s*:\s*"(#[0-9a-fA-F]{6})"', text)
    )
    keys = [
        "terminal.ansiBlack", "terminal.ansiRed", "terminal.ansiGreen",
        "terminal.ansiYellow", "terminal.ansiBlue", "terminal.ansiMagenta",
        "terminal.ansiCyan", "terminal.ansiWhite",
        "terminal.ansiBrightBlack", "terminal.ansiBrightRed",
        "terminal.ansiBrightGreen", "terminal.ansiBrightYellow",
        "terminal.ansiBrightBlue", "terminal.ansiBrightMagenta",
        "terminal.ansiBrightCyan", "terminal.ansiBrightWhite",
    ]
    return [got.get(k) for k in keys], got


def _check_ls_colors(lf_entries):
    """Compare the LS_COLORS theme.sh exports against lf's own table."""
    import subprocess

    path = os.path.join(REPO, "common/.config/shell/theme.sh")
    try:
        out = subprocess.run(
            ["bash", "-c", '. "$1"; printf %s "$LS_COLORS"', "_", path],
            capture_output=True, text=True, timeout=30,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return ["could not source theme.sh to read LS_COLORS: %s" % exc]
    if out.returncode != 0:
        return ["theme.sh failed to source: %s" % out.stderr.strip()]

    shell = {}
    for entry in out.stdout.split(":"):
        if "=" in entry:
            key, val = entry.split("=", 1)
            shell[key] = val

    problems = []
    for key in sorted(set(lf_entries) | set(shell)):
        if key not in shell:
            problems.append("%s is in lf/colors but not in theme.sh's LS_COLORS"
                            % key)
        elif key not in lf_entries:
            problems.append("%s is in theme.sh's LS_COLORS but not in lf/colors"
                            % key)
        elif lf_entries[key] != shell[key]:
            problems.append(
                "%s is %s in lf/colors but %s in theme.sh's LS_COLORS"
                % (key, lf_entries[key], shell[key])
            )
    return problems


def check_parity(doc, verbose):
    problems = []

    kitty_ansi, kitty = kitty_colours()
    wez_ansi, wez = wezterm_colours()
    code_ansi, code = vscode_colours()

    # The 16 ANSI slots, three ways. Every CLI tool that does not carry its own
    # truecolour theme -- git's own output, ls, grep, anything printing bare
    # SGR codes -- is themed *entirely* by these, so a slot that disagrees
    # between terminals is a tool that changes colour when you change window.
    for i, name in enumerate(ANSI_NAMES):
        trio = {
            "kitty": kitty_ansi[i],
            "wezterm": wez_ansi[i] if i < len(wez_ansi) else None,
            "vscode": code_ansi[i],
        }
        if len(set(v for v in trio.values() if v)) > 1:
            problems.append(
                "ANSI %d (%s) disagrees: %s"
                % (i, name, ", ".join("%s=%s" % kv for kv in sorted(trio.items())))
            )

    # The surfaces around the grid. Same argument: these are one visual
    # surface that happens to be configured in three files. `None` means the
    # tool has no such setting and simply sits the comparison out -- VS Code
    # draws its own tabs, so it has no say in the terminal tab bar.
    for label, k, w, c in [
        ("background", "background", "background", "terminal.background"),
        ("foreground", "foreground", "foreground", "terminal.foreground"),
        ("cursor", "cursor", "cursor_bg", "terminalCursor.foreground"),
        ("cursor text", "cursor_text_color", "cursor_fg", "terminalCursor.background"),
        ("selection bg", "selection_background", "selection_bg",
         "terminal.selectionBackground"),
        ("active tab bg", "active_tab_background", "active_tab.bg_color", None),
        ("active tab fg", "active_tab_foreground", "active_tab.fg_color", None),
        ("inactive tab bg", "inactive_tab_background", "inactive_tab.bg_color", None),
        ("inactive tab fg", "inactive_tab_foreground", "inactive_tab.fg_color", None),
    ]:
        trio = {
            "kitty": kitty.get(k),
            "wezterm": wez.get(w),
            "vscode": code.get(c) if c else None,
        }
        if len(set(v for v in trio.values() if v)) > 1:
            problems.append(
                "%s disagrees: %s"
                % (label, ", ".join("%s=%s" % kv for kv in sorted(trio.items())))
            )

    # lf and yazi are two views of the same directory. A .zip that is red in
    # one and orange in the other is worse than either choice alone.
    lf_entries = {}
    lf_map = {}
    lf_path = os.path.join(REPO, "common/.config/lf/colors")
    with open(lf_path, encoding="utf-8") as fh:
        for line in fh:
            code = line.split("#")[0].strip()
            if code:
                bits = code.split(None, 1)
                if len(bits) == 2:
                    lf_entries[bits[0]] = bits[1].strip()
            m = re.match(r"(\*\.\w+)\s+(?:38|48);2;(\d+);(\d+);(\d+)", line)
            if m:
                lf_map[m.group(1)] = "#%02x%02x%02x" % tuple(
                    int(m.group(i)) for i in (2, 3, 4)
                )

    # lf's config *is* an LS_COLORS table, so the shell exports the same data
    # to ls, eza and the zsh completion menu. It is spelled out a second time
    # in theme.sh rather than read from this file, to keep a `cat` off the
    # startup path of every non-interactive shell -- which only stays honest
    # if something compares the two. Sourcing the file is also the only check
    # that it is still valid shell.
    problems.extend(_check_ls_colors(lf_entries))

    yazi_map = {}
    yazi_path = os.path.join(REPO, "common/.config/yazi/theme.toml")
    with open(yazi_path, encoding="utf-8") as fh:
        for line in fh:
            m = re.search(r'name\s*=\s*"(\*\.\w+)"\s*,\s*fg\s*=\s*"(#[0-9a-fA-F]{6})"',
                          line)
            if m:
                yazi_map[m.group(1)] = norm(m.group(2))

    for ext in sorted(set(lf_map) & set(yazi_map)):
        if lf_map[ext] != yazi_map[ext]:
            problems.append(
                "%s is %s in lf but %s in yazi" % (ext, lf_map[ext], yazi_map[ext])
            )

    # Yazi matches images, video and audio by mime type rather than extension,
    # so those are legitimately in lf's list and not yazi's. Everything else
    # being in one list only is an omission.
    MIME_COVERED = {
        "*.png", "*.jpg", "*.jpeg", "*.gif", "*.webp", "*.svg", "*.ico",
        "*.mp4", "*.mkv", "*.mov", "*.webm",
        "*.mp3", "*.flac", "*.wav", "*.m4a", "*.ogg",
        "*.pdf", "*.epub",
    }
    for ext in sorted(set(lf_map) - set(yazi_map) - MIME_COVERED):
        problems.append("%s is coloured in lf but not in yazi" % ext)
    for ext in sorted(set(yazi_map) - set(lf_map)):
        problems.append("%s is coloured in yazi but not in lf" % ext)

    if verbose:
        print("  16 ANSI slots x 3 terminals, %d shared file extensions"
              % len(set(lf_map) & set(yazi_map)))
    return problems


# --------------------------------------------------------------------------
# check: contrast
# --------------------------------------------------------------------------

# What a pair is *for* decides how much contrast it owes. Holding the whole
# theme to WCAG AA would be wrong in both directions: it would fail comments
# and ghost text, which are quiet on purpose, while passing a border that is
# too bright. So each pair below declares its job, and owes that job's floor.
#
#   text   4.5  You read it: file contents, prompts, values, messages.
#   ui     3.0  You scan it: tab labels, headers, status fields, keys.
#   muted  2.5  Deliberately receding: comments, ghost text, inactive detail,
#               line numbers. Still has to be legible when you look straight
#               at it -- that is what separates 2.5 from the 1.7 that made
#               tmux's hostname field a rumour.
#
# Anything below 2.5 is a decoration, not text, and is not listed: borders,
# separators and fills are shapes and carry no glyphs.
TIERS = {"text": 4.5, "ui": 3.0, "muted": 2.5}

# (tier, foreground, background, config the pair comes from, what it is)
#
# Naming the config is not documentation, it is enforcement. A hand-written
# table of pairs is only as true as the day it was written, so each row also
# asserts that both of its colours still appear in the file it claims to
# describe. Recolour tmux's hostname and this table stops matching reality
# loudly, instead of going quietly out of date.
#
# The assertion is a floor, not a ceiling: it cannot tell that two colours in
# the same file are used *together*, and in a config that declares a whole
# palette up front (starship) it is nearly free. It still catches the case
# that actually happens, which is a value being changed in place.
PAIRS = [
    # kitty / wezterm chrome
    ("text", "#c0caf5", "#1a1b26", KITTY, "terminal body text"),
    ("text", "#16161e", "#7aa2f7", KITTY, "kitty active tab label"),
    ("ui", "#737aa2", "#292e42", KITTY, "kitty inactive tab label"),
    ("text", "#c0caf5", "#2e3c64", KITTY, "terminal selection"),
    ("ui", "#000000", "#ff5000", KITTY, "cursor glyph under the block cursor"),
    ("muted", "#85899c", "#1a1b26", KITTY, "ANSI 8, de-emphasised CLI output"),

    # tmux status line
    ("ui", "#ff9e64", "#1a1b26", TMUX, "tmux session name"),
    ("muted", "#565f89", "#1a1b26", TMUX, "tmux status base text"),
    ("muted", "#737aa2", "#1a1b26", TMUX, "tmux hostname"),
    ("ui", "#7aa2f7", "#3b4261", TMUX, "tmux current window index"),
    ("ui", "#7aa2f7", "#1a1b26", TMUX, "tmux current window name"),
    ("muted", "#545c7e", "#1a1b26", TMUX, "tmux inactive window index"),
    ("ui", "#a9b1d6", "#1a1b26", TMUX, "tmux inactive window name"),
    ("ui", "#e0af68", "#1a1b26", TMUX, "tmux window with activity"),
    ("ui", "#f7768e", "#1a1b26", TMUX, "tmux window with a bell"),
    ("text", "#e0af68", "#16161e", TMUX, "tmux message"),
    ("text", "#7aa2f7", "#16161e", TMUX, "tmux command prompt"),
    ("text", "#c0caf5", "#283457", TMUX, "tmux copy-mode selection"),
    # `ui`, not `text`, and the tier is the honest one rather than the
    # convenient one. No palette foreground clears 4.5:1 on blue0 -- the best
    # is 4.14 -- so calling this `text` would mean either abandoning the
    # search colour Tokyo Night itself uses (and that Neovim's Search is
    # painted with, which this deliberately mirrors) or picking a cyan-tinted
    # foreground that makes matches read as cyan. Neither is an improvement.
    # It is also the right tier on the merits: the glyphs under a search
    # highlight are a word you just typed, so what you need from the
    # highlight is to *find* it. That number is the fill against the page,
    # 2.56:1, which FILLS below pins.
    ("ui", "#c0caf5", "#3d59a1", TMUX, "tmux copy-mode search match"),
    ("text", "#16161e", "#ff9e64", TMUX, "tmux copy-mode current match"),
    ("text", "#16161e", "#7aa2f7", TMUX, "tmux copy-mode mark"),
    # prefix+q flashes these over each pane; you have about a second to read
    # one and type it.
    ("ui", "#737aa2", "#1a1b26", TMUX, "tmux pane number overlay"),
    ("ui", "#ff9e64", "#1a1b26", TMUX, "tmux active pane number overlay"),

    # starship
    ("muted", "#565f89", "#1a1b26", STARSHIP, "starship clock"),
    ("text", "#7aa2f7", "#1a1b26", STARSHIP, "starship directory"),
    ("text", "#bb9af7", "#1a1b26", STARSHIP, "starship branch"),

    # fzf
    ("text", "#c0caf5", "#283457", SHELL, "fzf current line"),
    ("text", "#1a1b26", "#e0af68", SHELL, "fzf match (reverse video)"),
    ("text", "#283457", "#faba4a", SHELL, "fzf match on the current line"),
    ("muted", "#565f89", "#1a1b26", SHELL, "fzf border label"),
    ("ui", "#7aa2f7", "#1a1b26", SHELL, "fzf prompt"),

    # delta
    # dark3 is the palette's own line-number colour and stays that way: a diff's
    # line numbers are reference you look up, not prose you read.
    ("muted", "#545c7e", "#1a1b26", GIT, "delta line numbers"),
    ("ui", "#7aa2f7", "#1a1b26", GIT, "delta hunk header"),
    ("text", "#c0caf5", "#20432b", GIT, "delta added line"),
    ("text", "#c0caf5", "#532727", GIT, "delta removed line"),
    ("text", "#c0caf5", "#2e2547", GIT, "delta moved-from line"),
    ("text", "#c0caf5", "#12384a", GIT, "delta moved-to line"),
    # The blame stripes cycle four backgrounds; the timestamp has to stay
    # legible on the lightest of them, which is the worst case.
    ("muted", "#737aa2", "#292e42", GIT, "delta blame timestamp, lightest stripe"),

    # lazygit
    ("text", "#c0caf5", "#283457", LAZYGIT, "lazygit selected line"),
    ("text", "#c0caf5", "#1f2335", LAZYGIT, "lazygit selection, unfocused panel"),
    ("ui", "#e0af68", "#1a1b26", LAZYGIT, "lazygit keybinding hints"),

    # yazi
    ("ui", "#737aa2", "#292e42", YAZI, "yazi inactive tab"),
    ("text", "#c0caf5", "#283457", YAZI, "yazi hovered row"),
    ("text", "#c0caf5", "#292e42", YAZI, "yazi hovered row, unfocused pane"),
    ("ui", "#16161e", "#9ece6a", YAZI, "yazi yank counter"),
    ("muted", "#565f89", "#1f2335", YAZI, "yazi which-key remainder"),

    # btop
    ("text", "#c0caf5", "#1a1b26", BTOP, "btop body"),
    ("muted", "#565f89", "#1a1b26", BTOP, "btop inactive text"),
    ("text", "#c0caf5", "#283457", BTOP, "btop selected process"),
]


# A fill has a second job the pairs above cannot see: standing off the page it
# sits on. A selection whose glyphs are perfectly legible is still useless if
# the row it marks looks like every other row.
#
# The floor is 1.35:1, which is just under Tokyo Night's own `bg_visual`
# (1.40:1) and deliberately so. bg_visual is the selection colour in six
# tools here, and moving it would be diverging from Tokyo Night rather than
# improving on it. What the floor is really guarding is the mistake that
# actually happens: reaching for one of the *unfocused* fills -- bg_highlight
# at 1.27, bg_dark1 at 1.10 -- for something that has focus.
#
# Not listed, on purpose: the unfocused fills themselves, which are quiet
# because nothing there has your attention, and delta's diff washes, where the
# non-emphasised remainder of a changed line is meant to nearly vanish.
FILL_FLOOR = 1.35

# (fill, page it sits on, source, what it is)
FILLS = [
    ("#2e3c64", "#1a1b26", KITTY, "terminal selection"),
    ("#283457", "#1a1b26", TMUX, "tmux copy-mode selection"),
    ("#3d59a1", "#1a1b26", TMUX, "tmux copy-mode search match"),
    ("#283457", "#1a1b26", SHELL, "fzf current line"),
    ("#283457", "#1a1b26", YAZI, "yazi hovered row"),
    ("#283457", "#1a1b26", LAZYGIT, "lazygit selected line"),
    ("#283457", "#1a1b26", BTOP, "btop selected process"),
]


def luminance(hexstr):
    parts = [int(hexstr[i:i + 2], 16) / 255.0 for i in (1, 3, 5)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
           for c in parts]
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def ratio(fg, bg):
    a, b = luminance(fg), luminance(bg)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


def check_contrast(doc, verbose):
    problems = []
    known = documented_colours(doc)
    bodies = {}
    for tier, fg, bg, source, what in PAIRS:
        if source not in bodies:
            bodies[source] = open(os.path.join(REPO, source),
                                  encoding="utf-8").read().lower()
        body = bodies[source]

        for colour in (fg, bg):
            if colour not in known:
                problems.append(
                    "%s uses %s, which docs/tokyonight.md does not name"
                    % (what, colour)
                )
            # `bg` is exempt: the terminal background is declared once, by the
            # terminal, and every TUI painting on top of it simply inherits
            # it. Demanding that lazygit's config restate #1a1b26 would only
            # teach people to hardcode a background they should not own.
            if colour != "#1a1b26" and colour not in body:
                problems.append(
                    "%s: %s no longer appears in %s -- either the config "
                    "changed and this row is stale, or the colour is gone"
                    % (what, colour, source)
                )

        got = ratio(fg, bg)
        floor = TIERS[tier]
        if got < floor:
            problems.append(
                "%s: %s on %s is %.2f:1, below the %.1f:1 floor for %s"
                % (what, fg, bg, got, floor, tier)
            )
        elif verbose:
            print("  %6.2f:1  %-5s %s" % (got, tier, what))

    for fill, page, source, what in FILLS:
        body = bodies.setdefault(
            source,
            open(os.path.join(REPO, source), encoding="utf-8").read().lower(),
        )
        if fill not in body:
            problems.append(
                "%s: %s no longer appears in %s" % (what, fill, source)
            )
        got = ratio(fill, page)
        if got < FILL_FLOOR:
            problems.append(
                "%s: the %s fill is only %.2f:1 against the page -- that is an "
                "unfocused fill doing a focused fill's job"
                % (what, fill, got)
            )
        elif verbose:
            print("  %6.2f:1  fill  %s" % (got, what))
    return problems


# --------------------------------------------------------------------------

CHECKS = {
    "palette": check_palette,
    "parity": check_parity,
    "contrast": check_contrast,
}


def main(argv):
    verbose = "--verbose" in argv or "-v" in argv
    wanted = [a for a in argv if not a.startswith("-")] or list(CHECKS)
    unknown = [w for w in wanted if w not in CHECKS]
    if unknown:
        sys.stderr.write("unknown check(s): %s\nknown: %s\n"
                         % (", ".join(unknown), ", ".join(CHECKS)))
        return 2

    doc = read_doc()
    failed = 0
    for name in wanted:
        if verbose:
            print("%s:" % name)
        problems = CHECKS[name](doc, verbose)
        if problems:
            failed += len(problems)
            for p in problems:
                print("FAIL [%s] %s" % (name, p))
        else:
            print("ok   [%s]" % name)
    if failed:
        print("\n%d problem(s)" % failed)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
