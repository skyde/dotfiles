#!/usr/bin/env bash
set -euo pipefail

if [[ $(uname -s) != Linux ]]; then
  printf 'nvim Linux dependency test skipped outside Linux\n'
  exit 0
fi

script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
installer=$repo_root/init-linux.sh

required_packages=(build-essential cmake curl file ninja-build nodejs npm python3 python3-venv unzip)
test_root=$(mktemp -d /tmp/nvim-linux-dependencies.XXXXXXXX)
cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

dependency_log=$test_root/ensure-apt.log
DOTFILES_INIT_LINUX_DEPENDENCY_TEST=1 \
  DOTFILES_INIT_LINUX_DEPENDENCY_LOG=$dependency_log \
  bash "$installer" >/dev/null
mapfile -t installed_packages <"$dependency_log"
if [[ ${installed_packages[*]} != "${required_packages[*]}" ]]; then
  printf 'error: init-linux.sh requested unexpected Neovim dependencies\n' >&2
  printf 'expected: %s\nactual:   %s\n' "${required_packages[*]}" "${installed_packages[*]}" >&2
  exit 1
fi

required_commands=(cc cmake curl file make ninja node npm python3 unzip)
for command_name in "${required_commands[@]}"; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'error: required Neovim runtime command is unavailable: %s\n' "$command_name" >&2
    exit 1
  fi
done

venv_root=$test_root/venv
python3 -m venv "$venv_root"
"$venv_root/bin/python" -c 'import sys; assert sys.prefix != sys.base_prefix'

printf 'nvim Linux dependency tests passed\n'
