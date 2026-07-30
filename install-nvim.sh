#!/usr/bin/env bash
# Install the latest Neovim release into ~/.local/bin.
#
#   ./install-nvim.sh                        # latest release
#   NVIM_VERSION=v0.11.2 ./install-nvim.sh   # a specific tag
#
# The official tarball is preferred because it needs no FUSE; the AppImage is
# the fallback and gets unpacked when FUSE is unavailable.
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "install-nvim.sh currently supports Linux hosts only (use Homebrew elsewhere)."
  exit 0
fi

for tool in curl tar; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "${tool} is required to install Neovim." >&2
    exit 1
  fi
done

case "$(uname -m)" in
x86_64 | amd64) readonly asset="nvim-linux-x86_64" ;;
aarch64 | arm64) readonly asset="nvim-linux-arm64" ;;
*)
  echo "Unsupported architecture: $(uname -m)" >&2
  exit 1
  ;;
esac

readonly repo="neovim/neovim"
readonly version="${NVIM_VERSION:-}"
if [[ -n "$version" ]]; then
  readonly base_url="https://github.com/${repo}/releases/download/${version}"
else
  readonly base_url="https://github.com/${repo}/releases/latest/download"
fi

readonly install_dir="${HOME}/.local/bin"
readonly install_target="${install_dir}/nvim"
readonly opt_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/nvim-release"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$install_dir"

install_tarball() {
  printf '⬇️  Downloading Neovim %s tarball...\n' "${version:-latest}"
  curl -fLSo "${tmp_dir}/${asset}.tar.gz" "${base_url}/${asset}.tar.gz" || return 1
  tar -xzf "${tmp_dir}/${asset}.tar.gz" -C "$tmp_dir" || return 1
  [[ -x "${tmp_dir}/${asset}/bin/nvim" ]] || return 1

  rm -rf "$opt_dir"
  mkdir -p "$(dirname "$opt_dir")"
  mv "${tmp_dir}/${asset}" "$opt_dir"
  ln -sfn "${opt_dir}/bin/nvim" "$install_target"
}

install_appimage() {
  printf '⬇️  Downloading Neovim %s AppImage...\n' "${version:-latest}"
  local image="${tmp_dir}/${asset}.appimage"
  curl -fLSo "$image" "${base_url}/${asset}.appimage" || return 1
  chmod u+x "$image"

  if "$image" --version >/dev/null 2>&1; then
    rm -rf "$opt_dir"
    mv -f "$image" "$install_target"
    return 0
  fi

  # No FUSE on this host: unpack the AppImage and run it from disk instead.
  printf 'ℹ️  FUSE unavailable, extracting the AppImage...\n'
  (cd "$tmp_dir" && "$image" --appimage-extract >/dev/null) || return 1
  [[ -x "${tmp_dir}/squashfs-root/usr/bin/nvim" ]] || return 1

  rm -rf "$opt_dir"
  mkdir -p "$(dirname "$opt_dir")"
  mv "${tmp_dir}/squashfs-root" "$opt_dir"
  ln -sfn "${opt_dir}/usr/bin/nvim" "$install_target"
}

if ! install_tarball; then
  printf '⚠️  Tarball install failed, falling back to the AppImage.\n' >&2
  install_appimage
fi

# Older versions of this script installed to ~/bin, which zsh puts ahead of
# ~/.local/bin. Repoint any leftover copy so the fresh install actually wins.
if [[ -e "${HOME}/bin/nvim" || -L "${HOME}/bin/nvim" ]]; then
  ln -sfn "$install_target" "${HOME}/bin/nvim"
  printf 'ℹ️  Repointed %s at the new install.\n' "${HOME}/bin/nvim"
fi

printf '✅ %s\n' "$("$install_target" --version | head -n 1)"
printf '   installed to %s\n' "$install_target"
