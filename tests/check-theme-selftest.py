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
INLINE_DIFF = "common/.config/nvim/lua/util/inline_diff.lua"
FF = "common/.local/bin/ff"

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

    ("a titlebar that disagrees between terminals", "parity", KITTY,
     r"macos_titlebar_color #16161e", "macos_titlebar_color #1a1b26",
     "titlebar disagrees", None),

    ("a file colour that differs between lf and yazi", "parity", YAZI,
     r'\{ name = "\*\.zip", fg = "#f7768e" \}',
     '{ name = "*.zip", fg = "#9ece6a" }',
     "in lf but", None),

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

    ("a delta option that does not exist", "parity", GIT,
     r'blame-separator-style = "#3b4261"',
     'blame-separator-style = "#3b4261"\n    blame-timestamp-style = "#737aa2"',
     "delta has no", "delta"),

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
    return shutil.which(tool) is not None


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
