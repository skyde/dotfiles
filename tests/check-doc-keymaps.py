#!/usr/bin/env python3
"""Check every key documented in docs/nvim-vscode-parity.md is really mapped.

Nothing enforced that table, so it drifted both ways: `<leader>ms` was listed
and bound in settings.json but never mapped in Neovim, `<leader>ce` outlived the
binding it described, and `<leader>Backspace` was written in a spelling Neovim
does not accept.

    tests/check-doc-keymaps.py              # against this checkout
    tests/check-doc-keymaps.py --installed  # against ~/.config/nvim

Buffer-local bindings cannot appear in a global keymap dump: the changed-files
panel section is skipped wholesale, and the rest are listed in BUFFER_LOCAL.
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = os.path.join(REPO, "docs/nvim-vscode-parity.md")

SKIP_SECTIONS = {"Inside the changed-files view"}

BUFFER_LOCAL = {
    "gd": "LazyVim LSP keymap",
    "gy": "LazyVim LSP keymap",
    "gr": "LazyVim LSP keymap",
    "<A-o>": "clangd only, attached per buffer",
    "<leader>cr": "LazyVim LSP keymap",
    "<leader>ca": "LazyVim LSP keymap",
    "]k": "treesitter-textobjects motion",
    "[k": "treesitter-textobjects motion",
    "vig": "prose for the `ig` text object, mapped in x and o",
    "yig": "prose for the `ig` text object, mapped in x and o",
    "dig": "prose for the `ig` text object, mapped in x and o",
}

MODES = ("n", "x", "o", "i", "v", "s", "t", "c")
DUMP = """
local out = {}
for _, mode in ipairs({ %s }) do
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
    out[#out + 1] = m.lhs
  end
end
vim.fn.writefile(out, vim.env.DOC_KEYMAP_DUMP)
""" % ", ".join('"%s"' % m for m in MODES)


def mapped_keys(config_home):
    """Boot the real config headless and return every global mapping's lhs."""
    fd, path = tempfile.mkstemp(prefix="doc-keymaps-")
    os.close(fd)
    lua = path + ".lua"
    with open(lua, "w") as f:
        f.write(DUMP)

    env = dict(os.environ, DOC_KEYMAP_DUMP=path)
    if config_home:
        env["XDG_CONFIG_HOME"] = config_home
    env.pop("NVIM", None)

    # VeryLazy is fired by UIEnter, which never happens headless, and most
    # bindings are registered from it.
    proc = subprocess.run(
        ["nvim", "--headless", "-c", "doautocmd User VeryLazy",
         "-c", "luafile " + lua, "-c", "qa!"],
        env=env, capture_output=True, text=True, timeout=900,
    )
    try:
        with open(path, encoding="utf-8") as f:
            # Only the newline is stripped: `<leader><leader>` is reported as
            # two literal spaces, and .strip() would discard it as blank.
            return {line.rstrip("\n") for line in f}
    except FileNotFoundError:
        sys.stderr.write(proc.stderr)
        raise SystemExit("nvim produced no keymap dump; is the config loadable?")
    finally:
        for p in (path, lua):
            try:
                os.unlink(p)
            except OSError:
                pass


def normalise(key):
    """Doc spelling -> the spelling nvim_get_keymap reports."""
    key = key.replace("<leader>", " ")
    key = re.sub(r"<A-(.)>", lambda m: "<M-%s>" % m.group(1), key)
    return re.sub(r"<C-(.)>", lambda m: "<C-%s>" % m.group(1).upper(), key)


def documented():
    section, found = "", []
    with open(DOC, encoding="utf-8") as f:
        for lineno, line in enumerate(f, 1):
            if line.startswith("#"):
                section = line.strip("# \n")
            elif section not in SKIP_SECTIONS:
                cell = re.match(r"^\|\s*(`[^|]*?`[^|]*?)\s*\|", line)
                if cell:
                    for key in re.findall(r"`([^`]+)`", cell.group(1)):
                        found.append((key, section, lineno))
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--installed", action="store_true",
                    help="check ~/.config/nvim instead of this checkout")
    args = ap.parse_args()

    mapped = mapped_keys(None if args.installed
                         else os.path.join(REPO, "common/.config"))

    seen, missing = set(), []
    for key, section, lineno in documented():
        if key in seen or key in BUFFER_LOCAL:
            continue
        seen.add(key)
        if normalise(key) not in mapped:
            missing.append((key, section, lineno))

    print("%d documented keys checked against %d global mappings"
          % (len(seen), len(mapped)))
    if not missing:
        print("every documented key is mapped")
        return 0

    print("\n%d documented but not mapped:" % len(missing))
    for key, section, lineno in missing:
        print("  %-24s docs/nvim-vscode-parity.md:%d  [%s]" % (key, lineno, section))
    print("\nMap it, correct the table, or add it to BUFFER_LOCAL with the reason.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
