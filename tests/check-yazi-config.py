#!/usr/bin/env python3
"""Check yazi actually accepts the configs in common/.config/yazi.

yazi validates each of its three files as a whole. One rejected key throws out
the *entire* file and it falls back to presets, after a single
"Press <Enter> to continue with preset settings..." line that scrolls past on
startup — so a stale key does not degrade one rule, it silently disables
everything in that file. All three had one at once:

  * yazi.toml   — a previewer keyed on `name`, which yazi renamed to `url`
  * keymap.toml — a `"$schema"` key, which fails yazi's kebab-case check
  * theme.toml  — 63 filetype rules keyed on `name`

Between them that meant the pane ratio, hidden files, the sort order, preview
wrapping, every custom keybinding, the whole Tokyo Night theme and all three
bat previewers were inert.

    tests/check-yazi-config.py

Two layers. The static checks need nothing installed and catch the exact
patterns above. The live check runs yazi against the config in a pty and fails
if it falls back to presets; it skips when yazi is not installed.
"""

import os
import re
import sys

try:
    import tomllib
except ImportError:  # Python < 3.11
    import tomli as tomllib

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_DIR = os.path.join(REPO, "common/.config/yazi")

# Tables whose entries are match rules; yazi requires `url` or `mime` on each.
RULE_TABLES = [
    ("yazi.toml", ("plugin", "prepend_previewers")),
    ("yazi.toml", ("plugin", "append_previewers")),
    ("yazi.toml", ("plugin", "prepend_fetchers")),
    ("yazi.toml", ("plugin", "append_fetchers")),
    ("yazi.toml", ("plugin", "prepend_preloaders")),
    ("yazi.toml", ("open", "prepend_rules")),
    ("yazi.toml", ("open", "append_rules")),
    ("theme.toml", ("filetype", "rules")),
]

failures = []


def fail(message):
    failures.append(message)
    print("FAIL " + message)


def load(name):
    path = os.path.join(CONFIG_DIR, name)
    with open(path, "rb") as handle:
        return tomllib.load(handle), path


def dig(data, path):
    for key in path:
        if not isinstance(data, dict) or key not in data:
            return None
        data = data[key]
    return data


def check_static():
    for name in ("yazi.toml", "keymap.toml", "theme.toml"):
        data, path = load(name)
        # `$schema` is not kebab-case, and yazi rejects the file over it.
        for key in data:
            if key.startswith("$"):
                fail("%s: top-level %r key — yazi requires kebab-cased keys and "
                     "rejects the whole file. Put the schema URL in a comment." % (name, key))
        print("OK    %s parses as TOML (%d top-level tables)" % (name, len(data)))

    for name, path_keys in RULE_TABLES:
        data, _ = load(name)
        rules = dig(data, path_keys)
        if not rules:
            continue
        table = ".".join(path_keys)
        for index, rule in enumerate(rules):
            if not isinstance(rule, dict):
                continue
            if "name" in rule:
                fail("%s: %s[%d] uses `name`, which yazi renamed to `url`; the "
                     "whole file is rejected over it (%r)" % (name, table, index, rule))
            elif not ("url" in rule or "mime" in rule or "is" in rule):
                fail("%s: %s[%d] has neither `url` nor `mime` nor `is` (%r)"
                     % (name, table, index, rule))
        print("OK    %s %s: %d rules, all keyed on url/mime/is" % (name, table, len(rules)))


def check_live():
    """Run yazi for real and fail if it falls back to preset settings."""
    import shutil

    yazi = shutil.which("yazi-real") or shutil.which("yazi")
    if not yazi:
        print("SKIP  live check (yazi not installed)")
        return
    # The `yazi` on PATH may be this repo's wrapper; it execs the real binary,
    # which is what we want either way.

    import fcntl
    import pty
    import signal
    import struct
    import termios
    import threading
    import time
    import tempfile

    env = dict(os.environ, TERM="xterm-256color")
    # Point yazi at this checkout rather than whatever is installed.
    env["YAZI_CONFIG_HOME"] = CONFIG_DIR
    workdir = tempfile.mkdtemp(prefix="yazi-check-")
    with open(os.path.join(workdir, "sample.txt"), "w") as handle:
        handle.write("hello from the yazi config check\n")

    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(workdir)
        os.execvpe(yazi, [yazi], env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 45, 175, 0, 0))

    buf = bytearray()

    def drain():
        while True:
            try:
                chunk = os.read(fd, 65536)
                if not chunk:
                    return
                buf.extend(chunk)
            except OSError:
                return

    threading.Thread(target=drain, daemon=True).start()
    time.sleep(4)
    os.write(fd, b"j")
    time.sleep(3)
    snapshot = bytes(buf)
    os.write(fd, b"q")
    time.sleep(0.8)
    try:
        os.kill(pid, signal.SIGTERM)
        os.waitpid(pid, 0)
    except (ProcessLookupError, ChildProcessError):
        pass

    text = re.sub(r"\x1b\[[0-9;?]*[a-zA-Z]", "", snapshot.decode("utf-8", "replace"))
    if "preset settings" in text or "TOML parse error" in text:
        detail = [l.strip() for l in text.split("\n") if l.strip()][:8]
        fail("yazi rejected the config and fell back to presets:\n      "
             + "\n      ".join(detail))
    else:
        print("OK    yazi loaded the config without falling back to presets")

    if "hello from the yazi config check" in text:
        print("OK    the bat-preview previewer rendered file content")
    else:
        # Not fatal: previewing needs bat, and the pane may not have painted in
        # the time allowed. The config-acceptance check above is the contract.
        print("NOTE  preview pane content not observed (bat missing, or slow paint)")


def main():
    check_static()
    check_live()
    print()
    if failures:
        print("%d problem(s)" % len(failures))
        return 1
    print("yazi config OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
