#!/usr/bin/env python3
"""Check that tests/check-theme.py catches what it says it catches.

    tests/check-theme-selftest.py
    tests/check-theme-selftest.py --verbose

A checker that never fails is indistinguishable from a checker that is broken,
and check-theme.py has grown to nine separate checks across four file formats
and three external binaries. Each one was proved to work once, by hand, by
breaking a config and watching it complain -- which is a real test, performed
once and then thrown away. This performs all of them, every time.

Two kinds of test:

  mutations   Copy the working tree, make one specific thing wrong in it, run
              the checker against the copy, and require it to fail *and* to say
              why in recognisable words. The copy is the working tree rather
              than HEAD, so this tests the files as they are right now.

  units       Direct assertions on the pure functions underneath -- the
              contrast maths, the tier floors, the palette parsing. These cover
              the branches a config mutation cannot reach: a pair's tier floor
              and the fill floor are compared against numbers the configs do
              not contain, so there is nothing to mutate.

Mutations that need a tool the machine does not have are skipped and reported,
in the same spirit as the checks themselves.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

KITTY = "common/.config/kitty/themes/tokyonight_night.conf"
VSCODE = "common/.config/Code/User/settings.json"
THEME_SH = "common/.config/shell/theme.sh"
LF_COLORS = "common/.config/lf/colors"
LFRC = "common/.config/lf/lfrc"
YAZI = "common/.config/yazi/theme.toml"
GIT = "common/.config/git/config"
TMUX = "common/.tmux.conf"
RGRC = "common/.ripgreprc"
BTOP = "common/.config/btop/themes/tokyo-night.theme"
LAZYGIT = "common/.config/lazygit/config.yml"
STARSHIP = "common/.config/starship.toml"
INLINE_DIFF = "common/.config/nvim/lua/util/inline_diff.lua"
NVIM_THEME = "common/.config/nvim/lua/plugins/tokyonight.lua"
WEZTERM = "common/.config/wezterm/wezterm.lua"
VSCODE_EXTS = "vscode_extensions.txt"
FF = "common/.local/bin/ff"
PSPROFILE = "windows/Documents/PowerShell/Microsoft.PowerShell_profile.ps1"
ZSHENV = "common/.zshenv"
BASHRC = "common/.bashrc-custom"
NVIM_SYNTAX = "common/.config/nvim/lua/util/vscode_syntax.lua"
TOKYODOC = "docs/tokyonight.md"

# (name, check to run, file, pattern, replacement, expected words, tool needed)
#
# The patterns are regexes applied once, so none of them depend on the exact
# spacing of the line they are aimed at.
MUTATIONS = [
    ("an off-palette hex", "palette", KITTY,
     r"url_color #73daca", "url_color #73dac0",
     "is not a colour", None),

    ("an off-palette decimal triplet", "palette", RGRC,
     r"--colors=path:fg:122,162,247", "--colors=path:fg:122,162,248",
     "is not a colour", None),

    ("an off-palette colour the shell builds at runtime", "palette", THEME_SH,
     r"_tn_teal='26;188;156'", "_tn_teal='26;188;150'",
     "exports", None),

    ("an ANSI slot that disagrees between terminals", "parity", VSCODE,
     r'"terminal\.ansiBrightBlack": "#85899c"',
     '"terminal.ansiBrightBlack": "#414868"',
     "ANSI 8", None),

    # kitty warns about an unknown key and carries on, so a renamed or
    # misspelled option looks perfectly correct in the file forever.
    ("a kitty option kitty does not know", "parity", KITTY,
     r"macos_titlebar_color #16161e", "macos_titlebar_colour #16161e",
     "unknown config key", "kitty"),

    # Neovim is the fourth copy of the 16 ANSI slots, via `terminal_colors`.
    # It is the least obvious one, and it was the only one still on upstream's
    # values for the two slots this theme changes on purpose.
    ("Neovim's :terminal disagreeing with the terminals", "parity", NVIM_THEME,
     r'c\.terminal\.black_bright = "#85899c"',
     'c.terminal.black_bright = "#414868"',
     "ANSI 8 disagrees", None),

    # wezterm's config is Lua converted into a Rust struct, so an unparseable
    # colour is a hard error naming the key. The strictest oracle here.
    ("a wezterm colour wezterm cannot parse", "parity", WEZTERM,
     r"inactive_tab_edge = '#16161e'", "inactive_tab_edge = '#zzzzzz'",
     "failed to parse", "wezterm"),

    # Neovim's syntax colours are resolved against one specific VS Code theme.
    # Drop the extension providing it and nothing breaks loudly: VS Code falls
    # back to another dark theme and Neovim keeps painting colours resolved
    # against one that is no longer installed.
    ("the VS Code theme extension going missing", "parity", VSCODE_EXTS,
     r"ms-vscode\.cpptools-themes\n", "",
     "not in vscode_extensions.txt", None),

    ("a titlebar that disagrees between terminals", "parity", KITTY,
     r"macos_titlebar_color #16161e", "macos_titlebar_color #1a1b26",
     "titlebar disagrees", None),

    ("a file colour that differs between lf and yazi", "parity", YAZI,
     r'\{ url = "\*\.zip", fg = "#f7768e" \}',
     '{ url = "*.zip", fg = "#9ece6a" }',
     "in lf but", None),

    # The one that cost the most to find by hand. Yazi tolerates an unknown
    # *style* key silently, but an unknown *rule* key is fatal: it refuses the
    # whole file and falls back to its presets, so a single stale `name = `
    # cost the entire theme while every colour in the file still looked right.
    ("a yazi rule key yazi no longer accepts", "parity", YAZI,
     r'\{ url = "\*\.tar", fg = "#f7768e" \}',
     '{ name = "*.tar", fg = "#f7768e" }',
     "rejects one of its configs", "yazi"),

    ("a file colour that differs between lf and the shell", "parity", LF_COLORS,
     r"\*\.lock\s+38;2;115;122;162", "*.lock  38;2;115;122;150",
     "LS_COLORS", None),

    ("lf chrome that differs from yazi's", "parity", LFRC,
     r"set copyfmt \"\\033\[7;38;2;158;206;106m\"",
     'set copyfmt "\\033[7;38;2;224;175;104m"',
     "the yank marker", None),

    ("a Neovim diff colour that differs from delta's", "parity", INLINE_DIFF,
     r'InlineDiffAdd = \{ bg = "#20432b" \}',
     'InlineDiffAdd = { bg = "#2c5a3a" }',
     "two colours", None),

    ("a command-line role that differs between zsh and PowerShell", "parity",
     PSPROFILE,
     r'Keyword            = "\$e\[38;2;187;154;247m"',
     'Keyword            = "$e[38;2;125;207;255m"',
     "on the PowerShell one", None),

    ("a bat call site that forgets COLORTERM", "parity", FF,
     r"COLORTERM=truecolor bat", "bat",
     "without forcing COLORTERM", None),

    # theme.sh returns early for non-interactive shells, so everything that
    # reads it has to ask for it interactively. If that guard ever widened to
    # skip interactive shells too, every colour it exports would silently
    # vanish -- and the shell-parity check would not notice, because empty
    # equals empty. The LS_COLORS comparison against lf's table is what does.
    ("a guard that skips every shell, not just quiet ones", "parity", THEME_SH,
     r"\*i\*\) ;;", "*i*) return 0 ;;",
     "not in theme.sh's LS_COLORS", None),

    ("shell colours that break in zsh but not bash", "parity", THEME_SH,
     r"\$\{_tn_yellow\}:so=", "$_tn_yellow:so=",
     "does not source cleanly", "zsh"),

    # starship reports this to a log file rather than to stderr, so the check
    # has to go and read it. An earlier version watched stderr, and with that
    # one this mutation passed -- the config was broken and the checker said
    # nothing. Worth keeping the mutation on a key inside a module: it is the
    # shape a real typo takes, and it is the one that fooled the first
    # attempt.
    ("a starship key starship does not know", "parity", STARSHIP,
     r"\[hostname\]\n", "[hostname]\nnot_a_key = 1\n",
     "Unknown key", "starship"),

    # BAT_THEME decides what code looks like in five places at once, and it is
    # written out twice, once per shell.
    ("BAT_THEME disagreeing between the shells", "parity", BASHRC,
     r'export BAT_THEME="Visual Studio Dark\+"',
     'export BAT_THEME="Monokai Extended"',
     "differs between the shells", None),

    ("BAT_THEME naming a theme bat does not have", "parity", ZSHENV,
     r'export BAT_THEME="Visual Studio Dark\+"',
     'export BAT_THEME="No Such Theme"',
     "does not have", "bat|batcat"),

    # A git colour is a hex plus attributes, and the palette check only sees
    # the hex -- it passes this happily while git rejects the whole value and
    # the setting does nothing. This is the half a colour scanner cannot cover.
    ("a git colour attribute git rejects", "parity", GIT,
     r'current = "#bb9af7 bold"', 'current = "#bb9af7 blod"',
     "git rejects", None),

    ("a delta option that does not exist", "parity", GIT,
     r'blame-separator-style = "#3b4261"',
     'blame-separator-style = "#3b4261"\n    blame-timestamp-style = "#737aa2"',
     "delta has no", "delta"),

    # Coverage is the check that stops a config carrying colours nobody looks
    # at. Both directions matter: a file that falls out of every list, and a
    # list entry for a file that no longer has a colour in it.
    ("a colour-bearing file that fell off every list", "parity", TOKYODOC,
     r"\n\| `common/\.config/kitty/kitty\.conf` \|[^\n]*", "",
     "nothing checks it", None),

    ("an exemption for a file with no colours left", "parity", TOKYODOC,
     r"`common/\.config/kitty/kitty\.conf`", "`common/.config/kitty/gone.conf`",
     "stale", None),

    # The parity doc is where the VS Code resolution work is written down and
    # the lua file is where it is acted on, so the two can disagree silently:
    # a scope re-resolved in the doc leaves Neovim painting the old answer, and
    # a capture dropped from the mapping leaves a doc describing a colour the
    # editor does not have. One mutation for each direction.
    ("a documented capture painted the wrong colour", "parity", NVIM_SYNTAX,
     r'tag_delimiter = "#808080"', 'tag_delimiter = "#DFDDB9"',
     "paints it", None),

    ("a documented capture that lost its mapping", "parity", NVIM_SYNTAX,
     r'\n\s*\["@tag\.attribute"\] = c\.variable,[^\n]*', "",
     "does not map it", None),

    # The pair that motivated the derived scan: sticky directories were
    # #c0caf5 on #7aa2f7, 1.56:1, in yazi and lf and LS_COLORS at once. All
    # three agreeing is what hid it -- parity was satisfied and no hand-written
    # row named the pair, so nothing had an opinion about whether it was
    # readable. Putting the old value back has to fail.
    ("an unreadable pair that no hand-written row names", "contrast", YAZI,
     r'is = "sticky", fg = "#16161e"', 'is = "sticky", fg = "#c0caf5"',
     "below 4.5:1", None),

    # The same pair in the other two syntaxes it was written in. Each file
    # needs its own reader -- a raw SGR sequence in lf, style segments in
    # tmux -- so each reader needs its own proof that it fires.
    ("an unreadable SGR pair in lf's colours", "contrast", LF_COLORS,
     r"st      38;2;22;22;30;48;2;122;162;247",
     "st      38;2;192;202;245;48;2;122;162;247",
     "below 4.5:1", None),

    ("an unreadable tmux style segment", "contrast", TMUX,
     r"set -g menu-style          'bg=#16161e,fg=#c0caf5'",
     "set -g menu-style          'bg=#16161e,fg=#565f89'",
     "below 4.5:1", None),

    # The exports are the fourth place a pair can be stated and the only one
    # with no file to read -- theme.sh builds them from palette variables, so
    # the pair exists only once it has been sourced. eza has keys lf has no
    # equivalent for, so a pair written under one of those has nothing to
    # disagree with and the parity check cannot see it either.
    ("an unreadable pair only the shell exports state", "contrast", THEME_SH,
     r'tx=38;2;\$\{_tn_green\}"',
     'tx=38;2;${_tn_green}:xx=38;2;${_tn_comment};48;2;${_tn_bg_high}"',
     "below 4.5:1", None),

    # btop and lazygit join a foreground to a background by key stem, not by
    # adjacency -- theme[selected_fg] and theme[selected_bg] sit a dozen lines
    # apart. A line-based reader saw none of these six pairs.
    ("a name-paired btop fg/bg gone unreadable", "contrast", BTOP,
     r'theme\[selected_fg\]="#c0caf5"', 'theme[selected_fg]="#3b4261"',
     "below 4.5:1", None),

    ("a name-paired lazygit fg/bg gone unreadable", "contrast", LAZYGIT,
     r'markedBaseCommitBgColor: \["#ff9e64"\]',
     'markedBaseCommitBgColor: ["#3b4261"]',
     "below 4.5:1", None),

    # The strip the tabs sit on. wezterm names it `background` inside the
    # tab_bar table, which is also what the window's own background is called,
    # so the flat scan stored one over the other and the surface had nothing
    # to be compared against. Both halves need proving: that the two terminals
    # are compared at all, and that the outer background is still read from the
    # window rather than from the tab bar.
    ("a tab bar strip that differs between terminals", "parity", WEZTERM,
     r"background = '#15161e'", "background = '#1a1b26'",
     "tab bar background disagrees", None),

    ("a window background read from the wrong table", "parity", KITTY,
     r"\nbackground #1a1b26", "\nbackground #16161e",
     "background disagrees", None),

    # A tinted wash too faint to survive colour blindness. For a deuteranope
    # the hue separating added from removed is already gone -- 3.0 apart, the
    # same colour -- so the lightness step off the page is the only cue left,
    # and a subtler tint takes it without looking wrong to anyone who can see
    # the hue. Added as a new row rather than by editing one, so the palette
    # check stays quiet and this proves the CVD floor specifically.
    ("a tinted wash too faint to survive colour blindness", "contrast",
     TOKYODOC,
     r"\| `#15423d` \| moved to here \(teal\)([^|]*)\|",
     r"| `#15423d` | moved to here (teal)\1|\n| `#1d2229` | a wash that is barely there |",
     "deuteranope", None),

    # btop's selection, which appears exactly once in its file. The tmux
    # hostname would have been the obvious choice and is a bad one: #737aa2 is
    # also the pane-number overlay two lines down, so the colour would still be
    # present and the check -- which is deliberately file-level, not
    # line-level -- would not fire. That is the documented limit of this
    # guard, and this mutation is placed to respect it rather than hide it.
    ("a contrast pair gone stale", "contrast", BTOP,
     r'theme\[selected_bg\]="#283457"', 'theme[selected_bg]="#1f2335"',
     "no longer appears in", None),
]


def tracked_files():
    out = subprocess.run(["git", "-C", REPO, "ls-files", "-z"],
                         capture_output=True, text=True, check=True)
    return [f for f in out.stdout.split("\0") if f]


def make_copy(files, dest):
    """Copy the *working tree*, so this tests the files as they are now."""
    for rel in files:
        src = os.path.join(REPO, rel)
        if not os.path.isfile(src):
            continue
        dst = os.path.join(dest, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)


def run_checker(root, check=None):
    """Run the checker in a copied tree. `check=None` runs all of them."""
    argv = [sys.executable, os.path.join(root, "tests", "check-theme.py")]
    if check:
        argv.append(check)
    out = subprocess.run(argv, capture_output=True, text=True, timeout=180)
    return out.returncode, out.stdout + out.stderr


def have(tool):
    """True if any of the named binaries exists. "bat|batcat" for Debian."""
    return any(shutil.which(name) for name in tool.split("|"))


def run_mutations(files, verbose):
    failures, skipped = [], []
    for name, check, rel, pattern, replacement, expected, needs in MUTATIONS:
        if needs and not have(needs):
            skipped.append("%s (needs %s)" % (name, needs))
            continue
        with tempfile.TemporaryDirectory() as tmp:
            make_copy(files, tmp)
            path = os.path.join(tmp, rel)
            before = open(path, encoding="utf-8").read()
            after, n = re.subn(pattern, replacement, before, count=1)
            if n != 1:
                failures.append(
                    "%s: could not apply the mutation to %s -- the pattern "
                    "matched %d times, so this test is testing nothing"
                    % (name, rel, n)
                )
                continue
            open(path, "w", encoding="utf-8").write(after)

            code, output = run_checker(tmp, check)
            if code == 0:
                failures.append("%s: the checker passed anyway" % name)
            elif expected not in output:
                failures.append(
                    "%s: the checker failed, but said %r rather than something "
                    "containing %r" % (name, output.strip()[:120], expected)
                )
            elif verbose:
                print("  caught  %s" % name)
    return failures, skipped


def run_units(verbose):
    """Assertions on the parts a config mutation cannot reach."""
    sys.path.insert(0, os.path.join(REPO, "tests"))
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "checktheme", os.path.join(REPO, "tests", "check-theme.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)

    failures = []

    def check(label, ok):
        if not ok:
            failures.append(label)
        elif verbose:
            print("  holds   %s" % label)

    # The contrast maths, against values worked out by hand from the WCAG
    # formula. If these drift, every floor in the table means something else.
    check("white on black is 21:1", abs(m.ratio("#ffffff", "#000000") - 21.0) < 0.01)
    check("a colour against itself is 1:1", abs(m.ratio("#7aa2f7", "#7aa2f7") - 1.0) < 0.01)
    check("fg on bg is 10.59:1", abs(m.ratio("#c0caf5", "#1a1b26") - 10.59) < 0.01)
    check("the ratio is symmetric",
          abs(m.ratio("#c0caf5", "#1a1b26") - m.ratio("#1a1b26", "#c0caf5")) < 1e-9)

    # The tiers only mean something if they are ordered and every pair uses one.
    check("the tier floors descend text > ui > muted",
          m.TIERS["text"] > m.TIERS["ui"] > m.TIERS["muted"])
    check("every pair names a real tier",
          all(t in m.TIERS for t, _, _, _, _ in m.PAIRS))
    check("every pair names a file that exists",
          all(os.path.isfile(os.path.join(REPO, s)) for _, _, _, s, _ in m.PAIRS))

    # The fill floor sits just under bg_visual on purpose, so that the
    # unfocused fills fall below it and the focused one does not. That is the
    # whole design, and neither number appears in any config to mutate.
    check("bg_visual clears the fill floor",
          m.ratio("#283457", "#1a1b26") >= m.FILL_FLOOR)
    check("bg_highlight does not clear it",
          m.ratio("#292e42", "#1a1b26") < m.FILL_FLOOR)
    check("bg_dark1 does not clear it",
          m.ratio("#1f2335", "#1a1b26") < m.FILL_FLOOR)

    # Palette parsing: a row's label belongs to the colour in its own cell.
    doc = m.read_doc()
    known = m.documented_colours(doc)
    check("the doc names every colour it lists",
          all(names for names in known.values()))
    check("#000000 is the cursor glyph, not the cursor",
          "cursor glyph" in known.get("#000000", set()))
    check("#ff5000 is the cursor",
          "cursor" in known.get("#ff5000", set()))
    check("Dark+'s foreground is not in the palette",
          "#d4d4d4" not in known)

    # The file list comes out of the doc, so an empty list would silently mean
    # "nothing is checked".
    files = m.themed_files(doc)
    check("the doc's table resolves to real files", len(files) >= 15)
    check("it reaches outside common/",
          any("/common/" not in f for f in files))
    return failures


def main(argv):
    verbose = "--verbose" in argv or "-v" in argv
    files = tracked_files()

    # A checker that fails on a clean tree would make every mutation below
    # "pass" for the wrong reason.
    with tempfile.TemporaryDirectory() as tmp:
        make_copy(files, tmp)
        code, output = run_checker(tmp)
    if code != 0:
        print("FAIL the checker does not pass on an unmodified tree:")
        print(output)
        return 1
    if verbose:
        print("baseline: the checker passes on an unmodified tree\n")

    if verbose:
        print("mutations:")
    failures, skipped = run_mutations(files, verbose)
    if verbose:
        print("\nunits:")
    failures += run_units(verbose)

    for s in skipped:
        print("skip %s" % s)
    for f in failures:
        print("FAIL %s" % f)
    if failures:
        print("\n%d problem(s)" % len(failures))
        return 1
    print("ok   %d mutations caught, %d skipped, units hold"
          % (len(MUTATIONS) - len(skipped), len(skipped)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
