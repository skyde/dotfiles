#!/usr/bin/env bash
set -euo pipefail
has() { command -v "$1" >/dev/null 2>&1; }
dry() { [ -n "${DOT_DRYRUN:-}" ]; }

log() { echo "[install-core] $*"; }

pkg_install() {
  local tool="$1"; shift || true
  dry && { log "dry-run: skip install $tool"; return 0; }
  case "$DOT_OS" in
    darwin)
      has brew || { log "brew not found; skip $tool"; return 0; }
      brew install "$tool" || true
      ;;
    linux)
      if has apt-get; then sudo apt-get update -y && sudo apt-get install -y "$tool" || true
      elif has dnf; then sudo dnf install -y "$tool" || true
      elif has pacman; then sudo pacman -Sy --noconfirm "$tool" || true
      elif has zypper; then sudo zypper refresh && sudo zypper install -y "$tool" || true
      fi
      ;;
  esac
}

log "install editors/tools"

# Neovim + LazyVim starter overlayed by stow/nvim
if ! has nvim; then
  log "install Neovim"
  case "$DOT_OS" in
    darwin) has brew && ! dry && brew install neovim || true ;;
    linux)
      if ! dry; then
        if has apt-get; then sudo apt-get update -y && sudo apt-get install -y neovim || true
        elif has pacman; then sudo pacman --noconfirm -S neovim || true
        elif has dnf; then sudo dnf install -y neovim || true
        fi
      fi
      ;;
  esac
fi

# LazyVim starter
if ! dry; then
  nvim_dir="$DOT_TARGET/.config/nvim"
  rm -rf "$nvim_dir"
  git clone https://github.com/LazyVim/starter "$nvim_dir" || true
  rm -rf "$nvim_dir/.git" || true
  rm -f "$nvim_dir/lazy-lock.json" "$nvim_dir/lua/config/keymaps.lua" \
        "$nvim_dir/lua/plugins/colorscheme.lua" "$nvim_dir/ftplugin/markdown.lua" 2>/dev/null || true
fi

# Helix, lazygit, ripgrep, bat
has hx || pkg_install helix
has lazygit || pkg_install lazygit
has rg || pkg_install ripgrep
if ! has bat; then
  if has batcat; then
    mkdir -p "$DOT_TARGET/.local/bin"
    [ -e "$DOT_TARGET/.local/bin/bat" ] || ln -s "$(command -v batcat)" "$DOT_TARGET/.local/bin/bat"
  else
    pkg_install bat
  fi
fi

# oh-my-zsh (non-Windows)
if [ "$DOT_OS" != windows ] && [ ! -d "$DOT_TARGET/.oh-my-zsh" ]; then
  log "install oh-my-zsh (unattended)"
  dry || RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" --unattended || true
fi

