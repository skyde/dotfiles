#!/usr/bin/env python3
"""Check every key documented in docs/nvim-vscode-parity.md against the config.

The parity table is the contract: it says the VS Code setup is the reference and
lists what each of its bindings does in Neovim. Nothing enforced that, so the two
drifted apart silently and in both directions:

  * `<leader>ms` (debug stop) was bound in settings.json and listed in the table,
    but never mapped in Neovim. Pressing it did nothing.
  * `<leader>ce` was removed when code actions moved to LazyVim's `<leader>ca`,
    and tests/nvim_keymap_check.lua went on asserting it for weeks.
  * `<leader>Backspace` was written in a spelling Neovim does not accept, so no
    amount of reading the table would tell you the key was `<leader><BS>`.

Each of those is a one-line table edit away from being caught mechanically, which
is what this does. It loads the real config, dumps the global keymaps, and
reports any documented key with nothing behind it.

    tests/check-doc-keymaps.py              # against this checkout
    tests/check-doc-keymaps.py --installed  # against ~/.config/nvim

Buffer-local bindings are out of scope: `nvim_get_keymap` only sees global maps,
and the panel keys, LSP keys and treesitter motions are all attached per buffer.
The "Inside the changed-files view" section is skipped wholesale for that reason,
and the handful of others are listed in BUFFER_LOCAL below with the reason.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = os.path.join(REPO, "docs/nvim-vscode-parity.md")

# Sections whose keys are buffer-local by construction, so a global dump can
# never see them.
SKIP_SECTIONS = {"Inside the changed-files view"}

# Individually exempt keys, each with the reason it cannot appear in a global
# keymap dump. Anything not listed here has to be really mapped.
BUFFER_LOCAL = {
    "gd": "LazyVim LSP keymap, attached per buffer",
    "gy": "LazyVim LSP keymap, attached per buffer",
    "gr": "LazyVim LSP keymap, attached per buffer",
    "<A-o>": "clangd only; mapped as <M-o>, which this normalises anyway",
    "<leader>cr": "LazyVim LSP keymap, attached per buffer",
    "<leader>ca": "LazyVim LSP keymap, attached per buffer",
    "]k": "nvim-treesitter-textobjects motion, attached per buffer",
    "[k": "nvim-treesitter-textobjects motion, attached per buffer",
    "vig": "prose for the `ig` text object, which is mapped in x and o",
    "yig": "prose for the `ig` text object, which is mapped in x and o",
    "dig": "prose for the `ig` text object, which is mapped in x and o",
}

MODES = ("n", "x", "o", "i", "v", "s", "t", "c")

DUMP_LUA = """
local out = {}
for _, mode in ipairs({ %s }) do
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
    out[#out + 1] = mode .. "\\t" .. m.lhs
  end
end
vim.fn.writefile(out, vim.env.DOC_KEYMAP_DUMP)
""" % ", ".join('"%s"' % m for m in MODES)


def dump_keymaps(config_home):
    """Boot the real config headless and write out every global mapping."""
    fd, path = tempfile.mkstemp(prefix="doc-keymaps-")
    os.close(fd)
    lua = path + ".lua"
    with open(lua, "w") as f:
        f.write(DUMP_LUA)

    env = dict(os.environ, DOC_KEYMAP_DUMP=path)
    if config_home:
        env["XDG_CONFIG_HOME"] = config_home
    env.pop("NVIM", None)
    env.pop("NVIM_LISTEN_ADDRESS", None)

    # VeryLazy is fired by UIEnter, which never happens headless, and most of
    # the bindings are registered from it.
    proc = subprocess.run(
        ["nvim", "--headless", "-c", "doautocmd User VeryLazy",
         "-c", "luafile " + lua, "-c", "qa!"],
        env=env, capture_output=True, text=True, timeout=900,
    )
    try:
        with open(path, encoding="utf-8") as f:
            lines = [ln.rstrip("\n") for ln in f if ln.strip()]
    except FileNotFoundError:
        sys.stderr.write(proc.stderr)
        raise SystemExit("nvim produced no keymap dump; is the config loadable?")
    finally:
        for p in (path, lua):
            try:
                os.unlink(p)
            except OSError:
                pass

    mapped = set()
    for line in lines:
        mode, _, lhs = line.partition("\t")
        mapped.add((mode, lhs))
        mapped.add(("*", lhs))
    return mapped


def normalise(key):
    """Doc spelling -> the spelling nvim_get_keymap reports.

    Leader is <space>, and nvim_get_keymap prints it literally. Modifier names
    come back canonicalised, so <A-o> is reported as <M-o> and <C-x> as <C-X>.
    """
    key = key.replace("<leader>", " ")
    key = re.sub(r"<A-(.)>", lambda m: "<M-%s>" % m.group(1), key)
    key = re.sub(r"<C-(.)>", lambda m: "<C-%s>" % m.group(1).upper(), key)
    return key


def documented_keys():
    """Every key in the first column of every table in the parity doc."""
    section = ""
    found = []
    with open(DOC, encoding="utf-8") as f:
        for lineno, line in enumerate(f, 1):
            if line.startswith("#"):
                section = line.strip("# \n")
                continue
            if section in SKIP_SECTIONS:
                continue
            m = re.match(r"^\|\s*(`[^|]*?`[^|]*?)\s*\|", line)
            if not m:
                continue
            for key in re.findall(r"`([^`]+)`", m.group(1)):
                found.append((key, section, lineno))
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--installed", action="store_true",
                    help="check ~/.config/nvim instead of this checkout")
    args = ap.parse_args()

    config_home = None if args.installed else os.path.join(REPO, "common/.config")
    mapped = dump_keymaps(config_home)

    keys = documented_keys()
    seen, missing = set(), []
    for key, section, lineno in keys:
        if key in seen:
            continue
        seen.add(key)
        if key in BUFFER_LOCAL:
            continue
        if ("*", normalise(key)) in mapped:
            continue
        missing.append((key, section, lineno))

    print("docs/nvim-vscode-parity.md: %d distinct keys checked against %d global mappings"
          % (len(seen), len({lhs for mode, lhs in mapped if mode != "*"})))

    if missing:
        print("\n%d documented but not mapped:" % len(missing))
        for key, section, lineno in missing:
            print("  %-24s docs/nvim-vscode-parity.md:%d  [%s]" % (key, lineno, section))
        print("\nEither map the key, correct the table, or add it to BUFFER_LOCAL")
        print("in this script with the reason a global dump cannot see it.")
        return 1

    print("every documented key is mapped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
