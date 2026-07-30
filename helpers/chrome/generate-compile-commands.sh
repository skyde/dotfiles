#!/usr/bin/env bash
# Generate the compilation database clangd needs for a Chromium (or any GN)
# checkout, so editor features like goto-definition work.
#
#   helpers/chrome/generate-compile-commands.sh              # cwd's checkout, out/Default
#   helpers/chrome/generate-compile-commands.sh ~/chrome/src # explicit root
#   helpers/chrome/generate-compile-commands.sh ~/chrome/src out/Debug
#
# It sets export_compile_commands=true in the build directory's args.gn (adding
# args.gn if the directory is new), runs `gn gen`, and points
# <root>/compile_commands.json at the result for editors that only look there.
# Neovim finds the database on its own; see docs/chromium-nvim-lsp.md.
set -euo pipefail

die() {
  echo "error: $*" >&2
  exit 1
}

# Outermost ancestor that is a GN root, matching util.clangd.gn_root in the
# Neovim config: Chromium nests .gn files under third_party/.
find_gn_root() {
  local dir="$1" root=""
  dir="$(cd "$dir" && pwd)"
  while :; do
    if [[ -f "$dir/.gn" && -f "$dir/build/config/BUILDCONFIG.gn" ]]; then
      root="$dir"
    fi
    [[ "$dir" == "/" ]] && break
    dir="$(dirname "$dir")"
  done
  [[ -n "$root" ]] && printf '%s\n' "$root"
}

root="${1:-$PWD}"
[[ -d "$root" ]] || die "not a directory: $root"
root="$(find_gn_root "$root")" || true
[[ -n "${root:-}" ]] || die "no GN checkout found at or above ${1:-$PWD}"

out_dir="${2:-out/Default}"
args_gn="$root/$out_dir/args.gn"

command -v gn >/dev/null 2>&1 ||
  die "gn not on PATH; add depot_tools (e.g. export PATH=\"\$PATH:$HOME/chrome/depot_tools\")"

mkdir -p "$root/$out_dir"
if [[ ! -f "$args_gn" ]]; then
  echo "# Created by helpers/chrome/generate-compile-commands.sh" >"$args_gn"
fi
if ! grep -qE '^[[:space:]]*export_compile_commands[[:space:]]*=' "$args_gn"; then
  {
    echo ""
    echo "# Emit compile_commands.json so clangd can index the tree."
    echo "export_compile_commands = true"
  } >>"$args_gn"
  echo "added export_compile_commands=true to $args_gn"
fi

echo "running: gn gen $out_dir (in $root)"
(cd "$root" && gn gen "$out_dir" --export-compile-commands)

db="$root/$out_dir/compile_commands.json"
[[ -f "$db" ]] || die "gn gen did not produce $db"

link="$root/compile_commands.json"
if [[ -L "$link" || ! -e "$link" ]]; then
  # Only ever replace a symlink, never a real file someone hand-made.
  ln -sfn "$out_dir/compile_commands.json" "$link"
  echo "linked $link -> $out_dir/compile_commands.json"
else
  echo "left existing $link alone (not a symlink)"
fi

echo "done: $db ($(wc -c <"$db" | tr -d ' ') bytes)"
