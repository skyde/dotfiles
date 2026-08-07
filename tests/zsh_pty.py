#!/usr/bin/env python3
"""Run an interactive zsh under a pseudo-terminal and feed it a script.

    tests/zsh_pty.py SCRIPT [zsh arg ...]

Parts of the shell only exist when a terminal is attached: fzf's key bindings
are skipped without one, terminfo lookups need a real $TERM, and the line editor
never starts at all. `zsh -i -c ...` is close enough for most assertions and much
cheaper, so the specs use it by default and come here for the rest.

The script is sourced in the shell. Anything it wants to report it should write
to a file of its own choosing, which the caller reads afterwards — parsing it
back out of the terminal would mean picking it out of the echo of the input, the
prompt, and the escape sequences those bring with them. What the terminal emitted
is copied to stdout, which is for looking at when a spec fails.

Exits with the shell's status, 124 if the shell had to be killed on timeout.
"""

import os
import pty
import select
import signal
import struct
import sys
import termios
import time
import fcntl

TIMEOUT = float(os.environ.get("ZSH_PTY_TIMEOUT", "30"))
# A fixed size keeps a wrapped prompt from splitting the output in ways that
# differ between machines.
ROWS, COLS = 24, 80


def main(argv):
    if not argv:
        sys.stderr.write("usage: zsh_pty.py SCRIPT [zsh arg ...]\n")
        return 2

    script = argv[0]
    zsh_args = argv[1:] or ["--no-globalrcs", "-i"]

    if not os.path.exists(script):
        sys.stderr.write("zsh_pty.py: no such script: %s\n" % script)
        return 2

    pid, fd = pty.fork()
    if pid == 0:
        # Child: becomes the shell. A $TERM that exists in terminfo matters —
        # bindings looked up through zsh/terminfo silently do nothing under
        # TERM=dumb, which is what some CI environments export.
        if os.environ.get("TERM", "") in ("", "dumb", "unknown"):
            os.environ["TERM"] = "xterm-256color"
        try:
            os.execvp("zsh", ["zsh"] + zsh_args)
        except OSError as exc:  # pragma: no cover - only on a broken PATH
            sys.stderr.write("zsh_pty.py: cannot exec zsh: %s\n" % exc)
            os._exit(127)

    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))

    # `source` rather than pasting the script's text in: the shell echoes what it
    # is sent, and a multi-line paste comes back interleaved with continuation
    # prompts. One line in, one line echoed.
    os.write(fd, ("source %s\nexit\n" % _quote(script)).encode())

    collected = bytearray()
    deadline = time.time() + TIMEOUT
    while True:
        remaining = deadline - time.time()
        if remaining <= 0:
            os.kill(pid, signal.SIGKILL)
            os.waitpid(pid, 0)
            _flush(collected)
            sys.stderr.write("zsh_pty.py: timed out after %gs\n" % TIMEOUT)
            return 124
        readable, _, _ = select.select([fd], [], [], min(0.2, remaining))
        if not readable:
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            # The child closed the terminal: it has exited.
            break
        if not chunk:
            break
        collected += chunk

    os.close(fd)
    _, status = os.waitpid(pid, 0)
    _flush(collected)
    if os.WIFEXITED(status):
        return os.WEXITSTATUS(status)
    return 128 + os.WTERMSIG(status)


def _quote(path):
    return "'" + path.replace("'", "'\\''") + "'"


def _flush(collected):
    sys.stdout.write(bytes(collected).decode("utf-8", errors="replace"))
    sys.stdout.flush()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
