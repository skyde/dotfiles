#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  printf 'skip - tmux passthrough consistency (python3 unavailable)\n'
  exit 0
fi

python3 - "$root" <<'PY'
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1])
helper = root / "common/.local/bin/tmux-pane-should-passthrough"


def shell_commands() -> list[str]:
    text = (root / "common/.local/bin/tmux-pane-should-passthrough").read_text(encoding="utf-8")
    match = re.search(r"passthrough_pattern='\^\(([^']+)\)\$'", text)
    if not match:
        raise AssertionError("missing shell passthrough_pattern")

    return [item.replace(r"\.", ".") for item in match.group(1).split("|")]


def shell_wrapper_commands() -> list[str]:
    text = (root / "common/.local/bin/tmux-pane-should-passthrough").read_text(encoding="utf-8")
    match = re.search(r"is_wrapper_command\(\).*?case \"\$1\" in\n(.*?)\n\s+\*", text, re.S)
    if not match:
        raise AssertionError("missing shell wrapper commands")

    labels = match.group(1).split(")", 1)[0]
    return re.findall(r"\b[A-Za-z][A-Za-z0-9_-]*\b", labels)


def shell_case_commands(function: str) -> list[str]:
    text = (root / "common/.local/bin/tmux-pane-should-passthrough").read_text(encoding="utf-8")
    match = re.search(rf"{re.escape(function)}\(\).*?case \"\$1\" in\n(.*?)\n\s+\*", text, re.S)
    if not match:
        raise AssertionError(f"missing shell {function} commands")

    labels = match.group(1).split(")", 1)[0]
    return re.findall(r"\b[A-Za-z][A-Za-z0-9_-]*\b", labels)


def shell_command_option_families() -> dict[str, set[str]]:
    text = (root / "common/.local/bin/tmux-pane-should-passthrough").read_text(encoding="utf-8")
    match = re.search(r"command_option_takes_value\(\).*?case \"\$family:\$key\" in\n(.*?)\n\s+\*", text, re.S)
    if not match:
        raise AssertionError("missing shell command option families")

    families: dict[str, set[str]] = {}
    for family, option in re.findall(r"([A-Za-z0-9_-]+):(--?[A-Za-z][A-Za-z0-9_-]*)", match.group(1)):
        families.setdefault(family, set()).add(option)

    return families


def shell_command_key_option_families(function: str) -> dict[str, set[str]]:
    text = (root / "common/.local/bin/tmux-pane-should-passthrough").read_text(encoding="utf-8")
    match = re.search(rf"{re.escape(function)}\(\).*?case \"\$command:\$key\" in\n(.*?)\n\s+\*", text, re.S)
    if not match:
        raise AssertionError(f"missing shell {function} families")

    families: dict[str, set[str]] = {}
    for family, option in re.findall(r"([A-Za-z0-9_-]+):((?:--?[A-Za-z][A-Za-z0-9_-]*)|(?:-\\\?))", match.group(1)):
        families.setdefault(family, set()).add(option.replace(r"\?", "?"))

    return families


def shell_wrapper_option_families() -> dict[str, set[str]]:
    text = (root / "common/.local/bin/tmux-pane-should-passthrough").read_text(encoding="utf-8")
    match = re.search(r"skip_wrapper_options\(\).*?case \"\$command:\$key\" in\n(.*?)\n\s+esac", text, re.S)
    if not match:
        raise AssertionError("missing shell wrapper option families")

    families: dict[str, set[str]] = {}
    for family, option in re.findall(r"([A-Za-z0-9_-]+):(--?[A-Za-z][A-Za-z0-9_-]*)", match.group(1)):
        families.setdefault(family, set()).add(option)

    return families


def shell_container_global_option_families() -> dict[str, set[str]]:
    text = (root / "common/.local/bin/tmux-pane-should-passthrough").read_text(encoding="utf-8")
    match = re.search(r"container_global_option_takes_value\(\).*?case \"\$command:\$key\" in\n(.*?)\n\s+\*", text, re.S)
    if not match:
        raise AssertionError("missing shell container global option families")

    families: dict[str, set[str]] = {}
    for family, option in re.findall(r"([A-Za-z0-9_-]+):(--?[A-Za-z][A-Za-z0-9_-]*)", match.group(1)):
        families.setdefault(family, set()).add(option)

    return families


def shell_kubernetes_exec_options() -> set[str]:
    text = (root / "common/.local/bin/tmux-pane-should-passthrough").read_text(encoding="utf-8")
    match = re.search(r"kubernetes_exec_option_takes_value\(\).*?case \"\$1\" in\n(.*?)\n\s+\*", text, re.S)
    if not match:
        raise AssertionError("missing shell kubernetes exec options")

    return set(re.findall(r"--?[A-Za-z][A-Za-z0-9_-]*", match.group(1)))


def shell_simple_options(function: str) -> set[str]:
    text = (root / "common/.local/bin/tmux-pane-should-passthrough").read_text(encoding="utf-8")
    match = re.search(rf"{re.escape(function)}\(\).*?case \"\$1\" in\n(.*?)\n\s+\*", text, re.S)
    if not match:
        raise AssertionError(f"missing shell {function} options")

    return set(re.findall(r"--?[A-Za-z][A-Za-z0-9_-]*", match.group(1)))


def lua_commands() -> list[str]:
    text = (root / "common/.config/nvim/lua/plugins/tmux-navigator.lua").read_text(encoding="utf-8")
    match = re.search(r"local passthrough_commands\s*=\s*\{(.*?)\n\}", text, re.S)
    if not match:
        raise AssertionError("missing Lua passthrough_commands table")

    block = match.group(1)
    quoted = re.findall(r'\["([^"]+)"\]\s*=\s*true', block)
    bare = re.findall(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*true", block, re.M)
    return quoted + bare


def lua_boolean_table(table: str) -> set[str]:
    text = (root / "common/.config/nvim/lua/plugins/tmux-navigator.lua").read_text(encoding="utf-8")
    match = re.search(rf"local {re.escape(table)}\s*=\s*\{{(.*?)\n\}}", text, re.S)
    if not match:
        raise AssertionError(f"missing Lua {table} table")

    block = match.group(1)
    quoted = re.findall(r'\["([^"]+)"\]\s*=\s*true', block)
    bare = re.findall(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*true", block, re.M)
    return set(quoted + bare)


def lua_nested_boolean_families(table: str) -> dict[str, set[str]]:
    text = (root / "common/.config/nvim/lua/plugins/tmux-navigator.lua").read_text(encoding="utf-8")
    match = re.search(rf"local {re.escape(table)}\s*=\s*\{{(.*?)\n\}}\n\nlocal ", text, re.S)
    if not match:
        raise AssertionError(f"missing Lua {table} table")

    families: dict[str, set[str]] = {}
    for quoted_family, bare_family, block in re.findall(
        r"^\s{2}(?:\[\"([^\"]+)\"\]|([A-Za-z0-9_-]+))\s*=\s*\{\n(.*?)^\s{2}\},",
        match.group(1),
        re.M | re.S,
    ):
        family_name = quoted_family or bare_family
        families[family_name] = set(re.findall(r'\["([^"]+)"\]\s*=\s*true', block))

    return families


def lua_option_family(table: str) -> set[str]:
    return lua_boolean_table(table)


def lua_wrapper_option_families() -> dict[str, set[str]]:
    return lua_nested_boolean_families("wrapper_options_with_value")


def lua_container_global_option_families() -> dict[str, set[str]]:
    text = (root / "common/.config/nvim/lua/plugins/tmux-navigator.lua").read_text(encoding="utf-8")
    match = re.search(
        r"local container_global_options_with_value\s*=\s*\{(.*?)\n\}\n\nlocal container_global_stop_options",
        text,
        re.S,
    )
    if not match:
        raise AssertionError("missing Lua container global option families")

    families: dict[str, set[str]] = {}
    for family, block in re.findall(r"^\s{2}([A-Za-z0-9_-]+)\s*=\s*\{\n(.*?)^\s{2}\},", match.group(1), re.M | re.S):
        families[family] = set(re.findall(r'\["([^"]+)"\]\s*=\s*true', block))

    return families


shell_set = set(shell_commands())
lua_set = set(lua_commands())

missing_from_lua = sorted(shell_set - lua_set)
missing_from_shell = sorted(lua_set - shell_set)

if missing_from_lua or missing_from_shell:
    raise AssertionError(
        "passthrough command drift: "
        f"missing from Lua={missing_from_lua}, missing from shell={missing_from_shell}"
    )

shell_wrapper_set = set(shell_wrapper_commands())
lua_wrapper_set = lua_boolean_table("wrapper_commands")

missing_wrappers_from_lua = sorted(shell_wrapper_set - lua_wrapper_set)
missing_wrappers_from_shell = sorted(lua_wrapper_set - shell_wrapper_set)

if missing_wrappers_from_lua or missing_wrappers_from_shell:
    raise AssertionError(
        "wrapper command drift: "
        f"missing from Lua={missing_wrappers_from_lua}, missing from shell={missing_wrappers_from_shell}"
    )

special_command_tables = {
    "database shell command": ("is_database_shell_command", "database_shell_commands"),
    "language REPL command": ("is_language_repl_command", "language_repl_commands"),
}

for label, (shell_function, lua_table) in special_command_tables.items():
    shell_special_set = set(shell_case_commands(shell_function))
    lua_special_set = lua_boolean_table(lua_table)
    missing_special_from_lua = sorted(shell_special_set - lua_special_set)
    missing_special_from_shell = sorted(lua_special_set - shell_special_set)
    if missing_special_from_lua or missing_special_from_shell:
        raise AssertionError(
            f"{label} drift: "
            f"missing from Lua={missing_special_from_lua}, missing from shell={missing_special_from_shell}"
        )

option_family_tables = {
    "bunx": "package_executable_options_with_value",
    "hatch-env-run": "hatch_env_run_options_with_value",
    "hatch-global": "hatch_global_options_with_value",
    "npm-exec": "npm_exec_options_with_value",
    "pipenv-global": "pipenv_global_options_with_value",
    "pipx-run": "pipx_run_options_with_value",
    "pixi-global": "pixi_global_options_with_value",
    "pixi-run": "pixi_run_options_with_value",
    "poetry-global": "poetry_global_options_with_value",
    "pnpm-dlx": "pnpm_dlx_options_with_value",
    "pnpm-exec": "pnpm_exec_options_with_value",
    "pnpm-global": "pnpm_global_options_with_value",
    "uv-global": "uv_global_options_with_value",
    "uv-run": "uv_run_options_with_value",
    "uv-tool-run": "uv_tool_run_options_with_value",
    "yarn-dlx": "package_executable_options_with_value",
}

shell_option_families = shell_command_option_families()
for shell_family, lua_table in option_family_tables.items():
    shell_options = shell_option_families.get(shell_family, set())
    lua_options = lua_option_family(lua_table)
    missing_options_from_lua = sorted(shell_options - lua_options)
    missing_options_from_shell = sorted(lua_options - shell_options)
    if missing_options_from_lua or missing_options_from_shell:
        raise AssertionError(
            f"option family drift for {shell_family}/{lua_table}: "
            f"missing from Lua={missing_options_from_lua}, missing from shell={missing_options_from_shell}"
        )

special_option_family_tables = {
    "database option": ("database_option_takes_value", "database_options_with_value"),
    "database one-shot option": ("database_one_shot_option", "database_one_shot_options"),
    "language REPL option": ("language_repl_option_takes_value", "language_repl_options_with_value"),
    "language REPL one-shot option": ("language_repl_one_shot_option", "language_repl_one_shot_options"),
}

for label, (shell_function, lua_table) in special_option_family_tables.items():
    shell_options = shell_command_key_option_families(shell_function)
    lua_options = lua_nested_boolean_families(lua_table)
    missing_families_from_lua = sorted(set(shell_options) - set(lua_options))
    missing_families_from_shell = sorted(set(lua_options) - set(shell_options))

    if missing_families_from_lua or missing_families_from_shell:
        raise AssertionError(
            f"{label} family drift: "
            f"missing from Lua={missing_families_from_lua}, missing from shell={missing_families_from_shell}"
        )

    for family in sorted(shell_options):
        missing_options_from_lua = sorted(shell_options[family] - lua_options[family])
        missing_options_from_shell = sorted(lua_options[family] - shell_options[family])
        if missing_options_from_lua or missing_options_from_shell:
            raise AssertionError(
                f"{label} drift for {family}: "
                f"missing from Lua={missing_options_from_lua}, missing from shell={missing_options_from_shell}"
            )

shell_wrapper_options = shell_wrapper_option_families()
lua_wrapper_options = lua_wrapper_option_families()
missing_wrapper_families_from_lua = sorted(set(shell_wrapper_options) - set(lua_wrapper_options))
missing_wrapper_families_from_shell = sorted(set(lua_wrapper_options) - set(shell_wrapper_options))

if missing_wrapper_families_from_lua or missing_wrapper_families_from_shell:
    raise AssertionError(
        "wrapper option family drift: "
        f"missing from Lua={missing_wrapper_families_from_lua}, "
        f"missing from shell={missing_wrapper_families_from_shell}"
    )

for family in sorted(shell_wrapper_options):
    shell_options = shell_wrapper_options[family]
    lua_options = lua_wrapper_options[family]
    missing_options_from_lua = sorted(shell_options - lua_options)
    missing_options_from_shell = sorted(lua_options - shell_options)
    if missing_options_from_lua or missing_options_from_shell:
        raise AssertionError(
            f"wrapper option drift for {family}: "
            f"missing from Lua={missing_options_from_lua}, missing from shell={missing_options_from_shell}"
        )

shell_container_global_options = shell_container_global_option_families()
lua_container_global_options = lua_container_global_option_families()
missing_container_families_from_lua = sorted(set(shell_container_global_options) - set(lua_container_global_options))
missing_container_families_from_shell = sorted(set(lua_container_global_options) - set(shell_container_global_options))

if missing_container_families_from_lua or missing_container_families_from_shell:
    raise AssertionError(
        "container global option family drift: "
        f"missing from Lua={missing_container_families_from_lua}, "
        f"missing from shell={missing_container_families_from_shell}"
    )

for family in sorted(shell_container_global_options):
    shell_options = shell_container_global_options[family]
    lua_options = lua_container_global_options[family]
    missing_options_from_lua = sorted(shell_options - lua_options)
    missing_options_from_shell = sorted(lua_options - shell_options)
    if missing_options_from_lua or missing_options_from_shell:
        raise AssertionError(
            f"container global option drift for {family}: "
            f"missing from Lua={missing_options_from_lua}, missing from shell={missing_options_from_shell}"
        )

shell_kubernetes_options = shell_kubernetes_exec_options()
lua_kubernetes_options = lua_option_family("kubernetes_exec_options_with_value")
missing_kubernetes_options_from_lua = sorted(shell_kubernetes_options - lua_kubernetes_options)
missing_kubernetes_options_from_shell = sorted(lua_kubernetes_options - shell_kubernetes_options)

if missing_kubernetes_options_from_lua or missing_kubernetes_options_from_shell:
    raise AssertionError(
        "kubernetes exec option drift: "
        f"missing from Lua={missing_kubernetes_options_from_lua}, "
        f"missing from shell={missing_kubernetes_options_from_shell}"
    )

simple_option_tables = {
    "deno options with value": ("deno_option_takes_value", "deno_options_with_value"),
    "deno one-shot options": ("deno_one_shot_option", "deno_one_shot_options"),
    "php options with value": ("php_option_takes_value", "php_options_with_value"),
    "rails options with value": ("rails_option_takes_value", "rails_options_with_value"),
    "rails one-shot options": ("rails_one_shot_option", "rails_one_shot_options"),
    "ruby options with value": ("ruby_option_takes_value", "ruby_options_with_value"),
    "ruby one-shot options": ("ruby_one_shot_option", "ruby_one_shot_options"),
}

for label, (shell_function, lua_table) in simple_option_tables.items():
    shell_options = shell_simple_options(shell_function)
    lua_options = lua_option_family(lua_table)
    missing_options_from_lua = sorted(shell_options - lua_options)
    missing_options_from_shell = sorted(lua_options - shell_options)
    if missing_options_from_lua or missing_options_from_shell:
        raise AssertionError(
            f"{label} drift: "
            f"missing from Lua={missing_options_from_lua}, missing from shell={missing_options_from_shell}"
        )

behavior_cases = [
    ("windows ssh path", r"C:\tools\ssh.exe devbox"),
    ("delta pager", "delta README.md"),
    ("windows unc ssh path", r"\\server\share\ssh.exe devbox"),
    ("windows slash unc ssh path", "//server/share/ssh.exe devbox"),
    ("windows ssh tunnel", r"C:\tools\ssh.exe -N -L 8080:localhost:80 devbox"),
    ("windows slash unc ssh tunnel", "//server/share/ssh.exe -N -L 8080:localhost:80 devbox"),
    ("windows nvim path", r"C:\tools\nvim.exe README.md"),
    ("windows unc uppercase nvim path", r"\\server\share\NVIM.EXE README.md"),
    ("windows slash unc uppercase nvim path", "//server/share/NVIM.EXE README.md"),
    ("ssh proxy equals", "ssh -oProxyCommand=ssh jump devbox"),
    ("ssh forced tty compact", "ssh -tt devbox nvim README.md"),
    ("ssh no tty then forced tty compact", "ssh -Tt devbox nvim README.md"),
    ("ssh forced tty then no tty compact", "ssh -tT devbox nvim README.md"),
    ("ssh RequestTTY auto remote shell", "ssh -oRequestTTY=auto devbox"),
    ("ssh RequestTTY no remote shell", "ssh -oRequestTTY=no devbox"),
    ("ssh remote one shot", "ssh devbox echo nvim"),
    ("ssh RequestTTY remote nvim", "ssh -oRequestTTY=yes devbox nvim README.md"),
    ("ssh RemoteCommand nvim without tty", "ssh -oRemoteCommand='nvim README.md' devbox"),
    ("ssh RequestTTY RemoteCommand nvim", "ssh -oRequestTTY=yes -oRemoteCommand='nvim README.md' devbox"),
    ("ssh forced tty RemoteCommand nvim", "ssh -tt -o RemoteCommand='nvim README.md' devbox"),
    ("ssh forced tty RemoteCommand one shot", "ssh -t -oRemoteCommand='echo nvim' devbox"),
    ("ssh RemoteCommand none remote shell", "ssh -oRemoteCommand=none devbox"),
    ("ssh RequestTTY remote one shot", "ssh -oRequestTTY=yes devbox echo nvim"),
    ("ssh RequestTTY auto remote nvim", "ssh -oRequestTTY=auto devbox nvim README.md"),
    ("ssh no pty compact", "ssh -tN devbox"),
    ("python repl module", "/usr/bin/python3 -m IPython"),
    ("python compact interactive command", "python3 -ic 'print(1)'"),
    ("python compact command", "python3 -cprint(1)"),
    ("python noninteractive module", "/usr/bin/python3 -m http.server"),
    ("node inspector", "/usr/local/bin/node inspect app.js"),
    ("node compact print", "node -pprocess.version"),
    ("node test runner", "/usr/local/bin/node --test"),
    ("pwsh command ssh", "pwsh -NoProfile -Command 'ssh devbox'"),
    ("pwsh single dash config", "pwsh -configurationName ssh"),
    ("pwsh single dash no command", "pwsh -NoProfile -configurationName default"),
    ("setup shell ssh", "/bin/bash -lc 'cd /tmp && ssh devbox'"),
    ("shell echoed ssh", "/bin/bash -lc 'echo ssh devbox'"),
    ("env assignment ssh", "FOO=bar ssh devbox"),
    ("env split ssh", "env -S 'FOO=bar ssh devbox'"),
    ("env split echoed ssh", "env -S 'echo ssh devbox'"),
    ("windows cmd ssh", r"C:\Windows\System32\cmd.exe /c ssh devbox"),
    ("windows cmd nvim", r'C:\Windows\System32\cmd.exe /s /c "nvim README.md"'),
    ("windows cmd echoed ssh", r'C:\Windows\System32\cmd.exe /k "echo ssh devbox"'),
    ("windows cmd shell", r"C:\Windows\System32\cmd.exe"),
    ("arch nvim", "arch -x86_64 nvim README.md"),
    ("arch ssh", "arch -arm64 ssh devbox"),
    ("arch echoed nvim", "arch -x86_64 echo nvim README.md"),
    ("sudo compact ut ssh", "sudo -ut ssh devbox"),
    ("sudo compact ug ssh", "sudo -ug ssh devbox"),
    ("sudo compact uT ssh", "sudo -uT ssh devbox"),
    ("sudo compact iu ssh", "sudo -iu root ssh devbox"),
    ("sudo compact in echo", "sudo -in echo ssh devbox"),
    ("sshpass ssh", "sshpass -p secret ssh devbox"),
    ("sshpass tunnel", "sshpass -p secret ssh -N -L 8080:localhost:80 devbox"),
    ("uv run compact python ssh", "uv run -p3.12 ssh devbox"),
    ("uvx compact python ssh", "uvx -p3.12 ssh devbox"),
    ("npm call ssh", "npm exec -c 'ssh devbox'"),
    ("npm call echoed ssh", "npm exec -c 'echo ssh devbox'"),
    ("pnpm shell ssh", "pnpm exec -c 'ssh devbox'"),
    ("pnpm shell echoed ssh", "pnpm exec -c 'echo ssh devbox'"),
    ("docker compose entrypoint nvim", "docker compose run --entrypoint=nvim app README.md"),
    ("docker compose entrypoint echo", "docker compose run --entrypoint echo app ssh devbox"),
    ("kubectl attach stdin", "kubectl attach -it pod/app -c api"),
    ("kubectl attach compact no stdin", "kubectl attach -t pod/app -c api"),
    ("kubectl attach no stdin", "kubectl attach --stdin=false pod/app -c api"),
    ("script wrapped nvim", "script -q /tmp/typescript nvim README.md"),
    ("script command string echo", "script -q -c 'echo ssh devbox' /tmp/typescript"),
]


def shell_behavior_results() -> dict[str, bool]:
    env = os.environ.copy()
    env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"

    results = {}
    for label, commandline in behavior_cases:
        result = subprocess.run(
            [str(helper), commandline, ""],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if result.returncode not in (0, 1):
            raise AssertionError(
                f"shell helper failed for {label}: exit={result.returncode} "
                f"stdout={result.stdout!r} stderr={result.stderr!r}"
            )
        results[label] = result.returncode == 0

    return results


def lua_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def nvim_behavior_results():
    nvim = shutil.which("nvim")
    if not nvim:
        return None

    with tempfile.TemporaryDirectory(prefix="tmux-passthrough-consistency.") as tempdir:
        script_path = Path(tempdir) / "check.lua"
        output_path = Path(tempdir) / "results.tsv"
        case_rows = "\n".join(
            f"  {{ label = {lua_quote(label)}, command = {lua_quote(commandline)} }},"
            for label, commandline in behavior_cases
        )

        script_path.write_text(
            f"""
local root = {lua_quote(str(root))}
local output_path = {lua_quote(str(output_path))}
local spec = dofile(root .. "/common/.config/nvim/lua/plugins/tmux-navigator.lua")
local terminal_left

for _, key in ipairs(spec[1].keys) do
  if key[1] == "<C-h>" and key.mode == "t" then
    terminal_left = key[2]
  end
end

assert(type(terminal_left) == "function", "missing terminal tmux left mapping")

local cases = {{
{case_rows}
}}
local lines = {{}}

for index, case in ipairs(cases) do
  vim.cmd("enew!")
  vim.api.nvim_buf_set_name(0, "term://~/repo//" .. tostring(1000 + index) .. ":" .. case.command)
  vim.bo.filetype = ""
  table.insert(lines, (terminal_left() == "<C-h>" and "1" or "0") .. "\\t" .. case.label)
  vim.cmd("bwipeout!")
end

local write_result = vim.fn.writefile(lines, output_path)
assert(write_result == 0, "writefile failed " .. tostring(write_result))
""",
            encoding="utf-8",
        )

        result = subprocess.run(
            [nvim, "--headless", "-u", "NONE", "-i", "NONE", "-n", "--noplugin", "-S", str(script_path), "+qa"],
            cwd=root,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            raise AssertionError(
                f"nvim behavior check failed: exit={result.returncode} "
                f"stdout={result.stdout!r} stderr={result.stderr!r}"
            )
        if not output_path.exists():
            raise AssertionError(
                "nvim behavior check did not produce results.tsv: "
                f"stdout={result.stdout!r} stderr={result.stderr!r}"
            )

        results = {}
        for line in output_path.read_text(encoding="utf-8").splitlines():
            value, label = line.split("\t", 1)
            results[label] = value == "1"

    return results


def nvim_foreground_behavior_results():
    nvim = shutil.which("nvim")
    if not nvim:
        return None

    with tempfile.TemporaryDirectory(prefix="tmux-passthrough-consistency.") as tempdir:
        script_path = Path(tempdir) / "foreground-check.lua"
        output_path = Path(tempdir) / "foreground-results.tsv"
        case_rows = "\n".join(
            f"  {{ label = {lua_quote(label)}, command = {lua_quote(commandline)} }},"
            for label, commandline in behavior_cases
        )

        script_path.write_text(
            f"""
local root = {lua_quote(str(root))}
local output_path = {lua_quote(str(output_path))}
local spec = dofile(root .. "/common/.config/nvim/lua/plugins/tmux-navigator.lua")
local terminal_left

for _, key in ipairs(spec[1].keys) do
  if key[1] == "<C-h>" and key.mode == "t" then
    terminal_left = key[2]
  end
end

assert(type(terminal_left) == "function", "missing terminal tmux left mapping")

local cases = {{
{case_rows}
}}
local lines = {{}}

for index, case in ipairs(cases) do
  local root_pid = 1000 + index
  local child_pid = 2000 + index
  vim.cmd("enew!")
  vim.api.nvim_buf_set_name(0, "term://~/repo//" .. tostring(root_pid) .. ":/bin/zsh")
  vim.bo.filetype = ""
  vim.b.terminal_job_pid = root_pid
  vim.env.DOTFILES_NVIM_TEST_PS_OUTPUT = table.concat({{
    tostring(root_pid) .. " 1 S+ /bin/zsh",
    tostring(child_pid) .. " " .. tostring(root_pid) .. " S+ " .. case.command,
  }}, "\\n")
  table.insert(lines, (terminal_left() == "<C-h>" and "1" or "0") .. "\\t" .. case.label)
  vim.env.DOTFILES_NVIM_TEST_PS_OUTPUT = nil
  vim.cmd("bwipeout!")
end

local write_result = vim.fn.writefile(lines, output_path)
assert(write_result == 0, "writefile failed " .. tostring(write_result))
""",
            encoding="utf-8",
        )

        result = subprocess.run(
            [nvim, "--headless", "-u", "NONE", "-i", "NONE", "-n", "--noplugin", "-S", str(script_path), "+qa"],
            cwd=root,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            raise AssertionError(
                f"nvim foreground behavior check failed: exit={result.returncode} "
                f"stdout={result.stdout!r} stderr={result.stderr!r}"
            )
        if not output_path.exists():
            raise AssertionError(
                "nvim foreground behavior check did not produce foreground-results.tsv: "
                f"stdout={result.stdout!r} stderr={result.stderr!r}"
            )

        results = {}
        for line in output_path.read_text(encoding="utf-8").splitlines():
            value, label = line.split("\t", 1)
            results[label] = value == "1"

    return results


shell_behavior = shell_behavior_results()
nvim_behavior = nvim_behavior_results()
nvim_foreground_behavior = nvim_foreground_behavior_results()

if nvim_behavior is None:
    print("skip - tmux passthrough behavior consistency (nvim unavailable)")
else:
    mismatches = [
        (label, shell_behavior[label], nvim_behavior.get(label))
        for label, _ in behavior_cases
        if shell_behavior[label] != nvim_behavior.get(label)
    ]
    if mismatches:
        raise AssertionError(
            "tmux passthrough behavior drift: "
            + ", ".join(
                f"{label}: shell={shell_result} nvim={nvim_result}"
                for label, shell_result, nvim_result in mismatches
            )
        )
    print("tmux-passthrough-behavior-consistency-ok")

    foreground_mismatches = [
        (label, shell_behavior[label], nvim_foreground_behavior.get(label))
        for label, _ in behavior_cases
        if shell_behavior[label] != nvim_foreground_behavior.get(label)
    ]
    if foreground_mismatches:
        raise AssertionError(
            "tmux passthrough foreground behavior drift: "
            + ", ".join(
                f"{label}: shell={shell_result} nvim={nvim_result}"
                for label, shell_result, nvim_result in foreground_mismatches
            )
        )
    print("tmux-passthrough-foreground-behavior-consistency-ok")

print("tmux-passthrough-consistency-ok")
PY
