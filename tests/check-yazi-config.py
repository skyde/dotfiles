#!/usr/bin/env python3
"""Check yazi actually accepts the configs in common/.config/yazi.

yazi validates each file as a whole, so one stale key discards the *entire* file
and it falls back to presets after a single "Press <Enter> to continue" line
that scrolls past on startup. All three files had one at once: previewer and
filetype rules keyed on `name` (renamed to `url`), and a `"$schema"` key that
fails yazi's kebab-case check.

    tests/check-yazi-config.py

The static checks need nothing installed; the live check runs yazi in a pty and
fails if it falls back to presets, skipping when yazi is not installed.
"""

import os
import re
import shutil
import sys

try:
    import tomllib
except ImportError:  # Python < 3.11
    import tomli as tomllib

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG_DIR = os.path.join(REPO, "common/.config/yazi")

# Tables whose entries are match rules; yazi requires url/mime (or `is`) on each.
RULE_TABLES = [
    ("yazi.toml", ("plugin", "prepend_previewers")),
    ("yazi.toml", ("plugin", "append_previewers")),
    ("yazi.toml", ("plugin", "prepend_fetchers")),
    ("yazi.toml", ("plugin", "prepend_preloaders")),
    ("yazi.toml", ("open", "prepend_rules")),
    ("theme.toml", ("filetype", "rules")),
]

failures = []


def fail(message):
    failures.append(message)
    print("FAIL " + message)


def load(name):
    with open(os.path.join(CONFIG_DIR, name), "rb") as handle:
        return tomllib.load(handle)


def dig(data, keys):
    for key in keys:
        if not isinstance(data, dict) or key not in data:
            return None
        data = data[key]
    return data


def check_static():
    for name in ("yazi.toml", "keymap.toml", "theme.toml"):
        data = load(name)
        for key in data:
            if key.startswith("$"):
                fail("%s: top-level %r key — yazi requires kebab-cased keys and "
                     "rejects the whole file over it" % (name, key))
        print("OK    %s parses as TOML" % name)

    for name, keys in RULE_TABLES:
        rules = dig(load(name), keys)
        if not rules:
            continue
        table = ".".join(keys)
        for index, rule in enumerate(rules):
            if not isinstance(rule, dict):
                continue
            if "name" in rule:
                fail("%s: %s[%d] uses `name`, renamed to `url`; the whole file "
                     "is rejected over it (%r)" % (name, table, index, rule))
            elif not {"url", "mime", "is"} & set(rule):
                fail("%s: %s[%d] has no url/mime/is (%r)" % (name, table, index, rule))
        print("OK    %s %s: %d rules keyed on url/mime/is" % (name, table, len(rules)))


def check_live():
    yazi = shutil.which("yazi-real") or shutil.which("yazi")
    if not yazi:
        print("SKIP  live check (yazi not installed)")
        return

    import fcntl, pty, signal, struct, tempfile, termios, threading, time

    env = dict(os.environ, TERM="xterm-256color", YAZI_CONFIG_HOME=CONFIG_DIR)
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


def main():
    check_static()
    check_live()
    if failures:
        print("\n%d problem(s)" % len(failures))
        return 1
    print("\nyazi config OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
