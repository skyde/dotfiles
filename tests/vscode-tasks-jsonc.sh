#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tasks_files=(
  "$root/common/.config/Code/User/tasks.json"
  "$root/mac/Library/Application Support/Code/User/tasks.json"
)
settings_file="$root/common/.config/Code/User/settings.json"
keybindings_file="$root/common/.config/Code/User/keybindings.json"

python3 - "$settings_file" "$keybindings_file" "${tasks_files[@]}" <<'PY'
import json
import sys
from pathlib import Path


def strip_jsonc(source: str) -> str:
    out = []
    i = 0
    in_string = False
    quote = ""
    escape = False

    while i < len(source):
        ch = source[i]
        nxt = source[i + 1] if i + 1 < len(source) else ""

        if in_string:
            out.append(ch)
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == quote:
                in_string = False
            i += 1
            continue

        if ch in ('"', "'"):
            in_string = True
            quote = ch
            out.append(ch)
            i += 1
            continue

        if ch == "/" and nxt == "/":
            out.extend((" ", " "))
            i += 2
            while i < len(source) and source[i] not in "\r\n":
                out.append(" ")
                i += 1
            continue

        if ch == "/" and nxt == "*":
            out.extend((" ", " "))
            i += 2
            while i < len(source):
                if source[i] == "*" and i + 1 < len(source) and source[i + 1] == "/":
                    out.extend((" ", " "))
                    i += 2
                    break
                out.append("\n" if source[i] in "\r\n" else " ")
                i += 1
            continue

        out.append(ch)
        i += 1

    return "".join(out)


def strip_trailing_commas(source: str) -> str:
    out = []
    i = 0
    in_string = False
    quote = ""
    escape = False

    while i < len(source):
        ch = source[i]

        if in_string:
            out.append(ch)
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == quote:
                in_string = False
            i += 1
            continue

        if ch in ('"', "'"):
            in_string = True
            quote = ch
            out.append(ch)
            i += 1
            continue

        if ch == ",":
            j = i + 1
            while j < len(source) and source[j].isspace():
                j += 1
            if j < len(source) and source[j] in "}]":
                i += 1
                continue

        out.append(ch)
        i += 1

    return "".join(out)


def load_jsonc(path: str):
    text = Path(path).read_text(encoding="utf-8")
    return json.loads(strip_trailing_commas(strip_jsonc(text)))


def has_mapping(mappings, before, command, args=None):
    for mapping in mappings:
        if mapping.get("before") != before:
            continue
        commands = mapping.get("commands", [])
        for item in commands:
            if item == command and args is None:
                return True
            if not isinstance(item, dict) or item.get("command") != command:
                continue
            if args is None or item.get("args") == args:
                return True
    return False


def mappings_for(mappings, before):
    return [mapping for mapping in mappings if mapping.get("before") == before]


def command_sequence(mappings, before):
    matches = mappings_for(mappings, before)
    assert len(matches) == 1, f"expected one mapping for {before!r}, got {len(matches)}"
    commands = []
    for item in matches[0].get("commands", []):
        commands.append(item.get("command") if isinstance(item, dict) else item)
    return commands


settings_file = sys.argv[1]
keybindings_file = sys.argv[2]
task_files = sys.argv[3:]

settings = load_jsonc(settings_file)
keybindings = load_jsonc(keybindings_file)
normal_mappings = settings["vim.normalModeKeyBindingsNonRecursive"]
settings_text = Path(settings_file).read_text(encoding="utf-8")

assert settings.get("terminal.integrated.cwd") == "${fileDirname}", settings_file
assert settings.get("terminal.integrated.copyOnSelection") is False, (
    f"{settings_file}: terminal selection must not overwrite the clipboard before tmux/Neovim copy helpers run"
)
assert settings.get("terminal.integrated.commandsToSkipShell") == ["-workbench.action.files.save"], (
    f"{settings_file}: keep VS Code terminal defaults while forwarding Cmd/Ctrl+S to terminal Neovim"
)

assert has_mapping(normal_mappings, ["<leader>", "f", "t"], "workbench.action.tasks.runTask", "StandardTerminal"), settings_file
assert has_mapping(normal_mappings, ["<leader>", "a"], "workbench.action.tasks.runTask", "Tmux: Switch to AI"), settings_file
assert has_mapping(normal_mappings, ["<leader>", "i"], "workbench.action.tasks.runTask", "Tmux: Switch to Terminal"), settings_file
assert has_mapping(normal_mappings, ["<leader>", "w", "r"], "workbench.action.tasks.runTask", "Tmux: Switch to Resume"), settings_file
assert has_mapping(normal_mappings, ["<leader>", "w", "a"], "workbench.action.tasks.runTask", "Tmux: Switch to AI"), settings_file
assert has_mapping(normal_mappings, ["<leader>", "w", "t"], "workbench.action.tasks.runTask", "Tmux: Switch to Terminal"), settings_file
assert has_mapping(normal_mappings, ["<leader>", "f", "T"], "workbench.action.tasks.runTask", "Tmux: Kill Sessions"), settings_file
assert has_mapping(normal_mappings, ["<leader>", "f", "l"], "workbench.action.files.copyPathOfActiveFile"), settings_file
assert has_mapping(normal_mappings, ["<leader>", "b", "u"], "workbench.action.unpinEditor"), settings_file
assert has_mapping(normal_mappings, ["<leader>", "b", "p"], "workbench.action.pinEditor"), settings_file
assert "TODO: Ideally <leader>bp is a toggle" not in settings_text, settings_file
for mapping in mappings_for(normal_mappings, ["<leader>", "b", "u"]) + mappings_for(normal_mappings, ["<leader>", "b", "p"]):
    assert "when" not in mapping, f"{settings_file}: VSCodeVim remaps do not evaluate VS Code when clauses"
assert "TODO: Make sure the debug hover is working here" not in settings_text, settings_file
assert '"Backspace"' not in settings_text, f"{settings_file}: VSCodeVim spells Backspace as <BS>"
assert command_sequence(normal_mappings, ["<leader>", "<BS>"]) == [
    "editor.action.showHover",
], settings_file
assert command_sequence(normal_mappings, ["<leader>", "d", "<BS>"]) == [
    "editor.debug.action.showDebugHover",
], settings_file
assert command_sequence(normal_mappings, ["<BS>", "<leader>"]) == [
    "editor.action.triggerParameterHints",
], settings_file
assert command_sequence(normal_mappings, ["<BS>", "<BS>"]) == [
    "editor.action.showHover",
], settings_file

assert any(
    binding.get("key") == "cmd+s"
    and binding.get("command") == "workbench.action.terminal.sendSequence"
    and binding.get("when") == "terminalFocus"
    and binding.get("args", {}).get("text") == "\u001B[15;2~"
    for binding in keybindings
), keybindings_file

terminal_sequences = {
    "shift+f1": "\u001B[1;2P",
    "shift+f2": "\u001B[1;2Q",
    "shift+f3": "\u001B[1;2R",
    "shift+f4": "\u001B[1;2S",
    "shift+f5": "\u001B[15;2~",
    "shift+f6": "\u001B[17;2~",
    "shift+f7": "\u001B[18;2~",
    "shift+f8": "\u001B[19;2~",
    "shift+f9": "\u001B[20;2~",
    "shift+f10": "\u001B[21;2~",
    "shift+f11": "\u001B[23;2~",
    "shift+f12": "\u001B[24;2~",
}
for key, sequence in terminal_sequences.items():
    assert any(
        binding.get("key") == key
        and binding.get("command") == "workbench.action.terminal.sendSequence"
        and binding.get("when") == "terminalFocus"
        and binding.get("args", {}).get("text") == sequence
        for binding in keybindings
    ), f"{keybindings_file}: {key} must send {sequence.encode()!r} to terminal Neovim/tmux"

for key, command in (
    ("ctrl+o", "workbench.action.navigateBack"),
    ("ctrl+i", "workbench.action.navigateForward"),
):
    matches = [
        binding
        for binding in keybindings
        if binding.get("key") == key and binding.get("command") == command
    ]
    assert matches, f"{keybindings_file}: missing {key} {command}"
    assert all("!terminalFocus" in binding.get("when", "") for binding in matches), (
        f"{keybindings_file}: {key} must not intercept terminal Neovim/tmux"
    )

for key, command in (
    ("shift+f2", "workbench.action.debug.start"),
    ("shift+f3", "workbench.action.quickOpen"),
    ("shift+f7", "runCommands"),
):
    matches = [
        binding
        for binding in keybindings
        if binding.get("key") == key and binding.get("command") == command
    ]
    assert matches, f"{keybindings_file}: missing {key} {command}"
    assert all("!terminalFocus" in binding.get("when", "") for binding in matches), (
        f"{keybindings_file}: {key} must pass through to terminal Neovim/tmux"
    )

for task_file in task_files:
    data = load_jsonc(task_file)
    tasks = {task["label"]: task for task in data["tasks"]}

    for label in ("StandardTerminal", "Tmux: Switch to AI", "Tmux: Switch to Resume", "Tmux: Switch to Terminal"):
        env = tasks[label].get("options", {}).get("env", {})
        assert env.get("TMUX_SESSION_START_DIR") == "${workspaceFolder}", f"{task_file}: {label}"

    installed_runner = "$HOME/.local/bin/dotfiles-run"
    repo_runner = "$HOME/dotfiles/common/.local/bin/dotfiles-run"
    direct_tmux_session = "$HOME/dotfiles/common/.local/bin/tmux-session"
    tmux_session_name = "$HOME/dotfiles/common/.local/bin/tmux-session-name"
    for label in ("StandardTerminal", "Tmux: Switch to AI", "Tmux: Switch to Resume", "Tmux: Switch to Terminal"):
        command = " ".join(tasks[label].get("args", []))
        assert installed_runner in command, f"{task_file}: {label}"
        assert repo_runner in command, f"{task_file}: {label}"
        assert "dotfiles-run unavailable" in command, f"{task_file}: {label}"
        assert direct_tmux_session not in command, f"{task_file}: {label}"
        assert tmux_session_name not in command, f"{task_file}: {label}"
        assert "sess=$(" not in command, f"{task_file}: {label}"
        assert "tmux-session" in command, f"{task_file}: {label}"
        assert "--start-dir" not in command, f"{task_file}: {label}"
        assert "${workspaceFolder}" not in command, f"{task_file}: {label}"
        assert 'basename "${workspaceFolder}"' not in command, f"{task_file}: {label}"
        assert "tr -c '[:alnum:]_-'" not in command, f"{task_file}: {label}"
        assert "sess=${sess:-workspace}" not in command, f"{task_file}: {label}"
        assert "echo '${workspaceFolder}' | tr '/.' '_'" not in command, f"{task_file}: {label}"
        assert "|| true" not in command, f"{task_file}: {label}"

    standard_command = " ".join(tasks["StandardTerminal"].get("args", []))
    assert " --window " not in standard_command, task_file

    ai_command = " ".join(tasks["Tmux: Switch to AI"].get("args", []))
    assert " --window agent --no-attach" in ai_command, task_file
    assert " --window 2" not in ai_command, task_file
    assert " --no-attach" in ai_command, task_file

    resume_command = " ".join(tasks["Tmux: Switch to Resume"].get("args", []))
    assert " --window resume --no-attach" in resume_command, task_file
    assert " --window 1" not in resume_command, task_file
    assert " --no-attach" in resume_command, task_file

    terminal_command = " ".join(tasks["Tmux: Switch to Terminal"].get("args", []))
    assert " --window terminal --no-attach" in terminal_command, task_file
    assert " --no-attach" in terminal_command, task_file

    kill_command = " ".join(tasks["Tmux: Kill Sessions"].get("args", []))
    assert installed_runner in kill_command, task_file
    assert repo_runner in kill_command, task_file
    assert "kill-tmux" in kill_command, task_file
    assert "$HOME/dotfiles/common/.local/bin/kill-tmux" not in kill_command, task_file

    assert tasks["Zoekt Search"].get("command") == "st-zoekt", task_file
    assert tasks["Zoekt Search"].get("args") == ["--code"], task_file
    assert tasks["Zoekt Index"].get("command") == "si", task_file
    assert tasks["Zoekt Index"].get("args") == ["${workspaceFolder}"], task_file

print("vscode-jsonc-ok")
PY
