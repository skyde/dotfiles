#!/usr/bin/env bash
set -euo pipefail

# Install VS Code (or Cursor) extensions from vscode_extensions.txt
repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ext_file="$repo_dir/vscode_extensions.txt"

CODE_CMD=""
if command -v code >/dev/null 2>&1; then
  CODE_CMD="code"
elif command -v cursor >/dev/null 2>&1; then
  CODE_CMD="cursor"
elif [ -f "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]; then
  CODE_CMD="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
else
  echo "VS Code 'code' or 'cursor' command not found, skipping extension install" >&2
  exit 0
fi

while IFS= read -r ext || [ -n "${ext:-}" ]; do
  [ -z "${ext:-}" ] && continue
  echo "Installing VS Code extension: $ext"
  "$CODE_CMD" --install-extension "$ext" --force || true
done < "$ext_file"
