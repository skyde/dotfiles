#!/usr/bin/env bash
# Install the latest lazygit release into ~/.local/bin.
#
#   ./install-lazygit.sh                          # latest release
#   LAZYGIT_VERSION=v0.54.2 ./install-lazygit.sh  # a specific tag
#
# Neovim drives lazygit through snacks (<leader>gg and the source-control
# pickers), and the config in common/.config/lazygit/config.yml uses recent
# options, so the distro package (often missing or years old) is not enough.
set -euo pipefail

for tool in curl tar; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "${tool} is required to install lazygit." >&2
    exit 1
  fi
done

readonly repo="jesseduffield/lazygit"

case "$(uname -s)" in
Linux) readonly os="Linux" ;;
Darwin) readonly os="Darwin" ;;
*)
  echo "install-lazygit.sh supports Linux and macOS only; install lazygit manually."
  exit 0
  ;;
esac

case "$(uname -m)" in
x86_64 | amd64) readonly arch="x86_64" ;;
aarch64 | arm64) readonly arch="arm64" ;;
armv7l) readonly arch="armv6" ;;
*)
  echo "Unsupported architecture: $(uname -m)" >&2
  exit 1
  ;;
esac

# Release assets embed the version in their name, so the tag has to be resolved
# first. Try the API, then the redirect on /releases/latest, then the tag list -
# the last one only needs git and survives networks that block the API.
latest_tag() {
  local tag

  tag="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null |
    sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]\+\)".*/\1/p' | head -n 1)"
  if [[ -n "$tag" ]]; then
    printf '%s\n' "$tag"
    return 0
  fi

  tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/${repo}/releases/latest" 2>/dev/null |
    sed -n 's#.*/tag/\(.*\)$#\1#p')"
  if [[ -n "$tag" ]]; then
    printf '%s\n' "$tag"
    return 0
  fi

  if command -v git >/dev/null 2>&1; then
    tag="$(git ls-remote --tags --refs --sort=-v:refname "https://github.com/${repo}" 'v[0-9]*' 2>/dev/null |
      sed -n 's#.*refs/tags/##p' | head -n 1)"
    if [[ -n "$tag" ]]; then
      printf '%s\n' "$tag"
      return 0
    fi
  fi

  return 1
}

version="${LAZYGIT_VERSION:-}"
if [[ -z "$version" ]]; then
  if ! version="$(latest_tag)"; then
    echo "Could not determine the latest lazygit release; set LAZYGIT_VERSION and retry." >&2
    exit 1
  fi
fi
readonly version
readonly plain_version="${version#v}"

readonly install_dir="${HOME}/.local/bin"
readonly install_target="${install_dir}/lazygit"
readonly url="https://github.com/${repo}/releases/download/${version}/lazygit_${plain_version}_${os}_${arch}.tar.gz"

if [[ -x "$install_target" ]] &&
  "$install_target" --version 2>/dev/null | grep -q "version=${plain_version}"; then
  printf '✅ lazygit %s already installed at %s\n' "$version" "$install_target"
  exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

printf '⬇️  Downloading lazygit %s...\n' "$version"
curl -fLSo "${tmp_dir}/lazygit.tar.gz" "$url"
tar -xzf "${tmp_dir}/lazygit.tar.gz" -C "$tmp_dir" lazygit

mkdir -p "$install_dir"
install -m 755 "${tmp_dir}/lazygit" "$install_target"

printf '✅ lazygit %s installed to %s\n' "$version" "$install_target"
