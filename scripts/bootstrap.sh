#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$os" in
  darwin) os=darwin;;
  linux) os=linux;;
  msys*|mingw*|cygwin*) os=windows;;
esac

echo "Detected OS: $os"

has() { command -v "$1" >/dev/null 2>&1; }

ensure_stow() {
  if has stow; then return; fi
  echo "Installing GNU Stow..."
  if [ "$os" = darwin ] && has brew; then
    brew install stow
  elif [ "$os" = linux ]; then
    if has apt-get; then sudo apt-get update -qq && sudo apt-get install -y stow
    elif has dnf; then sudo dnf install -y stow
    elif has pacman; then sudo pacman -Sy --noconfirm stow
    else echo "Please install 'stow' manually."; fi
  else
    echo "Skipping stow install on $os"
  fi
}


install_neovim_and_lazyvim() {
  if has nvim; then :; else
    echo "Installing Neovim..."
    if [ "$os" = darwin ] && has brew; then brew install neovim
    elif [ "$os" = linux ] && has apt-get; then sudo apt-get update -y && sudo apt-get install -y neovim
    elif [ "$os" = linux ] && has pacman; then sudo pacman --noconfirm -S neovim
    elif [ "$os" = linux ] && has dnf; then sudo dnf install -y neovim
    else echo "Install Neovim manually"; fi
  fi
  # Replace existing config with LazyVim starter like chezmoi did
  local nvim_dir="$HOME/.config/nvim"
  if [ -d "$nvim_dir" ]; then rm -rf "$nvim_dir"; fi
  git clone https://github.com/LazyVim/starter "$nvim_dir"
  rm -rf "$nvim_dir/.git"
  # Remove files that we overlay via stow to avoid conflicts
  rm -f \
    "$nvim_dir/lazy-lock.json" \
    "$nvim_dir/lua/config/keymaps.lua" \
    "$nvim_dir/lua/plugins/colorscheme.lua" \
    "$nvim_dir/ftplugin/markdown.lua" 2>/dev/null || true
}

install_helix() {
  if has hx; then return; fi
  echo "Installing Helix..."
  if [ "$os" = darwin ] && has brew; then
    brew install helix
  elif [ "$os" = linux ] && has apt-get; then
    sudo apt-get update -y && sudo apt-get install -y helix
  elif [ "$os" = linux ] && has pacman; then
    sudo pacman --noconfirm -S helix
  elif [ "$os" = linux ] && has dnf; then
    sudo dnf install -y helix
  else
    echo "No supported package manager found for Helix installation."
  fi
}

install_ohmyzsh() {
  [ "$os" = windows ] && return 0
  if [ -d "$HOME/.oh-my-zsh" ]; then return; fi
  echo "Installing oh-my-zsh (unattended)..."
  export RUNZSH=no CHSH=no KEEP_ZSHRC=yes
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" --unattended
}

install_lazygit() {
  if has lazygit; then return; fi
  echo "Installing lazygit..."
  if [ "$os" = darwin ] && has brew; then brew install lazygit
  elif [ "$os" = linux ] && has apt-get; then sudo apt-get update -y && sudo apt-get install -y lazygit
  elif [ "$os" = linux ] && has dnf; then sudo dnf install -y lazygit || { sudo dnf copr enable -y atim/lazygit; sudo dnf install -y lazygit; }
  elif [ "$os" = linux ] && has pacman; then sudo pacman -Sy --noconfirm lazygit
  elif [ "$os" = linux ] && has zypper; then sudo zypper refresh && sudo zypper install -y lazygit
  fi
}

install_ripgrep() {
  if has rg; then return; fi
  echo "Installing ripgrep..."
  if [ "$os" = darwin ] && has brew; then brew install ripgrep
  elif [ "$os" = linux ] && has apt-get; then sudo apt-get update -y && sudo apt-get install -y ripgrep
  elif [ "$os" = linux ] && has dnf; then sudo dnf install -y ripgrep
  elif [ "$os" = linux ] && has pacman; then sudo pacman -Sy --noconfirm ripgrep
  fi
}

install_bat() {
  if has bat; then return; fi
  if has batcat; then
    mkdir -p "$HOME/.local/bin"
    [ -e "$HOME/.local/bin/bat" ] || ln -s "$(command -v batcat)" "$HOME/.local/bin/bat"
    return
  fi
  echo "Installing bat..."
  if [ "$os" = darwin ] && has brew; then brew install bat
  elif [ "$os" = linux ] && has apt-get; then sudo apt-get update -y && sudo apt-get install -y bat || true
  elif [ "$os" = linux ] && has dnf; then sudo dnf install -y bat
  elif [ "$os" = linux ] && has pacman; then sudo pacman -Sy --noconfirm bat
  elif [ "$os" = linux ] && has zypper; then sudo zypper refresh && sudo zypper install -y bat
  elif [ "$os" = linux ] && has apk; then sudo apk add --no-cache bat
  fi
  if ! has bat && has batcat; then
    mkdir -p "$HOME/.local/bin"; [ -e "$HOME/.local/bin/bat" ] || ln -s "$(command -v batcat)" "$HOME/.local/bin/bat"
  fi
}

install_kitty() {
  [ "$os" = darwin ] || return 0
  # Skip if binary exists or app bundle is present
  if has kitty || [ -d "/Applications/kitty.app" ] || [ -d "$HOME/Applications/kitty.app" ]; then return; fi
  if has brew; then
    if brew list --cask kitty >/dev/null 2>&1; then return; fi
    brew install --cask kitty
  fi
}

install_wezterm() {
  if has wezterm || [ -d "/Applications/WezTerm.app" ] || [ -d "$HOME/Applications/WezTerm.app" ]; then return; fi
  if [ "$os" = darwin ] && has brew; then brew install --cask wezterm && return; fi
  if [ "$os" = linux ]; then
    if has apt-get; then
      if ! dpkg -s wezterm >/dev/null 2>&1; then
        sudo mkdir -p /usr/share/keyrings
        curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
        echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | sudo tee /etc/apt/sources.list.d/wezterm.list >/dev/null
        sudo chmod 644 /usr/share/keyrings/wezterm-fury.gpg
        sudo apt-get update -qq
        sudo apt-get install -y wezterm || true
      fi
    elif has dnf; then sudo dnf -y install wezterm || { sudo dnf -y copr enable wezfurlong/wezterm-nightly || true; sudo dnf -y install wezterm || sudo dnf -y install wezterm-nightly || true; }
    elif has pacman; then sudo pacman -S --noconfirm wezterm || true
    else
      if has flatpak; then flatpak install -y flathub org.wezfurlong.wezterm || true; fi
    fi
  fi
}

install_fonts() {
  if [ "$os" = darwin ]; then
    FONT_DIR="$HOME/Library/Fonts"
  elif [ "$os" = linux ]; then
    FONT_DIR="$HOME/.local/share/fonts"
  else
    return 0
  fi
  mkdir -p "$FONT_DIR"
  SRC="$here/fonts"
  if [ -d "$SRC" ]; then
    for f in "$SRC"/*.ttf; do [ -f "$f" ] && cp -f "$f" "$FONT_DIR/"; done
    if [ "$os" = linux ] && has fc-cache; then fc-cache -fv "$FONT_DIR" >/dev/null 2>&1 || true; fi
    echo "Fonts installed to $FONT_DIR"
  fi
}

rebuild_bat_cache() {
  if has bat; then bat cache --build || true; elif has batcat; then batcat cache --build || true; fi
}

ensure_shell_rc() {
  local line='[ -f "$HOME/.config/shell/00-editor.sh" ] && . "$HOME/.config/shell/00-editor.sh"'
  for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.zprofile"; do
    [ -f "$rc" ] || touch "$rc"
    if ! grep -Fq "$line" "$rc"; then echo "$line" >>"$rc"; fi
  done
}

ensure_git_editor() {
  if has git; then
    git config --global core.editor "nvim" || true
    git config --global sequence.editor "nvim" || true
  fi
}

disable_charge_chime_macos() {
  [ "$os" = darwin ] || return 0
  /usr/bin/defaults write com.apple.PowerChime ChimeOnNoHardware -bool true || true
  /usr/bin/killall PowerChime >/dev/null 2>&1 || true
}

main() {
  if [ "$os" = windows ]; then
    echo "Run scripts/bootstrap.ps1 in PowerShell on Windows."; exit 0
  fi

  # Dry-run mode: skip installations and only preview stow operations
  if [ -n "${DRYRUN:-}" ]; then
    echo "DRYRUN=1: skipping installations; previewing stow changes..."
    if [ -x "$here/dot" ]; then
      "$here/dot" diff
    else
      # Fallback dry-run directly via stow
      pkgs=()
      for p in $(find "$here/stow" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sed 's#.*/##' | sort); do
        case "$os" in
          darwin) case "$p" in vsvim|vscode-linux) continue;; esac ;;
          linux)  case "$p" in vsvim|macos|hammerspoon|vscode-macos) continue;; esac ;;
        esac
        pkgs+=("$p")
      done
      stow -n -v -d "$here/stow" -t "$HOME" ${STOW_FLAGS:-"--no-folding"} -S "${pkgs[@]}"
    fi
    echo "✅ Bootstrap complete."
    return 0
  fi

  ensure_stow

  # Install editors/tools first
  install_neovim_and_lazyvim
  install_helix
  install_lazygit
  install_ripgrep
  install_bat
  install_kitty
  install_wezterm
  install_ohmyzsh
  install_fonts
  rebuild_bat_cache
  ensure_shell_rc
  ensure_git_editor
  disable_charge_chime_macos

  # Ensure local bin scripts are executable before stow
  chmod +x "$here/stow/local-bin/.local/bin"/* 2>/dev/null || true

  # Stow all discovered packages using the repo's dot wrapper
  if [ -x "$here/dot" ]; then
    "$here/dot" apply
  else
    # Fallback: stow everything under stow/ for this OS
    pkgs=()
    for p in $(find "$here/stow" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sed 's#.*/##' | sort); do
      case "$os" in
        darwin) case "$p" in vsvim|vscode-linux) continue;; esac ;;
        linux)  case "$p" in vsvim|macos|hammerspoon|vscode-macos) continue;; esac ;;
      esac
      pkgs+=("$p")
    done
    stow -d "$here/stow" -t "$HOME" ${STOW_FLAGS:-"--no-folding"} -S "${pkgs[@]}"
  fi

  echo "✅ Bootstrap complete."
}

main "$@"
