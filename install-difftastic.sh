#!/usr/bin/env bash
# Install the latest difftastic release into ~/.local/bin.
#
#   ./install-difftastic.sh                      # latest release
#   DIFFTASTIC_VERSION=0.65.0 ./install-difftastic.sh  # a specific tag
#
# difftastic is the structural diff: it parses both sides and diffs the syntax
# trees, so it can tell a reindent or a moved block from a rewrite. lazygit
# cycles to it with `|` (see the `diffRenderers` list in
# common/.config/lazygit/config.yml), and `git dft` uses it from the shell.
# Neither is fatal without it — lazygit just shows "difft: not found" in the
# diff panel when cycled that far — but both are configured expecting it.
#
# Not installed through packages.txt because apt only ships difftastic on
# recent releases, and one unknown name fails the whole apt transaction.
set -euo pipefail

for tool in curl tar; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "${tool} is required to install difftastic." >&2
    exit 1
  fi
done

readonly repo="Wilfred/difftastic"

case "$(uname -s)" in
Linux) readonly platform="unknown-linux-gnu" ;;
Darwin) readonly platform="apple-darwin" ;;
*)
  echo "install-difftastic.sh supports Linux and macOS only; install difftastic manually."
  exit 0
  ;;
esac

case "$(uname -m)" in
x86_64 | amd64) readonly arch="x86_64" ;;
aarch64 | arm64) readonly arch="aarch64" ;;
*)
  echo "Unsupported architecture: $(uname -m)" >&2
  exit 1
  ;;
esac

readonly asset="difft-${arch}-${platform}.tar.gz"

asset_url() { printf 'https://github.com/%s/releases/download/%s/%s\n' "$repo" "$1" "$asset"; }

# Candidate tags, newest first. The API first, then the tag list over plain
# git, which is the one that survives networks blocking the API. difftastic's
# tags carry no `v` prefix.
candidate_tags() {
  curl -fsSL "https://api.github.com/repos/${repo}/releases" 2>/dev/null |
    sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]\+\)".*/\1/p'

  if command -v git >/dev/null 2>&1; then
    git ls-remote --tags --refs --sort=-v:refname "https://github.com/${repo}" '[0-9]*' 2>/dev/null |
      sed -n 's#.*refs/tags/##p'
  fi
}

# Not every difftastic release ships binaries — 0.70.0 has source archives only
# — so "newest tag" is not the same question as "newest tag we can install".
# Ask about the asset itself, walking back until one exists.
newest_release_with_binaries() {
  local tag seen=""
  while read -r tag; do
    [[ -z "$tag" ]] && continue
    case " $seen " in *" $tag "*) continue ;; esac
    seen+=" $tag"
    if curl -fsSLI -o /dev/null --max-time 20 "$(asset_url "$tag")" 2>/dev/null; then
      printf '%s\n' "$tag"
      return 0
    fi
    # Ten is well past the point where the answer is "the release process
    # changed", and worth failing loudly over instead of scanning history.
    [[ "$(printf '%s' "$seen" | wc -w)" -ge 10 ]] && break
  done < <(candidate_tags)
  return 1
}

version="${DIFFTASTIC_VERSION:-}"
if [[ -z "$version" ]]; then
  if ! version="$(newest_release_with_binaries)"; then
    echo "Could not find a difftastic release with a ${asset} binary; set DIFFTASTIC_VERSION and retry." >&2
    exit 1
  fi
fi
readonly version

readonly install_dir="${HOME}/.local/bin"
readonly install_target="${install_dir}/difft"
url="$(asset_url "$version")"
readonly url

if [[ -x "$install_target" ]] &&
  "$install_target" --version 2>/dev/null | grep -qi "difftastic ${version}"; then
  printf '✅ difftastic %s already installed at %s\n' "$version" "$install_target"
  exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

printf '⬇️  Downloading difftastic %s...\n' "$version"
curl -fLSo "${tmp_dir}/difft.tar.gz" "$url"
tar -xzf "${tmp_dir}/difft.tar.gz" -C "$tmp_dir" difft

mkdir -p "$install_dir"
install -m 755 "${tmp_dir}/difft" "$install_target"

printf '✅ difftastic %s installed to %s\n' "$version" "$install_target"
