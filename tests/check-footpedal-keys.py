#!/usr/bin/env python3
"""Drive the footpedal's Shift+F macro keys through a real terminal into a real
Neovim, and check each one does what its VS Code binding does.

Unlike tests/check-nvim-keymaps.sh, which calls the mapping callbacks directly,
this exercises the whole path: the terminal encodes the key press, Neovim's TUI
decodes it, and the keymap fires. That transport is where these keys actually
break -- Shift+Fn never arrives as <S-Fn> in a terminal, it arrives as
<F13>..<F24>, and the two terminals do not agree on the bytes for Shift+F3.

    tests/check-footpedal-keys.py              # both terminals
    tests/check-footpedal-keys.py kitty        # real kitty window, driven over
                                               # its remote-control socket
    tests/check-footpedal-keys.py vscode       # the escape sequences the VS Code
                                               # integrated terminal sends
    tests/check-footpedal-keys.py --keep       # leave the kitty window open

The kitty run opens a real, briefly visible window; that is the point of it.
"""

import argparse
import fcntl
import json
import os
import pty
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KITTY_SOCK = "unix:/tmp/footpedal-check-kitty"

# What the README's "Macro Bindings" list says each key does. Shift+F10 is the
# tmux prefix (see .tmux.conf) and never reaches Neovim, so it is not checked.
LABELS = {
    1: "previous buffer",
    2: "build and run",
    3: "find class / file",
    4: "scroll up 16",
    5: "save",
    6: "scroll down 16",
    7: "stop build",
    8: "goto definition",
    9: "next location",
    11: "toggle comment",
    12: "next buffer",
}

# Shift+F1..F12 as xterm-256color's kf13..kf24, which is what the VS Code
# integrated terminal sends. Note Shift+F3: kitty deliberately sends CSI 13;2~
# instead of CSI 1;2R, because CSI 1;2R collides with a cursor position report.
VSCODE_SEQS = {
    1: "\x1b[1;2P", 2: "\x1b[1;2Q", 3: "\x1b[1;2R", 4: "\x1b[1;2S",
    5: "\x1b[15;2~", 6: "\x1b[17;2~", 7: "\x1b[18;2~", 8: "\x1b[19;2~",
    9: "\x1b[20;2~", 10: "\x1b[21;2~", 11: "\x1b[23;2~", 12: "\x1b[24;2~",
}

ROWS, COLS = 40, 120


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


class Transport:
    """Starts Neovim behind some terminal and delivers key presses to it."""

    name = "?"

    def start(self, workdir, files, sock, env):
        raise NotImplementedError

    def send(self, n):
        """Deliver Shift+F<n>."""
        raise NotImplementedError

    def escape(self):
        raise NotImplementedError

    def stop(self):
        raise NotImplementedError


class KittyTransport(Transport):
    """A real kitty window, driven over kitty's remote-control socket, so kitty
    encodes the key exactly as it would for a physical press -- including the
    keyboard-protocol negotiation it does with Neovim."""

    name = "kitty"

    def _kitty(self, *args):
        return run(["kitten", "@", "--to", KITTY_SOCK, *args])

    def start(self, workdir, files, sock, env):
        self.proc = subprocess.Popen(
            [
                "kitty",
                "--listen-on", KITTY_SOCK,
                "-o", "allow_remote_control=yes",
                "-o", "confirm_os_window_close=0",
                "-o", "font_size=9",
                "--directory", workdir,
                "nvim", "--listen", sock, *files,
            ],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        for _ in range(120):
            if self._kitty("ls").returncode == 0 and os.path.exists(sock):
                return True
            time.sleep(0.5)
        return False

    def send(self, n):
        self._kitty("send-key", "shift+f%d" % n)

    # Printable keys go as text; modified keys go through send-key so kitty
    # encodes them exactly as it would a physical press.
    AS_TEXT = {"g": "g", "shift+g": "G"}

    def press(self, *specs):
        for s in specs:
            if s in self.AS_TEXT:
                self._kitty("send-text", self.AS_TEXT[s])
            else:
                self._kitty("send-key", s)
            time.sleep(0.15)

    def escape(self):
        self._kitty("send-key", "escape")

    def stop(self, keep=False):
        if keep:
            return
        self._kitty("close-window", "--self")
        time.sleep(0.5)
        self.proc.terminate()
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()


class VscodeTransport(Transport):
    """A bare pty with TERM=xterm-256color, fed the exact escape sequences the
    VS Code integrated terminal emits. Covers the encoding VS Code's xterm.js
    uses, which differs from kitty's for Shift+F3."""

    name = "vscode-terminal"

    def start(self, workdir, files, sock, env):
        env = dict(env, TERM="xterm-256color")
        env.pop("TERMINFO", None)
        pid, fd = pty.fork()
        if pid == 0:
            os.chdir(workdir)
            os.execvpe("nvim", ["nvim", "--listen", sock, *files], env)
        self.pid, self.fd = pid, fd
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
        # Neovim blocks on a full output buffer, so the pty has to be drained.
        self._drain = threading.Thread(target=self._reader, daemon=True)
        self._drain.start()
        for _ in range(120):
            if os.path.exists(sock):
                return True
            time.sleep(0.5)
        return False

    def _reader(self):
        while True:
            try:
                if not os.read(self.fd, 65536):
                    return
            except OSError:
                return

    def send(self, n):
        os.write(self.fd, VSCODE_SEQS[n].encode())

    # What VS Code puts on the wire for the few plain keys the jumplist check
    # needs. Cmd+Left/Cmd+Right are rewritten to Ctrl+O/Ctrl+I by the
    # sendSequence bindings in keybindings.json, so they arrive as these bytes.
    PLAIN = {"g": b"g", "shift+g": b"G", "ctrl+o": b"\x0f", "ctrl+i": b"\x09"}

    def press(self, *specs):
        for s in specs:
            os.write(self.fd, self.PLAIN[s])
            time.sleep(0.12)

    def escape(self):
        os.write(self.fd, b"\x1b")

    def stop(self, keep=False):
        try:
            os.close(self.fd)
        except OSError:
            pass
        try:
            os.kill(self.pid, signal.SIGTERM)
            os.waitpid(self.pid, 0)
        except (ProcessLookupError, ChildProcessError):
            pass


class KittyTmuxTransport(KittyTransport):
    """kitty with tmux in the middle. This is the everyday setup, and it is not
    the same as either half on its own: tmux picks default-terminal from the
    host terminal (xterm-kitty here, xterm-256color under VS Code), and it is
    tmux rather than kitty that ends up encoding the key for Neovim.

    Runs on a private tmux server socket so the real one is untouched.
    """

    name = "kitty+tmux"
    SERVER = "footpedal-check-kitty"

    def start(self, workdir, files, sock, env):
        env = dict(env)
        env.pop("TMUX", None)
        conf = os.path.join(REPO, "common/.tmux.conf")
        self.proc = subprocess.Popen(
            [
                "kitty",
                "--listen-on", KITTY_SOCK,
                "-o", "allow_remote_control=yes",
                "-o", "confirm_os_window_close=0",
                "-o", "font_size=9",
                "--directory", workdir,
                "tmux", "-L", self.SERVER, "-f", conf,
                "new-session", "-A", "-s", "fpk",
                "nvim", "--listen", sock, *files,
            ],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        for _ in range(120):
            if self._kitty("ls").returncode == 0 and os.path.exists(sock):
                return True
            time.sleep(0.5)
        return False

    def stop(self, keep=False):
        run(["tmux", "-L", self.SERVER, "kill-server"])
        super().stop(keep=keep)


class TmuxTransport(VscodeTransport):
    """Same escape sequences, but with tmux in the middle, since that is how
    Neovim usually gets run here. tmux has its own opinions about Shift+F keys
    (S-F10 is the prefix, S-F4/S-F6 are bound in copy-mode), so it is worth
    checking the rest still reach Neovim.

    Runs on a private tmux server socket so the real one is untouched.
    """

    name = "tmux"
    SERVER = "footpedal-check"

    def start(self, workdir, files, sock, env):
        env = dict(env, TERM="xterm-256color")
        env.pop("TERMINFO", None)
        env.pop("TMUX", None)
        conf = os.path.join(REPO, "common/.tmux.conf")
        pid, fd = pty.fork()
        if pid == 0:
            os.chdir(workdir)
            os.execvpe("tmux", [
                "tmux", "-L", self.SERVER, "-f", conf,
                "new-session", "-A", "-s", "fp",
                "nvim", "--listen", sock, *files,
            ], env)
        self.pid, self.fd = pid, fd
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
        self._drain = threading.Thread(target=self._reader, daemon=True)
        self._drain.start()
        for _ in range(120):
            if os.path.exists(sock):
                return True
            time.sleep(0.5)
        return False

    def stop(self, keep=False):
        run(["tmux", "-L", self.SERVER, "kill-server"])
        super().stop(keep=keep)


def check_transport(transport, keep=False):
    """Run the whole battery against one terminal. Returns a list of failures."""
    sock = "/tmp/footpedal-check-nvim-%s" % transport.name
    if os.path.exists(sock):
        os.unlink(sock)

    workdir = tempfile.mkdtemp(prefix="footpedal-")
    sample = os.path.join(workdir, "sample.lua")
    with open(sample, "w") as f:
        # Numbered lines make a 16-line scroll trivially checkable, and .lua
        # gives the comment key a commentstring to work with. A half-page scroll
        # in this window would be ROWS/2, which is not 16, so the two are
        # distinguishable.
        f.write("".join("local line%d = %d\n" % (i, i) for i in range(1, 201)))
    other = os.path.join(workdir, "other.lua")
    with open(other, "w") as f:
        f.write("local other = true\n")
    keylog = os.path.join(workdir, "keys.log")

    env = dict(os.environ)
    # Point Neovim at this checkout rather than whatever happens to be installed.
    env["XDG_CONFIG_HOME"] = os.path.join(REPO, "common/.config")
    env.pop("NVIM", None)
    env.pop("NVIM_LISTEN_ADDRESS", None)

    def expr(e):
        r = run(["nvim", "--server", sock, "--remote-expr", e])
        return r.stdout.strip() if r.returncode == 0 else "<ERR %s>" % r.stderr.strip()

    def lua(src):
        return expr("luaeval('(function() %s end)()')" % src.replace("'", "''"))

    def floats():
        return int(lua(
            "local n = 0 for _, w in ipairs(vim.api.nvim_list_wins()) do "
            "if vim.api.nvim_win_get_config(w).relative ~= \"\" then n = n + 1 end end return n"
        ) or 0)

    def arrived(n):
        """Did the key show up in the log, under either spelling?

        Bare kitty and the VS Code terminal both deliver Shift+Fn as terminfo's
        kf13..kf24, which Neovim reports as <F13>..<F24>. tmux, with
        extended-keys on, re-encodes it so Neovim sees a real <S-Fn>. Both are
        fine; config/keymaps.lua maps both.
        """
        try:
            with open(keylog) as f:
                seen = f.read().split()
        except FileNotFoundError:
            return False
        return ("<F%d>" % (n + 12)) in seen or ("<S-F%d>" % n) in seen

    def install_logger():
        """Observation only: record what the TUI decodes, so a failure can say
        whether the key never arrived or arrived and did nothing.

        Pinned to a namespace and wrapped in pcall, because Neovim silently
        drops an on_key callback that throws -- which would otherwise look
        exactly like a key that never arrived.
        """
        lua(
            "local p = %s "
            "vim.g.__fp_ns = vim.g.__fp_ns or vim.api.nvim_create_namespace(\"fp-keys\") "
            "vim.on_key(function(k, t) pcall(function() "
            "  local fd = io.open(p, \"a\") "
            "  fd:write(vim.fn.keytrans((t ~= nil and t ~= \"\") and t or k) .. \"\\n\") "
            "  fd:close() "
            "end) end, vim.g.__fp_ns) return 1" % json.dumps(keylog)
        )

    def reset():
        open(keylog, "w").close()
        transport.escape()
        time.sleep(0.3)
        install_logger()

    failures = []

    def check(n, ok, detail):
        label = "S-F%-2d %-20s" % (n, LABELS[n])
        if ok:
            print("  PASS  %s %s" % (label, detail))
        else:
            why = "key arrived" if arrived(n) else "KEY NEVER ARRIVED"
            print("  FAIL  %s %s  [%s]" % (label, detail, why))
            failures.append("%s S-F%d (%s): %s [%s]" % (transport.name, n, LABELS[n], detail, why))

    print("\n=== %s -> real nvim ===" % transport.name)
    if not transport.start(workdir, [sample, other], sock, env):
        print("  FAIL  terminal or nvim never came up")
        return ["%s: never started" % transport.name]

    try:
        # LazyVim loads most plugins on VeryLazy; let it settle so the
        # lazy-registered keys exist.
        time.sleep(3)

        install_logger()

        # --- both spellings are mapped in normal mode, since which one the
        # terminal delivers depends on the stack (see arrived() above) ---
        for n in sorted(LABELS):
            for lhs in ("<F%d>" % (n + 12), "<S-F%d>" % n):
                if expr("!empty(maparg('%s', 'n'))" % lhs) != "1":
                    print("  FAIL  S-F%-2d %-20s %s is not mapped" % (n, LABELS[n], lhs))
                    failures.append("%s S-F%d (%s): %s is not mapped" % (transport.name, n, LABELS[n], lhs))

        # --- S-F4 / S-F6: scroll exactly 16 lines ---
        reset()
        lua("vim.cmd('edit! %s') vim.cmd('100') return 1" % sample)
        time.sleep(0.5)
        before = int(expr("line('.')"))
        transport.send(4)
        time.sleep(0.7)
        after = int(expr("line('.')"))
        check(4, before - after == 16, "line %d -> %d (want -16)" % (before, after))

        reset()
        before = int(expr("line('.')"))
        transport.send(6)
        time.sleep(0.7)
        after = int(expr("line('.')"))
        check(6, after - before == 16, "line %d -> %d (want +16)" % (before, after))

        # --- S-F11: toggle comment ---
        reset()
        lua("vim.cmd('1') return 1")
        was = expr("getline(1)")
        transport.send(11)
        time.sleep(0.9)
        now = expr("getline(1)")
        check(11, now.strip().startswith("--") and now != was, "%r -> %r" % (was, now))

        # --- S-F5: save ---
        reset()
        lua("vim.bo.modified = true return 1")
        mod_was = expr("&modified")
        transport.send(5)
        time.sleep(0.9)
        mod_now = expr("&modified")
        check(5, mod_was == "1" and mod_now == "0", "modified %s -> %s" % (mod_was, mod_now))

        # --- S-F12 / S-F1: next / previous buffer ---
        reset()
        lua("vim.cmd('edit! %s') return 1" % sample)
        time.sleep(0.4)
        first = expr("expand('%:t')")
        transport.send(12)
        time.sleep(0.9)
        second = expr("expand('%:t')")
        check(12, second != first and second != "", "%s -> %s" % (first, second))

        reset()
        transport.send(1)
        time.sleep(0.9)
        back = expr("expand('%:t')")
        check(1, back == first, "%s -> %s (want %s)" % (second, back, first))

        # --- S-F3: quick open picker appears ---
        reset()
        f_was = floats()
        transport.send(3)
        time.sleep(2.5)
        f_now = floats()
        check(3, f_now > f_was, "float windows %d -> %d" % (f_was, f_now))
        for _ in range(2):
            transport.escape()
            time.sleep(0.5)

        # --- S-F2 / S-F7 / S-F8: nothing observable to assert without a debug
        # adapter or a language server, so check the key arrives and the mapping
        # runs without throwing.
        for n in (2, 7, 8):
            reset()
            lua("vim.cmd('messages clear') return 1")
            transport.send(n)
            time.sleep(1.5)
            errs = lua(
                "local out = {} "
                "for _, m in ipairs(vim.split(vim.fn.execute(\"messages\"), \"\\n\")) do "
                "if m:match(\"E%d\") or m:match(\"traceback\") then table.insert(out, m) end end "
                "return table.concat(out, \" | \")"
            )
            clean = not errs.strip() or errs.startswith("<ERR")
            check(n, arrived(n) and clean,
                  "arrived, raised nothing" if clean else "raised: %s" % errs[:120])

        # --- jumplist: go to the previous location, and back forward again ---
        # Not a macro key. Ctrl+O / Ctrl+I are what kitty and the VS Code
        # terminal rewrite Cmd+Left / Cmd+Right to, since Neovim cannot see Cmd.
        def jump_check(name, ok, detail):
            if ok:
                print("  PASS  %-25s %s" % (name, detail))
            else:
                print("  FAIL  %-25s %s" % (name, detail))
                failures.append("%s %s: %s" % (transport.name, name, detail))

        reset()
        lua("vim.cmd('edit! %s') return 1" % sample)
        time.sleep(0.4)
        # gg then G puts a real entry on the jumplist.
        transport.press("g", "g")
        time.sleep(0.4)
        transport.press("shift+g")
        time.sleep(0.5)
        top = int(expr("line('.')"))
        transport.press("ctrl+o")
        time.sleep(0.7)
        back = int(expr("line('.')"))
        jump_check("Ctrl+O previous location", top > 1 and back == 1,
                   "line %d -> %d (want 1)" % (top, back))

        # Forward goes on Shift+F9, not Ctrl+I: Neovim cannot tell Ctrl+I from
        # Tab even when the terminal disambiguates them, and normal-mode <Tab>
        # is mapped to indent, so Ctrl+I indents instead of jumping.
        transport.send(9)
        time.sleep(0.7)
        fwd = int(expr("line('.')"))
        jump_check("S-F9 next location", fwd == top,
                   "line %d -> %d (want %d)" % (back, fwd, top))
        return failures
    finally:
        transport.stop(keep=keep)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("which", nargs="?", default="all",
                    choices=["all", "kitty", "vscode", "tmux", "kitty+tmux"])
    ap.add_argument("--keep", action="store_true", help="leave the kitty window open")
    args = ap.parse_args()

    if not shutil.which("nvim"):
        print("nvim not found", file=sys.stderr)
        return 1

    transports = []
    if args.which in ("all", "vscode"):
        transports.append(VscodeTransport())
    if args.which in ("all", "tmux"):
        if shutil.which("tmux"):
            transports.append(TmuxTransport())
        elif args.which == "tmux":
            print("tmux not found", file=sys.stderr)
            return 1
        else:
            print("tmux not found, skipping that transport")
    have_kitty = shutil.which("kitty") and shutil.which("kitten")
    for want, cls in (("kitty", KittyTransport), ("kitty+tmux", KittyTmuxTransport)):
        if args.which not in ("all", want):
            continue
        if have_kitty:
            transports.append(cls())
        elif args.which == want:
            print("kitty not found", file=sys.stderr)
            return 1
        else:
            print("kitty not found, skipping the %s transport" % want)

    failures = []
    for t in transports:
        failures += check_transport(t, keep=args.keep)

    print("")
    if failures:
        print("%d FAILED:" % len(failures))
        for f in failures:
            print("  - %s" % f)
        return 1
    print("all %d footpedal keys OK in %s" % (
        len(LABELS), " and ".join(t.name for t in transports)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
