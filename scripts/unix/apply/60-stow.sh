#!/usr/bin/env bash
set -euo pipefail
log() { echo "[stow] $*"; }

discover_pkgs() {
  local dir="$DOT_REPO/stow"; [ -d "$dir" ] || return 0
  local p
  for p in $(find "$dir" -mindepth 1 -maxdepth 1 -type d -print | sed 's#.*/##' | sort); do
    case "$DOT_OS" in
      darwin) case "$p" in vsvim|vscode-linux) continue;; esac ;;
      linux)  case "$p" in vsvim|macos|hammerspoon|vscode-macos) continue;; esac ;;
    esac
    echo "$p"
  done
}

backup_conflicts() {
  local tmp tgt abs ts pkg
  for pkg in "$@"; do
    tmp="$(mktemp)" || exit 1
    stow -n -v -d "$DOT_REPO/stow" -t "$DOT_TARGET" -S "$pkg" >"$tmp" 2>&1 || true
    while IFS= read -r line; do
      case "$line" in
        *'existing target is not owned by stow:'*) tgt="${line##*: }" ;;
        *'cannot stow '*' over existing target '*' since'*) tgt="${line#*over existing target }"; tgt="${tgt%% since*}" ;;
        *) tgt="" ;;
      esac
      [ -z "$tgt" ] && continue
      case "$tgt" in /*) abs="$tgt" ;; *) abs="$DOT_TARGET/$tgt" ;; esac
      if [ -z "${DOT_DRYRUN:-}" ] && { [ -e "$abs" ] || [ -L "$abs" ]; }; then
        ts="$(date +%Y%m%d%H%M%S)"
        mv "$abs" "$abs.pre-stow.$ts" 2>/dev/null || true
        log "Backed up conflict: $abs -> $abs.pre-stow.$ts"
      fi
    done <"$tmp"
    rm -f "$tmp"
  done
}

if [ -n "${DOT_PACKAGES:-}" ]; then
  # shellcheck disable=SC2206
  pkgs=( ${DOT_PACKAGES} )
else
  pkgs=( $(discover_pkgs) )
fi
log "os=$DOT_OS target=$DOT_TARGET packages: ${pkgs[*]} (mode=${DOT_DRYRUN:+dry})"

# Ensure local bin exec perms before linking
[ -n "${DOT_DRYRUN:-}" ] || chmod +x "$DOT_REPO/stow/local-bin/.local/bin"/* 2>/dev/null || true

if [ -n "${DOT_DRYRUN:-}" ]; then
  stow -n -v -d "$DOT_REPO/stow" -t "$DOT_TARGET" -S "${pkgs[@]}"
else
  backup_conflicts "${pkgs[@]}"
  stow -d "$DOT_REPO/stow" -t "$DOT_TARGET" -S "${pkgs[@]}"
fi
