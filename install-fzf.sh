#!/usr/bin/env bash
# Install the latest fzf release into ~/.local/bin.
#
#   ./install-fzf.sh                      # latest release
#   FZF_VERSION=v0.65.0 ./install-fzf.sh  # a specific tag
#
# Distro packages are far behind, and fzf refuses to start when given an option
# it does not know — so an old one does not degrade, it fails. Ubuntu 24.04 ships
# 0.44, which lacks:
#
#   --style      (0.54)  the minimal look in ~/.config/shell/theme.sh
#   --wrap       (0.53)  wrapped entries in the Ctrl-R picker
#   --tmux       (0.53)  the popups used by tmux-fzf-url.sh and the download picker
#   --tiebreak=pathname  (0.53)  ff's ranking
#
# The shell config and those scripts all check the version and leave the flags
# out when they are not supported, so nothing breaks without this — you just get
# a plainer picker. Installing a current fzf is how you get the rest.
set -euo pipefail

for tool in curl tar; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "${tool} is required to install fzf." >&2
    exit 1
  fi
done

readonly repo="junegunn/fzf"

case "$(uname -s)" in
Linux) readonly os="linux" ;;
Darwin) readonly os="darwin" ;;
*)
  echo "install-fzf.sh supports Linux and macOS only; install fzf manually."
  exit 0
  ;;
esac

case "$(uname -m)" in
x86_64 | amd64) readonly arch="amd64" ;;
aarch64 | arm64) readonly arch="arm64" ;;
armv7l) readonly arch="armv7" ;;
*)
  echo "Unsupported architecture: $(uname -m)" >&2
  exit 1
  ;;
esac

# Release assets embed the version in their name, so the tag has to be resolved
# first. Try the API, then the redirect on /releases/latest, then the tag list —
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

version="${FZF_VERSION:-}"
if [[ -z "$version" ]]; then
  if ! version="$(latest_tag)"; then
    echo "Could not determine the latest fzf release; set FZF_VERSION and retry." >&2
    exit 1
  fi
fi
readonly version
readonly plain_version="${version#v}"

readonly install_dir="${HOME}/.local/bin"
readonly install_target="${install_dir}/fzf"
readonly url="https://github.com/${repo}/releases/download/${version}/fzf-${plain_version}-${os}_${arch}.tar.gz"

if [[ -x "$install_target" ]] &&
  "$install_target" --version 2>/dev/null | grep -q "^${plain_version}"; then
  printf '✅ fzf %s already installed at %s\n' "$version" "$install_target"
  exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

printf '⬇️  Downloading fzf %s...\n' "$version"
curl -fLSo "${tmp_dir}/fzf.tar.gz" "$url"
tar -xzf "${tmp_dir}/fzf.tar.gz" -C "$tmp_dir" fzf

mkdir -p "$install_dir"
install -m 755 "${tmp_dir}/fzf" "$install_target"

printf '✅ fzf %s installed to %s\n' "$version" "$install_target"

# The shell caches what `fzf --version` said, keyed on the binary's timestamp, so
# a new shell picks the new options up on its own. Say so, because the current
# shell will not change under you.
printf 'ℹ️  Open a new shell for the pickers to use the new options.\n'
