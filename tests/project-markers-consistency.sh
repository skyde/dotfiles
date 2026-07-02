#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  printf 'skip - project marker consistency (python3 unavailable)\n'
  exit 0
fi

python3 - "$root" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])


def quoted_items_from_block(text: str, start_pattern: str, end_pattern: str) -> list[str]:
    start = re.search(start_pattern, text)
    if not start:
        raise AssertionError(f"missing block: {start_pattern}")

    end = re.search(end_pattern, text[start.end() :])
    if not end:
        raise AssertionError(f"missing block end: {start_pattern}")

    block = text[start.end() : start.end() + end.start()]
    return re.findall(r'"([^"]+)"', block)


def lua_markers() -> tuple[list[str], list[str]]:
    text = (root / "common/.config/nvim/lua/config/project.lua").read_text(encoding="utf-8")
    return (
        quoted_items_from_block(text, r"M\.markers\s*=\s*\{", r"\n\}"),
        quoted_items_from_block(text, r"M\.fallback_markers\s*=\s*\{", r"\n\}"),
    )


def shell_markers(path: str) -> tuple[list[str], list[str]]:
    text = (root / path).read_text(encoding="utf-8")
    return (
        quoted_items_from_block(text, r"workspace_markers=\(", r"\n\)"),
        quoted_items_from_block(text, r"fallback_workspace_markers=\(", r"\n\)"),
    )


all_lua_markers, lua_fallback = lua_markers()
lua_primary = [marker for marker in all_lua_markers if marker not in lua_fallback]

for path in ("common/.local/bin/tmux-session-name", "common/.local/bin/tmux-status-name.sh"):
    shell_primary, shell_fallback = shell_markers(path)
    assert shell_primary == lua_primary, f"{path} primary markers drifted"
    assert shell_fallback == lua_fallback, f"{path} fallback markers drifted"

assert lua_fallback == [".vscode"], "expected .vscode to be the only fallback marker"
print("project-markers-consistency-ok")
PY
