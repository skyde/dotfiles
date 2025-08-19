#!/usr/bin/env bash
set -euo pipefail

HAVE() { command -v "$1" >/dev/null 2>&1; }

SUDO_CMD=""
if [ "$(id -u)" -ne 0 ] && HAVE sudo; then
  SUDO_CMD="sudo"
fi

# Try to source shared helpers if available
if [ -f "$HOME/lib/run_ensure.sh" ]; then
  . "$HOME/lib/run_ensure.sh"
fi

case "$(uname -s)" in
  Linux)
    if [ -r /etc/os-release ]; then . /etc/os-release; fi
    if [ "${ID:-}" = "debian" ] && HAVE apt-get; then
      ensure_apt curl
      ensure_apt tar
      if ! HAVE lf; then
        latest="$(curl -fsSL https://api.github.com/repos/gokcehan/lf/releases/latest | sed -n 's/.*\"tag_name\"\s*:\s*\"\([^\"]*\)\".*/\1/p' | head -n1)"
        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' EXIT
        curl -fsSL "https://github.com/gokcehan/lf/releases/download/${latest}/lf-linux-amd64.tar.gz" -o "$tmp/lf.tar.gz"
        tar -xzf "$tmp/lf.tar.gz" -C "$tmp"
        $SUDO_CMD install -m 0755 "$tmp/lf" /usr/local/bin/lf
      fi
    fi
    ;;
  *) : ;;
esac

echo "lf installation complete."
