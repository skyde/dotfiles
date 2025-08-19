#!/usr/bin/env bash
set -euo pipefail

# Ensure LF works on Debian via GitHub binary install (fallback when apt package is missing)

HAVE() { command -v "$1" >/dev/null 2>&1; }

SUDO_CMD=""
if [ "$(id -u)" -ne 0 ] && HAVE sudo; then
  SUDO_CMD="sudo"
fi

if [ -r /etc/os-release ]; then . /etc/os-release; fi
if [ "${ID:-}" = "debian" ] && HAVE apt-get; then
  $SUDO_CMD apt-get update -y
  $SUDO_CMD apt-get install -y curl tar
  if ! HAVE lf; then
    latest=$(curl -fsSL https://api.github.com/repos/gokcehan/lf/releases/latest | sed -n 's/.*"tag_name"\s*:\s*"\([^"]*\)".*/\1/p' | head -n1)
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    curl -fsSL "https://github.com/gokcehan/lf/releases/download/${latest}/lf-linux-amd64.tar.gz" -o "$tmp/lf.tar.gz"
    tar -xzf "$tmp/lf.tar.gz" -C "$tmp"
    $SUDO_CMD install -m 0755 "$tmp/lf" /usr/local/bin/lf
  fi
fi

echo "lf installation check complete."
