#!/usr/bin/env python3
"""Run an interactive zsh under a pseudo-terminal and feed it a script.

    tests/zsh_pty.py SCRIPT [--send KEYS ...] [-- zsh arg ...]

Parts of the shell only exist when a terminal is attached: fzf's key bindings
are skipped without one, terminfo lookups need a real $TERM, and the line editor
never starts at all. `zsh -i -c ...` is close enough for most assertions and much
cheaper, so the specs use it by default and come here for the rest.

The script is sourced in the shell. Anything it wants to report it should write
to a file of its own choosing, which the caller reads afterwards — parsing it
back out of the terminal would mean picking it out of the echo of the input, the
prompt, and the escape sequences those bring with them. What the terminal emitted
is copied to stdout, which is for looking at when a spec fails.

--send writes its argument to the terminal as if typed, after the script has been
sourced, with the usual backslash escapes understood (\\t for Tab, \\e for
Escape, \\x18 for Ctrl-X). That is how a binding gets tested by pressing the key
rather than by reading what `bindkey` claims: the shell cannot tell the difference
between this and a keyboard. Several --send arguments are written in order.

Return is \\r, not \\n. A terminal sends carriage return when Enter is pressed,
and while zle accepts either, a program that reads the terminal itself may not:
fzf ignores \\n, so a picker driven with it sits there until the timeout.

There is deliberately no bracketed-paste marker around them. With the markers
zsh would treat the whole run as pasted text and insert a literal tab instead of
completing; without them each byte arrives as its own key press.

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
        sys.stderr.write("usage: zsh_pty.py SCRIPT [--send KEYS ...] [-- zsh arg ...]\n")
        return 2

    script = argv[0]
    rest = argv[1:]
    sends = []
    send_delay = 0.0
    time_to_prompt = False
    if rest and rest[0] == "--time-to-prompt":
        time_to_prompt = True
        rest = rest[1:]
    while rest and rest[0] in ("--send", "--delay"):
        if len(rest) < 2:
            sys.stderr.write("zsh_pty.py: %s needs an argument\n" % rest[0])
            return 2
        if rest[0] == "--send":
            sends.append(_unescape(rest[1]))
        else:
            send_delay = float(rest[1])
        rest = rest[2:]
    if rest and rest[0] == "--":
        rest = rest[1:]
    zsh_args = rest or ["--no-globalrcs", "-i"]

    if not os.path.exists(script):
        sys.stderr.write("zsh_pty.py: no such script: %s\n" % script)
        return 2

    pid, fd = pty.fork()
    if pid == 0:
        # Child: becomes the shell. $TERM is pinned rather than inherited, for the
        # same reason as the window size below: what the config does depends on
        # it. Bindings looked up through zsh/terminfo do nothing under TERM=dumb,
        # and the terminal title is only set for terminals known to have one — so
        # inheriting whatever the CI image exports (TERM=linux, TERM=dumb) would
        # make the specs pass or fail according to where they ran.
        os.environ["TERM"] = os.environ.get("ZSH_PTY_TERM", "xterm-256color")
        try:
            os.execvp("zsh", ["zsh"] + zsh_args)
        except OSError as exc:  # pragma: no cover - only on a broken PATH
            sys.stderr.write("zsh_pty.py: cannot exec zsh: %s\n" % exc)
            os._exit(127)

    started = time.time()
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))

    collected = bytearray()
    deadline = time.time() + TIMEOUT

    def pump_once(timeout):
        """Read whatever is waiting. False when the terminal has closed."""
        readable, _, _ = select.select([fd], [], [], timeout)
        if not readable:
            return True
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            return False  # the child closed the terminal: it exited
        if not chunk:
            return False
        # .extend, not `+=`: rebinding the name would make it local to pump.
        collected.extend(chunk)
        return True

    def pump():
        """Read until the shell exits or the deadline passes."""
        while time.time() < deadline:
            if not pump_once(min(0.2, max(0.01, deadline - time.time()))):
                return True
        return False

    def pump_until(marker):
        """Read until `marker` shows up in the output."""
        while marker not in collected:
            if time.time() >= deadline:
                return False
            if not pump_once(0.05):
                return marker in collected
        return True

    def settle(quiet=0.4):
        """Read until the terminal has produced nothing for `quiet` seconds."""
        last = time.time()
        while time.time() < deadline and time.time() - last < quiet:
            before = len(collected)
            if not pump_once(0.05):
                return
            if len(collected) != before:
                last = time.time()

    def wait_for_raw_mode(poll=0.02):
        """Wait for zle to clear ICANON, which it does while editing a line."""
        while time.time() < deadline:
            try:
                if not termios.tcgetattr(fd)[3] & termios.ICANON:
                    return True
            except termios.error:
                return False
            pump_once(poll)
        return False

    if time_to_prompt:
        # How long the shell takes to be ready for a keystroke, which is what
        # "startup time" means to whoever is waiting for it. ICANON going away is
        # the moment zle takes the terminal, i.e. the prompt is up and accepting
        # input — and unlike timing `zsh -i -c exit`, it counts drawing the prompt
        # and stops counting at the point the shell became usable. Polled finely,
        # since the number being measured is a few tens of milliseconds.
        #
        # The script is not sourced in this mode: it would be measured too.
        if not wait_for_raw_mode(poll=0.001):
            return _give_up(pid, fd, collected, "no prompt appeared")
        elapsed = (time.time() - started) * 1000.0
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
        os.close(fd)
        sys.stdout.write("%.1f\n" % elapsed)
        sys.stdout.flush()
        return 0

    # `source` rather than pasting the script's text in: the shell echoes what it
    # is sent, and a multi-line paste comes back interleaved with continuation
    # prompts. One line in, one line echoed.
    # Both commands this file types are prefixed with a space, so hist_ignore_space
    # keeps them out of the history. Without that, a spec that presses Up or asks
    # for "the last command" gets this scaffolding instead of what it set up.
    os.write(fd, (" source %s\n" % _quote(script)).encode())

    if sends:
        # The keys must not be sent until the line editor is reading.
        #
        # Between commands the terminal is back in canonical mode, where the
        # driver echoes the bytes itself, buffers them until a newline, and turns
        # a Ctrl-C into a signal. Keys that land then arrive as one pasted line: a
        # Tab stays a literal tab instead of completing, and no binding fires.
        #
        # Two things have to be true. The script must have finished — proved by
        # the output of a marker command queued behind it, written as two adjacent
        # quoted strings so the echo of the command itself does not match. And the
        # editor must have the terminal in raw mode again, which the parent can
        # see directly: zle clears ICANON while it reads, so the flag going away
        # is the moment a key press will be read as a key press. A zle line-init
        # hook was tried first and is not equivalent — it runs while the terminal
        # is still canonical.
        os.write(fd, b" print -r -- '__PTY''_READY__'\n")
        if not pump_until(b"__PTY_READY__"):
            return _give_up(pid, fd, collected, "the script never finished")
        if not wait_for_raw_mode():
            return _give_up(pid, fd, collected, "the line editor never took the terminal")

        for index, keys in enumerate(sends):
            # --delay puts time between one batch of keys and the next, for the
            # cases where the shell has to *do* something in between: start the
            # job that the next key suspends, run the command whose output the
            # next key reacts to. Draining as we wait, so the shell is never
            # blocked writing to a full terminal buffer.
            if index and send_delay:
                until = time.time() + send_delay
                while time.time() < until:
                    if not pump_once(min(0.05, until - time.time())):
                        break
            os.write(fd, keys)

        # The shell is then killed rather than asked to exit.
        #
        # Sending Ctrl-C to clear the line first looks obvious and is wrong: ISIG
        # is still on under zle, so the driver raises SIGINT the moment the byte
        # arrives — before zle has read the keys queued ahead of it — and zsh
        # discards pending input when interrupted. The keys vanish and the test
        # silently measures nothing. Typing `exit` instead is no better, because
        # whatever the keys left on the command line would swallow it.
        #
        # By the time the terminal has gone quiet, every widget the keys triggered
        # has run and written whatever it was going to write, so there is nothing
        # left to wait for.
        settle()
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
        os.close(fd)
        _flush(collected)
        return 0

    os.write(fd, b"exit\n")
    pump()

    os.close(fd)
    _, status = os.waitpid(pid, 0)
    _flush(collected)
    if os.WIFEXITED(status):
        return os.WEXITSTATUS(status)
    return 128 + os.WTERMSIG(status)


def _give_up(pid, fd, collected, why):
    os.kill(pid, signal.SIGKILL)
    os.waitpid(pid, 0)
    os.close(fd)
    _flush(collected)
    sys.stderr.write("zsh_pty.py: %s\n" % why)
    return 124


def _quote(path):
    return "'" + path.replace("'", "'\\''") + "'"


def _unescape(text):
    """Turn \\t, \\e, \\n, \\x18 and friends into the bytes a terminal sends.

    latin-1 at the end rather than utf-8: unicode_escape produces one character
    per byte, and re-encoding those characters as utf-8 would turn every byte
    above 0x7f into two.
    """
    return text.encode("utf-8").decode("unicode_escape").encode("latin-1")


def _flush(collected):
    sys.stdout.write(bytes(collected).decode("utf-8", errors="replace"))
    sys.stdout.flush()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
