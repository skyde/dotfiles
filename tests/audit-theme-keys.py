#!/usr/bin/env python3
"""Check that the theme's keys are still keys — that upstream still reads them.

`tests/check-theme.py` compares colours. It cannot tell you that a key stopped
being read, because a colour nobody reads is still a valid colour, and most of
these tools ignore a key they do not recognise without a word. That failure
looks like nothing at all: the setting is there, spelled correctly, and simply
does not happen any more. Renames are the dangerous case — yazi moved
`[mgr] hovered` to `[indicator] current` and the hovered row silently went back
to `reversed` for a while.

docs/tokyonight.md describes the audit that catches it: fetch the list of keys
each tool actually reads, and diff ours against it. This is that audit, run for
you. It reports two things:

  DEAD    a key we set that the *released* upstream does not know. This is the
          real failure — the setting is doing nothing right now.
  AHEAD   a key the release still reads but upstream's default branch has
          dropped or renamed. Not broken yet; it breaks on the next upgrade.

A rename puts a config on both sides of it at once, so a key can also be
deliberately BEHIND: the pre-rename spelling, kept so a binary older than the
release still finds the setting. Those are listed in ACCEPTED_BEHIND, each
paired with the modern spelling that has to be present too — and the pairing is
verified, because an old spelling on its own is not a compatibility shim, it is
exactly the dead key this script is looking for.

The release/main split is the whole point of comparing against both. An
upstream preset on `main` includes renames that have not shipped, so diffing
against `main` alone cries wolf, and diffing against the release alone gives no
warning before an upgrade lands. yazi's `[help]` keys are the standing example:
superseded on `main`, still read by every release so far.

Unlike check-theme.py this needs the network, so it is not one of the checks
you run on every change — run it when a tool is upgraded, or every few months.

    tests/audit-theme-keys.py            # report dead keys, exit non-zero
    tests/audit-theme-keys.py --verbose  # also list keys upstream has that we
                                         # do not set, and what was checked

One kind of dead key a name diff structurally cannot see: an option upstream
advertises and then never applies. It is in the option list, so it looks alive,
and setting it does exactly as much as setting a key that does not exist. Those
are listed by hand in INERT below, with what was done to establish it.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TIMEOUT = 30


# --- talking to upstream ---------------------------------------------------


def latest_tag(remote: str) -> str:
    """The newest release tag of a GitHub repo, by version order.

    Asked of git rather than the REST API on purpose: the API wants a token for
    anything but a trickle of anonymous requests and answers 403 without one,
    while `ls-remote` is the same unauthenticated fetch git already does.
    """
    result = subprocess.run(
        ["git", "ls-remote", "--tags", "--refs", f"https://github.com/{remote}.git"],
        capture_output=True,
        text=True,
        check=False,
        timeout=TIMEOUT,
    )
    if result.returncode != 0:
        raise RuntimeError(f"could not list tags for {remote}: {result.stderr.strip()}")
    tags = [line.rsplit("/", 1)[-1] for line in result.stdout.splitlines() if line]
    # Version-sort on the numbers, so v26.5.6 beats v26.1.22 and a tag with no
    # numbers in it at all (delta ships a "windows-strip-binary" tag) sorts last
    # rather than winning on string order.
    numbered = [tag for tag in tags if re.search(r"\d", tag)]
    if not numbered:
        raise RuntimeError(f"{remote} has no version-like tags")
    return max(numbered, key=lambda tag: [int(n) for n in re.findall(r"\d+", tag)])


def fetch(remote: str, ref: str, path: str) -> str:
    url = f"https://raw.githubusercontent.com/{remote}/{ref}/{path}"
    try:
        with urllib.request.urlopen(url, timeout=TIMEOUT) as response:
            return response.read().decode("utf-8")
    except (urllib.error.URLError, TimeoutError) as error:
        raise RuntimeError(f"could not fetch {url}: {error}") from error


def read(relative: str) -> str:
    return (REPO / relative).read_text(encoding="utf-8")


# --- how each tool spells its key list -------------------------------------
#
# Each tool below answers "what do you actually read?" in a different place: a
# preset file, a clap option list, a C++ map, a JSON schema. The parsers are
# deliberately loose — they are looking for a set of names, not trying to
# understand the document.


def toml_sections(text: str) -> dict[str, set[str]]:
    """{section: {key}} for a flat TOML file. Array-of-table bodies are skipped."""
    found: dict[str, set[str]] = {}
    section = None
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and not stripped.startswith("[["):
            section = stripped.strip("[]")
            found.setdefault(section, set())
        elif section and re.match(r"^[a-z_]+\s*=", stripped):
            found[section].add(stripped.split("=")[0].strip())
    return found


def audit_yazi(ref: str) -> tuple[set[str], set[str], set[str]]:
    """yazi's preset lists every key it reads. Ours must be a subset."""
    upstream = toml_sections(fetch("sxyazi/yazi", ref, "yazi-config/preset/theme-dark.toml"))
    mine = toml_sections(read("common/.config/yazi/theme.toml"))
    dead: set[str] = set()
    for section, keys in mine.items():
        # [filetype] is a rules array, not a key table, and its contents are
        # check-theme.py's business.
        if section == "filetype":
            continue
        if section not in upstream:
            dead.add(f"[{section}] (whole section)")
            continue
        dead |= {f"[{section}] {key}" for key in keys - upstream[section]}
    unset = {
        f"[{section}] {key}"
        for section, keys in upstream.items()
        # Icons and flavours are not colours we set, and the filetype rules are
        # a different check.
        if section not in ("icon", "filetype", "flavor")
        for key in keys - mine.get(section, set())
    }
    flat = {f"[{section}] {key}" for section, keys in mine.items() for key in keys}
    return dead, unset, flat


def audit_delta(ref: str) -> tuple[set[str], set[str], set[str]]:
    """delta's options are its clap definitions."""
    upstream = set(re.findall(r'long\s*=\s*"([a-z0-9-]+)"', fetch("dandavison/delta", ref, "src/cli.rs")))
    block = re.search(r"^\[delta\]\n(.*?)(?=^\[)", read("common/.config/git/config"), re.S | re.M)
    if not block:
        raise RuntimeError("no [delta] section in common/.config/git/config")
    mine = {
        match.group(1)
        for line in block.group(1).splitlines()
        if (match := re.match(r"\s*([a-zA-Z0-9-]+)\s*=", line))
    }
    # Only the *-style options are worth listing as "not set": delta has a
    # hundred behavioural flags and this is a theme audit.
    unset = {option for option in upstream if option.endswith("-style")} - mine
    return mine - upstream, unset, mine


def audit_btop(ref: str) -> tuple[set[str], set[str], set[str]]:
    """btop's key list is the Default_theme map it falls back to."""
    source = fetch("aristocratos/btop", ref, "src/btop_theme.cpp")
    block = re.search(r"Default_theme.*?\{(.*?)^\s*\};", source, re.S | re.M)
    if not block:
        raise RuntimeError("could not find btop's Default_theme map")
    upstream = set(re.findall(r'\{\s*"(\w+)"', block.group(1)))
    mine = set(re.findall(r"theme\[(\w+)\]", read("common/.config/btop/themes/tokyo-night.theme")))
    return mine - upstream, upstream - mine, mine


def audit_lazygit(ref: str) -> tuple[set[str], set[str], set[str]]:
    """lazygit publishes a JSON schema, which is the list."""
    schema = json.loads(fetch("jesseduffield/lazygit", ref, "schema/config.json"))
    definitions = schema.get("$defs") or schema.get("definitions") or {}
    upstream = set(definitions.get("ThemeConfig", {}).get("properties", {}))
    if not upstream:
        raise RuntimeError("lazygit's schema has no ThemeConfig properties")
    block = re.search(r"^  theme:\s*$(.*?)(?=^  \w|\Z)", read("common/.config/lazygit/config.yml"), re.S | re.M)
    if not block:
        raise RuntimeError("no gui.theme block in common/.config/lazygit/config.yml")
    mine = set(re.findall(r"^\s+(\w+):", block.group(1), re.M))
    return mine - upstream, upstream - mine, mine


# repo, default branch, and the audit for it.
TOOLS = [
    ("yazi", "sxyazi/yazi", "main", audit_yazi),
    ("delta", "dandavison/delta", "main", audit_delta),
    ("btop", "aristocratos/btop", "main", audit_btop),
    ("lazygit", "jesseduffield/lazygit", "master", audit_lazygit),
]

# Options upstream advertises and then never applies. These are the dead keys a
# name diff cannot see: they are in the option list, so they look alive, and
# setting one does exactly as much as setting a key that does not exist.
#
# Each entry records how it was established, because the only way to find one is
# to read the source or probe the binary — and the only way to be sure it is
# still true after an upgrade is to do that again.
INERT = {
    "delta": {
        "grep-header-file-style": (
            "delta parses it into an internal `ripgrep-header-file-style` and "
            "then never reads that value; the ripgrep-format heading takes "
            "`grep-file-style` like the classic format does. Probed on 0.18.2: "
            "setting grep-header-file-style changes nothing, setting "
            "grep-file-style moves the heading."
        ),
    },
}

# Keys the *current* release no longer reads, kept on purpose so a binary from
# before the rename still finds them. The mirror image of ACCEPTED_AHEAD: that
# one is early, this one is late, and a config that has to work on machines
# whose yazi was installed at different times needs both spellings of a rename
# present at once.
#
# Each entry names the modern spelling that has to be there too, and that is
# checked rather than assumed — an old spelling on its own is not a
# compatibility shim, it is the dead key this script exists to find. (The
# filetype rules say `url` and `name` both ways for the same reason;
# check-theme.py already fails on a rule that carries only one, so they are not
# repeated here.)
ACCEPTED_BEHIND = {
    "yazi": {
        "[mgr.hovered] (whole section)": "[indicator] current",
        "[mgr.preview_hovered] (whole section)": "[indicator] preview",
        "[confirm] content": "[confirm] body",
    },
}

# Keys that are AHEAD on purpose, with the reason. An entry here says "yes, this
# is superseded upstream, and staying on it is the right call until the rename
# ships" — it does not silence DEAD, which is about the release we run.
ACCEPTED_AHEAD = {
    "yazi": {
        "[help] on": "renamed upstream; still read by every release so far",
        "[help] run": "renamed upstream; still read by every release so far",
        "[help] desc": "renamed upstream; still read by every release so far",
        "[help] footer": "renamed upstream; still read by every release so far",
    },
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verbose", action="store_true", help="list unset keys too")
    parser.add_argument("--tool", action="append", help="audit only these tools")
    arguments = parser.parse_args()

    failures = 0
    unreachable = 0
    for name, remote, branch, audit in TOOLS:
        if arguments.tool and name not in arguments.tool:
            continue
        try:
            tag = latest_tag(remote)
            dead, unset, mine = audit(tag)
            ahead, _, _ = audit(branch)
        except RuntimeError as error:
            print(f"SKIP  {name}: {error}")
            unreachable += 1
            continue

        behind = ACCEPTED_BEHIND.get(name, {})
        for key in sorted(dead):
            partner = behind.get(key)
            if partner and partner in mine:
                if arguments.verbose:
                    print(f"  ok  {name} {key} is behind, accepted (paired with {partner})")
                continue
            print(f"DEAD  {name} {key}")
            if partner:
                print(f"      -> kept for a pre-rename {name}, but {partner} is gone, so "
                      f"nothing reads this on {tag} either")
            else:
                print(f"      -> {tag} does not read this; it is doing nothing right now")
            failures += 1

        inert = mine & set(INERT.get(name, {}))
        for key in sorted(inert):
            print(f"DEAD  {name} {key} (inert)")
            print(f"      -> {INERT[name][key]}")
            failures += 1

        # Anything dead in the release is already reported; AHEAD is only about
        # what the *next* upgrade will take away.
        for key in sorted(ahead - dead):
            reason = ACCEPTED_AHEAD.get(name, {}).get(key)
            if reason:
                if arguments.verbose:
                    print(f"  ok  {name} {key} is ahead, accepted ({reason})")
            else:
                print(f"AHEAD {name} {key}")
                print(f"      -> {tag} still reads it, {remote}@{branch} does not; check the CHANGELOG")

        if not dead and not inert:
            print(f"  ok  {name} {tag}: all keys are read")
        if arguments.verbose and unset:
            print(f"      {name} reads these and we do not set them:")
            for key in sorted(unset):
                print(f"        {key}")

    if unreachable:
        print(f"\naudit incomplete: {unreachable} tool(s) could not be reached")
        return 2
    if failures:
        print(f"\naudit: {failures} dead key(s)")
        return 1
    print("\naudit: every key we set is still read")
    return 0


if __name__ == "__main__":
    sys.exit(main())
