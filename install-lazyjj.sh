#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname)" != "Linux" ]]; then
  echo "install-lazyjj.sh currently supports Linux hosts only."
  exit 0
fi

if ! command -v cargo >/dev/null 2>&1; then
  cat >&2 <<'EOF'
error: cargo is required to install lazyjj.
Install Rust (https://rustup.rs/) and re-run this script.
EOF
  exit 1
fi

version_spec="${LAZYJJ_VERSION:-latest}"

echo "Installing lazyjj (${version_spec})..."
if [[ "$version_spec" == "latest" ]]; then
  cargo install --locked --force lazyjj
else
  cargo install --locked --force --version "$version_spec" lazyjj
fi

if command -v lazyjj >/dev/null 2>&1; then
  echo "✅ lazyjj installed: $(lazyjj --version)"
else
  echo "⚠️ lazyjj installed, but it is not on PATH yet."
  echo "   Add ~/.cargo/bin to PATH and restart your shell."
fi
