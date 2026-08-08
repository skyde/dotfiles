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
DOCTOR = "doctor-theme.sh"
ZSHRC = "common/.zshrc"
PREVIEW_SH = "common/.config/lf/preview.sh"
BATPREVIEW = "common/.config/yazi/plugins/bat-preview.yazi/main.lua"
STZOEKT = "common/.local/bin/st-zoekt"
STRG = "common/.local/bin/st-rg"
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
     r'\{ url = "\*\.zip", name = "\*\.zip", fg = "#f7768e" \}',
     '{ url = "*.zip", name = "*.zip", fg = "#9ece6a" }',
     "in lf but", None),

    # The one that cost the most to find by hand. Yazi tolerates an unknown
    # *style* key silently, but an unknown *rule* key is fatal: it refuses the
    # whole file and falls back to its presets, so a single stale `name = `
    # cost the entire theme while every colour in the file still looked right.
    ("a yazi rule key yazi no longer accepts", "parity", YAZI,
     r'\{ url = "\*\.tar", name = "\*\.tar", fg = "#f7768e" \}',
     '{ urls = "*.tar", name = "*.tar", fg = "#f7768e" }',
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
     r"Command            = '#dcdcaa'",
     "Command            = '#7dcfff'",
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
     r"\n\| `common/\.config/nvim/lua/util/vscode_syntax\.lua` \|[^\n]*", "",
     "nothing checks it", None),

    ("an exemption for a file with no colours left", "parity", TOKYODOC,
     r"`common/\.config/nvim/lua/util/vscode_syntax\.lua`", "`common/.config/nvim/lua/util/gone.lua`",
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

    # yazi colours audio by mime and lf by extension, so the two describe the
    # same *.mp3 and never meet in the rule-by-rule parity comparison. Repaint
    # one side and only a bridge across the two matching styles notices.
    ("a mime rule that disagrees with lf's extensions", "parity", YAZI,
     r'\{ mime = "\*\*/audio/\*", fg = "#9d7cd8" \}',
     '{ mime = "**/audio/*", fg = "#bb9af7" }',
     "the same file, two colours", None),

    # git ignores a config key it does not recognise, so a misspelled slot is
    # a setting that reads correctly in the file and does nothing forever --
    # the same shape as the phantom delta option and the three dead lazygit
    # keys. There is no list of valid slots to check against, so git itself
    # is asked: paint a real repository and see whether the colour arrives.
    ("a git colour slot that git does not have", "parity", GIT,
     r"    untracked = \"#1abc9c\"", '    untraked = "#1abc9c"',
     "paints nothing", None),

    # A misspelled tmux option is not an error -- the config loads without a
    # word and the option simply is not there afterwards. tmux also accepts a
    # truncated name, because option names match by unambiguous prefix, so
    # "it started fine" proves nothing. Asking tmux what it holds does.
    ("a tmux option tmux quietly drops", "parity", TMUX,
     r"set -g menu-selected-style", "set -g menu-selcted-style",
     "does not hold it", "tmux"),

    # lazygit accepts an unknown key without a word -- three in this section
    # were dead at once, found by hand against a schema fetched over the
    # network. Its own --config dump lists every gui.theme key, because all
    # twelve have non-empty defaults, so it can name them itself.
    ("a lazygit theme key lazygit does not have", "parity", LAZYGIT,
     r"    optionsTextColor:", "    optionsTxtColor:",
     "no such key", "lazygit"),

    # doctor-theme.sh demonstrates the colours the shell exports, which makes
    # its swatch a second copy of a fact theme.sh already states. Drift and the
    # doctor keeps painting a colour the shell never produces -- while
    # reporting PASS, since what it checks is that the variable is set at all.
    # The two files write the same SGR in opposite parameter orders, so the
    # comparison has to be order-insensitive and this has to still fire.
    ("a doctor swatch that no longer matches the shell", "parity", DOCTOR,
     r"a directory:      %s\[1;38;2;122;162;247msrc/",
     "a directory:      %s[1;38;2;158;206;106msrc/",
     "theme.sh exports", None),

    # The pickers strip ripgrep's colouring and repaint, so the same
    # file:line is one colour from `rg` and another from the picker wrapping
    # it if they drift. Aimed at st-zoekt rather than st-rg because it nests
    # its awk one quoting layer deeper -- the escapes arrive doubled, and a
    # reader that only handles st-rg's form silently checks nothing here.
    ("a picker that repaints a result off-palette", "parity", STZOEKT,
     r"mag=\\\"\\\\033\[38;2;122;162;247m",
     'mag=\\"\\\\033[38;2;158;206;106m',
     "the same result, two colours", None),

    # Every one of these files explains in a comment why it forces truecolor,
    # and the check used to accept the explanation as the deed: deleting the
    # real export left the comment above it and nothing complained.
    ("a bat call site whose COLORTERM is only a comment", "parity", PREVIEW_SH,
     r"COLORTERM=truecolor\nexport COLORTERM\n", "",
     "without forcing COLORTERM", None),

    # yazi previews through bat from Lua, with two spawn paths ~28 lines apart
    # that each set COLORTERM separately. Aimed at the capped one, which runs
    # bat inside an `sh -c` string rather than as a command object, so it needs
    # both a different pattern and a window too short to be covered by the
    # other path's env call.
    ("a yazi preview path that drops to 256 colours", "parity", BATPREVIEW,
     r'Command\("sh"\)\n\tpcall\(function\(\)\n\t\tcmd = cmd:env\("COLORTERM", "truecolor"\)',
     'Command("sh")\n\tpcall(function()\n\t\tcmd = cmd',
     "drops to 256 colours", None),

    # The stale-pair guard asks whether a colour still appears in its config,
    # and a change to that colour is exactly what leaves a comment naming it
    # behind. Moving btop's inactive text to #414868 -- the value the doc
    # itself calls unreadable, at 1.91:1 -- while saying so above the line left
    # the checker asserting 2.76:1 against a config painting 1.91:1, silently.
    ("a contrast pair whose colour survives only in a comment", "contrast",
     BTOP,
     r'theme\[inactive_fg\]="#565f89"',
     '# inactive_fg was #565f89 until this line\ntheme[inactive_fg]="#414868"',
     "no longer appears in", None),

    # Four readers searched raw file text for a line that proves a colour is
    # right. A change to that colour is exactly what leaves a commented-out
    # copy of the old line behind, which satisfies the pattern perfectly while
    # the live line says something else. One mutation each, because each reads
    # a different syntax and the comment marker differs.
    ("a shared role whose old value survives as a comment", "parity", WEZTERM,
     r"  cursor_bg = '#FF5000',",
     "  -- cursor_bg = '#FF5000',\n  cursor_bg = '#7aa2f7',",
     "the cursor", None),

    ("a doctor swatch whose old value survives as a comment", "parity", DOCTOR,
     r"printf 'a directory:      %s\[1;38;2;122;162;247msrc/",
     "# printf 'a directory: %s[1;38;2;122;162;247msrc/'\n"
     "printf 'a directory:      %s[1;38;2;158;206;106msrc/",
     "theme.sh exports", None),

    # st-rg carries two awk prefixes and only the first was ever read, so the
    # second could paint results any colour it liked.
    ("a second awk prefix nothing was reading", "parity", STRG,
     r"(GIT_GREP_AWK_SCRIPT='BEGIN\{[\s\S]*?mag=\")\\033\[38;2;122;162;247m",
     r"\1\\033[38;2;158;206;106m",
     "two colours", None),

    # The command line is Dark+, and the roles the two shells share are
    # compared with each other -- which covered 9 of zsh's 41 colours. The
    # other 32 could be any documented colour at all until the doc's table
    # became the thing they answer to.
    ("a command-line role painted off the Dark+ table", "parity", ZSHRC,
     r"globbing                      'fg=#d7ba7d'",
     "globbing                      'fg=#9ece6a'",
     "does not list", None),

    # The [delta] section was the largest unpinned block in the tree: its
    # option names are checked by delta and git's slots by git, but the values
    # answered to nothing. Two mutations, because the doc states them in two
    # differently-shaped tables -- a row/column grid, and a list keyed by the
    # map-styles gesture it belongs to.
    ("a diff tint that differs from the doc's grid", "parity", GIT,
     r'plus-emph-style = "syntax #2c5a3a"',
     'plus-emph-style = "syntax #683131"',
     "Diff tints", None),

    ("a moved-code colour that differs from the doc", "parity", GIT,
     r"bold cyan => syntax #12384a",
     "bold cyan => syntax #15423d",
     "Diff tints", None),

    # theme.sh's palette states each colour three ways on one line -- the
    # decimals the shell emits, the hex in the comment, the palette's name for
    # it -- and every LS_COLORS, EZA_COLORS and GREP_COLORS entry is built from
    # those decimals. Nothing held the three together.
    ("a palette variable that drifts from its own comment", "parity", THEME_SH,
     r"_tn_blue='122;162;247'", "_tn_blue='158;206;106'",
     "the comment beside it says", None),

    # The doctor paints the same palette as swatches, in the same three parts.
    ("a doctor swatch labelled as the wrong palette entry", "parity", DOCTOR,
     r'block "247;118;142" "red', 'block "158;206;106" "red',
     "is labelled", None),

    # starship restates the palette a third time, as a named TOML table its
    # modules then refer to by name -- so a wrong entry here repaints
    # everything that names it, and the name still reads correctly.
    ("a starship palette entry that is not the doc's", "parity", STARSHIP,
     r'magenta = "#bb9af7"', 'magenta = "#9d7cd8"',
     "the doc's magenta is", None),

    # Each yazi mode is one accent used twice -- as the fill of the solid
    # badge and as the text of the muted one beside it -- and nothing kept the
    # halves of a pair together.
    ("a yazi mode badge whose two halves disagree", "parity", YAZI,
     r'select_alt = \{ fg = "#9ece6a"', 'select_alt = { fg = "#bb9af7"',
     "one mode, two accents", None),

    # yazi's permission column and eza's permission bits show the same thing.
    # eza writes its half symbolically, so the two meet through the palette.
    ("a permission bit yazi and eza disagree on", "parity", YAZI,
     r'perm_write = \{ fg = "#f7768e" \}', 'perm_write = { fg = "#ff9e64" }',
     "eza's uw is", None),

    # inline_diff.lua states its own rule -- the departure stays in the red
    # family, the arrival in the green -- and then writes nine blended
    # backgrounds by hand, where the family is not obvious from the hex.
    ("a moved shade that left its colour family", "parity", INLINE_DIFF,
     r'InlineDiffMovedToTint = \{ bg = "#175035" \}',
     'InlineDiffMovedToTint = { bg = "#4a2139" }',
     "left the green family", None),

    ("a departure shade writing in its own colour", "parity", INLINE_DIFF,
     r'InlineDiffMovedFromSubtle2 = \{ bg = "#352337", fg = "#8a7080" \}',
     'InlineDiffMovedFromSubtle2 = { bg = "#352337", fg = "#565f89" }',
     "one colour, so they read as one thing", None),

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


def load_checker():
    """Import tests/check-theme.py as a module."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "checktheme", os.path.join(REPO, "tests", "check-theme.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


# --------------------------------------------------------------------------
# The comment-decoy probe.
#
# Four separate readers were found accepting a commented-out copy of the line
# they look for, while the live line said something else. Each fix was easy;
# noticing was not, and knowing the failure by name did not stop it being
# written again three commits later. So it is generated rather than
# remembered: every colour in every scanned config gets the same two-step
# treatment, and a reader added next year is probed the day it lands.
#
#   1. change the colour to another documented one and run the checker.
#      Nothing fails -> nothing constrains this colour, move on.
#   2. make the same change, but leave a commented-out copy of the original
#      line above it. Something must still fail; if not, the reader is
#      reading the comment.
#
# The replacement is always a documented colour, so the palette check stays
# quiet and what is left is the readers.

PROBE_SWAP = ("#9ece6a", "#f7768e")


def _probe_replacement(colour):
    return PROBE_SWAP[1] if colour.lower() == PROBE_SWAP[0] else PROBE_SWAP[0]


def probe_targets(module, sample_per_file=None):
    """Every colour a tool will actually read, as (file, line, colour, marker).

    Shared by the probe and the unpinned report: two implementations of "which
    colours count" would disagree eventually, and the first version of the
    report did -- it counted hexes in trailing comments, which nothing can
    constrain, and overstated how much of the theme was loose.
    """
    hexes = re.compile(r"#[0-9a-fA-F]{6}")
    targets = []
    for path in module.themed_files(module.read_doc()):
        rel = os.path.relpath(path, REPO)
        marker = module.COMMENT_MARKERS.get(
            os.path.splitext(rel)[1], module.DEFAULT_COMMENT_MARKER)
        found = []
        for i, line in enumerate(open(path, encoding="utf-8").read().splitlines()):
            if line.lstrip().startswith(marker):
                continue
            cut = module.comment_start(marker, line)
            code = line if cut < 0 else line[:cut]
            # Every distinct colour on the line, not the first. fzf's options
            # put four on one line, and testing only the leading one reported
            # the other three as untested when some of them are pinned -- the
            # same first-match-only mistake this session already fixed in a
            # check, repeated in the thing measuring the checks.
            for colour in dict.fromkeys(hexes.findall(code)):
                found.append((i, colour))
        if sample_per_file is not None:
            found = found[:sample_per_file]
        targets.extend((rel, i, colour, marker) for i, colour in found)
    return targets


def report_unpinned(files, only=None):
    """How much of the theme is held in place, per file.

    Change a colour to another *documented* colour and see whether anything
    fails. If nothing does, that colour is pinned by nothing -- which is not
    automatically wrong (a colour with no counterpart in another tool has
    nothing to be pinned to) but is the honest measure, and the ranked list is
    a better way to choose the next check than deciding which surface feels
    unexamined.
    """
    module = load_checker()
    free, total = {}, {}
    with tempfile.TemporaryDirectory() as tmp:
        make_copy(files, tmp)
        detail = []
        for rel, lineno, colour, _marker in probe_targets(module):
            if only and only not in rel:
                continue
            total[rel] = total.get(rel, 0) + 1
            path = os.path.join(tmp, rel)
            original = open(path, encoding="utf-8").read()
            lines = original.splitlines(True)
            swapped = lines[lineno].replace(colour, _probe_replacement(colour), 1)
            if not _probe_run(tmp, path, lines, lineno, swapped, original):
                free[rel] = free.get(rel, 0) + 1
                detail.append("%s:%d %s  %s"
                              % (rel, lineno + 1, colour,
                                 lines[lineno].strip()[:64]))
    if only:
        for line in detail:
            print("  " + line)
        print()
    print("%-52s %6s %6s" % ("file", "unpinned", "all"))
    for rel in sorted(total, key=lambda r: -free.get(r, 0)):
        print("  %-50s %6d %6d" % (rel, free.get(rel, 0), total[rel]))
    print("  %-50s %6d %6d" % ("TOTAL", sum(free.values()), sum(total.values())))
    return []


def probe_comments(verbose, files, sample_per_file=None):
    """Require every reader to distinguish a live line from a commented one.

    Runs against a copy of the working tree, never the tree itself. The first
    version edited the real files in place and restored them afterwards, which
    worked right up until something else touched the repo mid-run and left a
    mutated colour sitting in it. A test that can leave the repository dirty is
    not one to keep -- and the mutation framework above already copies for
    exactly this reason.
    """
    module = load_checker()
    targets = probe_targets(module, sample_per_file)
    fooled, constrained = [], 0
    with tempfile.TemporaryDirectory() as tmp:
        make_copy(files, tmp)
        for rel, lineno, colour, marker in targets:
            path = os.path.join(tmp, rel)
            original = open(path, encoding="utf-8").read()
            lines = original.splitlines(True)
            live = lines[lineno].replace(colour, _probe_replacement(colour), 1)

            if not _probe_run(tmp, path, lines, lineno, live, original):
                continue  # nothing constrains this colour
            constrained += 1
            decoy = marker + " " + lines[lineno].rstrip("\n") + "\n" + live
            if not _probe_run(tmp, path, lines, lineno, decoy, original):
                fooled.append("%s:%d — %s survives as a comment"
                              % (rel, lineno + 1, colour))

    if verbose:
        for f in fooled:
            print("  fooled  %s" % f)
        print("  probe: %d colour(s) constrained, %d fooled"
              % (constrained, len(fooled)))
    return fooled


def _probe_run(root, path, lines, lineno, replacement, original):
    """Swap one line into the copy, run the checker there, put it back."""
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("".join(lines[:lineno]) + replacement
                 + "".join(lines[lineno + 1:]))
    env = dict(os.environ, THEME_CHECK_NO_TOOLS="1")
    out = subprocess.run(
        [sys.executable, os.path.join(root, "tests", "check-theme.py")],
        capture_output=True, text=True, env=env, timeout=180)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(original)
    return out.returncode != 0


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
    m = load_checker()

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
    # Dark+ used to be deliberately absent from the doc. It is not any more:
    # the command line is code, both shells paint it from the Dark+ table, and
    # a colour a config uses is a colour the doc has to account for.
    check("Dark+'s foreground is documented, since the command line uses it",
          "#d4d4d4" in known)

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

    # One colour per file by default, every colour under --probe-comments.
    # A full sweep is ~776 lines and two checker runs each, which is why the
    # tools-off mode exists; the sample keeps the default run honest without
    # making it slow.
    if "--report-unpinned" in argv:
        at = argv.index("--report-unpinned")
        only = argv[at + 1] if len(argv) > at + 1 else None
        return 0 if not report_unpinned(files, only) else 1

    if verbose:
        print("\ncomment-decoy probe:")
    failures += probe_comments(
        verbose, files, None if "--probe-comments" in argv else 1)

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
