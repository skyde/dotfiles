#!/usr/bin/env python3
"""Check that the Tokyo Night theme is consistent across every tool that wears it.

    tests/check-theme.py              # all checks
    tests/check-theme.py palette      # only one check
    tests/check-theme.py --verbose    # also print what passed
    tests/check-theme.py swatch       # render the theme instead of checking it

The theme is spread over a dozen config files in four different syntaxes, and
nothing in any of them refers to any other. Every "keep these in sync" comment
in the tree is a promise a human has to keep by hand, which is exactly the kind
of promise that quietly stops being true. These three checks turn those
comments into something that fails loudly instead.

  palette   Every colour literal in a themed config is one that
            docs/tokyonight.md names. A hex that appears nowhere in the doc is
            either drift or an undocumented deliberate choice; both want
            fixing, one in the config and one in the doc.

  parity    The mirrors actually mirror, and the tools agree they exist.
            kitty, wezterm and the VS Code integrated terminal each carry
            their own copy of the 16 ANSI slots and of the window titlebar;
            lf, yazi and the LS_COLORS the shell exports each carry their own
            copy of the per-extension file colours; Neovim's inline diff and
            delta paint the same diff from two different files. theme.sh is
            sourced in both bash and zsh and the results compared, because
            `$var:s` means something in one of them and not the other. And
            where a tool can be asked about its own options -- delta, ripgrep
            -- it is, since a config section will hold a misspelled key
            forever without complaining.

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
        # but the derived-colour tables put the hex first instead, so take the
        # label from the first cell that is not itself a colour rather than
        # from a fixed column.
        cells = [c.strip().strip("`") for c in line.split("|")]
        label = ""
        for cell in cells[1:3]:
            if cell and not HEX.match(cell) and not set(cell) <= set("-: "):
                label = cell
                break
        # A row's label belongs to the colour sitting in its own cell, not to
        # every colour the row happens to mention: the cursor row names both
        # the black glyph it is about and the orange it sits on.
        owned = {norm(c) for c in cells if HEX.fullmatch(c)}
        for found in HEX.findall(line):
            key = norm(found)
            names.setdefault(key, set())
            if label and key in owned:
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


# Everything theme.sh exports, for the shell-parity check below.
THEME_EXPORTS = [
    "LS_COLORS", "EZA_COLORS", "GREP_COLORS", "GROFF_NO_SGR",
    "LESS_TERMCAP_md", "LESS_TERMCAP_mb", "LESS_TERMCAP_me",
    "LESS_TERMCAP_us", "LESS_TERMCAP_ue", "LESS_TERMCAP_so", "LESS_TERMCAP_se",
    "ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE", "FZF_DEFAULT_OPTS", "FZF_HISTORY_PREVIEW",
]


def _read_exports(shell, path):
    """Source theme.sh in one shell and return what it exported."""
    import subprocess

    script = '. "$1"; for v in %s; do eval "printf \'%%s\\034\' \\"\\$$v\\""; done' \
        % " ".join(THEME_EXPORTS)
    argv = [shell, "-c", script, "_", path]
    if shell == "zsh":
        # -f skips the user's own rc files, which would otherwise set some of
        # these themselves and mask a difference.
        argv = [shell, "-fc", script, "_", path]
    out = subprocess.run(argv, capture_output=True, text=True, timeout=30)
    if out.returncode != 0 or out.stderr.strip():
        raise RuntimeError("%s: %s" % (shell, out.stderr.strip() or "non-zero exit"))
    return dict(zip(THEME_EXPORTS, out.stdout.split("\034")))


def _check_shell_parity(verbose):
    """theme.sh says the two shells "cannot drift". Find out.

    Worth a check of its own because the two shells disagree in ways that are
    invisible in the one you happen to test in. zsh treats `$var:s` as a
    history modifier, so `38;2;$_tn_yellow:so=...` -- perfectly ordinary text
    to bash -- is a parse error there, and LS_COLORS came out empty in the
    shell this file actually runs in.
    """
    import shutil

    if shutil.which("zsh") is None:
        if verbose:
            print("  zsh not installed, shell parity not checked")
        return []

    path = os.path.join(REPO, "common/.config/shell/theme.sh")
    try:
        bash = _read_exports("bash", path)
        zsh = _read_exports("zsh", path)
    except (OSError, RuntimeError) as exc:
        return ["theme.sh does not source cleanly: %s" % exc]

    problems = []
    for name in THEME_EXPORTS:
        if bash.get(name) != zsh.get(name):
            problems.append(
                "$%s differs between the shells: bash gives %r, zsh gives %r"
                % (name, (bash.get(name) or "")[:60], (zsh.get(name) or "")[:60])
            )
    if verbose and not problems:
        print("  %d exported values identical in bash and zsh" % len(THEME_EXPORTS))
    return problems


def _check_delta_options(verbose):
    """Ask delta whether every key under [delta] is an option it has.

    Worth doing because a git config section is a dumping ground: git stores
    whatever you write there and delta reads the keys it recognises, so a name
    that is subtly wrong is not an error, it is a setting that never applies.
    This config carried `blame-timestamp-style` for a long time -- a name that
    reads exactly like the real ones around it, and that delta has never had.

    delta's --help is not a usable list (it summarises), but the binary itself
    is a perfect oracle: it rejects an unknown flag by name. Only that specific
    complaint counts, so a key delta knows but dislikes the *value* of does not
    turn into a false positive here.
    """
    import shutil
    import subprocess

    if shutil.which("delta") is None:
        if verbose:
            print("  delta not installed, its option names not checked")
        return []

    cfg = open(os.path.join(REPO, GIT), encoding="utf-8").read()
    section = re.search(r"^\[delta\]\n(.*?)(?=^\[)", cfg, re.M | re.S)
    if not section:
        return ["no [delta] section found in %s" % GIT]

    problems = []
    checked = 0
    for key, value in re.findall(r"^\s*([a-z0-9-]+)\s*=\s*(.*)$",
                                 section.group(1), re.M):
        checked += 1
        value = value.split("#")[0].strip().strip('"')
        try:
            out = subprocess.run(
                ["delta", "--%s=%s" % (key, value)],
                input="", capture_output=True, text=True, timeout=15,
            )
        except (OSError, subprocess.SubprocessError):
            continue
        if "unexpected argument" in out.stderr and key in out.stderr:
            problems.append(
                "delta has no --%s: it is set in %s and has never applied"
                % (key, GIT)
            )
    if verbose and not problems:
        print("  %d [delta] keys are options delta actually has" % checked)
    return problems


# Neovim's inline diff renders the same thing delta does, and its own header
# comment says so pair by pair -- "InlineDiffAdd / plus-style", "InlineDiffMovedAdd
# / map-styles cyan". That table is the promise; this is the part that keeps it.
# Two files, two languages, no reference between them.
NVIM_INLINE_DIFF = "common/.config/nvim/lua/util/inline_diff.lua"
NVIM_DELTA_PAIRS = [
    ("InlineDiffAdd", "plus-style"),
    ("InlineDiffAddDim", "plus-non-emph-style"),
    ("InlineDiffAddEmph", "plus-emph-style"),
    ("InlineDiffDelete", "minus-style"),
    ("InlineDiffDeleteDim", "minus-non-emph-style"),
    ("InlineDiffDeleteEmph", "minus-emph-style"),
    ("InlineDiffWsError", "whitespace-error-style"),
]
# The two move colours come out of delta's map-styles instead, which is one
# string holding four remappings.
NVIM_MAP_STYLE_PAIRS = [
    ("InlineDiffMovedDelete", "bold purple"),
    ("InlineDiffMovedAdd", "bold cyan"),
]


def _check_nvim_delta_parity(verbose):
    nvim_path = os.path.join(REPO, NVIM_INLINE_DIFF)
    if not os.path.isfile(nvim_path):
        return []
    nvim_src = open(nvim_path, encoding="utf-8").read()
    nvim = {}
    for name, spec in re.findall(r"(InlineDiff\w+)\s*=\s*\{([^}]*)\}", nvim_src):
        m = re.search(r'bg\s*=\s*"(#[0-9a-fA-F]{6})"', spec)
        if m:
            nvim[name] = norm(m.group(1))

    cfg = open(os.path.join(REPO, GIT), encoding="utf-8").read()
    section = re.search(r"^\[delta\]\n(.*?)(?=^\[)", cfg, re.M | re.S)
    delta = {}
    if section:
        for key, value in re.findall(r"^\s*([a-z0-9-]+)\s*=\s*(.*)$",
                                     section.group(1), re.M):
            found = HEX.findall(value)
            if found:
                delta[key] = norm(found[0])
        maps = re.search(r"^\s*map-styles\s*=\s*(.*)$", section.group(1), re.M)
        if maps:
            for src, dst in re.findall(r"([a-z ]+?)\s*=>\s*\w+\s+(#[0-9a-fA-F]{6})",
                                       maps.group(1)):
                delta["map:" + src.strip()] = norm(dst)

    problems = []
    checked = 0
    for hl, style in NVIM_DELTA_PAIRS + [(h, "map:" + s)
                                         for h, s in NVIM_MAP_STYLE_PAIRS]:
        if hl not in nvim or style not in delta:
            problems.append(
                "cannot compare %s with delta's %s: one of them is missing"
                % (hl, style.replace("map:", "map-styles "))
            )
            continue
        checked += 1
        if nvim[hl] != delta[style]:
            problems.append(
                "%s is %s in Neovim but delta's %s is %s -- the same diff, "
                "two colours" % (hl, nvim[hl],
                                 style.replace("map:", "map-styles "),
                                 delta[style])
            )
    if verbose and not problems:
        print("  %d diff colours identical in Neovim and delta" % checked)
    return problems


# Everywhere the tree shells out to bat. bat chooses 24-bit colour versus the
# 256-colour cube from COLORTERM, which is not reliably set under tmux, the VS
# Code terminal, or ssh — so a call site that forgets it does not fail, it
# quietly renders the same file in approximated colours next to panes showing
# the real ones. Three of these were doing exactly that.
BAT_CALL_SITES = [
    "common/.config/lf/preview.sh",
    "common/.config/lf/lfrc",
    "common/.config/shell/theme.sh",
    "common/.local/bin/ff",
    "common/.local/bin/st-rg",
    "common/.local/bin/st-zoekt",
]
BAT_INVOCATION = re.compile(r"(?<![\w-])bat\s+--")


def _check_bat_truecolor(verbose):
    problems = []
    sites = 0
    for rel in BAT_CALL_SITES:
        path = os.path.join(REPO, rel)
        if not os.path.isfile(path):
            continue
        lines = open(path, encoding="utf-8").read().splitlines()
        for i, line in enumerate(lines, 1):
            stripped = line.strip()
            if stripped.startswith("#") or not BAT_INVOCATION.search(line):
                continue
            sites += 1
            # On the line itself, or exported earlier in the same file.
            if "COLORTERM" in line or any("COLORTERM" in earlier
                                          for earlier in lines[:i - 1]):
                continue
            problems.append(
                "%s:%d runs bat without forcing COLORTERM, so this pane drops "
                "to 256 colours under tmux, the VS Code terminal or ssh"
                % (rel, i)
            )
    if verbose and not problems:
        print("  %d bat call sites all force truecolor" % sites)
    return problems


def _check_ripgrep_config(verbose):
    """Let ripgrep parse its own config, since it is strict about colours.

    ripgrep validates a --colors flag and names what it did not like, which
    makes it the same kind of oracle delta is above. It only does so on a real
    search, not on --version, so this runs one against /dev/null.

    tmux and fzf are deliberately not checked the same way: tmux accepts a
    config containing an unknown option without a word, and CI's fzf predates
    --style=minimal, so a strict check there would fail on the runner rather
    than on the config.
    """
    import shutil
    import subprocess

    if shutil.which("rg") is None:
        if verbose:
            print("  ripgrep not installed, its config not parsed")
        return []

    env = dict(os.environ)
    env["RIPGREP_CONFIG_PATH"] = os.path.join(REPO, "common/.ripgreprc")
    try:
        out = subprocess.run(["rg", "--color=always", "x", os.devnull],
                             capture_output=True, text=True, timeout=15, env=env)
    except (OSError, subprocess.SubprocessError) as exc:
        return ["could not run ripgrep: %s" % exc]
    if out.stderr.strip():
        return ["ripgrep rejects its own config: %s" % out.stderr.strip()]
    if verbose:
        print("  ripgrep parses common/.ripgreprc")
    return []


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
        # The window's own titlebar. All three draw one, and on a desktop they
        # sit side by side, so a difference here is visible without switching
        # to anything.
        ("titlebar", "macos_titlebar_color", "active_titlebar_bg",
         "titleBar.activeBackground"),
        ("titlebar, unfocused", "wayland_titlebar_color", "inactive_titlebar_bg",
         "titleBar.inactiveBackground"),
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
    problems.extend(_check_shell_parity(verbose))
    problems.extend(_check_delta_options(verbose))
    problems.extend(_check_ripgrep_config(verbose))
    problems.extend(_check_nvim_delta_parity(verbose))
    problems.extend(_check_bat_truecolor(verbose))

    yazi_map = {}
    yazi_path = os.path.join(REPO, "common/.config/yazi/theme.toml")
    with open(yazi_path, encoding="utf-8") as fh:
        for line in fh:
            m = re.search(r'name\s*=\s*"(\*\.\w+)"\s*,\s*fg\s*=\s*"(#[0-9a-fA-F]{6})"',
                          line)
            if m:
                yazi_map[m.group(1)] = norm(m.group(2))

    # lf's chrome, against yazi's. The file colours below are the obvious
    # mirror, but the two file managers also mark the same *actions* -- yank,
    # cut, select, the row under the cursor -- and lf spent a long time doing
    # it in plain ANSI while yazi's were spelled out.
    yazi_src = open(yazi_path, encoding="utf-8").read()
    lfrc = open(os.path.join(REPO, "common/.config/lf/lfrc"), encoding="utf-8").read()

    def lf_fmt(option):
        m = re.search(r'^set\s+%s\s+"([^"]*)"' % option, lfrc, re.M)
        if not m:
            return None
        found = DECIMAL_TRIPLE.findall(m.group(1))
        return "#%02x%02x%02x" % tuple(int(x) for x in found[0]) if found else None

    def yazi_key(section, key):
        """The colour of a yazi key: its bg if it has one, else its fg.

        lf paints a whole row, so what it is comparable to is yazi's fill.
        Reading the first hex on the line instead would pick up `current`'s
        foreground and compare a text colour against a background.
        """
        sec = re.search(r"^\[%s\]\n(.*?)(?=^\[|\Z)" % section, yazi_src, re.M | re.S)
        if not sec:
            return None
        m = re.search(r"^%s\s*=(.*)$" % key, sec.group(1), re.M)
        if not m:
            return None
        for attr in ("bg", "fg"):
            hit = re.search(r'%s\s*=\s*"(#[0-9a-fA-F]{6})"' % attr, m.group(1))
            if hit:
                return norm(hit.group(1))
        return None

    for option, section, key, what in [
        ("copyfmt", "mgr", "marker_copied", "the yank marker"),
        ("cutfmt", "mgr", "marker_cut", "the cut marker"),
        ("selectfmt", "mgr", "marker_selected", "the selection marker"),
        ("cursoractivefmt", "indicator", "current", "the hovered row"),
        ("cursorpreviewfmt", "indicator", "preview", "the preview pane's row"),
        ("borderfmt", "mgr", "border_style", "the pane border"),
    ]:
        a, b = lf_fmt(option), yazi_key(section, key)
        if a and b and a != b:
            problems.append(
                "%s is %s in lf (%s) but %s in yazi (%s.%s)"
                % (what, a, option, b, section, key)
            )

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
    ("text", "#c0caf5", "#16161e", TMUX, "tmux menu"),
    ("text", "#c0caf5", "#283457", TMUX, "tmux menu, selected row"),
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
    ("ui", "#ff9e64", "#1a1b26", STARSHIP, "starship hostname, over SSH"),
    ("ui", "#1abc9c", "#1a1b26", STARSHIP, "starship username"),

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
    # The blame stripes cycle four backgrounds, so the code on top has to stay
    # legible on the lightest of them, which is the worst case. It is the code
    # style that matters here and not a timestamp style: delta has no
    # blame-timestamp-style, whatever its option list looks like it should have.
    ("text", "#c0caf5", "#292e42", GIT, "delta blame line, lightest stripe"),

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
    # The menu paints its own darker page, so its selected row is measured
    # against that rather than against the terminal background.
    ("#283457", "#16161e", TMUX, "tmux menu selection"),
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


def swatch(doc):
    """Print the whole theme, in the theme, so it can be looked at.

    The checks above prove the numbers are right, which is not the same thing
    as the theme being right. This renders every documented colour and every
    pair the contrast table knows about, using real escape sequences -- so it
    doubles as the fastest way to find out whether a terminal is really doing
    24-bit colour or quietly approximating it.
    """
    known = documented_colours(doc)

    def block(hexstr):
        r, g, b = (int(hexstr[i:i + 2], 16) for i in (1, 3, 5))
        return "\033[48;2;%d;%d;%dm      \033[0m" % (r, g, b)

    def on(fg, bg, text):
        fr, fg_, fb = (int(fg[i:i + 2], 16) for i in (1, 3, 5))
        br, bg_, bb = (int(bg[i:i + 2], 16) for i in (1, 3, 5))
        return "\033[38;2;%d;%d;%d;48;2;%d;%d;%dm%s\033[0m" % (
            fr, fg_, fb, br, bg_, bb, text)

    print("\033[1mPalette\033[0m  (docs/tokyonight.md, in the order it lists them)\n")
    for hexstr, names in known.items():
        label = ", ".join(sorted(names)) if names else ""
        print("  %s  %s  %s" % (block(hexstr), hexstr, label))

    print("\n\033[1mPairs\033[0m  (floors: %s)\n"
          % ", ".join("%s %.1f:1" % (t, f) for t, f in sorted(TIERS.items())))
    for tier, fg, bg, _source, what in PAIRS:
        print("  %s  %6.2f:1  %-5s  %s"
              % (on(fg, bg, "  sample  "), ratio(fg, bg), tier, what))

    print("\n\033[1mFills\033[0m  (floor: %.2f:1 against the page)\n" % FILL_FLOOR)
    for fill, page, _source, what in FILLS:
        row = on("#c0caf5", page, "   page   ") + on("#c0caf5", fill, "   fill   ")
        print("  %s  %6.2f:1  %s" % (row, ratio(fill, page), what))
    return 0


def main(argv):
    verbose = "--verbose" in argv or "-v" in argv
    if "swatch" in argv:
        return swatch(read_doc())

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
