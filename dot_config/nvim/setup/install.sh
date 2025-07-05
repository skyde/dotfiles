#!/usr/bin/env bash
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"

# Clone or copy repo
if [ ! -d "$CONFIG_DIR" ]; then
  echo "Setting up Neovim config in $CONFIG_DIR"
  mkdir -p "$(dirname "$CONFIG_DIR")"
  git clone "$REPO_ROOT" "$CONFIG_DIR"
elif [ -d "$CONFIG_DIR/.git" ]; then
  echo "Neovim config already exists at $CONFIG_DIR, updating..."
  if git -C "$CONFIG_DIR" remote >/dev/null 2>&1 && [ -n "$(git -C "$CONFIG_DIR" remote)" ]; then
    git -C "$CONFIG_DIR" pull --ff-only
  else
    echo "No git remote found, copying files instead..."
    cp -rT "$REPO_ROOT" "$CONFIG_DIR"
  fi
else
  echo "Neovim config already exists at $CONFIG_DIR but is not a git repo. Copying files..."
  cp -rT "$REPO_ROOT" "$CONFIG_DIR"
fi

install_lazygit_release() {
  if command -v lazygit >/dev/null 2>&1; then
    return
  fi

  echo "Installing lazygit from GitHub releases..."
  local version
  version="$(curl -sL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep tag_name | cut -d '"' -f4)"
  local arch
  case "$(uname -m)" in
    x86_64|amd64)
      arch="x86_64"
      ;;
    arm64|aarch64)
      arch="arm64"
      ;;
    *)
      echo "Unsupported architecture $(uname -m) for lazygit installation"
      return 1
      ;;
  esac

  local tarball="lazygit_${version#v}_Linux_${arch}.tar.gz"
  curl -L "https://github.com/jesseduffield/lazygit/releases/download/${version}/${tarball}" -o "/tmp/${tarball}"
  tar -C /tmp -xf "/tmp/${tarball}" lazygit
  sudo install /tmp/lazygit /usr/local/bin/lazygit
  rm -f "/tmp/${tarball}" /tmp/lazygit
}

install_packages() {
  if command -v brew >/dev/null 2>&1; then
    brew install neovim git fd lazygit kitty
  elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y ppa:neovim-ppa/stable
    sudo apt-get update
    if apt-cache show lazygit >/dev/null 2>&1; then
      sudo apt-get install -y neovim git fd-find lazygit kitty
    else
      sudo apt-get install -y neovim git fd-find kitty
      install_lazygit_release
    fi
    if ! command -v fd >/dev/null && command -v fdfind >/dev/null; then
      sudo ln -s "$(command -v fdfind)" /usr/local/bin/fd
    fi
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --needed neovim git fd lazygit kitty
  else
    echo "Please install neovim, git, fd, lazygit and kitty manually."
  fi
}

case "$(uname)" in
  Darwin)
    install_packages
    ;;
  Linux)
    install_packages
    ;;
  *)
    echo "install.sh only supports macOS and Linux."
    exit 1
    ;;
 esac

nvim --headless "+Lazy! sync" +qa

echo "Neovim is ready."
if command -v kitty >/dev/null 2>&1 && [ -n "$DISPLAY" ]; then
  echo "Launching kitty with Neovim..."
  kitty nvim
elif [ -n "$DISPLAY" ]; then
  nvim
else
  echo "No DISPLAY detected. Run 'nvim' manually to start." >&2
fi
