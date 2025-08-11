#!/usr/bin/env bash set -euo pipefail # Truthy if env var is 1/true/yes/on
_truthy() { case "${1:-}" in 1|true|TRUE|True|yes|YES|Yes|on|ON|On) return 0 ;;
*) return 1 ;; esac } have() { command -v "$1" >/dev/null 2>&1; } is_tty() { [
-t 0 ] && [ -t 1 ]; } ask() { local prompt="$1" if ! is_tty; then echo "[skip]
$prompt (non-interactive; default = no)" return 1 fi read -r -p "$prompt [y/N] "
reply [[ "$reply" =~ ^([yY]|[yY][eE][sS])$ ]] } # Core policy: # - present
(update) → proceed without asking # - missing (install) → always ask
confirm_change() { local verb="$1" name="$2" present="$3" # present: 1 or 0 if
[[ "$present" -eq 1 ]]; then # Auto-update without prompting return 0 fi #
Prompt for installs ask "$verb $name?" } # Generic ensure: pass a check, an
install, and an update/configure action. ensure() { local name="$1"; shift local
check="$1"; shift local install="$1"; shift local update="${1:-}"; # optional
local present=0 if eval "$check"; then present=1; fi if [[ "$present" -eq 1 ]];
then if confirm_change "Update/configure" "$name" 1; then [[ -n "$update" ]] &&
eval "$update" || true fi else if confirm_change "Install" "$name" 0; then eval
"$install" fi fi } # Package helpers (macOS + Debian/Ubuntu; add more if you
need) ensure_brew() { local pkg="$1" ensure "$pkg" \ "brew list --formula
--versions '$pkg' >/dev/null 2>&1" \ "brew install '$pkg'" \ "brew upgrade
'$pkg' || true" } ensure_cask() { local cask="$1" ensure "$cask (cask)" \ "brew
list --cask --versions '$cask' >/dev/null 2>&1" \ "brew install --cask '$cask'"
\ "brew upgrade --cask '$cask' || true" } ensure_apt() { local pkg="$1" ensure
"$pkg" \ "dpkg -s '$pkg' >/dev/null 2>&1" \ "sudo apt-get update -y && sudo
apt-get install -y '$pkg'" \ "sudo apt-get install -y --only-upgrade '$pkg' ||
true" }
