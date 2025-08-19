#!/usr/bin/env bash
set -euo pipefail

# Truthy if env var is 1/true/yes/on
_truthy() {
  case "${1:-}" in
    1|true|TRUE|True|yes|YES|Yes|on|ON|On) return 0 ;;
    *) return 1 ;;
  esac
}

have() { command -v "$1" >/dev/null 2>&1; }

# Optional: source cask->app mapping if available
if [ -f "$HOME/lib/cask_app_map.sh" ]; then
  # shellcheck disable=SC1090
  source "$HOME/lib/cask_app_map.sh"
fi

is_tty() { [ -t 0 ] && [ -t 1 ]; }

ask() {
  local prompt="$1"
  # If AUTO_INSTALL is set, auto-accept prompts
  if _truthy "${AUTO_INSTALL:-}"; then
    echo "[auto] $prompt (AUTO_INSTALL=1)"
    return 0
  fi
  if ! is_tty; then
    echo "[skip] $prompt (non-interactive; default = no)"
    return 1
  fi
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" =~ ^([yY]|[yY][eE][sS])$ ]]
}

# Core policy:
# - present (update) → proceed without asking
# - missing (install) → always ask, unless AUTO_INSTALL
confirm_change() {
  local verb="$1"
  local name="$2"
  local present="$3" # 1 or 0
  # Auto-update without prompting when already present
  if [[ "$present" -eq 1 ]]; then
    return 0
  fi
  # If AUTO_INSTALL is truthy, proceed without prompting
  if _truthy "${AUTO_INSTALL:-}"; then
    echo "[auto] $verb $name (AUTO_INSTALL=1)"
    return 0
  fi
  ask "$verb $name?"
}

# Generic ensure: pass a check, an install, and an optional update/configure action.
ensure() {
  local name="$1"; shift
  local check="$1"; shift
  local install="$1"; shift
  local update="${1:-}"
  local present=0

  if eval "$check"; then present=1; fi

  if [[ "$present" -eq 1 ]]; then
    if confirm_change "Update/configure" "$name" 1; then
      [[ -n "$update" ]] && eval "$update" || true
    fi
  else
    if confirm_change "Install" "$name" 0; then
      eval "$install"
    fi
  fi
}

# Package helpers (macOS + Debian/Ubuntu; add more if you need)
ensure_brew() {
  local pkg="$1"
  ensure "$pkg" \
    "brew list --formula --versions '$pkg' >/dev/null 2>&1" \
    "brew install '$pkg'" \
    "brew upgrade '$pkg' || true"
}

ensure_cask() {
  local cask="$1"
  local app_path=""
  local home_app_path=""
  if declare -F cask_app_paths >/dev/null 2>&1; then
    read -r app_path home_app_path < <(cask_app_paths "$cask")
  fi

  # If app bundle already exists, treat as present to avoid prompting
  if { [ -n "$app_path" ] && [ -d "$app_path" ]; } || { [ -n "$home_app_path" ] && [ -d "$home_app_path" ]; }; then
    ensure "$cask (cask)" \
      "true" \
      "brew install --cask '$cask'" \
      "brew upgrade --cask '$cask' || true"
    return
  fi

  ensure "$cask (cask)" \
    "brew list --cask --versions '$cask' >/dev/null 2>&1" \
    "brew install --cask '$cask' || brew reinstall --cask '$cask' || { echo '[warn] brew cask install failed for $cask (possibly already present in /Applications). Continuing.' >&2; true; }" \
    "brew upgrade --cask '$cask' || true"
}

ensure_apt() {
  local pkg="$1"
  local SUDO_CMD=""
  if [ "$(id -u)" -ne 0 ] && have sudo; then
    SUDO_CMD="sudo"
  fi
  ensure "$pkg" \
    "dpkg -s '$pkg' >/dev/null 2>&1" \
    "$SUDO_CMD apt-get update -y && $SUDO_CMD apt-get install -y '$pkg'" \
    "$SUDO_CMD apt-get install -y --only-upgrade '$pkg' || true"
}
