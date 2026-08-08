#!/usr/bin/env bash
# Static-check the Neovim Lua with lua-language-server, the same analysis an
# editor runs against this config — undefined globals and fields, calls with the
# wrong arity, values used without a nil check, and anything Neovim has
# deprecated. It catches the class of mistake the specs cannot: a typo down a
# branch no test happens to take.
#
#   tests/check-nvim-types.sh                 # against this checkout
#   tests/check-nvim-types.sh --level=Warning # only the ones LuaLS calls warnings
#
# The default is Hint, the strictest level lua-language-server has, because the
# config is clean at it — and a check that already passes is the cheapest time
# to tighten one. Drop to Warning to see what a normal editor would surface.
#
# Needs `lua-language-server` on PATH; skips cleanly when it is missing, so this
# stays usable on a machine that has not installed it. Release binaries:
# https://github.com/LuaLS/lua-language-server/releases
#
# NVIM_CHECKS_NO_SKIP=1 turns those skips into failures. CI sets it: it installs
# both tools, so a skip there means an install step quietly stopped working and
# the whole type check evaporated while the job still reported success.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
here="$PWD"

level="Hint"
for arg in "$@"; do
  case "$arg" in
    --level=*) level="${arg#--level=}" ;;
    *)
      echo "unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

skip() {
  if [[ "${NVIM_CHECKS_NO_SKIP:-}" == "1" ]]; then
    echo "FAIL: $1 (NVIM_CHECKS_NO_SKIP=1)" >&2
    exit 1
  fi
  echo "SKIP: $1"
  exit 0
}

if ! command -v lua-language-server >/dev/null 2>&1; then
  skip "lua-language-server not found"
fi

if ! command -v nvim >/dev/null 2>&1; then
  skip "nvim not found (its runtime is the type library)"
fi

# The Neovim runtime's own Lua is the library every `vim.*` annotation comes
# from. Ask the binary in use rather than guessing at an install prefix, so this
# works for a tarball in ~/.local, a Homebrew install and a distro package
# alike.
runtime="$(nvim --headless -c 'lua io.write(vim.env.VIMRUNTIME or "")' -c qa 2>/dev/null)"
if [[ -z "$runtime" || ! -d "$runtime/lua" ]]; then
  echo "SKIP: could not locate VIMRUNTIME" >&2
  exit 0
fi

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

# Plugins are libraries too, when they happen to be installed: without LazyVim
# and snacks on the path every `Snacks.picker.*` and `LazyVim.root()` reads as a
# call into an unknown table. They are optional — the config's own modules are
# what this checks, and they must analyse cleanly on a machine that has never
# run :Lazy.
libraries=("$runtime/lua")
lazy_root="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy"
for plugin in lazy.nvim snacks.nvim LazyVim; do
  if [[ -d "$lazy_root/$plugin/lua" ]]; then
    libraries+=("$lazy_root/$plugin/lua")
  fi
done

# Splice the machine-specific library paths into the checked-in settings.
library_json="$(printf '%s\n' "${libraries[@]}" | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')"
python3 - "$here/tests/nvim-luarc.json" "$sandbox/.luarc.json" "$library_json" <<'PY'
import json, re, sys

src, dst, libraries = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
text = open(src, encoding="utf-8").read()
# The settings file is JSONC so it can explain itself; strip the comments that
# json.loads would choke on. Nothing in it contains a string with "//" in it.
text = re.sub(r"^\s*//.*$", "", text, flags=re.MULTILINE)
config = json.loads(text)
config.setdefault("workspace", {})["library"] = libraries
json.dump(config, open(dst, "w", encoding="utf-8"), indent=2)
PY

echo "Checking common/.config/nvim/lua at level $level"
raw="$sandbox/raw.txt"
lua-language-server \
  --check "$here/common/.config/nvim/lua" \
  --checklevel="$level" \
  --configpath="$sandbox/.luarc.json" \
  --logpath="$sandbox/log" \
  >"$raw" 2>&1

# The progress meter is drawn with carriage returns on the same stream as the
# diagnostics, so split on \r and drop the meter before anyone reads this.
report="$sandbox/report.txt"
tr '\r' '\n' <"$raw" | sed 's/\x1b\[[0-9;]*m//g' | grep -vE '^\s*$|^[>=]+ *[0-9]+/[0-9]+|^Initializing' >"$report"
cat "$report"

# --check exits 0 whether or not it found anything, so the summary line is the
# only reliable verdict.
if grep -q "no problems found" "$report"; then
  echo "✅ no problems found"
  exit 0
fi

if ! grep -q "Diagnosis complete" "$report"; then
  echo "❌ lua-language-server did not finish; see the output above" >&2
  exit 1
fi
echo "❌ $(grep -oE '[0-9]+ problems? found' "$report" | tail -1)" >&2
exit 1
