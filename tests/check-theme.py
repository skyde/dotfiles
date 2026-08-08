#!/usr/bin/env python3
"""Check that the Tokyo Night theme is consistent across every tool that wears it.

    tests/check-theme.py              # all checks
    tests/check-theme.py palette      # only one check
    tests/check-theme.py --verbose    # also print what passed
    tests/check-theme.py swatch       # every documented colour, then the preview
    tests/check-theme.py preview      # mock-ups of the surfaces, in the theme

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

import math
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
        # A cell may hold several colours -- the diff-tint rows list a whole
        # family of steps in one -- so a cell counts as owning every colour in
        # it as long as it holds nothing else.
        owned = set()
        for cell in cells:
            found = HEX.findall(cell)
            if found and not re.sub(r"#[0-9a-fA-F]{6}|[`\s]", "", cell):
                owned.update(norm(c) for c in found)
        # Outside a table there is no label cell, and the sentence is the
        # explanation -- which is the thing the label stands for anyway.
        if len(cells) < 3:
            label = line.strip().lstrip("> ").rstrip()[:80]
            owned = {norm(c) for c in HEX.findall(line)}
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

    Scoped to that one table, and not to every table in the doc, because the
    doc has other tables -- the exemption list right below it names files
    precisely in order to say they are *not* scanned, and reading it as an
    enrolment list turned each of those into a scan target. So the table is
    the run of rows that follows the heading, and it ends where the rows do.
    """
    lines = doc.splitlines()
    start = next((i for i, line in enumerate(lines)
                  if line.startswith("## ") and "Where the theme lives" in line),
                 None)
    if start is None:
        return []
    table = []
    for line in lines[start + 1:]:
        if line.lstrip().startswith("|"):
            table.append(line)
        elif table:
            break  # the run of rows has ended

    files = []
    for line in table:
        cells = [c.strip() for c in line.split("|")]
        if len(cells) < 3:
            continue
        # The path cell may list two files ("theme.toml`, `plugins/...").
        for path in re.findall(r"`([^`]+)`", cells[2]):
            # Rows also carry backticked things that are not paths at all --
            # "(the `# Theme` section)", `gui.theme`, `LS_COLORS`. A path has a
            # separator in it and resolves to a file in this repo; nothing else
            # does, so that is the whole test. Directories are excluded by the
            # same rule, which is why the yazi plugin folder is not scanned.
            if "/" not in path:
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


# Checks that need an external binary or a subshell. Skipping them is what
# makes the comment-decoy probe in the self-test affordable: it runs the
# checker twice per colour line in the tree, and the oracles are 2.2 of the
# 2.3 seconds a full run costs. THEME_CHECK_NO_TOOLS=1 turns them off.
#
# Not a general-purpose fast mode to reach for casually -- the oracles are the
# half that catches a key a tool has silently stopped accepting.
TOOL_CHECKS = {
    "_check_shell_parity", "_check_delta_options", "_check_ripgrep_config",
    "_check_yazi_configs", "_check_starship_config", "_check_bat_theme",
    "_check_kitty_config", "_check_git_colours", "_check_wezterm_config",
    "_check_git_paints", "_check_tmux_options", "_check_lazygit_theme_keys",
    "_check_doctor_swatches", "_check_shell_exports",
}


def without_tools():
    return bool(os.environ.get("THEME_CHECK_NO_TOOLS"))


def run_check(fn, *args):
    """Call a sub-check, unless it needs a tool and tools are switched off."""
    if without_tools() and fn.__name__ in TOOL_CHECKS:
        return []
    return fn(*args)


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

    problems.extend(run_check(_check_shell_exports, known, verbose))
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
        code, stdout, stderr = source_theme("bash", path, script)
    except (OSError, subprocess.SubprocessError) as exc:
        return ["could not source theme.sh: %s" % exc]
    if code != 0:
        return ["theme.sh failed to source: %s" % stderr.strip()]

    problems = []
    seen = 0
    for name, value in zip(SHELL_EXPORTS, stdout.split("\n")):
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
    # The flat scan runs with the tab_bar block cut out. Both it and the window
    # define `background`, and whichever came last silently won -- which stayed
    # harmless only while the two held the same colour.
    outer = re.sub(r"tab_bar\s*=\s*\{.*?\n  \}", "", text, flags=re.S)
    scalars = dict(
        (k, norm(v))
        for k, v in re.findall(r"(\w+)\s*=\s*'(#[0-9a-fA-F]{6})'", outer)
    )
    # The tab entries nest, and every one of them spells its keys the same
    # way, so a flat scan would have active_tab and inactive_tab overwrite
    # each other. Read each sub-table under its own name instead.
    for tab in ("active_tab", "inactive_tab"):
        m = re.search(tab + r"\s*=\s*\{(.*?)\}", text, re.S)
        if m:
            for k, v in re.findall(r"(\w+)\s*=\s*'(#[0-9a-fA-F]{6})'", m.group(1)):
                scalars["%s.%s" % (tab, k)] = norm(v)

    # `tab_bar.background` is the strip the tabs sit on, and the flat scan
    # above stored it as plain `background` -- the same key the window's own
    # background writes to. Both happened to be #1a1b26, so the collision was
    # invisible, and the strip was the one terminal surface with no counterpart
    # to be compared against. Read tab_bar's own scalars under their own name,
    # with the nested sub-tables removed first so active_tab's keys stay out.
    m = re.search(r"tab_bar\s*=\s*\{(.*?)\n  \}", text, re.S)
    if m:
        direct = re.sub(r"\w+\s*=\s*\{.*?\}", "", m.group(1), flags=re.S)
        for k, v in re.findall(r"(\w+)\s*=\s*'(#[0-9a-fA-F]{6})'", direct):
            scalars["tab_bar.%s" % k] = norm(v)
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


# Forcing a shell interactive without a terminal makes bash complain about job
# control, twice, on stderr. It is not a problem with the file being sourced.
SHELL_NOISE = ("cannot set terminal process group", "no job control in this shell")


def source_theme(shell, path, script):
    """Run `script` in `shell` after sourcing theme.sh, interactively.

    Interactively because theme.sh returns early for non-interactive shells --
    it is on the startup path of every zsh a script ever spawns, and none of
    those have a terminal to paint. Reading it any other way would see an empty
    file and quietly check nothing.
    """
    import subprocess

    # -f / --norc so the user's own rc files cannot set these variables
    # themselves and mask a difference between the two shells.
    flags = "-fic" if shell == "zsh" else "-ic"
    argv = [shell] + (["--norc"] if shell == "bash" else []) + [flags, script, "_", path]
    out = subprocess.run(argv, capture_output=True, text=True, timeout=30)
    stderr = "\n".join(line for line in out.stderr.splitlines()
                       if line.strip() and not any(n in line for n in SHELL_NOISE))
    return out.returncode, out.stdout, stderr


def _read_exports(shell, path):
    """Source theme.sh in one shell and return what it exported."""
    script = '. "$1"; for v in %s; do eval "printf \'%%s\\034\' \\"\\$$v\\""; done' \
        % " ".join(THEME_EXPORTS)
    code, stdout, stderr = source_theme(shell, path, script)
    if code != 0 or stderr:
        raise RuntimeError("%s: %s" % (shell, stderr or "non-zero exit"))
    return dict(zip(THEME_EXPORTS, stdout.split("\034")))


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

# COLORTERM has to be *set*, not merely mentioned. Every one of these files
# explains in a comment why it forces truecolor, and an earlier version of this
# check accepted the explanation as the deed: deleting the real
# `export COLORTERM` from lf/preview.sh left the comment above it, and the
# check went on passing.
BAT_COLORTERM_SET = re.compile(
    r'COLORTERM\s*=|export\s+COLORTERM|:env\(\s*[\'"]COLORTERM[\'"]')

# yazi previews through bat from Lua, which spawns it as a command object
# rather than a shell word, so the pattern above never saw it. It has two
# spawn paths -- the plain one and the byte-capped one for single-line
# monsters -- and each sets COLORTERM separately, so one could lose it while
# the other kept it and only huge files would go dull.
BAT_LUA = "common/.config/yazi/plugins/bat-preview.yazi/main.lua"
# Two shapes: the plain path spawns bat directly, the capped one pipes into it
# inside an `sh -c` string. Both are bat, both need COLORTERM.
BAT_LUA_SPAWN = re.compile(r'Command\(\s*"bat"\s*\)|(?<![\w-])bat\s+--')
# Deliberately short. The two spawn paths sit ~28 lines apart, so a window wide
# enough to reach from one to the other would let either of them satisfy the
# check on the other's behalf -- and the failure being guarded against is
# exactly one of them losing it while the other keeps it.
BAT_LUA_WINDOW = 15


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
            # On the line itself, or really set earlier in the same file --
            # in code, not in the comment that explains why it is needed.
            earlier = [e for e in lines[:i - 1]
                       if not e.strip().startswith("#")]
            if BAT_COLORTERM_SET.search(line) or any(
                    BAT_COLORTERM_SET.search(e) for e in earlier):
                continue
            problems.append(
                "%s:%d runs bat without forcing COLORTERM, so this pane drops "
                "to 256 colours under tmux, the VS Code terminal or ssh"
                % (rel, i)
            )
    lua = os.path.join(REPO, BAT_LUA)
    if os.path.isfile(lua):
        lua_lines = open(lua, encoding="utf-8").read().splitlines()
        for i, line in enumerate(lua_lines):
            if line.strip().startswith("--") or not BAT_LUA_SPAWN.search(line):
                continue
            sites += 1
            window = lua_lines[i:i + BAT_LUA_WINDOW]
            if not any(BAT_COLORTERM_SET.search(w) for w in window
                       if not w.strip().startswith("--")):
                problems.append(
                    "%s:%d spawns bat without setting COLORTERM on it, so "
                    "this preview path drops to 256 colours"
                    % (BAT_LUA, i + 1))

    if verbose and not problems:
        print("  %d bat call sites all force truecolor" % sites)
    return problems


# The two command lines. fast-syntax-highlighting themes zsh's and PSReadLine
# themes PowerShell's, and they were written to agree role for role -- the
# whole point being that the prompt looks the same on either machine. Two
# files, two syntaxes, one written in hex and the other in SGR escapes.
PSPROFILE = "windows/Documents/PowerShell/Microsoft.PowerShell_profile.ps1"
ZSHRC = "common/.zshrc"

# zsh's key -> PSReadLine's key, for the roles both name. Both command lines
# are Visual Studio Dark+ (see "Dark+ on the command line" in the palette doc),
# so these are not merely analogous roles -- they must be the same hex.
COMMAND_LINE_ROLES = [
    ("default", "Default", "plain text"),
    ("comment", "Comment", "comments"),
    ("single-quoted-argument", "String", "strings"),
    ("command", "Command", "a command that will run"),
    ("single-hyphen-option", "Parameter", "options"),
    ("variable", "Variable", "variables"),
    ("mathnum", "Number", "numbers"),
    ("redirection", "Operator", "operators"),
    ("unknown-token", "Error", "a command that will not run"),
]


CLI_HEADING = "Dark+ on the command line"
# The doc's own sentence: "a word that resolves to no command is `red`, and a
# path that has not resolved to anything yet is `comment`". Named by palette
# role rather than by hex, so they are looked up rather than copied here.
CLI_TOKYO_EXCEPTIONS = ("red", "comment")


def _check_command_line_palette(doc, verbose):
    """Every colour on either command line is one the Dark+ table sanctions.

    The roles the two shells share are compared with each other elsewhere, but
    that covered 9 of the 41 colours zsh sets: the rest could be changed to any
    documented colour and nothing would notice, because nothing tied them to
    the table the doc writes them down in.

    Two are deliberately not Dark+ at all, and the doc says so in a sentence
    rather than a row -- they are named by palette role, so they are resolved
    through the palette instead of being restated here.
    """
    section = doc.split(CLI_HEADING, 1)
    if len(section) != 2:
        return ["docs/tokyonight.md no longer has a %r section, so the "
                "command line has nothing to be checked against" % CLI_HEADING]
    table = set()
    for line in section[1].splitlines():
        if line.startswith("### ") or line.startswith("## "):
            break
        cells = [c.strip() for c in line.split("|")]
        if len(cells) >= 3:
            table.update(norm(h) for cell in cells for h in HEX.findall(cell))
    if not table:
        return ["the %r table lists no colours" % CLI_HEADING]

    known = documented_colours(doc)
    allowed = set(table)
    for colour, names in known.items():
        if names & set(CLI_TOKYO_EXCEPTIONS):
            allowed.add(colour)

    problems, checked = [], 0
    zsh = os.path.join(REPO, ZSHRC)
    if os.path.isfile(zsh):
        block = re.search(r"_tn_cli_styles=\((.*?)\n\)",
                          uncommented(zsh, open(zsh, encoding="utf-8").read()),
                          re.S)
        if block:
            for key, value in re.findall(r"^\s*([\w-]+)\s+'([^']+)'",
                                         block.group(1), re.M):
                for found in HEX.findall(value):
                    checked += 1
                    if norm(found) not in allowed:
                        problems.append(
                            "%s paints %s %s, which the %r table does not list"
                            % (ZSHRC, key, norm(found), CLI_HEADING))

    ps = os.path.join(REPO, PSPROFILE)
    if os.path.isfile(ps):
        body = uncommented(ps, open(ps, encoding="utf-8").read())
        block = re.search(r"Set-PSReadLineOption -Colors @\{(.*?)\n\}",
                          body, re.S)
        if block:
            for key, found in re.findall(
                    r"^\s*(\w+)\s*=\s*'(#[0-9a-fA-F]{6})'",
                    block.group(1), re.M):
                checked += 1
                if norm(found) not in allowed:
                    problems.append(
                        "%s paints %s %s, which the %r table does not list"
                        % (PSPROFILE, key, norm(found), CLI_HEADING))
    if verbose and not problems:
        print("  %d command-line colour(s) are all sanctioned by the doc"
              % checked)
    return problems


def _check_command_lines(verbose):
    """The zsh and PowerShell command lines are the same table.

    Both are Visual Studio Dark+ rather than Tokyo Night, because the line you
    are typing is code -- and because Ctrl-R pipes history through bat, which
    has already painted it that way one keystroke earlier. So these are not two
    themes that ought to rhyme; they are one table written twice, and a role
    that differs is a command that changes colour when you change machine.

    zsh's half used to live in an fsh .ini and now lives in `_tn_cli_styles` in
    .zshrc, which is what made this check stop finding it during the merge.
    """
    zsh_path = os.path.join(REPO, ZSHRC)
    ps_path = os.path.join(REPO, PSPROFILE)
    if not (os.path.isfile(zsh_path) and os.path.isfile(ps_path)):
        return []

    zsh = {}
    block = re.search(r"_tn_cli_styles=\((.*?)\n\)", 
                      open(zsh_path, encoding="utf-8").read(), re.S)
    if not block:
        return ["%s no longer defines _tn_cli_styles, so the zsh command line "
                "cannot be compared with the PowerShell one" % ZSHRC]
    for key, value in re.findall(r"^\s*([\w-]+)\s+'([^']+)'", block.group(1), re.M):
        found = HEX.findall(value)
        if found:
            zsh[key] = norm(found[0])

    ps_src = open(ps_path, encoding="utf-8").read()
    ps = {}
    for key, value in re.findall(r"^\s*(\w+)\s*=\s*'(#[0-9a-fA-F]{6})'",
                                 ps_src, re.M):
        ps[key] = norm(value)
    for key, value in re.findall(r"^\s*(\w+)\s*=\s*\"`?e\[([0-9;]+)m\"",
                                 ps_src, re.M):
        m = DECIMAL_TRIPLE.search(value)
        if m:
            ps.setdefault(key, "#%02x%02x%02x" % tuple(int(x) for x in m.groups()))

    problems, checked = [], 0
    for zsh_key, ps_key, role in COMMAND_LINE_ROLES:
        if zsh_key not in zsh or ps_key not in ps:
            problems.append(
                "cannot compare %s: %s in .zshrc, %s in the PowerShell profile"
                % (role,
                   "set" if zsh_key in zsh else "missing",
                   "set" if ps_key in ps else "missing"))
            continue
        checked += 1
        if zsh[zsh_key] != ps[ps_key]:
            problems.append(
                "%s is %s on the zsh command line but %s on the PowerShell one"
                % (role, zsh[zsh_key], ps[ps_key]))
    if verbose and not problems:
        print("  %d command-line role(s) identical in zsh and PowerShell" % checked)
    return problems


# Slots this fixture cannot reach, and why. Kept explicit rather than silently
# skipped: a slot that is never exercised is a slot whose name is never checked,
# and that is exactly the thing being looked for here.
GIT_UNEXERCISED = {
    "color.status.nobranch": "needs a detached HEAD",
    "color.status.unmerged": "needs a merge conflict, which stops `changed` "
                             "from being reachable in the same tree",
    "color.branch.plain": "git paints no branch with it in any state reached here",
    "color.decorate.stash": "needs refs/stash asked for by name",
    "color.decorate.grafted": "needs a grafted or replaced commit",
}

# Which commands can show a section's colours at all.
GIT_SECTION_COMMANDS = {
    "status": [["status"], ["status", "-sb"]],
    "branch": [["branch", "-a", "-vv"]],
    "decorate": [["log", "--decorate", "--all", "-3"]],
}

# A colour nothing in the palette uses, so its presence in the output can only
# have come from the slot being overridden.
GIT_SENTINEL = "#010203"


DOCTOR = "doctor-theme.sh"

# What the doctor demonstrates, and the export it is demonstrating. Its swatch
# is a second copy of a fact theme.sh already states, so the two can drift and
# the doctor would go on cheerfully painting a colour the shell never produces
# -- while reporting PASS, because what it checks is that the variable is set.
DOCTOR_SWATCHES = [
    (r"a directory:.*?\[([0-9;]+)m", "LS_COLORS", "di", "a directory"),
    (r"a broken symlink:.*?\[([0-9;]+)m", "LS_COLORS", "or", "a broken symlink"),
    (r"an in-buffer one:.*?\[([0-9;]+)m", "LESS_TERMCAP_so", None,
     "a match inside text you are reading"),
]


def _sgr_params(sgr):
    """An SGR parameter list as an unordered set of whole parameters.

    `38;2;R;G;B;1` and `1;38;2;R;G;B` paint the same thing, and theme.sh and
    the doctor happen to write them in opposite orders, so comparing the
    strings would report a difference that does not exist. Splitting naively on
    `;` would be worse: it would make a truecolour triple indistinguishable
    from three unrelated attributes.
    """
    parts, out, i = sgr.split(";"), [], 0
    while i < len(parts):
        if parts[i] in ("38", "48") and parts[i + 1:i + 2] == ["2"]:
            out.append(";".join(parts[i:i + 5]))
            i += 5
        else:
            out.append(parts[i])
            i += 1
    return frozenset(out)


def _check_doctor_swatches(verbose):
    """The doctor shows the colours the shell actually exports."""
    import subprocess

    doc_path = os.path.join(REPO, DOCTOR)
    theme = os.path.join(REPO, "common/.config/shell/theme.sh")
    if not (os.path.isfile(doc_path) and os.path.isfile(theme)):
        return []
    wanted = sorted({v for _p, v, _k, _w in DOCTOR_SWATCHES})
    script = '. "$1"; for v in %s; do eval "printf \'%%s\\n\' \\"\\$$v\\""; done' \
        % " ".join(wanted)
    try:
        code, stdout, stderr = source_theme("bash", theme, script)
    except (OSError, subprocess.SubprocessError) as exc:
        return ["could not source theme.sh for the doctor check: %s" % exc]
    if code != 0:
        return ["theme.sh failed to source: %s" % stderr.strip()]
    live = dict(zip(wanted, stdout.split("\n")))

    body = uncommented(doc_path, open(doc_path, encoding="utf-8").read())
    problems, checked = [], 0
    for pattern, var, key, what in DOCTOR_SWATCHES:
        m = re.search(pattern, body, re.S)
        if not m:
            problems.append(
                "%s no longer shows %s where this looks for it" % (DOCTOR, what))
            continue
        value = live.get(var, "")
        if key:
            value = next((e.split("=", 1)[1] for e in value.split(":")
                          if e.startswith(key + "=")), "")
        else:
            value = value.replace("\033[", "").replace("\x1b[", "").rstrip("m")
            value = re.sub(r"^\x1b\[", "", value)
        if not value:
            problems.append(
                "%s demonstrates %s and theme.sh exports nothing for it"
                % (DOCTOR, what))
            continue
        checked += 1
        if _sgr_params(m.group(1)) != _sgr_params(value):
            problems.append(
                "%s paints %s as %s and theme.sh exports %s"
                % (DOCTOR, what, m.group(1), value))
    if verbose and not problems:
        print("  %d doctor swatch(es) match what the shell exports" % checked)
    return problems


# The two colours a search result is made of, stated three times: once in
# ripgrep's own config as decimal triples, and once in each picker's awk prefix
# as an SGR escape. The pickers strip ripgrep's colouring and repaint, so a
# disagreement means the same file:line is one colour from `rg` and another
# from the picker wrapping it.
RGRC = "common/.ripgreprc"

PICKER_COLOURS = [
    ("path", r"--colors=path:fg:(\d+,\d+,\d+)", "mag", "the file name"),
    ("line", r"--colors=line:fg:(\d+,\d+,\d+)", "gre", "the line number"),
]
PICKERS = ["common/.local/bin/st-rg", "common/.local/bin/st-zoekt"]


def _check_picker_colours(verbose):
    """`rg` and the pickers that wrap it paint a result the same way."""
    rc = os.path.join(REPO, RGRC)
    if not os.path.isfile(rc):
        return []
    rc_body = open(rc, encoding="utf-8").read()

    problems, checked = [], 0
    for _name, pattern, var, what in PICKER_COLOURS:
        m = re.search(pattern, rc_body)
        if not m:
            problems.append(
                "%s no longer sets %s, so the pickers have nothing to agree "
                "with" % (RGRC, what))
            continue
        want = "#%02x%02x%02x" % tuple(int(x) for x in m.group(1).split(","))
        for rel in PICKERS:
            path = os.path.join(REPO, rel)
            if not os.path.isfile(path):
                continue
            # st-rg embeds its awk in a single-quoted string and st-zoekt
            # nests it one layer deeper, so the quotes and the escape arrive
            # with one or two backslashes depending on which file this is.
            #
            # Every occurrence, not the first: st-rg carries two awk prefixes
            # and only one of them was being read, so the other could paint
            # results any colour it liked. And comments are stripped first,
            # because the first match in a file where the old value has been
            # commented out above the new one is the comment.
            body = uncommented(path, open(path, encoding="utf-8").read())
            found = re.findall(r'%s=\\?"\\+033\[([0-9;]+)m' % var, body)
            if not found:
                problems.append(
                    "%s no longer sets %s where this looks for it" % (rel, var))
                continue
            for raw in found:
                trip = DECIMAL_TRIPLE.search(raw)
                got = ("#%02x%02x%02x" % tuple(int(x) for x in trip.groups())
                       if trip else raw)
                checked += 1
                if got != want:
                    problems.append(
                        "%s paints %s %s and %s says %s -- the same result, "
                        "two colours" % (rel, what, got, RGRC, want))
    if verbose and not problems:
        print("  %d picker colour(s) agree with ripgrep's own" % checked)
    return problems


def _check_lazygit_theme_keys(verbose):
    """lazygit's own defaults are the list of theme keys it knows.

    This file has said for a while that lazygit cannot be an oracle, because
    `lazygit --config` prints the *default* config and omits every field whose
    default is empty, so a key missing from that output proves nothing.

    That is true of the config as a whole and false of `gui.theme`, which is
    the only part of it that carries colour: all twelve of its fields have
    non-empty defaults, so for that block the dump is a complete list of
    valid names. Three keys in this section were dead once -- lightTheme,
    promptToOpenMergeTool, and scrollOffBehavior in the wrong place -- and
    they were found by hand against a schema fetched over the network.
    """
    import shutil
    import subprocess

    if not shutil.which("lazygit"):
        return []
    cfg = os.path.join(REPO, LAZYGIT)
    if not os.path.isfile(cfg):
        return []
    try:
        import yaml
    except ImportError:
        return []

    class Loader(yaml.SafeLoader):
        pass

    # lazygit's dump contains a bare `=` key, which is YAML's "default value"
    # tag and has no Python constructor by default.
    Loader.add_constructor("tag:yaml.org,2002:value",
                           lambda l, n: l.construct_scalar(n))

    def theme_keys(text, what):
        try:
            data = yaml.load(text, Loader) or {}
        except yaml.YAMLError as exc:
            return None, "could not parse %s: %s" % (what, exc)
        return set(((data.get("gui") or {}).get("theme") or {})), None

    try:
        dump = subprocess.run(["lazygit", "--config"], capture_output=True,
                              text=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as exc:
        return ["could not ask lazygit for its defaults: %s" % exc]
    if dump.returncode != 0:
        return []

    known, err = theme_keys(dump.stdout, "lazygit --config")
    if err:
        return [err]
    mine, err = theme_keys(open(cfg, encoding="utf-8").read(), LAZYGIT)
    if err:
        return [err]
    if not known:
        return ["lazygit --config no longer lists gui.theme, so its keys "
                "cannot be checked against it"]

    problems = [
        "%s sets gui.theme.%s and lazygit has no such key -- it reads "
        "correctly and does nothing" % (LAZYGIT, key)
        for key in sorted(mine - known)
    ]
    if verbose and not problems:
        print("  lazygit knows all %d of its theme keys" % len(mine))
    return problems


SHARED_ROLES = [
    {
        "name": "the cursor",
        "hex": "#ff5000",
        "aliases": (),
        # The one colour here that is not Tokyo Night at all: chosen to be
        # findable against a blue-violet palette. docs/tokyonight.md: "Keep it."
        "settings": [
            ("common/.config/kitty/themes/tokyonight_night.conf", r"^cursor\s+(#[0-9a-fA-F]{6})"),
            ("common/.config/wezterm/wezterm.lua", r"cursor_bg\s*=\s*'(#[0-9a-fA-F]{6})'"),
            ("common/.config/wezterm/wezterm.lua", r"cursor_border\s*=\s*'(#[0-9a-fA-F]{6})'"),
            (
                "common/.config/wezterm/wezterm.lua",
                r"quick_select_label_bg\s*=\s*\{\s*Color\s*=\s*'(#[0-9a-fA-F]{6})'",
            ),
            (
                "common/.config/Code/User/settings.json",
                r'"editorCursor\.foreground"\s*:\s*"(#[0-9a-fA-F]{6})"',
            ),
            (
                "common/.config/Code/User/settings.json",
                r'"terminalCursor\.foreground"\s*:\s*"(#[0-9a-fA-F]{6})"',
            ),
            (
                "common/.config/nvim/lua/plugins/tokyonight.lua",
                r"hl\.Cursor\s*=\s*\{[^}]*bg\s*=\s*\"(#[0-9a-fA-F]{6})\"",
            ),
            (
                "common/.config/nvim/lua/plugins/tokyonight.lua",
                r"hl\.TermCursor\s*=\s*\{[^}]*bg\s*=\s*\"(#[0-9a-fA-F]{6})\"",
            ),
            (
                "common/.config/nvim/lua/plugins/tokyonight.lua",
                r"hl\.lCursor\s*=\s*\{[^}]*bg\s*=\s*\"(#[0-9a-fA-F]{6})\"",
            ),
            (
                "common/.config/nvim/lua/plugins/tokyonight.lua",
                r"hl\.CursorIM\s*=\s*\{[^}]*bg\s*=\s*\"(#[0-9a-fA-F]{6})\"",
            ),
            ("common/.config/shell/theme.sh", r"pointer:(#[0-9a-fA-F]{6})"),
        ],
    },
    {
        "name": "the selected row",
        "hex": "#283457",
        # Neovim names it rather than spelling it, which is the better habit.
        "aliases": ("c.bg_visual",),
        "settings": [
            ("common/.config/shell/theme.sh", r"bg\+:(#[0-9a-fA-F]{6})"),
            ("common/.tmux.conf", r"mode-style\s+'bg=(#[0-9a-fA-F]{6})"),
            ("common/.zshrc", r"'ma=48;2;(\d+;\d+;\d+)'"),
            (
                # [indicator] current — read by yazi v25.12.29 and later.
                "common/.config/yazi/theme.toml",
                r"^current = \{ fg = \"#[0-9a-fA-F]{6}\", bg = \"(#[0-9a-fA-F]{6})\"",
            ),
            (
                # [mgr] hovered — the same setting as read by older yazi;
                # both spellings live in the file so both versions get it.
                "common/.config/yazi/theme.toml",
                r"\[mgr\.hovered\]\nfg = \"#[0-9a-fA-F]{6}\"\nbg = \"(#[0-9a-fA-F]{6})\"",
            ),
            (
                "common/.config/btop/themes/tokyo-night.theme",
                r'theme\[selected_bg\]="(#[0-9a-fA-F]{6})"',
            ),
            (
                "common/.config/lazygit/config.yml",
                r'selectedLineBgColor:\s*\["(#[0-9a-fA-F]{6})"\]',
            ),
            (
                "common/.config/nvim/lua/plugins/tokyonight.lua",
                r"hl\.PmenuSel\s*=\s*\{\s*bg\s*=\s*([\w.]+)\s*\}",
            ),
        ],
    },
    {
        "name": "a match inside text you are reading",
        "hex": "#3d59a1",
        "aliases": (),
        # The other half of this convention — orange for the *current* match —
        # is the role below. See "Two kinds of match" in docs/tokyonight.md.
        "settings": [
            ("common/.tmux.conf", r"copy-mode-match-style\s+'bg=(#[0-9a-fA-F]{6})"),
            (
                "common/.config/wezterm/wezterm.lua",
                r"copy_mode_inactive_highlight_bg\s*=\s*\{\s*Color\s*=\s*'(#[0-9a-fA-F]{6})'",
            ),
            (
                "common/.config/wezterm/wezterm.lua",
                r"quick_select_match_bg\s*=\s*\{\s*Color\s*=\s*'(#[0-9a-fA-F]{6})'",
            ),
            # less gets it through theme.sh's shorthand for the same colour.
            ("common/.config/shell/theme.sh", r"_tn_bg_search='48;2;(\d+;\d+;\d+)'"),
        ],
    },
    {
        "name": "the current match",
        "hex": "#ff9e64",
        "aliases": (),
        "settings": [
            ("common/.tmux.conf", r"copy-mode-current-match-style\s+'bg=(#[0-9a-fA-F]{6})"),
            (
                "common/.config/wezterm/wezterm.lua",
                r"copy_mode_active_highlight_bg\s*=\s*\{\s*Color\s*=\s*'(#[0-9a-fA-F]{6})'",
            ),
        ],
    },
]


def _check_shared_roles(verbose):
    """One role, one hex, everywhere it is set.

    Carried over from the checker that landed on main in #475, which was
    written independently of this one and got to this idea first. The other
    checks here ask whether a file is internally right or whether two named
    files agree; this asks whether a *role* -- the cursor, the selected row --
    holds one colour across every tool that draws it, which is the thing a
    person actually notices when it drifts.

    Each entry names the exact line it expects in each file, so a setting that
    moves or is renamed fails loudly rather than silently going unchecked.
    """
    problems, checked = [], 0
    for role in SHARED_ROLES:
        for rel, pattern in role["settings"]:
            path = os.path.join(REPO, rel)
            if not os.path.isfile(path):
                continue
            # Comments stripped first: a commented-out copy of the old line
            # is what a change to one of these leaves behind, and it satisfies
            # the pattern perfectly while the live line says something else.
            m = re.search(pattern,
                          uncommented(path, open(path, encoding="utf-8").read()),
                          re.M)
            if not m:
                problems.append(
                    "%s no longer sets %s where this looks for it (%s)"
                    % (rel, role["name"], pattern))
                continue
            found = m.group(1)
            if re.fullmatch(r"\d{1,3};\d{1,3};\d{1,3}", found):
                found = "#%02x%02x%02x" % tuple(int(x) for x in found.split(";"))
            checked += 1
            if norm(found) != norm(role["hex"]) and found not in role["aliases"]:
                problems.append(
                    "%s sets %s to %s, not %s"
                    % (rel, role["name"], norm(found), role["hex"]))
    if verbose and not problems:
        print("  %d shared-role setting(s) hold one colour each" % checked)
    return problems


def _check_tmux_options(verbose):
    """tmux holds every colour the config sets, under the name it was set by.

    A misspelled tmux option is not an error. `menu-selcted-style` loads
    without a word and simply is not there afterwards -- tmux even accepts a
    truncated name like `status-styl`, because option names are matched by
    unambiguous prefix, so "it started fine" proves very little.

    What proves something is asking tmux what it ended up holding. The server
    is started on its own socket with this config, every option the file sets
    to something containing a colour is looked up in `show-options`, and both
    the presence and the colours have to match. An option tmux dropped is an
    option that never applied.
    """
    import shutil
    import subprocess

    if not shutil.which("tmux"):
        return []
    conf = os.path.join(REPO, TMUX)
    if not os.path.isfile(conf):
        return []
    sock = "theme-check"

    def tmux(*args):
        return subprocess.run(["tmux", "-L", sock] + list(args),
                              capture_output=True, text=True, timeout=30)

    tmux("kill-server")
    try:
        started = tmux("-f", conf, "new-session", "-d", "-s", "probe")
        if started.returncode != 0:
            return ["tmux will not load %s: %s"
                    % (TMUX, (started.stderr or started.stdout).strip()[:200])]
        held = {}
        for scope in ("-g", "-gw"):
            for line in tmux("show-options", scope).stdout.splitlines():
                parts = line.split(None, 1)
                if len(parts) == 2:
                    held[parts[0]] = parts[1].strip().strip('"')

        problems, checked = [], 0
        for line in open(conf, encoding="utf-8"):
            if line.lstrip().startswith("#"):
                continue
            m = re.match(r"\s*setw?\s+-g\w*\s+(\S+)\s+(.*)$", line)
            if not m:
                continue
            key, value = m.group(1), m.group(2).strip()
            wanted = [norm(h) for h in HEX.findall(value)]
            if not wanted:
                continue
            checked += 1
            if key not in held:
                problems.append(
                    "%s sets %s and tmux does not hold it afterwards -- the "
                    "name is not one tmux knows, so the line does nothing"
                    % (TMUX, key))
                continue
            got = [norm(h) for h in HEX.findall(held[key])]
            if got != wanted:
                problems.append(
                    "%s: tmux holds %s as %s, not %s"
                    % (TMUX, key, ",".join(got) or "no colour",
                       ",".join(wanted)))
        if verbose and not problems:
            print("  tmux holds all %d of its colour options" % checked)
        return problems
    except (OSError, subprocess.SubprocessError) as exc:
        return ["could not ask tmux about its options: %s" % exc]
    finally:
        tmux("kill-server")


def _git_section(body, name):
    """The body of a [color "x"] section, or "" when it is absent."""
    section = name.split(".", 1)[1] if "." in name else name
    m = re.search(r'\[color "%s"\](.*?)(?=\n\[|\Z)' % re.escape(section),
                  body, re.S)
    return m.group(1) if m else ""


def _check_git_paints(verbose):
    """Every git colour slot in the config is a slot git actually has.

    git ignores a config key it does not recognise, so a misspelled slot --
    `color.status.chagned` -- reads correctly in the file and does nothing
    forever. Same failure as the phantom delta option, same as three dead
    lazygit keys.

    There is no list of valid slots to check against, and writing one here
    would make the checker its own authority. So git is asked. Each key in the
    config is overridden to a sentinel colour nothing else uses, the real
    commands are run against a small repository holding every state, and the
    sentinel has to come back. A name git does not know paints nothing.

    The sentinel matters: four of these slots share #bb9af7, so looking for
    the configured colour would have found it in the output no matter which of
    the four was misspelled.
    """
    import shutil
    import subprocess
    import tempfile

    if not shutil.which("git"):
        return []
    cfg = os.path.join(REPO, GIT)
    if not os.path.isfile(cfg):
        return []
    body = open(cfg, encoding="utf-8").read()

    tmp = tempfile.mkdtemp(prefix="theme-git-")
    work = os.path.join(tmp, "work")
    env = dict(os.environ, GIT_CONFIG_GLOBAL=cfg, GIT_CONFIG_SYSTEM="/dev/null",
               HOME=tmp, GIT_TERMINAL_PROMPT="0")
    ident = ["-c", "user.email=t@t", "-c", "user.name=t"]

    def git(*args, cwd=None):
        return subprocess.run(["git"] + list(args), cwd=cwd or work, env=env,
                              capture_output=True, text=True)

    problems = []
    try:
        up = os.path.join(tmp, "up")
        os.makedirs(up)
        git("init", "-q", "-b", "main", ".", cwd=up)
        open(os.path.join(up, "f.txt"), "w").write("a\n")
        git("add", "-A", cwd=up)
        git(*ident, "commit", "-qm", "init", cwd=up)
        git("tag", "v0", cwd=up)
        git("clone", "-q", up, work, cwd=tmp)
        # every state a slot might need, short of a conflict
        open(os.path.join(work, "tracked.txt"), "w").write("a\n")
        git("add", "-A")
        git(*ident, "commit", "-qm", "second")
        open(os.path.join(work, "tracked.txt"), "a").write("b\n")  # changed
        open(os.path.join(work, "staged.txt"), "w").write("c\n")
        git("add", "staged.txt")                                   # added
        open(os.path.join(work, "untracked.txt"), "w").write("d\n")
        git("branch", "-q", "other", "main")                       # branch.local

        sgr = "38;2;%d;%d;%d" % tuple(
            int(GIT_SENTINEL[i:i + 2], 16) for i in (1, 3, 5))
        checked = 0
        for section, commands in sorted(GIT_SECTION_COMMANDS.items()):
            for key, _colour in re.findall(
                    r'^\s*(\w+)\s*=\s*"?(#[0-9a-fA-F]{6})',
                    _git_section(body, "color." + section), re.M):
                full = "color.%s.%s" % (section, key)
                painted = any(
                    sgr in git("--no-pager", "-c", "color.ui=always",
                               "-c", "core.pager=cat",
                               "-c", "%s=%s" % (full, GIT_SENTINEL),
                               *cmd).stdout
                    for cmd in commands)
                if full in GIT_UNEXERCISED:
                    if painted:
                        problems.append(
                            "%s is listed as unexercisable (%s) and git does "
                            "paint with it -- the exemption is stale"
                            % (full, GIT_UNEXERCISED[full]))
                    continue
                checked += 1
                if not painted:
                    problems.append(
                        "%s paints nothing -- git does not know that slot, so "
                        "the key reads correctly and does nothing" % full)
        if verbose and not problems:
            print("  %d git colour slot(s) paint; %d cannot be reached here"
                  % (checked, len(GIT_UNEXERCISED)))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return problems


def _check_mime_extension_bridge(verbose):
    """A file matched by mime in yazi and by extension in lf is one colour.

    yazi colours images, video, audio and PDFs with `mime = "**/image/*"` and
    friends; lf and LS_COLORS have no notion of mime and spell out `*.png`.
    The lf/yazi parity check compares rules that share a pattern, so these two
    describe the same 18 files and never meet: yazi's `**/audio/*` could be
    repainted and nothing would notice `*.mp3` in lf disagreeing with it.

    The mapping from extension to mime type comes from the standard library
    rather than a list written here, so the bridge cannot quietly go stale
    against a hand-maintained table that is itself the thing being checked.
    """
    import fnmatch
    import mimetypes

    yazi_path = os.path.join(REPO, YAZI)
    lf_path = os.path.join(REPO, "common/.config/lf/colors")
    if not (os.path.isfile(yazi_path) and os.path.isfile(lf_path)):
        return []
    # Comments stripped: yazi's theme explains several of its mime rules in a
    # comment directly above them, so a commented-out rule reads as a rule.
    body = uncommented(yazi_path, open(yazi_path, encoding="utf-8").read())

    mime_rules = [(pat, norm(col)) for pat, col in re.findall(
        r'\{\s*mime\s*=\s*"([^"]+)"\s*,\s*fg\s*=\s*"(#[0-9a-fA-F]{6})"', body)]
    by_ext = set(re.findall(r'url = "(\*\.[^"]+)"', body))
    if not mime_rules:
        return []

    lf_colours = {}
    for line in open(lf_path, encoding="utf-8"):
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split()
        m = re.search(r"38;2;(\d+);(\d+);(\d+)", parts[1]) if len(parts) > 1 else None
        if parts[0].startswith("*.") and m:
            lf_colours[parts[0]] = "#%02x%02x%02x" % tuple(
                int(x) for x in m.groups())

    problems, checked = [], 0
    for ext, lf_colour in sorted(lf_colours.items()):
        if ext in by_ext:
            continue  # yazi names this extension itself; parity covers it
        mime = mimetypes.guess_type("x" + ext[1:])[0]
        if not mime:
            continue
        for pat, yazi_colour in mime_rules:
            if fnmatch.fnmatch(mime, pat.replace("**/", "")):
                checked += 1
                if yazi_colour != lf_colour:
                    problems.append(
                        "%s is %s in lf/colors but yazi paints it %s via "
                        "%s -- the same file, two colours"
                        % (ext, lf_colour, yazi_colour, pat))
                break
    if verbose and not problems:
        print("  %d file type(s) matched by mime in yazi and by extension in "
              "lf agree" % checked)
    return problems


def _check_yazi_configs(verbose):
    """Have yazi load our yazi configs and say whether it accepted them.

    This is the check that would have saved the most time. Yazi tolerates an
    unknown *style* key silently -- that is the gotcha the palette doc has
    always warned about -- but an unknown *rule* key is fatal: it refuses the
    entire file and falls back to its presets. So a single stale `name = ` in
    the filetype rules did not cost the filetype colours, it cost the whole
    theme, quietly, while every colour in the file still looked perfectly
    correct to a reader and to every check here.

    `yazi --debug` reports what it managed to load, which makes it the oracle:
    each config either appears with a character count or with the reason it was
    rejected.
    """
    import shutil
    import subprocess

    yazi = shutil.which("yazi")
    if yazi is None:
        if verbose:
            print("  yazi not installed, its configs not loaded")
        return []

    config_dir = os.path.join(REPO, "common/.config/yazi")
    env = dict(os.environ, YAZI_CONFIG_HOME=config_dir)
    try:
        out = subprocess.run([yazi, "--debug"], capture_output=True, text=True,
                             timeout=60, env=env, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError) as exc:
        return ["could not run yazi --debug: %s" % exc]
    text = out.stdout + out.stderr

    problems = []
    if "parse error" in text:
        detail = " ".join(line.strip() for line in text.splitlines()
                          if line.strip())[:300]
        problems.append("yazi rejects one of its configs: %s" % detail)
    for bad in re.findall(r"invalid color[^\n]*", text):
        problems.append("yazi: %s" % bad.strip())

    # Each config has to actually be loaded, not merely not-complained-about.
    for label in ("Yazi", "Keymap", "Theme"):
        m = re.search(r"^\s+%s\s+: (.+)$" % label, text, re.M)
        if m and "chars" not in m.group(1):
            problems.append("yazi did not load its %s config: %s"
                            % (label.lower(), m.group(1).strip()))
    if verbose and not problems:
        print("  yazi loads its yazi, keymap and theme configs")
    return problems


def _check_starship_config(verbose):
    """Let starship read its own config and report what it did not understand.

    starship warns rather than fails on a key it does not recognise, so a
    typo'd module or option sits there doing nothing and the prompt quietly
    lacks a piece.

    The warnings do not go to stderr, which is the trap: starship appends them
    to a session log under $STARSHIP_CACHE and carries on. Watching stderr
    finds them only occasionally -- an earlier version of this check did, and
    it passed a config with a misspelled section in it. Note the cache
    variable is starship's own, not XDG_CACHE_HOME; pointing the latter
    somewhere empty produces no log at all and a check that always passes. So
    this points STARSHIP_CACHE at an empty directory, runs starship once, and
    reads the log it leaves behind. That is deterministic, and it catches all three shapes:
    an unknown top-level section, a misspelled section header, and a bad key
    inside a module starship knows.
    """
    import shutil
    import subprocess
    import tempfile

    if shutil.which("starship") is None:
        if verbose:
            print("  starship not installed, its config not read")
        return []

    with tempfile.TemporaryDirectory() as cache:
        env = dict(os.environ,
                   STARSHIP_CONFIG=os.path.join(REPO, STARSHIP),
                   STARSHIP_CACHE=cache,
                   STARSHIP_SESSION_KEY="themecheck",
                   # Render the modules that only appear on a remote host, so
                   # a mistake in those is seen rather than skipped.
                   SSH_CONNECTION="1.2.3.4 22 5.6.7.8 22")
        try:
            subprocess.run(["starship", "explain"], capture_output=True,
                           text=True, timeout=30, env=env,
                           stdin=subprocess.DEVNULL)
        except (OSError, subprocess.SubprocessError) as exc:
            return ["could not run starship: %s" % exc]

        problems = []
        for name in sorted(os.listdir(cache)):
            for line in open(os.path.join(cache, name),
                             encoding="utf-8", errors="replace"):
                clean = re.sub(r"\x1b\[[0-9;]*m", "", line).strip()
                if clean:
                    problems.append("starship: %s" % clean)

    if verbose and not problems:
        print("  starship reads common/.config/starship.toml without complaint")
    return problems


def _check_bat_theme(verbose):
    """BAT_THEME agrees between the shells, and names a theme bat has.

    docs/tokyonight.md calls this "the single source of truth" for syntax
    highlighting, and it reaches further than that suggests: bat reads it,
    delta inherits bat's theme set, and the yazi preview, the lf preview and
    the Ctrl-R history picker all shell out to bat precisely so they follow it.
    One setting decides what code looks like in five places.

    Two ways for that to break quietly, so both are checked. It is written out
    twice, once per shell, so the two can disagree. And if the name stops
    matching a theme bat actually carries -- a rename upstream, a cache never
    built -- bat does not complain, it just falls back to its default and every
    one of those five surfaces changes together.
    """
    import shutil
    import subprocess

    values = {}
    for rel in ("common/.zshenv", "common/.bashrc-custom"):
        path = os.path.join(REPO, rel)
        if not os.path.isfile(path):
            continue
        m = re.search(r'^\s*export BAT_THEME=(.+)$',
                      open(path, encoding="utf-8").read(), re.M)
        if m:
            values[rel] = m.group(1).strip().strip('"').strip("'")

    problems = []
    if len(values) < 2:
        problems.append(
            "BAT_THEME is exported in %s but not in both shells' files"
            % ", ".join(sorted(values)) if values else
            "BAT_THEME is not exported by either shell")
    elif len(set(values.values())) > 1:
        problems.append(
            "BAT_THEME differs between the shells: %s"
            % ", ".join("%s=%r" % kv for kv in sorted(values.items())))

    theme = next(iter(values.values()), None)
    # Debian ships the binary as batcat.
    bat = shutil.which("bat") or shutil.which("batcat")
    if theme and bat:
        try:
            out = subprocess.run([bat, "--list-themes"], capture_output=True,
                                 text=True, timeout=30,
                                 stdin=subprocess.DEVNULL)
            names = {line.strip() for line in out.stdout.splitlines()}
            if theme not in names:
                problems.append(
                    "BAT_THEME is %r, which %s does not have -- bat falls back "
                    "to its default and takes delta, the yazi and lf previews "
                    "and the history picker with it" % (theme, bat))
            elif verbose:
                print("  BAT_THEME %r exists in %s and matches in both shells"
                      % (theme, os.path.basename(bat)))
        except (OSError, subprocess.SubprocessError) as exc:
            problems.append("could not ask bat for its themes: %s" % exc)
    elif verbose and theme:
        print("  BAT_THEME matches in both shells; bat not installed to verify it")
    return problems


def _check_kitty_config(verbose):
    """Have kitty parse its own config and report the keys it ignored.

    kitty warns about an unknown option and carries on, which is the usual
    trap: a setting that was renamed upstream, or never existed, sits in the
    file looking correct. It has no --debug-config before 0.36, but it ships
    its own Python, so `kitty +runpy` can call the real config loader on any
    version.

    Only unknown *keys* are reported this way. kitty does not object to a
    colour value it cannot parse -- it silently uses black -- which is what
    the palette check is for.
    """
    import shutil
    import subprocess

    if shutil.which("kitty") is None:
        if verbose:
            print("  kitty not installed, its config not parsed")
        return []

    conf = os.path.join(REPO, "common/.config/kitty/kitty.conf")
    script = (
        "from kitty.config import load_config\n"
        "o = load_config(%r)\n"
        "print('background', o.background)\n" % conf
    )
    try:
        out = subprocess.run(["kitty", "+runpy", script], capture_output=True,
                             text=True, timeout=60, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError) as exc:
        return ["could not run kitty: %s" % exc]

    problems = []
    for line in (out.stderr + out.stdout).splitlines():
        if "unknown config key" in line.lower():
            problems.append("kitty: %s" % line.split("]", 1)[-1].strip())
    if out.returncode != 0 and not problems:
        problems.append("kitty could not load its config: %s"
                        % out.stderr.strip()[:200])
    if verbose and not problems:
        print("  kitty parses its config with no unknown keys")
    return problems


def _check_git_colours(verbose):
    """Have git resolve every colour it is given, since it validates the spec.

    A git colour is a hex plus optional attributes -- "#7aa2f7 bold" -- and the
    palette check only sees the hex. `#7aa2f7 blod` passes it happily while git
    rejects the whole value, so the setting does nothing. Asking git to resolve
    each one covers the half a colour scanner cannot.

    Keys come from --get-regexp rather than being listed here, so a section
    added later is covered without anyone remembering to. They arrive already
    lowercased, which matters: --get-color is case-sensitive where --get is
    not, so `color.decorate.HEAD` spelled as written in the file resolves to
    nothing at all.
    """
    import shutil
    import subprocess

    if shutil.which("git") is None:
        if verbose:
            print("  git not installed, its colour specs not resolved")
        return []

    path = os.path.join(REPO, GIT)
    try:
        listed = subprocess.run(
            ["git", "config", "--file", path, "--get-regexp", r"^color\."],
            capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as exc:
        return ["could not read git colours: %s" % exc]

    problems = []
    checked = 0
    for line in listed.stdout.splitlines():
        key = line.split(None, 1)[0] if line.strip() else ""
        if not key:
            continue
        checked += 1
        out = subprocess.run(
            ["git", "config", "--file", path, "--get-color", key],
            capture_output=True, text=True, timeout=30)
        if out.returncode != 0 or out.stderr.strip():
            problems.append("git rejects %s: %s"
                            % (key, out.stderr.strip() or "non-zero exit"))
        elif not out.stdout:
            problems.append("git resolves %s to nothing" % key)
    if verbose and not problems:
        print("  %d git colour specs resolve" % checked)
    return problems


def _check_wezterm_config(verbose):
    """Have wezterm evaluate its config, since it validates every colour.

    wezterm's config is Lua that has to convert into a Rust struct, so a bad
    key or an unparseable colour is a hard error naming both -- "Error
    processing colors.foreground ... failed to parse #zzzzzz as RgbaColor".
    That makes it the strictest oracle here.

    `ls-fonts` is used only because it is a subcommand that loads the config
    and exits. Its own complaint -- that the configured font is not installed
    -- is ignored: that is a property of the machine, not of the config, and
    treating it as a failure would make this fail on every box without
    JetBrainsMono.
    """
    import shutil
    import subprocess

    if shutil.which("wezterm") is None:
        if verbose:
            print("  wezterm not installed, its config not evaluated")
        return []

    conf = os.path.join(REPO, "common/.config/wezterm/wezterm.lua")
    try:
        out = subprocess.run(["wezterm", "--config-file", conf, "ls-fonts"],
                             capture_output=True, text=True, timeout=60,
                             stdin=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError) as exc:
        return ["could not run wezterm: %s" % exc]

    problems = []
    for line in (out.stdout + out.stderr).splitlines():
        if "ERROR" in line and "font" not in line.lower():
            problems.append("wezterm: %s" % line.split("ERROR", 1)[-1].strip())
    if verbose and not problems:
        print("  wezterm evaluates its config with every colour parsing")
    return problems


SYNTAX_DOC = "docs/vscode-syntax-parity.md"
VSCODE_SETTINGS = "common/.config/Code/User/settings.json"
VSCODE_EXTENSIONS = "vscode_extensions.txt"


def _check_vscode_theme_chain(verbose):
    """The base theme Neovim's syntax colours are resolved against still exists.

    docs/vscode-syntax-parity.md is explicit that every hex in
    lua/util/vscode_syntax.lua is the value VS Code *resolves* for a construct
    once two things combine: a specific theme extension, and the user's
    textMateRules. Those hexes are therefore only correct while VS Code is
    actually running that theme.

    Three files have to agree for that to hold, and none of them mentions the
    others: the doc names the theme and the extension that provides it,
    settings.json selects the theme by name, and vscode_extensions.txt decides
    whether the extension is installed at all. Change the theme or drop the
    extension and nothing breaks loudly -- VS Code falls back to another dark
    theme, and Neovim keeps painting colours resolved against a theme that is
    no longer there.
    """
    doc_path = os.path.join(REPO, SYNTAX_DOC)
    if not os.path.isfile(doc_path):
        return []
    doc = open(doc_path, encoding="utf-8").read()
    m = re.search(r"\*\*([^*]+)\*\* theme \(`([\w.-]+)`", doc)
    if not m:
        return ["%s no longer names the theme and the extension providing it, "
                "so nothing can check them" % SYNTAX_DOC]
    theme, extension = m.group(1).strip(), m.group(2).strip()

    problems = []
    settings = os.path.join(REPO, VSCODE_SETTINGS)
    if os.path.isfile(settings):
        sm = re.search(r'"workbench\.colorTheme"\s*:\s*"([^"]+)"',
                       open(settings, encoding="utf-8").read())
        if not sm:
            problems.append("settings.json sets no workbench.colorTheme, so the "
                            "syntax colours resolve against an unknown theme")
        elif sm.group(1) != theme:
            problems.append(
                "VS Code is set to the %r theme but %s resolves Neovim's "
                "syntax colours against %r"
                % (sm.group(1), SYNTAX_DOC, theme))

    exts = os.path.join(REPO, VSCODE_EXTENSIONS)
    if os.path.isfile(exts):
        installed = {line.strip().lower()
                     for line in open(exts, encoding="utf-8")
                     if line.strip() and not line.startswith("#")}
        if extension.lower() not in installed:
            problems.append(
                "%s is what provides the %r theme, and it is not in %s"
                % (extension, theme, VSCODE_EXTENSIONS))

    problems.extend(run_check(_check_syntax_doc_table, doc, verbose))

    if verbose and not problems:
        print("  VS Code runs %r, provided by %s" % (theme, extension))
    return problems


NVIM_SYNTAX = "common/.config/nvim/lua/util/vscode_syntax.lua"


def _check_syntax_doc_table(doc, verbose):
    """Tables in the parity doc naming a capture and a hex have to be true.

    The doc is where the resolution work is written down -- which VS Code scope
    a capture stands in for, and what that scope resolves to once the theme and
    the user's textMateRules combine. The lua file is where that answer is
    acted on. Nothing connects them, so a colour corrected in one and not the
    other leaves a doc that describes a mapping the editor does not have.

    Any row of the form `| ... | #RRGGBB | @capture, @capture |` is checked, so
    documenting a scope is what enrols it -- there is no second list to update.
    """
    src_path = os.path.join(REPO, NVIM_SYNTAX)
    if not os.path.isfile(src_path):
        return []
    src = open(src_path, encoding="utf-8").read()

    # The palette is `role = "#RRGGBB",`; the mapping is `["@cap"] = c.role,`.
    roles = {name: norm(hexa) for name, hexa
             in re.findall(r'^\s*(\w+)\s*=\s*"(#[0-9A-Fa-f]{6})"',
                           src, re.M)}
    mapped = {}
    for cap, role in re.findall(r'\["(@[\w.]+)"\]\s*=\s*c\.(\w+)', src):
        mapped.setdefault(cap, roles.get(role))

    problems, checked = [], 0
    for row in re.findall(r"^\|(.+)\|\s*$", doc, re.M):
        cells = [cell.strip() for cell in row.split("|")]
        hexes = [c for c in cells if re.fullmatch(r"`#[0-9A-Fa-f]{6}`", c)]
        caps = [m.group(0) for cell in cells
                for m in re.finditer(r"@[\w.]+", cell)]
        if len(hexes) != 1 or not caps:
            continue
        want = norm(hexes[0].strip("`"))
        for cap in caps:
            checked += 1
            got = mapped.get(cap)
            if got is None:
                problems.append(
                    "%s documents %s as %s and %s does not map it"
                    % (SYNTAX_DOC, cap, want, NVIM_SYNTAX))
            elif got != want:
                problems.append(
                    "%s documents %s as %s but %s paints it %s"
                    % (SYNTAX_DOC, cap, want, NVIM_SYNTAX, got))
    if verbose and not problems and checked:
        print("  %d capture(s) documented in %s match %s"
              % (checked, SYNTAX_DOC, NVIM_SYNTAX))
    return problems


EXEMPT_HEADING = "Carries colour, deliberately not palette-checked"


def _check_colour_coverage(doc, verbose):
    """No tracked file carries a colour that nothing looks at.

    The palette scan covers what the "Where the theme lives" table lists, which
    means a config can carry colours and simply not be in it -- and being
    absent from a table looks like nothing at all. Two files are legitimately
    out (VS Code's settings.json, Neovim's inline diff), and both were out
    silently until this check existed.

    So the exemptions are a list in the doc rather than a fact about the
    checker, and the list has to be exactly right in both directions: a file
    that grows a colour without a row anywhere fails, and a row for a file that
    no longer carries one fails too. Docs and the checkers only quote colours,
    and the per-platform paths are symlinks onto the same file, so neither is
    a place a colour can hide.
    """
    import subprocess

    section = doc.split(EXEMPT_HEADING, 1)
    if len(section) != 2:
        return ["docs/tokyonight.md no longer has a %r section, so nothing "
                "records which colour-bearing files are out of scope"
                % EXEMPT_HEADING]
    exempt = set()
    for line in section[1].splitlines():
        if line.startswith("## "):
            break
        cells = [c.strip() for c in line.split("|")]
        if len(cells) >= 3:
            for path in re.findall(r"`([^`]+)`", cells[1]):
                if "/" in path:
                    exempt.add(path)

    scanned = {os.path.relpath(p, REPO) for p in themed_files(doc)}

    # git ls-files is the better list -- it excludes build output and anything
    # a developer happens to have lying around -- but it is not the only way to
    # get one, and an earlier version of this returned an empty list when the
    # command failed. That made the whole check vanish wherever the tree is not
    # a checkout, including the self-test's sandbox, where it duly passed two
    # mutations aimed straight at it. Falling back to a walk means the answer
    # can get noisier, never absent.
    try:
        listing = subprocess.run(["git", "-C", REPO, "ls-files", "-z"],
                                 capture_output=True, text=True,
                                 check=True).stdout.split("\0")
    except (OSError, subprocess.SubprocessError):
        listing = []
        for root, dirs, names in os.walk(REPO):
            dirs[:] = [d for d in dirs
                       if d not in (".git", "node_modules", "__pycache__")]
            for name in names:
                listing.append(os.path.relpath(os.path.join(root, name), REPO))

    carriers, problems = set(), []
    for rel in listing:
        if not rel:
            continue
        full = os.path.join(REPO, rel)
        if not os.path.isfile(full):
            continue
        if rel.startswith(("docs/", "tests/")) or rel == "README.md":
            continue
        try:
            body = open(full, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        if HEX.search(body) or DECIMAL_TRIPLE.search(body):
            carriers.add(rel)

    # mac/ and windows/ reach into common/ by symlink, so the same file arrives
    # here under three names. Identity is decided by content rather than by
    # os.path.islink: a copy that still matches byte for byte is the same file
    # however the tree was produced, and one that has drifted is a second copy
    # worth reporting -- which is the answer islink cannot give.
    accounted = {}
    for rel in sorted(scanned | exempt):
        full = os.path.join(REPO, rel)
        if os.path.isfile(full):
            accounted[open(full, "rb").read()] = rel
    for rel in sorted(carriers - scanned - exempt):
        body = open(os.path.join(REPO, rel), "rb").read()
        if body in accounted:
            carriers.discard(rel)

    for rel in sorted(carriers - scanned - exempt):
        problems.append(
            "%s carries a colour and is in neither the \"Where the theme "
            "lives\" table nor the %r list, so nothing checks it"
            % (rel, EXEMPT_HEADING))
    for rel in sorted(exempt - carriers):
        problems.append(
            "docs/tokyonight.md exempts %s from the palette scan and it no "
            "longer carries a colour, so the exemption is stale" % rel)

    if verbose and not problems:
        print("  %d colour-bearing file(s) scanned, %d exempted by name"
              % (len(carriers & scanned), len(exempt)))
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
        code, stdout, stderr = source_theme(
            "bash", path, '. "$1"; printf %s "$LS_COLORS"')
    except (OSError, subprocess.SubprocessError) as exc:
        return ["could not source theme.sh to read LS_COLORS: %s" % exc]
    if code != 0:
        return ["theme.sh failed to source: %s" % stderr.strip()]

    shell = {}
    for entry in stdout.split(":"):
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

    # Neovim is the fourth copy, and the least obvious one: `terminal_colors =
    # true` pushes tokyonight's own palette into `:terminal`, which puts
    # upstream's values back for the two slots this theme deliberately
    # changed. The config overrides them in `on_colors`; this is what keeps
    # those overrides pointing at the same colours the terminals use.
    nvim_theme = os.path.join(REPO, "common/.config/nvim/lua/plugins/tokyonight.lua")
    if os.path.isfile(nvim_theme):
        # Comments stripped: a commented-out `c.terminal.black = "#1d202f"`
        # above a live line setting something else satisfies the pattern, and
        # the generated probe in the self-test caught exactly that here.
        src = uncommented(nvim_theme,
                          open(nvim_theme, encoding="utf-8").read())
        for field, slot, label in [("black", 0, "ANSI 0"),
                                   ("black_bright", 8, "ANSI 8")]:
            m = re.search(r'c\.terminal\.%s\s*=\s*"(#[0-9a-fA-F]{6})"' % field, src)
            if not m:
                problems.append(
                    "Neovim does not override c.terminal.%s, so a :terminal "
                    "buffer uses upstream's %s instead of the terminals'"
                    % (field, label))
            elif norm(m.group(1)) != kitty_ansi[slot]:
                problems.append(
                    "%s disagrees: nvim :terminal=%s, kitty=%s"
                    % (label, norm(m.group(1)), kitty_ansi[slot]))

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
        # The strip the tabs sit on, behind and around them. kitty had it at
        # #15161e and wezterm at #1a1b26 -- a real difference, invisible for
        # as long as nothing named the wezterm side distinctly enough to
        # compare.
        ("tab bar background", "tab_bar_background", "tab_bar.background", None),
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
    problems.extend(run_check(_check_ls_colors, lf_entries))
    problems.extend(run_check(_check_shell_parity, verbose))
    problems.extend(run_check(_check_delta_options, verbose))
    problems.extend(run_check(_check_ripgrep_config, verbose))
    problems.extend(run_check(_check_yazi_configs, verbose))
    problems.extend(run_check(_check_starship_config, verbose))
    problems.extend(run_check(_check_bat_theme, verbose))
    problems.extend(run_check(_check_kitty_config, verbose))
    problems.extend(run_check(_check_git_colours, verbose))
    problems.extend(run_check(_check_wezterm_config, verbose))
    problems.extend(run_check(_check_vscode_theme_chain, verbose))
    problems.extend(run_check(_check_nvim_delta_parity, verbose))
    problems.extend(run_check(_check_colour_coverage, doc, verbose))
    problems.extend(run_check(_check_mime_extension_bridge, verbose))
    problems.extend(run_check(_check_git_paints, verbose))
    problems.extend(run_check(_check_tmux_options, verbose))
    problems.extend(run_check(_check_shared_roles, verbose))
    problems.extend(run_check(_check_doctor_swatches, verbose))
    problems.extend(run_check(_check_picker_colours, verbose))
    problems.extend(run_check(_check_lazygit_theme_keys, verbose))
    problems.extend(run_check(_check_bat_truecolor, verbose))
    problems.extend(run_check(_check_command_lines, verbose))
    problems.extend(run_check(_check_command_line_palette, doc, verbose))

    yazi_map = {}
    yazi_path = os.path.join(REPO, "common/.config/yazi/theme.toml")
    with open(yazi_path, encoding="utf-8") as fh:
        for line in fh:
            # `url` since yazi v25.12.29; `name` before it. Both accepted here
            # so the check keeps working either side of that rename rather
            # than reporting all 53 extensions as missing.
            m = re.search(r'(?:url|name)\s*=\s*"(\*\.\w+)"\s*,'
                          r'\s*fg\s*=\s*"(#[0-9a-fA-F]{6})"', line)
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
        print("  16 ANSI slots x 3 terminals + Neovim's :terminal, "
              "%d shared file extensions" % len(set(lf_map) & set(yazi_map)))
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
    ("muted", "#565f89", "#1a1b26", TMUX, "tmux hostname"),
    ("ui", "#7aa2f7", "#3b4261", TMUX, "tmux current window index"),
    ("ui", "#7aa2f7", "#1a1b26", TMUX, "tmux current window name"),
    ("muted", "#565f89", "#1a1b26", TMUX, "tmux inactive window index"),
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
    ("muted", "#565f89", "#1a1b26", TMUX, "tmux pane number overlay"),
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
    # A .log or .pyc, on the page and then under the cursor. The second one is
    # the reason these files are dark5 rather than comment grey: you put the
    # cursor on one in order to decide whether to delete it, and comment grey
    # on this fill is 1.97:1.
    ("muted", "#737aa2", "#1a1b26", YAZI, "build-noise file"),
    ("muted", "#737aa2", "#283457", YAZI, "build-noise file, under the cursor"),

    # btop
    ("text", "#c0caf5", "#1a1b26", BTOP, "btop body"),
    ("muted", "#565f89", "#1a1b26", BTOP, "btop inactive text"),
    ("text", "#c0caf5", "#283457", BTOP, "btop selected process"),

    # The command line. Both shells and both platforms share these roles, and
    # all of them sit on the page rather than on a fill.
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


# --------------------------------------------------------------------------
# Colour-vision deficiency.
#
# delta's added and removed backgrounds are 39.7 apart in Lab and 3.0 apart to
# a deuteranope -- the same colour. That is not a fault to be repainted away:
# roughly one man in twelve cannot separate those hues no matter what green and
# red you pick, so a diff that carries direction in hue alone is broken for
# them by construction.
#
# This diff does not. Direction lives in the line-number gutter -- a removed
# line has no new number, so its column is blank -- and *presence* lives in
# lightness, which CVD leaves alone: added and removed each stand ~23 from the
# page for a deuteranope, against 32 and 27 for everyone else. Three states,
# separable without hue.
#
# So what is worth pinning is not the hue difference, which cannot be fixed,
# but the lightness difference, which can be lost by a well-meaning tweak that
# makes a tint subtler. Anything that drifts a diff background back toward the
# page takes the last cue a deuteranope has.
CVD_FLOOR = 10.0
CVD_HEADING = "Tinted washes"


def _cvd_tints(doc):
    """The tinted-wash table, read from the doc rather than copied here.

    An earlier version listed the seven hexes in this file, which made the
    check an assertion about its own constants: the tints could drift in the
    doc and in every config together and it would still have passed. The table
    is the source of truth for what a tinted wash is, so it is what gets read.
    """
    section = doc.split(CVD_HEADING, 1)
    if len(section) != 2:
        return []
    tints = []
    for line in section[1].splitlines():
        if line.startswith("#"):
            break
        cells = [c.strip() for c in line.split("|")]
        if len(cells) >= 3 and re.fullmatch(r"`#[0-9a-fA-F]{6}`", cells[1]):
            tints.append((norm(cells[1].strip("`")), cells[2]))
    return tints


def _to_lms(hexstr):
    r, g, b = (_linear(int(hexstr[i:i + 2], 16) / 255) for i in (1, 3, 5))
    return (17.8824 * r + 43.5161 * g + 4.11935 * b,
            3.45565 * r + 27.1554 * g + 3.86714 * b,
            0.0299566 * r + 0.184309 * g + 1.46709 * b)


def _deuteranope(hexstr):
    """Brettel/Vienot simulation of the commonest colour-vision deficiency."""
    L, M, S = _to_lms(hexstr)
    M = 0.494207 * L + 1.24827 * S
    rgb = (0.0809444479 * L - 0.130504409 * M + 0.116721066 * S,
           -0.0102485335 * L + 0.0540193266 * M - 0.113614708 * S,
           -0.000365296938 * L - 0.00412161469 * M + 0.693511405 * S)
    out = []
    for c in rgb:
        c = max(0.0, min(1.0, c))
        c = 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055
        out.append(max(0, min(255, round(c * 255))))
    return "#%02x%02x%02x" % tuple(out)


def _lab(hexstr):
    r, g, b = (_linear(int(hexstr[i:i + 2], 16) / 255) for i in (1, 3, 5))
    X = r * 0.4124 + g * 0.3576 + b * 0.1805
    Y = r * 0.2126 + g * 0.7152 + b * 0.0722
    Z = r * 0.0193 + g * 0.1192 + b * 0.9505

    def f(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116

    fx, fy, fz = f(X / 0.95047), f(Y), f(Z / 1.08883)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def _delta_e(a, b):
    return math.dist(_lab(a), _lab(b))


def _check_cvd(doc, verbose):
    tints = _cvd_tints(doc)
    if not tints:
        return ["docs/tokyonight.md no longer has a %r table, so the diff "
                "tints cannot be checked for colour-vision safety"
                % CVD_HEADING]
    problems = []
    page = "#1a1b26"
    for tint, what in tints:
        got = _delta_e(_deuteranope(tint), _deuteranope(page))
        if got < CVD_FLOOR:
            problems.append(
                "%s: %s is only %.1f from the page to a deuteranope -- the "
                "hue that separates it from its opposite is already gone for "
                "them, so this lightness step is the whole cue"
                % (what, tint, got))
        elif verbose:
            print("  %6.1f dE  cvd   %s" % (got, what))
    return problems


def _linear(c):
    """One sRGB channel, 0-1, undone back to light."""
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(hexstr):
    lin = [_linear(int(hexstr[i:i + 2], 16) / 255.0) for i in (1, 3, 5)]
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def ratio(fg, bg):
    a, b = luminance(fg), luminance(bg)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


# Comment markers by file, so a colour can be looked for in what a tool will
# actually read rather than in the prose around it.
COMMENT_MARKERS = {
    ".lua": "--", ".json": "//", ".jsonc": "//",
}
DEFAULT_COMMENT_MARKER = "#"


def uncommented(path, text):
    """`text` with whole-line comments removed.

    The pair rows below carry a colour and the file it should be in, and the
    membership test used to run against the raw file. Every one of these
    configs explains its choices in comments, and a comment naming a colour is
    exactly what a change to that colour leaves behind -- so moving btop's
    inactive text from #565f89 to #414868, and saying so in a comment above it,
    left the checker asserting a 2.76:1 pair against a config painting 1.91:1
    and reporting nothing. Verified before this existed.
    """
    marker = COMMENT_MARKERS.get(os.path.splitext(path)[1],
                                 DEFAULT_COMMENT_MARKER)
    return "\n".join(line for line in text.splitlines()
                      if not line.lstrip().startswith(marker))


def check_contrast(doc, verbose):
    problems = []
    known = documented_colours(doc)
    bodies = {}
    for tier, fg, bg, source, what in PAIRS:
        if source not in bodies:
            bodies[source] = uncommented(
                source,
                open(os.path.join(REPO, source), encoding="utf-8").read()).lower()
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
            uncommented(source, open(os.path.join(REPO, source),
                                     encoding="utf-8").read()).lower(),
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

    problems.extend(run_check(_check_stated_pairs, verbose))
    problems.extend(run_check(_check_cvd, doc, verbose))
    return problems


# yazi is the one config that writes a foreground and a background together on
# a single line, which makes every pair in it readable without a human deciding
# which pairs exist. PAIRS above is hand-written and therefore covers what
# someone thought to list: 10 of yazi's 16 real pairs were missing from it, and
# one of those was the least readable pair in the repository.
STATED_FLOOR = 4.5

# Three syntaxes state a foreground against a background, so each needs its own
# reader. The bug that motivated all of this was written in all three at once.
SGR_PAIR = re.compile(r"38;2;(\d+);(\d+);(\d+);48;2;(\d+);(\d+);(\d+)")
TOML_FG = re.compile(r'\bfg\s*=\s*"(#[0-9a-fA-F]{6})"')
TOML_BG = re.compile(r'\bbg\s*=\s*"(#[0-9a-fA-F]{6})"')
TMUX_FG = re.compile(r"\bfg=(#[0-9a-fA-F]{6})")
TMUX_BG = re.compile(r"\bbg=(#[0-9a-fA-F]{6})")


def _pairs_toml(line):
    """yazi: one table per line, fg and bg beside each other."""
    fg, bg = TOML_FG.search(line), TOML_BG.search(line)
    return [(fg.group(1), bg.group(1))] if fg and bg else []


def _pairs_sgr(line):
    """lf's colours file: a raw SGR sequence, foreground then background."""
    return [("#%02x%02x%02x" % tuple(int(x) for x in m.group(1, 2, 3)),
             "#%02x%02x%02x" % tuple(int(x) for x in m.group(4, 5, 6)))
            for m in SGR_PAIR.finditer(line)]


def _pairs_tmux(line):
    """tmux: several independent style segments can share one line.

    Read per segment rather than per line. `window-status-current-format` sets
    three `#[...]` blocks in a row, and taking the first fg with the first bg
    across the whole line would invent a pair that is never drawn.
    """
    pairs = []
    for seg in re.split(r"#\[|\]|'|\"", line):
        fg, bg = TMUX_FG.search(seg), TMUX_BG.search(seg)
        if fg and bg:
            pairs.append((fg.group(1), bg.group(1)))
    return pairs


# fast-syntax-highlighting writes one role per line, a bare colour for text and
# `bg:` for a fill. Both are pairs against something implicit -- the page for a
# foreground, the default text colour for a fill -- which is why a scan looking
# for two colours on one line found none of its 52 roles.
FSH_ROLE = re.compile(r"^([\w-]+)\s*=\s*(\S.*)$")

# A rule glyph rather than text: it draws the line between a command and its
# output, so it is meant to sit just above the page the way a border does, and
# no tier in this file describes that.
FSH_NOT_TEXT = {"subtle-separator"}


def _pairs_fsh(line):
    m = FSH_ROLE.match(line.strip())
    if not m:
        return []
    role, value = m.group(1), m.group(2)
    if role in FSH_NOT_TEXT:
        return []
    hexes = HEX.findall(value)
    if len(hexes) != 1:
        return []
    if "bg:" in value:
        return [("#c0caf5", hexes[0])]   # default text on the fill
    return [(hexes[0], "#1a1b26")]       # text on the page


STATED_PAIRS = [
    (YAZI, _pairs_toml),
    ("common/.config/lf/colors", _pairs_sgr),
    (TMUX, _pairs_tmux),
]


def _check_stated_pairs(verbose):
    """Every foreground a config states against its own background is legible.

    Derived rather than listed, so it cannot go stale and a pair added later
    is covered the day it lands. That is the whole point: the sticky-directory
    rule was `#c0caf5` on `#7aa2f7` -- 1.56:1, effectively unreadable -- in
    yazi, lf and LS_COLORS alike, and it survived precisely because all three
    agreed, so the parity check was satisfied and no row in PAIRS named it.

    A line setting fg and bg to the same colour is skipped: those are yazi's
    solid marker blocks, where the point is a bar of colour with no text.

    Where PAIRS already tiers a pair, that tier wins. Some of these are meant
    to be quiet -- an inactive tab label is `ui`, not body text -- and the
    hand-written list is where that judgement belongs. The derived floor only
    applies to pairs nobody has tiered, which is exactly the set that had no
    floor at all before.
    """
    tiered = {(norm(fg), norm(bg)): TIERS[tier]
              for tier, fg, bg, _source, _what in PAIRS}
    problems, checked = [], 0
    for rel, extract in STATED_PAIRS:
        path = os.path.join(REPO, rel)
        if not os.path.isfile(path):
            continue
        for lineno, line in enumerate(open(path, encoding="utf-8"), 1):
            if line.lstrip().startswith("#"):
                continue
            for raw_fg, raw_bg in extract(line):
                f, b = norm(raw_fg), norm(raw_bg)
                if f == b:
                    continue
                checked += 1
                got = ratio(f, b)
                floor = tiered.get((f, b), STATED_FLOOR)
                if got < floor:
                    problems.append(
                        "%s:%d: %s on %s is %.2f:1, below %.1f:1 -- %s"
                        % (rel, lineno, f, b, got, floor, line.strip()[:60]))
    for rel, stem, f, b in _name_paired():
        checked += 1
        got = ratio(f, b)
        floor = tiered.get((f, b), STATED_FLOOR)
        if got < floor:
            problems.append(
                "%s: %s is %s on %s, %.2f:1, below %.1f:1"
                % (rel, stem, f, b, got, floor))

    exported, extra = _exported_pairs()
    problems.extend(extra)
    for name, entry, f, b in exported:
        checked += 1
        got = ratio(f, b)
        floor = tiered.get((f, b), STATED_FLOOR)
        if got < floor:
            problems.append(
                "$%s: %s on %s is %.2f:1, below %.1f:1 -- %s"
                % (name, f, b, got, floor, entry))

    if verbose and not problems:
        print("  %6s   %d stated fg/bg pairs, all at or above %.1f:1"
              % ("", checked, STATED_FLOOR))
    return problems


# The shell exports are the fourth place a pair can be stated, and the one with
# no file to read: theme.sh builds them from palette variables, so the pair only
# exists once the file has been sourced.
#
# Most of what is in here is mirrored in lf's colours file and kept honest by
# the parity check, which is why the sticky bug could not have hidden here
# alone. But eza has keys lf has no equivalent for, and a pair written only
# under one of those has nothing to disagree with -- an eza-only foreground on
# an eza-only background at 2.76:1 passed palette, parity and contrast alike
# before this existed.
SGR_PAIR_EITHER = re.compile(
    r"(?:38;2;(\d+);(\d+);(\d+);48;2;(\d+);(\d+);(\d+))"
    r"|(?:48;2;(\d+);(\d+);(\d+);38;2;(\d+);(\d+);(\d+))")


# Two more configs pair a foreground with a background, but by *naming* rather
# than by adjacency: btop writes theme[selected_fg] and theme[selected_bg] a
# dozen lines apart, lazygit writes cherryPickedCommitFgColor beside its
# BgColor. Nothing reads them as pairs unless the shared stem is what joins
# them, which is why a line-based reader saw none of these six.
NAME_PAIRED = [
    ("common/.config/btop/themes/tokyo-night.theme",
     r'theme\[([a-z_]+)\]="(#[0-9a-fA-F]{6})"', "_fg", "_bg"),
    ("common/.config/lazygit/config.yml",
     r'(\w+Color):\s*\["(#[0-9a-fA-F]{6})"', "FgColor", "BgColor"),
]


def _name_paired():
    """Foregrounds and backgrounds joined by a shared key stem."""
    found = []
    for rel, key_re, fg_suffix, bg_suffix in NAME_PAIRED:
        path = os.path.join(REPO, rel)
        if not os.path.isfile(path):
            continue
        keys = dict((k, norm(v)) for k, v in
                    re.findall(key_re, open(path, encoding="utf-8").read()))
        for key, fg in sorted(keys.items()):
            if not key.endswith(fg_suffix):
                continue
            bg = keys.get(key[:-len(fg_suffix)] + bg_suffix)
            if bg and bg != fg:
                found.append((rel, key[:-len(fg_suffix)], fg, bg))
    return found


def _exported_pairs():
    import subprocess

    path = os.path.join(REPO, "common/.config/shell/theme.sh")
    names = ["LS_COLORS", "EZA_COLORS", "GREP_COLORS"]
    script = '. "$1"; for v in %s; do eval "printf \'%%s\\n\' \\"\\$$v\\""; done' \
        % " ".join(names)
    try:
        code, stdout, stderr = source_theme("bash", path, script)
    except (OSError, subprocess.SubprocessError) as exc:
        return [], ["could not source theme.sh for its stated pairs: %s" % exc]
    if code != 0:
        return [], ["theme.sh failed to source: %s" % stderr.strip()]

    found = []
    for name, value in zip(names, stdout.split("\n")):
        for entry in value.split(":"):
            m = SGR_PAIR_EITHER.search(entry)
            if not m:
                continue
            nums = [n for n in m.groups() if n is not None]
            fg, bg = nums[:3], nums[3:]
            if m.group(7) is not None:  # the background came first
                fg, bg = bg, fg
            f = "#%02x%02x%02x" % tuple(int(n) for n in fg)
            b = "#%02x%02x%02x" % tuple(int(n) for n in bg)
            if f != b:
                found.append((name, entry, f, b))
    return found, []


# --------------------------------------------------------------------------

CHECKS = {
    "palette": check_palette,
    "parity": check_parity,
    "contrast": check_contrast,
}


def preview():
    """Render the theme as the things it is actually for.

    A column of swatches tells you the colours are right. It does not tell you
    whether a diff is readable, whether a selected row stands out, or whether
    build noise recedes far enough without vanishing -- and those are the
    questions the theme exists to answer. So this draws small mock-ups of the
    surfaces, out of the same colours the configs use, in one screen instead of
    twelve tools.

    Everything below is a still image made of escape sequences. It runs no
    tool and reads no config beyond the palette already loaded above.
    """

    def sgr(fg=None, bg=None, bold=False, dim=False):
        parts = []
        if bold:
            parts.append("1")
        if dim:
            parts.append("2")
        for role, colour in (("38", fg), ("48", bg)):
            if colour:
                r, g, b = (int(colour[i:i + 2], 16) for i in (1, 3, 5))
                parts.append("%s;2;%d;%d;%d" % (role, r, g, b))
        return "\033[%sm" % ";".join(parts) if parts else ""

    R = "\033[0m"

    def line(text, fg=None, bg=None, bold=False, dim=False, width=64):
        pad = " " * max(0, width - len(text))
        return "  %s%s%s%s" % (sgr(fg, bg, bold, dim), text + pad, R, "")

    P = {"bg": "#1a1b26", "bg_dark": "#16161e", "vis": "#283457",
         "high": "#292e42", "fg": "#c0caf5", "dark5": "#737aa2",
         "comment": "#565f89", "dark3": "#545c7e", "red": "#f7768e",
         "green": "#9ece6a", "yellow": "#e0af68", "blue": "#7aa2f7",
         "magenta": "#bb9af7", "cyan": "#7dcfff", "orange": "#ff9e64",
         "teal": "#1abc9c", "purple": "#9d7cd8", "blue5": "#89ddff",
         "plus": "#20432b", "plus_emph": "#2c5a3a", "minus": "#532727",
         "minus_emph": "#683131", "moved_to": "#12384a"}

    print("\n\033[1mA file listing\033[0m  (lf, yazi, ls, eza and the completion menu)\n")
    rows = [("  src/", "blue", True, False), ("  build.log", "dark5", False, False),
            ("  main.cpp", "green", False, False), ("  Cargo.toml", "yellow", False, False),
            ("  README.md", "fg", False, False), ("  archive.zip", "red", False, False),
            ("  notes.pdf", "orange", False, False), ("  target.o", "dark5", False, False)]
    for i, (name, colour, bold, _) in enumerate(rows):
        # The fourth row is under the cursor, which is the case that matters:
        # a file colour has to survive the selection fill behind it.
        on_cursor = i == 1
        print(line(name + ("      <- cursor" if on_cursor else ""),
                   fg=P[colour], bg=P["vis"] if on_cursor else P["bg"], bold=bold))

    print("\n\033[1mA diff\033[0m  (delta, and Neovim's inline diff)\n")
    for text, bg, fg in [
        ("   context line, unchanged", "bg", "fg"),
        ("  -    return old_value;", "minus", "fg"),
        ("  -    return OLD;", "minus_emph", "fg"),
        ("  +    return new_value;", "plus", "fg"),
        ("  +    return NEW;", "plus_emph", "fg"),
        ("  ~    moved here from line 118", "moved_to", "fg"),
    ]:
        print(line(text, fg=P[fg], bg=P[bg]))

    print("\n\033[1mA search result\033[0m  (ripgrep, grep, delta --grep, fzf)\n")
    hit = sgr(P["bg"], P["yellow"], bold=True) + "needle" + R
    print("  %ssrc/main.cpp%s%s:%s%s42%s: const auto %s = find();"
          % (sgr(P["blue"]), R, sgr(P["dark3"]), R, sgr(P["dark3"]), R, hit))
    print("  %ssrc/util.h%s%s:%s%s7%s:  // the %s lives here"
          % (sgr(P["blue"]), R, sgr(P["dark3"]), R, sgr(P["dark3"]), R, hit))

    print("\n\033[1mA command line\033[0m  (fast-syntax-highlighting, PSReadLine)\n")
    cl = [("for", "magenta"), (" f ", "fg"), ("in", "magenta"), (" *.txt", "blue5"),
          ("; ", "blue5"), ("do ", "magenta"), ("grep", "green"),
          (" --color=auto", "cyan"), (' "needle"', "yellow"), (" $f", "purple"),
          ("; ", "blue5"), ("done", "magenta"), ("   # and a comment", "comment")]
    print("  " + "".join(sgr(P[c]) + t + R for t, c in cl))
    print("  " + sgr(P["green"]) + "git" + R + sgr(P["fg"]) + " status" + R
          + sgr(P["comment"]) + "  --short   <- the suggestion, not yours yet" + R)

    print("\n\033[1mA prompt and a status bar\033[0m  (starship, tmux)\n")
    print("  " + sgr(P["teal"], bold=True) + "you" + R + sgr(P["fg"]) + " " + R
          + sgr(P["blue"], bold=True) + "~/dotfiles" + R + sgr(P["fg"]) + " on " + R
          + sgr(P["magenta"], bold=True) + " main" + R
          + sgr(P["yellow"]) + "  1.2s" + R)
    print("  " + sgr(P["green"], bold=True) + "➜" + R + " ")
    bar = (sgr(P["orange"], P["bg"]) + " work " + R
           + sgr(P["blue"], P["high"]) + " 1 " + R
           + sgr(P["blue"], P["bg"]) + "editor " + R
           + sgr(P["dark3"], P["bg"]) + "2 " + R
           + sgr(P["fg"], P["bg"]) + "build" + R
           + sgr(P["comment"], P["bg"]) + "        " + R
           + sgr(P["dark5"], P["bg"]) + "hostname " + R)
    print("  " + bar)
    print()
    return 0


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
    if "preview" in argv:
        return preview()
    if "swatch" in argv:
        rc = swatch(read_doc())
        return rc or preview()

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
