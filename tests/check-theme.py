#!/usr/bin/env python3
"""Check that the Tokyo Night theme says the same thing everywhere.

The theme is spread across a dozen tools that each want it in their own
syntax — hex here, decimal SGR triples there, a TOML table somewhere else —
and nothing but care has been keeping them in agreement. This is that care,
written down:

  1. every colour in a themed config is one docs/tokyonight.md documents
  2. kitty, wezterm and VS Code's terminal agree, slot for slot
  3. the file-type table is the same in LS_COLORS, lf and yazi
  4. Neovim's inline diff uses delta's tints, exactly
  5. every file naming the syntax theme names the same one
  6. the roles that only work if they are one colour (the cursor, the
     selected row, a search match) are that one colour everywhere
  7. docs/tokyonight.md's file table points at files that exist

Run it after touching any colour:

    tests/check-theme.py            # report and exit non-zero on drift
    tests/check-theme.py --verbose  # also list what was checked

It needs nothing but python3 and a POSIX shell.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# --- helpers ---------------------------------------------------------------

HEX_RE = re.compile(r"#[0-9a-fA-F]{6}\b")
SGR_RE = re.compile(r"\b(?:38|48);2;(\d{1,3});(\d{1,3});(\d{1,3})\b")


def norm(hex_colour: str) -> str:
    """Lowercase a #rrggbb so #FF5000 and #ff5000 compare equal."""
    return hex_colour.lower()


def sgr_to_hex(red: str, green: str, blue: str) -> str:
    return "#{:02x}{:02x}{:02x}".format(int(red), int(green), int(blue))


def read(relative: str) -> str:
    return (REPO / relative).read_text(encoding="utf-8")


class Report:
    """Collects failures so one run reports every problem, not just the first."""

    def __init__(self, verbose: bool) -> None:
        self.failures: list[str] = []
        self.verbose = verbose

    def fail(self, check: str, message: str) -> None:
        self.failures.append(f"{check}: {message}")

    def ok(self, message: str) -> None:
        if self.verbose:
            print(f"  ok  {message}")


# --- 1. every colour is a documented colour --------------------------------

# Files whose colours are theme chrome, and so must come from the palette.
#
# Deliberately absent: the files that colour *code* rather than chrome.
# lua/util/vscode_syntax.lua and the token customisations in the VS Code
# settings are Visual Studio Dark+ / Dark-C++ values by design
# (docs/vscode-syntax-parity.md), and tests/check-nvim-syntax-roles.sh is
# what guards those.
CHROME_FILES = [
    "common/.config/kitty/themes/tokyonight_night.conf",
    "common/.config/kitty/kitty.conf",
    "common/.config/wezterm/wezterm.lua",
    "common/.tmux.conf",
    "common/.config/lazygit/config.yml",
    "common/.config/starship.toml",
    "common/.config/shell/theme.sh",
    "common/.zshrc",
    "common/.ripgreprc",
    "common/.config/yazi/theme.toml",
    "common/.config/lf/colors",
    "common/.config/btop/themes/tokyo-night.theme",
    "common/.config/git/config",
    "common/.config/nvim/lua/plugins/tokyonight.lua",
    "common/.config/nvim/lua/util/inline_diff.lua",
    "common/.local/bin/st-rg",
    "common/.local/bin/st-zoekt",
    "windows/Documents/PowerShell/Microsoft.PowerShell_profile.ps1",
    "doctor-theme.sh",
]

# #000000 is not a palette entry and never will be: it is the text colour
# under the #ff5000 cursor, where the point is maximum contrast against the
# one deliberately non-Tokyo-Night colour in the setup.
ALWAYS_ALLOWED = {"#000000"}


def documented_colours() -> set[str]:
    """Every hex docs/tokyonight.md mentions, from any table or paragraph.

    The doc is the registry, so a new colour is legal exactly when someone
    has written down what it is for.
    """
    return {norm(h) for h in HEX_RE.findall(read("docs/tokyonight.md"))}


def colours_in(relative: str) -> dict[str, list[int]]:
    """Every colour a file names, hex or SGR triple, with line numbers."""
    found: dict[str, list[int]] = {}
    for number, line in enumerate(read(relative).splitlines(), start=1):
        # A comment that explains which hex an SGR triple stands for would
        # otherwise be double counted; both forms land on the same colour, so
        # it makes no difference to the result.
        for hex_colour in HEX_RE.findall(line):
            found.setdefault(norm(hex_colour), []).append(number)
        for red, green, blue in SGR_RE.findall(line):
            found.setdefault(sgr_to_hex(red, green, blue), []).append(number)
    return found


def check_documented(report: Report) -> None:
    palette = documented_colours()
    if len(palette) < 30:
        report.fail("palette", f"only {len(palette)} colours found in docs/tokyonight.md")
        return
    for relative in CHROME_FILES:
        undocumented = {
            colour: lines
            for colour, lines in colours_in(relative).items()
            if colour not in palette and colour not in ALWAYS_ALLOWED
        }
        for colour, lines in sorted(undocumented.items()):
            where = ", ".join(str(line) for line in lines)
            report.fail(
                "palette",
                f"{relative}:{where} uses {colour}, which docs/tokyonight.md "
                f"does not document",
            )
        if not undocumented:
            report.ok(f"{relative} uses only documented colours")


# --- 2. kitty and wezterm agree --------------------------------------------

# The pairs that have to match, named as kitty spells them.
TERMINAL_KEYS = [
    "background",
    "foreground",
    "cursor",
    "cursor_text_color",
    "selection_background",
    "selection_foreground",
] + [f"color{index}" for index in range(18)]

# How wezterm.lua spells the same thing. ansi/brights are indexed lists, so
# they are handled separately.
WEZTERM_KEYS = {
    "background": "background",
    "foreground": "foreground",
    "cursor": "cursor_bg",
    "cursor_text_color": "cursor_fg",
    "selection_background": "selection_bg",
    "selection_foreground": "selection_fg",
}


# VS Code's integrated terminal is the third terminal these dotfiles ship, and
# it runs exactly the same tools as the other two.
#
# Only these keys are compared. The rest of settings.json is out of scope for
# the palette check on purpose: it carries Dark+ token colours and a handful of
# debug-view colours that are not Tokyo Night and are not trying to be.
VSCODE_TERMINAL_KEYS = {
    "background": "terminal.background",
    "foreground": "terminal.foreground",
    "cursor": "terminalCursor.foreground",
    "cursor_text_color": "terminalCursor.background",
    "selection_background": "terminal.selectionBackground",
    "selection_foreground": "terminal.selectionForeground",
    "color0": "terminal.ansiBlack",
    "color1": "terminal.ansiRed",
    "color2": "terminal.ansiGreen",
    "color3": "terminal.ansiYellow",
    "color4": "terminal.ansiBlue",
    "color5": "terminal.ansiMagenta",
    "color6": "terminal.ansiCyan",
    "color7": "terminal.ansiWhite",
    "color8": "terminal.ansiBrightBlack",
    "color9": "terminal.ansiBrightRed",
    "color10": "terminal.ansiBrightGreen",
    "color11": "terminal.ansiBrightYellow",
    "color12": "terminal.ansiBrightBlue",
    "color13": "terminal.ansiBrightMagenta",
    "color14": "terminal.ansiBrightCyan",
    "color15": "terminal.ansiBrightWhite",
}


def parse_vscode_terminal() -> dict[str, str]:
    """The terminal colours out of settings.json.

    Read with a regex rather than a JSON parser: the file is JSON with
    comments, and the point here is to find a fixed set of known keys, not to
    understand the document.
    """
    text = read("common/.config/Code/User/settings.json")
    # Drop line comments so a commented-out key is not mistaken for a live one.
    text = re.sub(r"^\s*//.*$", "", text, flags=re.M)
    values: dict[str, str] = {}
    for key in VSCODE_TERMINAL_KEYS.values():
        match = re.search(rf'"{re.escape(key)}"\s*:\s*"(#[0-9a-fA-F]{{6}})"', text)
        if match:
            values[key] = norm(match.group(1))
    return values


def parse_kitty_theme() -> dict[str, str]:
    values: dict[str, str] = {}
    for line in read("common/.config/kitty/themes/tokyonight_night.conf").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 1)
        if len(parts) == 2 and HEX_RE.fullmatch(parts[1].strip()):
            values[parts[0]] = norm(parts[1].strip())
    return values


def parse_wezterm_colours() -> tuple[dict[str, str], list[str], list[str]]:
    # Strip Lua comments first. The brights table carries a note explaining
    # why bright black is lightened, and that note names the upstream hex —
    # left in, it reads as a ninth bright colour.
    text = re.sub(r"--[^\n]*", "", read("common/.config/wezterm/wezterm.lua"))
    scalars = {
        key: norm(match.group(1))
        for key in WEZTERM_KEYS.values()
        if (match := re.search(rf"^\s*{key}\s*=\s*'(#[0-9a-fA-F]{{6}})'", text, re.M))
    }

    def indexed(name: str) -> list[str]:
        block = re.search(rf"{name}\s*=\s*\{{(.*?)\}}", text, re.S)
        return [norm(h) for h in HEX_RE.findall(block.group(1))] if block else []

    return scalars, indexed("ansi"), indexed("brights")


def check_terminals(report: Report) -> None:
    kitty = parse_kitty_theme()
    scalars, ansi, brights = parse_wezterm_colours()

    if len(ansi) != 8 or len(brights) != 8:
        report.fail(
            "terminals",
            f"wezterm.lua has {len(ansi)} ansi and {len(brights)} bright colours, "
            f"expected 8 and 8",
        )
        return

    for key in TERMINAL_KEYS:
        expected = kitty.get(key)
        if expected is None:
            report.fail("terminals", f"kitty theme has no {key}")
            continue
        if key.startswith("color"):
            index = int(key[len("color") :])
            if index < 8:
                actual = ansi[index]
            elif index < 16:
                actual = brights[index - 8]
            else:
                # color16/17 are kitty's extended slots. wezterm has no
                # equivalent, so there is nothing to compare — but they do
                # have to be documented colours, which check 1 covers.
                continue
        else:
            actual = scalars.get(WEZTERM_KEYS[key])
        if actual is None:
            report.fail("terminals", f"wezterm.lua does not set the equivalent of {key}")
        elif actual != expected:
            report.fail(
                "terminals",
                f"{key} is {expected} in kitty but {actual} in wezterm",
            )
    report.ok("kitty and wezterm agree on every shared slot")

    vscode = parse_vscode_terminal()
    for key, setting in VSCODE_TERMINAL_KEYS.items():
        expected = kitty.get(key)
        if expected is None:
            continue  # already reported above
        actual = vscode.get(setting)
        if actual is None:
            report.fail(
                "terminals",
                f"VS Code's settings.json does not set {setting} (kitty's {key})",
            )
        elif actual != expected:
            report.fail(
                "terminals",
                f"{key} is {expected} in kitty but {setting} is {actual} in VS Code",
            )
    report.ok("VS Code's integrated terminal agrees with kitty")


# --- 3. one file-type table, three dialects --------------------------------

# yazi describes some categories by mime type where LS_COLORS and lf can only
# name extensions. The extensions on the left are expected to take the colour
# of the yazi rule on the right.
YAZI_MIME_FOR_EXTENSION = {
    "png": "image/*",
    "jpg": "image/*",
    "jpeg": "image/*",
    "gif": "image/*",
    "webp": "image/*",
    "svg": "image/*",
    "ico": "image/*",
    "mp4": "video/*",
    "mkv": "video/*",
    "mov": "video/*",
    "webm": "video/*",
    "mp3": "audio/*",
    "flac": "audio/*",
    "wav": "audio/*",
    "m4a": "audio/*",
    "ogg": "audio/*",
    "pdf": "application/pdf",
    "epub": "application/epub+zip",
}

# LS_COLORS / lf file-kind keys and the yazi `is =` rule that means the same.
# The keys with no yazi equivalent (mh, ow, tw, su, sg) are simply absent.
KIND_TO_YAZI_IS = {
    "or": "orphan",
    "ln": "link",
    "bd": "block",
    "cd": "char",
    "pi": "fifo",
    "so": "sock",
    "st": "sticky",
    "ex": "exec",
}


def ls_colors_from_theme_sh() -> dict[str, str]:
    """Ask a real shell for LS_COLORS rather than reparsing theme.sh."""
    script = ". " + str(REPO / "common/.config/shell/theme.sh") + '; printf %s "$LS_COLORS"'
    result = subprocess.run(
        ["sh", "-c", script],
        capture_output=True,
        text=True,
        check=False,
        env={"PATH": "/usr/bin:/bin", "HOME": str(REPO)},
    )
    if result.returncode != 0:
        raise RuntimeError(f"sourcing theme.sh failed: {result.stderr.strip()}")
    entries: dict[str, str] = {}
    for entry in result.stdout.split(":"):
        if "=" in entry:
            key, _, value = entry.partition("=")
            entries[key] = value
    return entries


def parse_lf_colors() -> dict[str, str]:
    entries: dict[str, str] = {}
    for line in read("common/.config/lf/colors").splitlines():
        line = line.split("#", 1)[0].strip() if not line.lstrip().startswith("#") else ""
        if not line:
            continue
        parts = line.split()
        if len(parts) >= 2:
            entries[parts[0]] = parts[1]
    return entries


def parse_yazi_filetypes() -> dict[str, dict[str, str]]:
    """Map each yazi [filetype] rule to its attributes.

    Keyed by "*.ext", a mime string, or "is:<kind>" so the caller can look a
    rule up the way it thinks about it.
    """
    text = read("common/.config/yazi/theme.toml")
    block = re.search(r"^\[filetype\]\s*\nrules\s*=\s*\[(.*?)^\]", text, re.S | re.M)
    if not block:
        raise RuntimeError("could not find the [filetype] rules array in yazi's theme")
    rules: dict[str, dict[str, str]] = {}
    for raw in re.findall(r"\{([^}]*)\}", block.group(1)):
        fields = dict(
            (key, value)
            for key, value in re.findall(r"(\w+)\s*=\s*\"([^\"]*)\"", raw)
        )
        flags = dict(re.findall(r"(\w+)\s*=\s*(true|false)", raw))
        fields.update(flags)
        if "mime" in fields:
            key = fields["mime"]
        elif "is" in fields:
            key = "is:" + fields["is"]
        elif "name" in fields:
            key = fields["name"]
        else:
            continue
        rules.setdefault(key, fields)
    return rules


def sgr_fg_hex(value: str) -> str | None:
    """The foreground hex an LS_COLORS value sets, if it sets one."""
    match = re.search(r"38;2;(\d{1,3});(\d{1,3});(\d{1,3})", value)
    return sgr_to_hex(*match.groups()) if match else None


def check_filetypes(report: Report) -> None:
    try:
        ls_colors = ls_colors_from_theme_sh()
    except RuntimeError as error:
        report.fail("filetypes", str(error))
        return
    lf_colors = parse_lf_colors()
    yazi = parse_yazi_filetypes()

    # LS_COLORS and lf/colors are the same dialect, so they must be identical.
    ls_keys = set(ls_colors)
    lf_keys = set(lf_colors)
    for key in sorted(ls_keys - lf_keys):
        report.fail("filetypes", f"{key} is in theme.sh's LS_COLORS but not in lf/colors")
    for key in sorted(lf_keys - ls_keys):
        report.fail("filetypes", f"{key} is in lf/colors but not in theme.sh's LS_COLORS")
    for key in sorted(ls_keys & lf_keys):
        if ls_colors[key] != lf_colors[key]:
            report.fail(
                "filetypes",
                f"{key} is {ls_colors[key]} in theme.sh but {lf_colors[key]} in lf/colors",
            )
    if ls_keys == lf_keys and all(ls_colors[k] == lf_colors[k] for k in ls_keys):
        report.ok(f"theme.sh and lf/colors agree on all {len(ls_keys)} entries")

    # yazi says the same thing in its own schema.
    for key, value in sorted(ls_colors.items()):
        expected = sgr_fg_hex(value)
        if expected is None:
            continue
        if key.startswith("*."):
            extension = key[2:]
            mime = YAZI_MIME_FOR_EXTENSION.get(extension)
            rule = yazi.get(key) or (yazi.get(mime) if mime else None)
            label = f"{key} (via {mime})" if mime and key not in yazi else key
        elif key == "di":
            rule, label = yazi.get("*/"), "di (yazi's */ glob)"
        elif key in KIND_TO_YAZI_IS:
            rule = yazi.get("is:" + KIND_TO_YAZI_IS[key])
            label = f"{key} (yazi is = {KIND_TO_YAZI_IS[key]})"
        else:
            # mh/ow/tw/su/sg have no yazi counterpart.
            continue
        if rule is None:
            report.fail("filetypes", f"yazi's theme has no rule matching {label}")
            continue
        actual = norm(rule.get("fg", ""))
        if actual != expected:
            report.fail(
                "filetypes",
                f"{label} is {expected} in LS_COLORS but {actual or 'unset'} in yazi",
            )
        # Bold has to agree too, or a broken symlink shouts in one pane and
        # whispers in the next.
        ls_bold = bool(re.search(r"(?:^|;)0?1(?:;|$)", value))
        yazi_bold = rule.get("bold") == "true"
        if ls_bold != yazi_bold:
            report.fail(
                "filetypes",
                f"{label} is {'bold' if ls_bold else 'not bold'} in LS_COLORS but "
                f"{'bold' if yazi_bold else 'not bold'} in yazi",
            )
    report.ok("yazi's filetype rules match LS_COLORS")


# --- 4. the inline diff uses delta's tints ---------------------------------

# Neovim's inline diff exists to look like delta. These are the pairs that
# have to be the same colour for that to be true.
DIFF_PAIRS = [
    ("plus-style", "InlineDiffAdd"),
    ("plus-emph-style", "InlineDiffAddEmph"),
    ("plus-non-emph-style", "InlineDiffAddDim"),
    ("minus-style", "InlineDiffDelete"),
    ("minus-emph-style", "InlineDiffDeleteEmph"),
    ("minus-non-emph-style", "InlineDiffDeleteDim"),
]


def delta_styles() -> dict[str, str]:
    text = read("common/.config/git/config")
    styles: dict[str, str] = {}
    for key, value in re.findall(r"^\s*([a-z-]+)\s*=\s*\"?([^\"\n]+)\"?\s*$", text, re.M):
        styles[key] = value.strip()
    return styles


def inline_diff_groups() -> dict[str, str]:
    text = read("common/.config/nvim/lua/util/inline_diff.lua")
    return {
        name: norm(colour)
        for name, colour in re.findall(
            r"(InlineDiff\w+)\s*=\s*\{[^}]*bg\s*=\s*\"(#[0-9a-fA-F]{6})\"", text
        )
    }


def check_diff_tints(report: Report) -> None:
    styles = delta_styles()
    groups = inline_diff_groups()
    for delta_key, group in DIFF_PAIRS:
        raw = styles.get(delta_key)
        if raw is None:
            report.fail("diff", f"delta has no {delta_key} in the git config")
            continue
        match = HEX_RE.search(raw)
        if not match:
            report.fail("diff", f"delta's {delta_key} ({raw!r}) names no colour")
            continue
        expected = norm(match.group(0))
        actual = groups.get(group)
        if actual is None:
            report.fail("diff", f"inline_diff.lua has no {group} background")
        elif actual != expected:
            report.fail(
                "diff",
                f"delta's {delta_key} is {expected} but {group} is {actual}",
            )

    # The move colours come from delta's map-styles, which is one string.
    map_styles = styles.get("map-styles", "")
    move_expectations = {
        "bold cyan": "InlineDiffMovedAdd",
        "bold purple": "InlineDiffMovedDelete",
    }
    for git_colour, group in move_expectations.items():
        match = re.search(
            rf"{git_colour}\s*=>\s*\w+\s+(#[0-9a-fA-F]{{6}})", map_styles
        )
        if not match:
            report.fail("diff", f"delta's map-styles does not remap {git_colour!r}")
            continue
        expected = norm(match.group(1))
        actual = groups.get(group)
        if actual != expected:
            report.fail(
                "diff",
                f"delta maps {git_colour!r} to {expected} but {group} is {actual}",
            )
    report.ok("the inline diff and delta use the same tints")


# --- 5. one name for the syntax theme --------------------------------------

# Where the syntax theme is named, and the pattern that pulls the name out.
# These have to agree: bat, delta and the yazi preview are meant to render the
# same file identically, and each learns the theme from a different one of
# these. A change to one alone is invisible until two panes disagree.
SYNTAX_THEME_SOURCES = [
    ("common/.zshenv", r'BAT_THEME="([^"]+)"'),
    ("common/.bashrc-custom", r'BAT_THEME="([^"]+)"'),
    ("common/.config/git/config", r'syntax-theme\s*=\s*"([^"]+)"'),
    ("common/.config/bat/config", r'--theme="([^"]+)"'),
]


def check_syntax_theme(report: Report) -> None:
    found: dict[str, str] = {}
    for relative, pattern in SYNTAX_THEME_SOURCES:
        match = re.search(pattern, read(relative))
        if not match:
            report.fail("syntax-theme", f"{relative} no longer names a syntax theme")
            continue
        found[relative] = match.group(1)
    names = set(found.values())
    if len(names) > 1:
        listing = ", ".join(f"{path} says {name!r}" for path, name in sorted(found.items()))
        report.fail("syntax-theme", f"the syntax theme is not the same everywhere: {listing}")
    elif names:
        report.ok(f"every file names the same syntax theme ({names.pop()!r})")


# --- 6. the roles that must be one colour ----------------------------------

# Some colours only earn their keep by being the same in every tool that uses
# them. "You are here" is worthless if it is orange in one pane and white in
# the next; a selected row that shifts shade between two panes reads as two
# different kinds of selection. Each role below lists every setting that makes
# the claim, so a tool added later cannot quietly make it in a new colour.
#
# A pattern's capture may be a hex, an "R;G;B" SGR triple, or a name the config
# uses for the colour (Lua's `c.bg_visual`) — anything in `aliases`.
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
                # [indicator] current — `[mgr] hovered` before yazi v25.12.29.
                "common/.config/yazi/theme.toml",
                r"^current = \{ fg = \"#[0-9a-fA-F]{6}\", bg = \"(#[0-9a-fA-F]{6})\"",
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


def check_shared_roles(report: Report) -> None:
    for role in SHARED_ROLES:
        expected = role["hex"]
        for relative, pattern in role["settings"]:
            match = re.search(pattern, read(relative), re.M)
            if not match:
                report.fail(
                    "roles",
                    f"{relative} no longer sets {role['name']} where the test looks "
                    f"for it ({pattern})",
                )
                continue
            found = match.group(1)
            if re.fullmatch(r"\d{1,3};\d{1,3};\d{1,3}", found):
                found = sgr_to_hex(*found.split(";"))
            if norm(found) != expected and found not in role["aliases"]:
                report.fail(
                    "roles",
                    f"{relative} sets {role['name']} to {found}, not {expected}",
                )
        report.ok(
            f"{role['name']} is {expected} in all {len(role['settings'])} "
            f"places that set it"
        )


# --- 7. the docs point at real files ---------------------------------------


def check_doc_paths(report: Report) -> None:
    text = read("docs/tokyonight.md")
    section = text.split("## Where the theme lives", 1)
    if len(section) != 2:
        report.fail("docs", "docs/tokyonight.md has no 'Where the theme lives' section")
        return
    # Package directories, plus the root-level doctor scripts.
    paths = re.findall(
        r"`((?:common|windows|mac|tests)/[^`]+?|doctor-[a-z-]+\.(?:sh|py))`", section[1]
    )
    if not paths:
        report.fail("docs", "the 'Where the theme lives' table lists no files")
        return
    for raw in paths:
        # A cell may name a file and then a section of it in parentheses.
        candidate = raw.split()[0].rstrip(",")
        if not (REPO / candidate).exists():
            report.fail("docs", f"the theme table points at {candidate}, which does not exist")
    report.ok(f"all {len(paths)} paths in the theme table exist")

    # And every file this test checks should be findable from the docs, so the
    # table stays the index it claims to be.
    listed = {raw.split()[0].rstrip(",") for raw in paths}
    for relative in CHROME_FILES:
        if relative not in listed:
            report.fail(
                "docs",
                f"{relative} is themed but missing from the 'Where the theme lives' table",
            )


# --- main ------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--verbose", action="store_true", help="list the checks that passed too"
    )
    arguments = parser.parse_args()

    report = Report(arguments.verbose)
    for check in (
        check_documented,
        check_terminals,
        check_filetypes,
        check_diff_tints,
        check_syntax_theme,
        check_shared_roles,
        check_doc_paths,
    ):
        try:
            check(report)
        except Exception as error:  # a broken parse is a failure, not a crash
            report.fail(check.__name__, f"{type(error).__name__}: {error}")

    if report.failures:
        print(f"theme check: {len(report.failures)} problem(s)\n", file=sys.stderr)
        for failure in report.failures:
            print(f"  {failure}", file=sys.stderr)
        print(
            "\nEvery colour has to be in docs/tokyonight.md, and the tools that "
            "say the same\nthing have to say it the same way. Fix the config, or "
            "document the colour.",
            file=sys.stderr,
        )
        return 1

    print("theme check: all consistent")
    return 0


if __name__ == "__main__":
    sys.exit(main())
