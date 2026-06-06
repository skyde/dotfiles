#!/usr/bin/env bash
# Install a LazyVim/nvim-treesitter-compatible tree-sitter CLI.
set -euo pipefail

min_version="0.26.1"

version_ge() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)" = "$2" ]
}

if command -v tree-sitter >/dev/null 2>&1; then
  current_version="$(tree-sitter --version 2>/dev/null | awk '{print $2}' | sed 's/^v//')"
  if [ -n "$current_version" ] && version_ge "$current_version" "$min_version"; then
    echo "tree-sitter ${current_version} is already installed."
    exit 0
  fi
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to download tree-sitter-cli." >&2
  exit 1
fi

case "$(uname -s)" in
  Linux) platform="linux" ;;
  Darwin) platform="macos" ;;
  *)
    echo "install-tree-sitter-cli.sh supports Linux and macOS hosts only." >&2
    exit 1
    ;;
esac

case "$(uname -m)" in
  x86_64 | amd64) arch="x64" ;;
  arm64 | aarch64) arch="arm64" ;;
  *)
    echo "Unsupported architecture for tree-sitter-cli: $(uname -m)" >&2
    exit 1
    ;;
esac

tmp_dir="$(mktemp -d)"
readonly tmp_dir
cleanup() {
  rm -rf -- "$tmp_dir"
}
trap cleanup EXIT

api_url="https://api.github.com/repos/tree-sitter/tree-sitter/releases/latest"
asset_name="tree-sitter-cli-${platform}-${arch}.zip"
archive="${tmp_dir}/${asset_name}"
bin_dir="${HOME}/.local/bin"
install_target="${bin_dir}/tree-sitter"

download_url="$(
  curl -fsSL "$api_url" |
    awk -v asset="$asset_name" '
      /"browser_download_url"/ && index($0, asset) {
        gsub(/[",]/, "", $2)
        print $2
        exit
      }
    '
)"

if [ -z "$download_url" ]; then
  echo "Could not find release asset ${asset_name}." >&2
  exit 1
fi

echo "Downloading ${asset_name}..."
curl -fLSo "$archive" "$download_url"

mkdir -p "$bin_dir"
if command -v unzip >/dev/null 2>&1; then
  unzip -p "$archive" tree-sitter >"$install_target"
else
  python3 - "$archive" "$install_target" <<'PY'
import sys
import zipfile

archive, target = sys.argv[1:3]
with zipfile.ZipFile(archive) as zf:
    with zf.open("tree-sitter") as source, open(target, "wb") as dest:
        dest.write(source.read())
PY
fi
chmod +x "$install_target"

"$install_target" --version
