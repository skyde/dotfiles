#!/usr/bin/env bash
set -euo pipefail

# Linux-specific setup script
echo "🐧 Running Linux-specific setup..."

# Use sudo only if not running as root
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helper functions
source "${SCRIPT_DIR}/lib/run_ensure.sh"

echo "Installing Linux-specific packages..."

# Install zsh shell enhancements and fonts not in packages.txt
ensure_apt zsh
ensure_apt zsh-autosuggestions
ensure_apt zsh-syntax-highlighting
ensure_apt fonts-jetbrains-mono

# Install kitty terminfo so ssh sessions from kitty come up correctly.
#
# Into a temp directory, not the cwd: `curl -LO` wrote kitty.terminfo into the
# repo root (init.sh runs this from there) and `set -e` left it behind whenever
# tic was missing or the download failed. The sudo only made that stray file
# root-owned. Non-fatal, so a machine with no network still finishes setup.
install_kitty_terminfo() {
  if ! have tic; then
    echo "[warn] tic not found (install ncurses-bin); skipping kitty terminfo" >&2
    return 0
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  # shellcheck disable=SC2064  # expand tmp_dir now, it is about to go out of scope
  trap "rm -rf '$tmp_dir'" RETURN

  if ! curl -fsSLo "$tmp_dir/kitty.terminfo" \
    https://raw.githubusercontent.com/kovidgoyal/kitty/master/terminfo/kitty.terminfo; then
    echo "[warn] could not download kitty.terminfo; skipping" >&2
    return 0
  fi

  if tic -x -o "$HOME/.terminfo" "$tmp_dir/kitty.terminfo"; then
    echo "Installed kitty terminfo into ~/.terminfo"
  else
    echo "[warn] tic failed to compile kitty.terminfo; skipping" >&2
  fi
}

install_kitty_terminfo

# Change default shell to zsh
if have zsh; then
  ZSH_PATH=$(command -v zsh)
  TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"
  if getent passwd "$TARGET_USER" >/dev/null 2>&1; then
    CURRENT_SHELL=$(getent passwd "$TARGET_USER" | cut -d: -f7)
    if [ -n "$CURRENT_SHELL" ] && [ "$CURRENT_SHELL" != "$ZSH_PATH" ]; then
      if confirm_change "Change default shell to $ZSH_PATH" "$TARGET_USER" 1; then
        $SUDO chsh -s "$ZSH_PATH" "$TARGET_USER" || true
      fi
    fi
  else
    echo "Skipping default shell change: user '$TARGET_USER' not found in /etc/passwd."
  fi
fi

echo "✅ Linux-specific setup complete!"
