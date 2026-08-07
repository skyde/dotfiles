#!/usr/bin/env bash
# Validate common/.config/lazygit/config.yml against the lazygit that is
# actually installed.
#
# lazygit ignores configuration it does not understand — a key that moved
# between releases, sits at the wrong nesting level, or is misspelled produces
# no error, the feature just stops happening. This catches that.
#
#   ./tests/check-lazygit-config.sh            # check
#   ./tests/check-lazygit-config.sh --strict   # also fail on warnings
#
# Two levels of checking, picked automatically:
#   * against lazygit's published JSON schema for the installed version (types
#     and enum values included); downloaded once into the cache directory
#   * offline, against `lazygit --config`, which lists every key the binary
#     knows about
set -euo pipefail

cd "$(dirname "$0")/.."

readonly config="common/.config/lazygit/config.yml"
readonly checker="tests/lazygit_config_check.py"
readonly cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"

if ! command -v python3 >/dev/null 2>&1; then
  echo "⏭️  python3 not found; skipping the lazygit config check."
  exit 0
fi

lazygit_bin="$(command -v lazygit || true)"
if [[ -z "$lazygit_bin" && -x "$HOME/.local/bin/lazygit" ]]; then
  lazygit_bin="$HOME/.local/bin/lazygit"
fi
if [[ -z "$lazygit_bin" ]]; then
  echo "⏭️  lazygit not installed; skipping (run ./install-lazygit.sh)."
  exit 0
fi

# version=0.64.0 in a comma-separated banner
version="$("$lazygit_bin" --version 2>/dev/null | tr ',' '\n' |
  sed -n 's/^ *version=//p' | head -n 1)"
if [[ -z "$version" ]]; then
  echo "❌ could not read the version from ${lazygit_bin} --version" >&2
  exit 1
fi
echo "🔍 checking ${config} against lazygit ${version}"

# 0.64 renamed the custom-pager settings (git.pagers -> git.diffRenderers) and
# this config uses the new shape. On an older binary every 0.64 key reads as
# unknown, so say the one useful thing instead of listing them all.
readonly minimum="0.64.0"
if [[ "$(printf '%s\n%s\n' "$minimum" "$version" | sort -V | head -n 1)" != "$minimum" ]]; then
  echo "❌ this config targets lazygit ${minimum}+, but ${lazygit_bin} is ${version}." >&2
  echo "   Run ./install-lazygit.sh to update." >&2
  exit 1
fi

defaults="$(mktemp)"
trap 'rm -f "$defaults"' EXIT
# --config prints the defaults for the *installed* binary, so this is the
# authoritative list of keys it will act on. It is not affected by the user's
# own config file.
"$lazygit_bin" --config >"$defaults"

# The schema is generated from the same structs lazygit parses configs with,
# and is published per release. Cache it per version: it never changes for a
# given tag, and this way the check keeps working offline afterwards.
schema="${LAZYGIT_CONFIG_SCHEMA:-}"
if [[ -z "$schema" ]]; then
  schema="${cache_dir}/lazygit-config-schema-${version}.json"
  if [[ ! -s "$schema" ]]; then
    mkdir -p "$cache_dir"
    url="https://raw.githubusercontent.com/jesseduffield/lazygit/v${version}/schema/config.json"
    if ! curl -fsSL --max-time 15 -o "${schema}.tmp" "$url" 2>/dev/null; then
      rm -f "${schema}.tmp"
      schema=""
    else
      mv "${schema}.tmp" "$schema"
    fi
  fi
fi

args=(--defaults "$defaults")
if [[ -n "$schema" && -s "$schema" ]]; then
  args+=(--schema "$schema")
else
  echo "ℹ️  schema unavailable (offline?); falling back to the key check"
fi

# A checker that has quietly stopped checking passes every config, so prove it
# still rejects known-bad ones before trusting it on the real file.
python3 "$checker" --selftest "${args[@]}"
python3 "$checker" --config "$config" "${args[@]}" "$@"
