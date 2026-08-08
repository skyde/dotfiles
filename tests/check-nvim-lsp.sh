#!/usr/bin/env bash
# Drive the C++ language server against the real Neovim config and report
# anything that does not work. Unlike tests/run-nvim-specs.sh this needs the
# config, its plugins and a real clangd, so it checks the chain as actually
# assembled — which is where servers that are configured but never enabled,
# keymaps naming a renamed command, and settings LazyVim replaces after
# config/options.lua all hide.
#
#   tests/check-nvim-lsp.sh            # against the installed config
#   tests/check-nvim-lsp.sh /path/dir  # against a checkout's common/.config
#
# Everything happens in a throwaway directory; the working tree is untouched.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
here="$PWD"

if [[ $# -ge 1 ]]; then
  export XDG_CONFIG_HOME="$1/common/.config"
fi

if ! command -v nvim >/dev/null 2>&1; then
  echo "nvim not found" >&2
  exit 1
fi
if ! command -v clangd >/dev/null 2>&1; then
  echo "SKIP: clangd not found (this check drives a real language server)"
  exit 0
fi
python="$(command -v python3 || command -v python)"
if [[ -z "$python" ]]; then
  echo "SKIP: python not found (the compdb generator needs it)"
  exit 0
fi

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

# A plain C++ project, with the compilation database already in place.
mkdir -p "$sandbox/plain"
cat >"$sandbox/plain/lib.h" <<'EOF'
#pragma once
int add_numbers(int a, int b);
EOF
cat >"$sandbox/plain/lib.cc" <<'EOF'
#include "lib.h"
int add_numbers(int a, int b) { return a + b; }
EOF
cat >"$sandbox/plain/main.cc" <<'EOF'
#include "lib.h"
int main() {
  int x = add_numbers(1, 2);
  return x + add_numbers(3, 4);
}
EOF
"$python" - "$sandbox/plain" <<'PY'
import json, sys, os
d = sys.argv[1]
entries = [
    {"directory": d, "file": os.path.join(d, f), "command": f"clang++ -std=c++17 -c {f}"}
    for f in ("lib.cc", "main.cc")
]
json.dump(entries, open(os.path.join(d, "compile_commands.json"), "w"), indent=1)
PY

# A fake Chromium checkout: detected by the compdb generator's path, with a
# generator that writes a real database and a build dir that looks generated.
src="$sandbox/chromium/src"
mkdir -p "$src/tools/clang/scripts" "$src/out/Default" "$src/base"
printf 'ninja\n' >"$src/out/Default/build.ninja"
cat >"$src/tools/clang/scripts/generate_compdb.py" <<'EOF'
"""Stand-in for Chromium's generator: writes a database for the checkout's
own sources, which is all the editor side of the chain needs to be real."""
import json, os, sys

out = sys.argv[sys.argv.index("-o") + 1] if "-o" in sys.argv else "compile_commands.json"
root = os.getcwd()
entries = []
for dirpath, _, names in os.walk(root):
    if os.path.relpath(dirpath, root).startswith(("out", "tools")):
        continue
    for name in names:
        if name.endswith((".cc", ".cpp")):
            path = os.path.join(dirpath, name)
            entries.append({
                "directory": root,
                "file": os.path.relpath(path, root),
                "command": "clang++ -std=c++17 -c " + os.path.relpath(path, root),
            })
json.dump(entries, open(os.path.join(root, out), "w"), indent=1)
EOF
cat >"$src/base/logging.h" <<'EOF'
#pragma once
int log_value(int v);
EOF
cat >"$src/base/logging.cc" <<'EOF'
#include "base/logging.h"
int log_value(int v) { return v; }
EOF
cat >"$src/main.cc" <<'EOF'
#include "base/logging.h"
int main() { return log_value(7); }
EOF

export NVIM_LSP_SANDBOX="$sandbox"
export NVIM_LSP_REPORT="$sandbox/report.txt"

cd "$sandbox/plain" || exit 1
# VeryLazy is normally fired by UIEnter, which never happens headless.
nvim --headless \
  -c 'doautocmd User VeryLazy' \
  -c "luafile $here/tests/nvim_lsp_check.lua" \
  -c 'qa!'
status=$?

echo
cat "$NVIM_LSP_REPORT" 2>/dev/null
if [[ -f "$NVIM_LSP_REPORT" ]] && ! grep -q 'failed 0$' "$NVIM_LSP_REPORT"; then
  status=1
fi
exit "$status"
