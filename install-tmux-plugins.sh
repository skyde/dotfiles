#!/usr/bin/env bash
set -euo pipefail

TPM_REPO="https://github.com/tmux-plugins/tpm"
TPM_DIR="${HOME}/.tmux/plugins/tpm"

log() {
  printf '[tmux-plugins] %s\n' "$1"
}

ensure_tpm() {
  if [ -d "$TPM_DIR/.git" ]; then
    log "Updating TPM in $TPM_DIR"
    git -C "$TPM_DIR" pull --ff-only
  else
    log "Installing TPM to $TPM_DIR"
    mkdir -p "$(dirname "$TPM_DIR")"
    git clone "$TPM_REPO" "$TPM_DIR"
  fi
}

install_plugins() {
  if ! command -v tmux >/dev/null 2>&1; then
    log "tmux is not available; skipping plugin installation"
    return 0
  fi

  local installer="$TPM_DIR/bin/install_plugins"
  if [ -x "$installer" ]; then
    log "Installing plugins via TPM"
    "$installer"
  else
    log "TPM installer not found at $installer"
  fi
}

ensure_tpm
install_plugins

log "Done"
