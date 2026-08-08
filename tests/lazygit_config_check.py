#!/usr/bin/env python3
"""Check that lazygit actually understands every key in our lazygit config.

lazygit reacts to a config it does not fully recognise in two silent ways, and
this checks for both:

  * A key it has never heard of is dropped. Misspell one, or nest it wrongly,
    and the feature simply stops happening with no error — `gui.theme.lightTheme`
    and a top-level `scrollOffBehavior` lived in this repo's config that way.
  * A key it has *renamed* is migrated, and lazygit then writes the migrated
    config back to disk. The write follows the stow symlink, so it edits the
    tracked file in this repo. `git.pagers` (renamed in 0.64) did exactly that.

Two modes for the first kind, strongest first:

  schema   Validate against lazygit's own published JSON schema (generated
           from the same structs the binary parses with). Catches unknown
           keys, wrong types, and bad enum values.
  defaults Compare key paths against `lazygit --config`, which prints the
           binary's default config and therefore enumerates every key it
           knows. Catches unknown keys and gross type mistakes. Used when the
           schema is not available offline.

Run through tests/check-lazygit-config.sh, which locates lazygit and the
schema; this file only does the checking.

No third-party imports: this has to run on a stock python3 (macOS ships one
without PyYAML). The YAML subset parser below covers what our config uses and
refuses anything else rather than guessing. When PyYAML *is* importable it is
used as a cross-check, so the subset parser cannot drift unnoticed.
"""

from __future__ import annotations

import argparse
import json
import re
import sys

# ---------------------------------------------------------------- YAML subset


class YamlError(Exception):
    pass


class Line:
    __slots__ = ("col", "text", "num")

    def __init__(self, col: int, text: str, num: int):
        self.col = col
        self.text = text
        self.num = num


def _strip_comment(raw: str) -> str:
    """Drop a trailing `# ...` comment, honouring quotes.

    A '#' only starts a comment at the start of the line or after whitespace,
    which is what keeps `"#7aa2f7"` and `'#'`-containing values intact.
    """
    quote = ""
    for i, ch in enumerate(raw):
        if quote:
            if ch == quote:
                quote = ""
            elif ch == "\\" and quote == '"':
                pass
        elif ch in "\"'":
            quote = ch
        elif ch == "#" and (i == 0 or raw[i - 1] in " \t"):
            return raw[:i]
    return raw


def _tokenize(text: str) -> list[Line]:
    lines: list[Line] = []
    for num, raw in enumerate(text.splitlines(), start=1):
        if "\t" in raw[: len(raw) - len(raw.lstrip())]:
            raise YamlError(f"line {num}: tab used for indentation")
        stripped = _strip_comment(raw).rstrip()
        if not stripped.strip():
            continue
        if stripped.strip() in ("---", "..."):
            continue
        col = len(stripped) - len(stripped.lstrip())
        lines.append(Line(col, stripped.strip(), num))
    return lines


_INT_RE = re.compile(r"^-?\d+$")
_FLOAT_RE = re.compile(r"^-?(\d+\.\d*|\.\d+)([eE][-+]?\d+)?$")


def _scalar(token: str, num: int):
    token = token.strip()
    if not token:
        return None
    if token[0] in "\"'":
        return _quoted(token, num)[0]
    if token in ("true", "True", "yes", "on"):
        return True
    if token in ("false", "False", "no", "off"):
        return False
    if token in ("null", "Null", "~"):
        return None
    if _INT_RE.match(token):
        return int(token)
    if _FLOAT_RE.match(token):
        return float(token)
    for bad in ("&", "*", "|", ">"):
        if token.startswith(bad):
            raise YamlError(
                f"line {num}: unsupported YAML construct {token[0]!r}; "
                "this checker only handles plain block YAML"
            )
    return token


def _quoted(token: str, num: int) -> tuple[str, int]:
    """Read one quoted scalar from the start of `token`; return (value, length)."""
    quote = token[0]
    out = []
    i = 1
    while i < len(token):
        ch = token[i]
        if quote == "'":
            if ch == "'":
                if i + 1 < len(token) and token[i + 1] == "'":
                    out.append("'")
                    i += 2
                    continue
                return "".join(out), i + 1
            out.append(ch)
            i += 1
        else:
            if ch == "\\" and i + 1 < len(token):
                nxt = token[i + 1]
                # \uXXXX / \UXXXXXXXX: how lazygit's docs write Nerd Font
                # glyphs, so gui.customIcons is full of them.
                width = {"u": 4, "U": 8, "x": 2}.get(nxt)
                if width:
                    digits = token[i + 2 : i + 2 + width]
                    if len(digits) != width or any(c not in "0123456789abcdefABCDEF" for c in digits):
                        raise YamlError(f"line {num}: bad \\{nxt} escape")
                    out.append(chr(int(digits, 16)))
                    i += 2 + width
                    continue
                out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(nxt, nxt))
                i += 2
                continue
            if ch == '"':
                return "".join(out), i + 1
            out.append(ch)
            i += 1
    raise YamlError(f"line {num}: unterminated quoted string")


def _split_key(token: str, num: int) -> tuple[str, str] | None:
    """Split `key: value` at the first colon that is a real key separator."""
    if token[0] in "\"'":
        key, length = _quoted(token, num)
        rest = token[length:]
        if not rest.startswith(":"):
            return None
        return key, rest[1:].strip()
    for i, ch in enumerate(token):
        if ch == ":" and (i + 1 == len(token) or token[i + 1] in " \t"):
            return token[:i].strip(), token[i + 1 :].strip()
    return None


def _parse_flow(token: str, num: int):
    value, rest = _flow_value(token, num)
    if rest.strip():
        raise YamlError(f"line {num}: trailing text after flow collection: {rest!r}")
    return value


def _flow_value(token: str, num: int):
    token = token.lstrip()
    if token.startswith("["):
        items = []
        rest = token[1:].lstrip()
        while True:
            if rest.startswith("]"):
                return items, rest[1:]
            item, rest = _flow_value(rest, num)
            items.append(item)
            rest = rest.lstrip()
            if rest.startswith(","):
                rest = rest[1:].lstrip()
            elif not rest.startswith("]"):
                raise YamlError(f"line {num}: malformed flow sequence")
    if token.startswith("{"):
        out = {}
        rest = token[1:].lstrip()
        while True:
            if rest.startswith("}"):
                return out, rest[1:]
            if rest.startswith(("'", '"')):
                key, length = _quoted(rest, num)
                rest = rest[length:].lstrip()
            else:
                end = 0
                while end < len(rest) and rest[end] not in ":,}":
                    end += 1
                key = rest[:end].strip()
                rest = rest[end:]
            if not rest.startswith(":"):
                raise YamlError(f"line {num}: flow mapping key {key!r} has no value")
            value, rest = _flow_value(rest[1:], num)
            out[key] = value
            rest = rest.lstrip()
            if rest.startswith(","):
                rest = rest[1:].lstrip()
            elif not rest.startswith("}"):
                raise YamlError(f"line {num}: malformed flow mapping")
    if token.startswith(("'", '"')):
        value, length = _quoted(token, num)
        return value, token[length:]
    end = 0
    while end < len(token) and token[end] not in ",}]":
        end += 1
    return _scalar(token[:end], num), token[end:]


def _parse_node(lines: list[Line], idx: int, col: int):
    if lines[idx].text.startswith("- ") or lines[idx].text == "-":
        return _parse_sequence(lines, idx, col)
    return _parse_mapping(lines, idx, col)


def _parse_sequence(lines: list[Line], idx: int, col: int):
    out = []
    while idx < len(lines) and lines[idx].col == col:
        line = lines[idx]
        if not (line.text.startswith("- ") or line.text == "-"):
            break
        rest = line.text[1:].strip()
        if not rest:
            if idx + 1 < len(lines) and lines[idx + 1].col > col:
                value, idx = _parse_node(lines, idx + 1, lines[idx + 1].col)
            else:
                value, idx = None, idx + 1
            out.append(value)
            continue
        if rest[0] in "[{":
            out.append(_parse_flow(rest, line.num))
            idx += 1
            continue
        pair = _split_key(rest, line.num)
        if pair is None:
            out.append(_scalar(rest, line.num))
            idx += 1
            continue
        # `- key: value` opens a mapping whose column is where the key starts.
        inner_col = col + (len(line.text) - len(line.text[1:].lstrip()))
        virtual = [Line(inner_col, rest, line.num)] + lines[idx + 1 :]
        value, consumed = _parse_mapping(virtual, 0, inner_col)
        out.append(value)
        idx += consumed
    return out, idx


def _parse_mapping(lines: list[Line], idx: int, col: int):
    out: dict = {}
    while idx < len(lines) and lines[idx].col == col:
        line = lines[idx]
        if line.text.startswith("- "):
            break
        pair = _split_key(line.text, line.num)
        if pair is None:
            raise YamlError(f"line {line.num}: expected `key: value`, got {line.text!r}")
        key, rest = pair
        if rest:
            out[key] = _parse_flow(rest, line.num) if rest[0] in "[{" else _scalar(rest, line.num)
            idx += 1
            continue
        if idx + 1 < len(lines) and lines[idx + 1].col > col:
            out[key], idx = _parse_node(lines, idx + 1, lines[idx + 1].col)
        elif idx + 1 < len(lines) and lines[idx + 1].col == col and lines[idx + 1].text.startswith("- "):
            out[key], idx = _parse_sequence(lines, idx + 1, col)
        else:
            out[key] = None
            idx += 1
    return out, idx


def mini_yaml_load(text: str):
    lines = _tokenize(text)
    if not lines:
        return {}
    value, idx = _parse_node(lines, 0, lines[0].col)
    if idx != len(lines):
        raise YamlError(f"line {lines[idx].num}: unexpected indentation")
    return value


def load_yaml(path: str):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    parsed = mini_yaml_load(text)
    try:
        import yaml  # noqa: PLC0415 — optional cross-check only
    except ImportError:
        return parsed, None
    try:
        reference = yaml.safe_load(text)
    except yaml.YAMLError:
        # PyYAML is the stricter reader of the two: `lazygit --config` prints
        # things like `expandAll: =`, where a bare `=` is YAML's rarely-used
        # "value" tag and PyYAML refuses it while lazygit's own parser (and the
        # reader above) take it as the string it obviously is. Nothing to
        # cross-check against, so don't.
        return parsed, None
    if reference != parsed:
        return parsed, "the built-in YAML subset parser disagrees with PyYAML"
    return parsed, None


# ------------------------------------------------------------ schema checking


class SchemaValidator:
    """Just enough JSON Schema for lazygit's config schema.

    Supported keywords are exactly the ones that schema uses: $ref, type,
    properties, additionalProperties, items, oneOf, enum, minItems, minLength,
    minimum, maximum, exclusiveMinimum, uniqueItems.
    """

    _TYPES = {
        "object": dict,
        "array": list,
        "string": str,
        "integer": int,
        "number": (int, float),
        "boolean": bool,
        "null": type(None),
    }

    def __init__(self, schema: dict):
        self.schema = schema
        self.defs = schema.get("$defs", {})
        self.errors: list[str] = []

    def validate(self, instance, node=None, path="") -> list[str]:
        self.errors = []
        self._check(instance, node if node is not None else self.schema, path)
        return self.errors

    def _resolve(self, node: dict) -> dict:
        seen = 0
        while "$ref" in node:
            ref = node["$ref"]
            if not ref.startswith("#/$defs/"):
                raise ValueError(f"unsupported $ref: {ref}")
            merged = dict(self.defs[ref[len("#/$defs/") :]])
            merged.update({k: v for k, v in node.items() if k != "$ref"})
            node = merged
            seen += 1
            if seen > 32:
                raise ValueError("cyclic $ref")
        return node

    def _fail(self, path: str, message: str) -> None:
        self.errors.append(f"{path or '<root>'}: {message}")

    def _check(self, instance, node: dict, path: str) -> None:
        node = self._resolve(node)

        if "oneOf" in node:
            for option in node["oneOf"]:
                probe = SchemaValidator(self.schema)
                if not probe.validate(instance, option, path):
                    return
            self._fail(path, f"{instance!r} matches none of the allowed forms")
            return

        expected = node.get("type")
        if expected:
            wanted = self._TYPES[expected]
            # bool is an int subclass in Python; lazygit's schema means them
            # as distinct types.
            if expected in ("integer", "number") and isinstance(instance, bool):
                self._fail(path, f"expected {expected}, got boolean")
                return
            if not isinstance(instance, wanted):
                got = type(instance).__name__
                self._fail(path, f"expected {expected}, got {got} ({instance!r})")
                return

        if "enum" in node and instance not in node["enum"]:
            allowed = " | ".join(repr(v) for v in node["enum"])
            self._fail(path, f"{instance!r} is not one of {allowed}")
            return

        if isinstance(instance, str):
            if "minLength" in node and len(instance) < node["minLength"]:
                self._fail(path, "must not be empty")

        if isinstance(instance, (int, float)) and not isinstance(instance, bool):
            if "minimum" in node and instance < node["minimum"]:
                self._fail(path, f"must be >= {node['minimum']}")
            if "exclusiveMinimum" in node and instance <= node["exclusiveMinimum"]:
                self._fail(path, f"must be > {node['exclusiveMinimum']}")
            if "maximum" in node and instance > node["maximum"]:
                self._fail(path, f"must be <= {node['maximum']}")

        if isinstance(instance, list):
            if "minItems" in node and len(instance) < node["minItems"]:
                self._fail(path, f"needs at least {node['minItems']} items")
            item_schema = node.get("items")
            if item_schema:
                for i, item in enumerate(instance):
                    self._check(item, item_schema, f"{path}[{i}]")

        if isinstance(instance, dict):
            properties = node.get("properties", {})
            extra = node.get("additionalProperties")
            for key, value in instance.items():
                sub = f"{path}.{key}" if path else key
                if key in properties:
                    self._check(value, properties[key], sub)
                elif extra is False:
                    known = ", ".join(sorted(properties)) or "(none)"
                    self._fail(sub, f"unknown key; lazygit would ignore it. Known keys: {known}")
                elif isinstance(extra, dict):
                    self._check(value, extra, sub)


# ---------------------------------------------------------- defaults checking

# `lazygit --config` prints defaults for everything except the `os` section
# (its defaults are computed per platform), and free-form maps print as `{}`
# with no hint of what may go inside them. Both gaps are filled here; this is
# only the offline fallback, the schema mode above needs none of it.
OS_KEYS = {
    "edit",
    "editAtLine",
    "editAtLineAndWait",
    "editInTerminal",
    "editPreset",
    "open",
    "openDirInEditor",
    "openLink",
    "copyToClipboardCmd",
    "readFromClipboardCmd",
    "shellFunctionsFile",
}

# Subtrees whose keys are user-defined rather than lazygit-defined.
FREE_FORM = {
    "gui.authorColors",
    "gui.branchColors",
    "gui.branchColorPatterns",
    "gui.customIcons.filenames",
    "gui.customIcons.extensions",
    "git.commitPrefixes",
    "services",
}

CUSTOM_COMMAND_KEYS = {
    "key",
    "context",
    "command",
    "commandMenu",
    "prompts",
    "loadingText",
    "description",
    "output",
    "outputTitle",
    "after",
}
PROMPT_KEYS = {
    "type",
    "key",
    "title",
    "initialValue",
    "suggestions",
    "body",
    "options",
    "command",
    "filter",
    "valueFormat",
    "labelFormat",
    "condition",
}
OPTION_KEYS = {"name", "description", "value", "key"}
SUGGESTION_KEYS = {"preset", "command"}
DIFF_RENDERER_KEYS = {"type", "name", "colorArg", "command", "args"}


def kind(value) -> str:
    """The shape a value has, at the granularity the defaults dump can prove.

    int and float are one kind on purpose: a default of 0.3333 tells us the
    key takes a number, not that 1 would be wrong.
    """
    if isinstance(value, dict):
        return "map"
    if isinstance(value, list):
        return "list"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, (int, float)):
        return "number"
    if value is None:
        return "empty"
    return "string"


def check_against_defaults(config: dict, defaults: dict) -> list[str]:
    errors: list[str] = []

    def walk(node, reference, path: str) -> None:
        for key, value in node.items():
            sub = f"{path}.{key}" if path else key
            if sub in FREE_FORM:
                continue
            if path == "" and key == "os":
                for os_key in value or {}:
                    if os_key not in OS_KEYS:
                        errors.append(f"os.{os_key}: unknown key; lazygit would ignore it")
                continue
            if key not in reference:
                known = ", ".join(sorted(reference)) or "(none)"
                errors.append(f"{sub}: unknown key; lazygit would ignore it. Known keys: {known}")
                continue
            expected = reference[key]
            # An empty default (`nerdFontsVersion: ""`, `branchPrefix: ""`)
            # still pins the type; an explicitly null one says nothing.
            if kind(expected) != "empty" and kind(value) != kind(expected):
                errors.append(f"{sub}: expected {kind(expected)}, got {kind(value)}")
                continue
            if isinstance(value, dict):
                walk(value, expected, sub)

    walk({k: v for k, v in config.items() if k != "customCommands"}, defaults, "")
    errors.extend(check_custom_commands(config.get("customCommands") or [], "customCommands"))

    for i, renderer in enumerate(config.get("git", {}).get("diffRenderers") or []):
        for key in renderer:
            if key not in DIFF_RENDERER_KEYS:
                errors.append(f"git.diffRenderers[{i}].{key}: unknown key")
    return errors


def check_custom_commands(commands, path: str) -> list[str]:
    errors: list[str] = []
    for i, command in enumerate(commands):
        here = f"{path}[{i}]"
        if not isinstance(command, dict):
            errors.append(f"{here}: expected a mapping")
            continue
        for key in command:
            if key not in CUSTOM_COMMAND_KEYS:
                errors.append(f"{here}.{key}: unknown key")
        errors.extend(check_custom_commands(command.get("commandMenu") or [], f"{here}.commandMenu"))
        for j, prompt in enumerate(command.get("prompts") or []):
            prompt_path = f"{here}.prompts[{j}]"
            for key in prompt:
                if key not in PROMPT_KEYS:
                    errors.append(f"{prompt_path}.{key}: unknown key")
            for k, option in enumerate(prompt.get("options") or []):
                for key in option:
                    if key not in OPTION_KEYS:
                        errors.append(f"{prompt_path}.options[{k}].{key}: unknown key")
            for key in prompt.get("suggestions") or {}:
                if key not in SUGGESTION_KEYS:
                    errors.append(f"{prompt_path}.suggestions.{key}: unknown key")
    return errors




# ------------------------------------------------------------- semantic rules

VALID_CONTEXTS = {
    "status",
    "files",
    "worktrees",
    "submodules",
    "localBranches",
    "remotes",
    "remoteBranches",
    "tags",
    "commits",
    "reflogCommits",
    "subCommits",
    "commitFiles",
    "stash",
    "global",
}

# Which section of `keybinding:` governs each custom-command context, for the
# shadowing report. Approximate by design: it only decides whether a warning is
# printed.
CONTEXT_SECTIONS = {
    "status": ["status"],
    "files": ["files"],
    "submodules": ["submodules"],
    "localBranches": ["branches"],
    "remotes": ["branches"],
    "remoteBranches": ["branches"],
    "tags": ["branches"],
    "commits": ["commits"],
    "reflogCommits": ["commits"],
    "subCommits": ["commits"],
    "commitFiles": ["commitFiles"],
    "stash": ["stash"],
    "worktrees": [],
    "global": [],
}

SPECIAL_KEYS = {
    "insert", "delete", "home", "end", "pgup", "pgdown", "up", "down", "left",
    "right", "tab", "backtab", "enter", "esc", "backspace", "space", "minus",
    "plus", "disabled", "mouse wheel up", "mouse wheel down",
} | {f"f{n}" for n in range(1, 13)}

MODIFIERS = {
    "ctrl": "ctrl", "c": "ctrl",
    "alt": "alt", "a": "alt",
    "shift": "shift", "s": "shift",
    "meta": "meta", "m": "meta",
}


def normalize_key(key) -> tuple[str | None, str | None]:
    """Return (canonical form, error). A key lazygit cannot parse binds nothing."""
    if not isinstance(key, str) or not key:
        return None, f"{key!r} is not a key name"
    if not key.startswith("<"):
        if len(key) == 1:
            return key, None
        return None, f"{key!r} is neither a single character nor a <bracketed> key"
    if not key.endswith(">"):
        return None, f"{key!r} is missing its closing '>'"
    inner = key[1:-1]
    if inner in SPECIAL_KEYS:
        return f"<{inner}>", None
    parts = re.split(r"[-+]", inner)
    if len(parts) < 2:
        if len(inner) == 1:
            return f"<{inner}>", None
        return None, f"{key!r} is not a known key name"
    *mods, base = parts
    seen = set()
    for mod in mods:
        if mod.lower() not in MODIFIERS:
            return None, f"{key!r} has unknown modifier {mod!r}"
        seen.add(MODIFIERS[mod.lower()])
    if base not in SPECIAL_KEYS and len(base) != 1:
        return None, f"{key!r} has unknown base key {base!r}"
    if len(base) == 1 and base.isascii() and base.isupper():
        return None, f"{key!r} puts a modifier on an uppercase letter; use <ctrl+shift+{base.lower()}>"
    if seen == {"shift"} and len(base) == 1:
        return None, f"{key!r} is shift on a printable character; write {base.upper()!r} instead"
    return "<" + "+".join(sorted(seen) + [base]) + ">", None


def builtin_keys(defaults: dict, overrides: dict) -> dict[str, dict[str, str]]:
    """section -> {canonical key: action name} for the effective keybindings.

    Defaults from the installed binary, with the config's own `keybinding:`
    overrides applied on top — otherwise a rebound action still looks like it
    owns its old key, and every report about it is wrong.
    """
    out: dict[str, dict[str, str]] = {}
    for section, bindings in (defaults.get("keybinding") or {}).items():
        if not isinstance(bindings, dict):
            continue
        merged = dict(bindings)
        merged.update((overrides.get("keybinding") or {}).get(section) or {})
        table: dict[str, str] = {}
        for action, value in merged.items():
            for key in value if isinstance(value, list) else [value]:
                canonical, _ = normalize_key(key)
                if canonical and canonical != "<disabled>":
                    table[canonical] = f"{section}.{action}"
        out[section] = table
    return out


def shell_check(command: str) -> str | None:
    """Parse a command with `sh -n` after neutralising Go template placeholders.

    Catches the quoting mistakes that only show up when the command actually
    runs — the kind that silently produce an empty timestamp or eat an argument.
    """
    import shutil
    import subprocess

    shell = shutil.which("sh")
    if not shell:
        return None
    neutralised = re.sub(r"\{\{.*?\}\}", "placeholder", command, flags=re.DOTALL)
    result = subprocess.run(
        [shell, "-n"], input=neutralised, capture_output=True, text=True, check=False
    )
    if result.returncode == 0:
        return None
    return (result.stderr or result.stdout).strip().splitlines()[-1]


# Model fields custom commands may reference, from lazygit's custom-command
# shims (pkg/gui/services/custom_commands/models.go). The deprecated aliases
# (SelectedLocalCommit, Commit.Sha, Branch.Pushables) are deliberately absent
# so that using one fails here rather than the day it is removed.
MODELS = {
    "SelectedCommit": {
        "Hash", "Name", "Status", "Action", "Tags", "ExtraInfo", "AuthorName",
        "AuthorEmail", "UnixTimestamp", "Divergence", "Parents",
    },
    "SelectedCommitRange": {"From", "To"},
    "SelectedFile": {
        "Name", "PreviousName", "HasStagedChanges", "HasUnstagedChanges", "Tracked",
        "Added", "Deleted", "HasMergeConflicts", "HasInlineMergeConflicts",
        "DisplayString", "ShortStatus", "IsWorktree",
    },
    "SelectedPath": set(),
    "SelectedSubmodule": {"Name", "Path", "Url"},
    "SelectedLocalBranch": {
        "Name", "DisplayName", "Recency", "AheadForPull", "BehindForPull",
        "AheadForPush", "BehindForPush", "UpstreamGone", "Head", "DetachedHead",
        "UpstreamRemote", "UpstreamBranch", "Subject", "CommitHash",
    },
    "SelectedRemoteBranch": {"Name", "RemoteName"},
    "SelectedRemote": {"Name", "Urls", "PushUrls", "Branches"},
    "SelectedTag": {"Name", "Message"},
    "SelectedStashEntry": {"Index", "Recency", "Name"},
    "SelectedCommitFile": {"Name", "ChangeStatus"},
    "SelectedWorktree": {
        "IsMain", "IsCurrent", "Path", "IsPathMissing", "GitDir", "Branch", "Name",
    },
    "CheckedOutBranch": {
        "Name", "DisplayName", "Recency", "AheadForPull", "BehindForPull",
        "AheadForPush", "BehindForPush", "UpstreamGone", "Head", "DetachedHead",
        "UpstreamRemote", "UpstreamBranch", "Subject", "CommitHash",
    },
}

# `.Form.X` is user-defined; everything else starting with a capital is a model.
PLACEHOLDER_RE = re.compile(r"\{\{[^}]*?\.(?P<object>[A-Z]\w+)(?P<field>(\.\w+)*)")


def check_semantics(config: dict, defaults: dict | None) -> tuple[list[str], list[str]]:
    """Rules the schema cannot express. Returns (errors, warnings)."""
    errors: list[str] = []
    warnings: list[str] = []
    builtins = builtin_keys(defaults or {}, config)
    # scope -> {(key, context): description}, where scope is "" for top level
    # and the menu's own key for a commandMenu (menu keys only need to be
    # unique within their menu).
    claimed: dict[str, dict[tuple[str, str], str]] = {}

    for section, bindings in (config.get("keybinding") or {}).items():
        if not isinstance(bindings, dict):
            continue
        for action, value in bindings.items():
            for key in value if isinstance(value, list) else [value]:
                _, error = normalize_key(key)
                if error:
                    errors.append(f"keybinding.{section}.{action}: {error}")

    def walk(commands, scope: str) -> None:
        for command in commands:
            if not isinstance(command, dict):
                errors.append("customCommands: entry is not a mapping")
                continue
            label = command.get("description") or command.get("key") or "?"
            has_menu = "commandMenu" in command
            menu = command.get("commandMenu") or []
            contexts = [c.strip() for c in (command.get("context") or "").split(",") if c.strip()]

            keys = command.get("key")
            keys = keys if isinstance(keys, list) else [keys] if keys else []
            canonical_keys = []
            for key in keys:
                canonical, error = normalize_key(key)
                if error:
                    errors.append(f"custom command {label!r}: {error}")
                else:
                    canonical_keys.append(canonical)

            if has_menu:
                for ignored in ("context", "command", "prompts", "output", "loadingText"):
                    if ignored in command:
                        errors.append(
                            f"custom command {label!r}: `{ignored}` is ignored alongside `commandMenu`"
                        )
                for key in canonical_keys:
                    _claim(claimed, scope, key, "global", label, errors)
                walk(menu, f"menu:{command.get('key')}")
                continue

            if not command.get("command"):
                errors.append(f"custom command {label!r}: has no command")
            if not contexts:
                errors.append(f"custom command {label!r}: has no context")
            for context in contexts:
                if context not in VALID_CONTEXTS:
                    errors.append(f"custom command {label!r}: unknown context {context!r}")
                for key in canonical_keys:
                    _claim(claimed, scope, key, context, label, errors)
                    if scope:
                        continue
                    for section in ["universal"] + CONTEXT_SECTIONS.get(context, []):
                        action = builtins.get(section, {}).get(key)
                        if action:
                            warnings.append(
                                f"custom command {label!r} takes {key} in {context!r}, "
                                f"shadowing the built-in {action}"
                            )

            command_text = command.get("command") or ""
            problem = shell_check(command_text)
            if problem:
                errors.append(f"custom command {label!r}: shell cannot parse the command: {problem}")

            for match in PLACEHOLDER_RE.finditer(command_text):
                obj = match.group("object")
                if obj == "Form":
                    continue
                if obj not in MODELS:
                    errors.append(f"custom command {label!r}: unknown placeholder object {obj!r}")
                    continue
                field = match.group("field").lstrip(".").split(".")[0]
                if field and MODELS[obj] and field not in MODELS[obj]:
                    errors.append(f"custom command {label!r}: {obj} has no field {field!r}")

            errors.extend(check_quoting(command_text, command, label))

            for prompt in command.get("prompts") or []:
                if not prompt.get("key"):
                    errors.append(f"custom command {label!r}: a prompt has no key")
                if prompt.get("type") not in ("input", "menu", "confirm", "menuFromCommand"):
                    errors.append(
                        f"custom command {label!r}: prompt type {prompt.get('type')!r} is not one of "
                        "input | menu | confirm | menuFromCommand"
                    )
                if prompt.get("type") == "menu" and not prompt.get("options"):
                    errors.append(f"custom command {label!r}: menu prompt has no options")

            # Every {{.Form.X}} must come from a prompt, and every prompt should
            # be used: both directions are silent failures at runtime.
            prompt_keys = {p.get("key") for p in command.get("prompts") or []}
            used = set(re.findall(r"\{\{[^}]*?\.Form\.(\w+)", command_text))
            for name in used - prompt_keys:
                errors.append(f"custom command {label!r}: {{{{.Form.{name}}}}} has no matching prompt")
            for name in prompt_keys - used:
                conditions = " ".join(str(p.get("condition") or "") for p in command["prompts"])
                if name and f".Form.{name}" not in conditions:
                    warnings.append(f"custom command {label!r}: prompt {name!r} is never used")

    walk(config.get("customCommands") or [], "")
    errors += check_migrations(config)
    warnings += check_programs(config)
    return errors, warnings



# Placeholders whose value cannot carry shell metacharacters, so interpolating
# them directly is safe. Everything else — file names, branch names, and every
# value a prompt collects — has to go through `quote`.
SAFE_PLACEHOLDERS = {
    "SelectedCommit.Hash",
    "SelectedCommit.Sha",
    "SelectedCommitRange.From",
    "SelectedCommitRange.To",
    "SelectedLocalBranch.CommitHash",
    "CheckedOutBranch.CommitHash",
    "SelectedStashEntry.Index",
}

# `{{ ... }}` with the pipeline captured, so we can ask whether it ends in quote.
EXPRESSION_RE = re.compile(r"\{\{(?P<body>.*?)\}\}", re.DOTALL)
REFERENCE_RE = re.compile(r"\.(?P<path>(Form|Selected\w+|CheckedOutBranch)(?:\.\w+)*)")


def check_quoting(command_text: str, command: dict, label: str) -> list[str]:
    """Every free-text value must reach the shell as an argument, not as source.

    lazygit resolves the template and hands the result to `$SHELL -c`, so a
    value spliced in unquoted is re-parsed as shell: `cost is $5` loses the
    `$5`, a backtick runs a command, and an odd quote aborts the command. The
    only tool lazygit gives you is `quote`, and it has to wrap the whole value
    — inside hand-written quotes it splits the argument instead of protecting
    it, which is worse than leaving it out.
    """
    errors = []
    prompt_types = {
        p.get("key"): p.get("type") for p in (command.get("prompts") or []) if isinstance(p, dict)
    }
    for expression in EXPRESSION_RE.finditer(command_text):
        body = expression.group("body")
        quoted = re.search(r"\|\s*quote\b", body)
        for reference in REFERENCE_RE.finditer(body):
            path = reference.group("path")
            if path in SAFE_PLACEHOLDERS:
                continue
            if path.startswith("Form."):
                name = path.split(".", 1)[1]
                # Menu answers are values this file itself lists, so they are
                # as fixed as the command text around them.
                if prompt_types.get(name) == "menu":
                    continue
            elif path.split(".", 1)[0] not in ("Form",) and "." not in path:
                # A bare model reference (e.g. inside an `if`) is a truth test,
                # not an interpolation.
                continue
            if not quoted:
                errors.append(
                    f"custom command {label!r}: {{{{{body.strip()}}}}} reaches the shell unquoted; "
                    "pipe the whole value through `quote`, or pass it as an argument to `sh -c`"
                )
    return errors

# Keys lazygit renames on load, from computeMigratedConfig in
# pkg/config/app_config.go. These are NOT ignored — lazygit migrates them and
# then writes the migrated file back to disk with os.WriteFile, which follows
# the stow symlink and edits the copy inside this repo. Verified on 0.64.0:
# a config with `git.pagers` came back rewritten to `git.diffRenderers`, with
# every comment intact, through a symlink.
MIGRATED_KEYS = {
    ("gui", "skipUnstageLineWarning"): "gui.skipDiscardChangeWarning",
    ("gui", "windowSize"): "gui.screenMode",
    ("git", "paging"): "git.diffRenderers (a list)",
    ("git", "pagers"): "git.diffRenderers",
    ("git", "allBranchesLogCmd"): "git.allBranchesLogCmds (a list)",
    ("keybinding", "universal", "executeCustomCommand"): "keybinding.universal.executeShellCommand",
    ("keybinding", "universal", "cyclePagers"): "keybinding.universal.cycleDiffRenderers",
    ("keybinding", "universal", "cyclePagersReverse"): "keybinding.universal.cycleDiffRenderersReverse",
    ("keybinding", "files", "openMergeTool"): "keybinding.files.openMergeOptions",
    ("keybinding", "worktrees", "viewWorktreeOptions"): "keybinding.universal.newWorktree",
}

MIGRATION_NOTE = (
    "lazygit migrates this on load and rewrites the config file in place — "
    "through the stow symlink, so it edits the copy in this repo. Write it as {} instead"
)


def check_migrations(config: dict) -> list[str]:
    """Reject anything lazygit would rewrite, rather than let it edit the repo."""
    errors = []

    def get(path):
        node = config
        for part in path:
            if not isinstance(node, dict) or part not in node:
                return None, False
            node = node[part]
        return node, True

    for path, replacement in MIGRATED_KEYS.items():
        _, present = get(path)
        if present:
            errors.append(f"{'.'.join(path)}: " + MIGRATION_NOTE.format(replacement))

    # Shape migrations: same rewrite, triggered by the type rather than the name.
    prefix = (config.get("git") or {}).get("commitPrefix")
    if isinstance(prefix, dict):
        errors.append("git.commitPrefix: " + MIGRATION_NOTE.format("a list of {pattern, replace}"))
    prefixes = (config.get("git") or {}).get("commitPrefixes")
    if isinstance(prefixes, dict) and any(isinstance(v, dict) for v in prefixes.values()):
        errors.append("git.commitPrefixes: " + MIGRATION_NOTE.format("a list per repository"))

    def walk_commands(commands, path):
        for i, command in enumerate(commands):
            if not isinstance(command, dict):
                continue
            here = f"{path}[{i}]"
            for old in ("stream", "showOutput"):
                if old in command:
                    errors.append(f"{here}.{old}: " + MIGRATION_NOTE.format("output: log | popup | terminal"))
            walk_commands(command.get("commandMenu") or [], f"{here}.commandMenu")

    walk_commands(config.get("customCommands") or [], "customCommands")

    for section, bindings in (config.get("keybinding") or {}).items():
        if not isinstance(bindings, dict):
            continue
        for action, value in bindings.items():
            if value is None:
                errors.append(
                    f"keybinding.{section}.{action}: " + MIGRATION_NOTE.format("'<disabled>'")
                )
    return errors


def check_programs(config: dict) -> list[str]:
    """Warn about configured programs that are not installed on this machine.

    Only a warning: the config is shared across machines, and a renderer that
    is missing here may well be present where it is used. The failure is loud
    when it happens (the diff pane says `difft: not found`), but finding out at
    that moment is worse than finding out now.
    """
    import shutil

    warnings = []
    for i, renderer in enumerate(config.get("git", {}).get("diffRenderers") or []):
        command = (renderer.get("command") or "").split()
        if command and not shutil.which(command[0]):
            name = renderer.get("name") or command[0]
            warnings.append(f"diff renderer {name!r} needs {command[0]!r}, which is not installed")
    return warnings


def _claim(claimed, scope, key, context, label, errors) -> None:
    table = claimed.setdefault(scope, {})
    previous = table.get((key, context))
    if previous:
        errors.append(
            f"custom command {label!r}: key {key} in context {context!r} is already bound to {previous!r}"
        )
    table[(key, context)] = label


# ------------------------------------------------------------------ self-test

SELFTEST_YAML = """
# a comment
gui:
  nerdFontsVersion: "3"       # trailing comment
  branchColorPatterns:
    '^(main|master)$': "#7aa2f7"   # a hex colour is not a comment
  theme:
    activeBorderColor: ["#7aa2f7", "bold"]
git:
  diffRenderers:
    - name: delta
      command: 'delta --paging=never'
    - type: rawGit
      args: ["--color-words"]
  diffContextSize: 10
  fetchAll: false
customCommands:
  - key: "X"
    description: "menu"
    commandMenu:
      - key: "b"
        context: "files"
        command: "git blame -- {{.SelectedFile.Name | quote}}"
        prompts:
          - type: "menu"
            key: "Kind"
            options:
              - { value: "one", name: "first", key: "1" }
"""

SELFTEST_EXPECTED = {
    "gui": {
        "nerdFontsVersion": "3",
        "branchColorPatterns": {"^(main|master)$": "#7aa2f7"},
        "theme": {"activeBorderColor": ["#7aa2f7", "bold"]},
    },
    "git": {
        "diffRenderers": [
            {"name": "delta", "command": "delta --paging=never"},
            {"type": "rawGit", "args": ["--color-words"]},
        ],
        "diffContextSize": 10,
        "fetchAll": False,
    },
    "customCommands": [
        {
            "key": "X",
            "description": "menu",
            "commandMenu": [
                {
                    "key": "b",
                    "context": "files",
                    "command": "git blame -- {{.SelectedFile.Name | quote}}",
                    "prompts": [
                        {
                            "type": "menu",
                            "key": "Kind",
                            "options": [{"value": "one", "name": "first", "key": "1"}],
                        }
                    ],
                }
            ],
        }
    ],
}

# Each case is (config, substring that must appear in the reported problems).
SELFTEST_CASES = [
    ({"git": {"pagers": [{"pager": "delta"}]}}, "rewrites the config file in place"),
    ({"gui": {"windowSize": "half"}}, "gui.windowSize"),
    ({"git": {"commitPrefix": {"pattern": "x", "replace": "y"}}}, "git.commitPrefix"),
    ({"keybinding": {"universal": {"undo": None}}}, "'<disabled>'"),
    (
        {"customCommands": [{"key": "a", "context": "files", "command": "true", "stream": True}]},
        "output: log | popup | terminal",
    ),
    ({"scrollOffBehavior": "margin"}, "scrollOffBehavior"),
    ({"gui": {"theme": {"lightTheme": False}}}, "lightTheme"),
    ({"gui": {"showFileIcons": "yes"}}, "showFileIcons"),
    (
        {"customCommands": [{"key": "<ctrl-N>", "context": "files", "command": "true"}]},
        "uppercase letter",
    ),
    ({"customCommands": [{"key": "a", "context": "filez", "command": "true"}]}, "unknown context"),
    (
        {"customCommands": [{"key": "a", "context": "files", "command": "x {{.SelectedLocalCommit.Hash}}"}]},
        "SelectedLocalCommit",
    ),
    (
        {"customCommands": [{"key": "a", "context": "commits", "command": "x {{.SelectedCommit.Sha}}"}]},
        "no field 'Sha'",
    ),
    (
        {"customCommands": [{"key": "a", "context": "files", "command": "echo {{.Form.Nope}}"}]},
        "no matching prompt",
    ),
    (
        {"customCommands": [{"key": "a", "context": "files", "command": "sh -c 'oops"}]},
        "shell cannot parse",
    ),
    (
        {
            "customCommands": [
                {"key": "a", "context": "files", "command": "true"},
                {"key": "a", "context": "files", "command": "false"},
            ]
        },
        "already bound",
    ),
    (
        {"customCommands": [{"key": "a", "context": "files", "commandMenu": [], "command": "true"}]},
        "ignored alongside",
    ),
    ({"customCommands": [{"key": "a", "context": "files"}]}, "has no command"),
    (
        {
            "customCommands": [
                {
                    "key": "a",
                    "context": "files",
                    "command": 'git commit -m "{{.Form.Subject}}"',
                    "prompts": [{"type": "input", "key": "Subject"}],
                }
            ]
        },
        "reaches the shell unquoted",
    ),
    (
        {"customCommands": [{"key": "a", "context": "files", "command": "git add {{.SelectedFile.Name}}"}]},
        "reaches the shell unquoted",
    ),
]


def selftest(schema_path: str | None, defaults_path: str | None) -> int:
    """Prove the checker still catches the mistakes it exists to catch.

    A validator that silently accepts everything looks exactly like a valid
    config, so this runs known-bad inputs through it and fails if any of them
    comes back clean.
    """
    failures = []

    parsed = mini_yaml_load(SELFTEST_YAML)
    if parsed != SELFTEST_EXPECTED:
        failures.append(f"YAML subset parser produced {parsed!r}")

    defaults = None
    if defaults_path:
        defaults, _ = load_yaml(defaults_path)
    schema = None
    if schema_path:
        with open(schema_path, encoding="utf-8") as handle:
            schema = json.load(handle)

    def problems(config: dict) -> list[str]:
        found: list[str] = []
        if schema:
            found += SchemaValidator(schema).validate(config)
        elif defaults:
            found += check_against_defaults(config, defaults)
        errors, _ = check_semantics(config, defaults)
        return found + errors

    for config, expected in SELFTEST_CASES:
        found = problems(config)
        if not any(expected in problem for problem in found):
            failures.append(f"{expected!r} not reported for {config!r}; got {found}")

    for failure in failures:
        print(f"   {failure}", file=sys.stderr)
    if failures:
        print(f"❌ checker self-test: {len(failures)} failure(s)", file=sys.stderr)
        return 1
    print(f"✅ checker self-test ({len(SELFTEST_CASES)} cases)")
    return 0


# --------------------------------------------------------------------- driver


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate a lazygit config file")
    parser.add_argument("--config", help="lazygit config.yml to check")
    parser.add_argument("--schema", help="lazygit's schema/config.json for this version")
    parser.add_argument("--defaults", help="output of `lazygit --config`")
    parser.add_argument(
        "--strict", action="store_true", help="treat warnings (e.g. shadowed built-ins) as failures"
    )
    parser.add_argument(
        "--selftest", action="store_true", help="check the checker against known-bad configs"
    )
    args = parser.parse_args()

    if args.selftest:
        return selftest(args.schema, args.defaults)

    if not args.config:
        print("❌ --config is required", file=sys.stderr)
        return 2

    try:
        config, mismatch = load_yaml(args.config)
    except (YamlError, OSError) as exc:
        print(f"❌ {args.config}: {exc}", file=sys.stderr)
        return 1
    if mismatch:
        print(f"❌ {args.config}: {mismatch}", file=sys.stderr)
        return 1
    if not isinstance(config, dict):
        print(f"❌ {args.config}: the top level is not a mapping", file=sys.stderr)
        return 1

    defaults = None
    if args.defaults:
        try:
            defaults, mismatch = load_yaml(args.defaults)
        except (YamlError, OSError) as exc:
            print(f"❌ {args.defaults}: {exc}", file=sys.stderr)
            return 1
        if mismatch:
            print(f"❌ {args.defaults}: {mismatch}", file=sys.stderr)
            return 1

    errors: list[str] = []
    if args.schema:
        with open(args.schema, encoding="utf-8") as handle:
            schema = json.load(handle)
        errors += SchemaValidator(schema).validate(config)
        mode = "schema"
    elif defaults is not None:
        errors += check_against_defaults(config, defaults)
        mode = "defaults"
    else:
        print("❌ need --schema or --defaults", file=sys.stderr)
        return 2

    # A migrated key is not an unknown key: the schema does not list it, but
    # lazygit acts on it (and rewrites the file). Let check_migrations be the
    # one that explains it, rather than reporting it twice, half wrongly.
    migrated = {".".join(path) for path in MIGRATED_KEYS}
    errors = [
        e
        for e in errors
        if not (e.split(":")[0] in migrated and "unknown key" in e)
    ]

    semantic_errors, warnings = check_semantics(config, defaults)
    errors += semantic_errors

    for warning in warnings:
        print(f"⚠️  {warning}")
    if args.strict and warnings:
        errors += warnings

    if errors:
        print(f"❌ {args.config} ({mode} check) has {len(errors)} problem(s):", file=sys.stderr)
        for error in errors:
            print(f"   {error}", file=sys.stderr)
        return 1

    print(f"✅ {args.config} is valid ({mode} check)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
