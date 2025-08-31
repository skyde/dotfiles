#!/usr/bin/env bash
set -euo pipefail
discover_pkgs() { for p in $(find "$DOT_REPO/stow" -mindepth 1 -maxdepth 1 -type d -print | sed 's#.*/##' | sort); do case "$DOT_OS" in darwin) case "$p" in vsvim|vscode-linux) continue;; esac ;; linux) case "$p" in vsvim|macos|hammerspoon|vscode-macos) continue;; esac ;; esac; echo "$p"; done; }
if [ -n "${DOT_PACKAGES:-}" ]; then pkgs=( ${DOT_PACKAGES} ); else pkgs=( $(discover_pkgs) ); fi
echo "[stow-restow] os=$DOT_OS target=$DOT_TARGET packages: ${pkgs[*]}"
stow -d "$DOT_REPO/stow" -t "$DOT_TARGET" -R "${pkgs[@]}"
