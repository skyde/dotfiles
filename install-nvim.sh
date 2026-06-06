#!/usr/bin/env bash
# Install the latest Neovim release into ~/.local/bin
set -euo pipefail

if [[ "$(uname)" != "Linux" ]]; then
  echo "install-nvim.sh currently supports Linux hosts only."
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to download Neovim." >&2
  exit 1
fi

readonly url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz"
tmp_dir="$(mktemp -d)"
readonly tmp_dir
readonly archive="${tmp_dir}/nvim-linux-x86_64.tar.gz"
readonly install_root="${HOME}/.local/opt/nvim"
readonly bin_dir="${HOME}/.local/bin"
readonly install_target="${bin_dir}/nvim"

cleanup() {
  rm -rf -- "${tmp_dir}"
}
trap cleanup EXIT

printf '⬇️  Downloading Neovim release...\n'
curl -fLSo "${archive}" "${url}"

mkdir -p "$(dirname "${install_root}")" "${bin_dir}"
tar -xzf "${archive}" -C "${tmp_dir}"
extracted_dir="$(find "${tmp_dir}" -maxdepth 1 -type d -name 'nvim-linux-*' | head -n 1)"
if [[ -z "${extracted_dir}" ]]; then
  echo "Could not find extracted Neovim directory." >&2
  exit 1
fi

case "${install_root}" in
  "${HOME}/.local/opt/nvim") rm -rf -- "${install_root}" ;;
  *) echo "Refusing to replace unexpected install root: ${install_root}" >&2; exit 1 ;;
esac

mv "${extracted_dir}" "${install_root}"
ln -sfn "${install_root}/bin/nvim" "${install_target}"

printf '✅ Neovim installed to %s\n' "${install_target}"
"${install_target}" --version | head -n 1
