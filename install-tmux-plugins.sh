#!/usr/bin/env bash
set -euo pipefail

TPM_REPO="https://github.com/tmux-plugins/tpm"
DEFAULT_TPM_PATH="${HOME}/.tmux/plugins"
TPM_PATH="$DEFAULT_TPM_PATH"
TPM_DIR=""

log() {
  printf '[tmux-plugins] %s\n' "$1"
}

resolve_tpm_path() {
  TPM_PATH="$DEFAULT_TPM_PATH"

  if command -v tmux >/dev/null 2>&1; then
    if tmux start-server >/dev/null 2>&1; then
      local raw_path
      if raw_path=$(tmux show-environment -g TMUX_PLUGIN_MANAGER_PATH 2>/dev/null); then
        raw_path="${raw_path#TMUX_PLUGIN_MANAGER_PATH=}"
        if [ -n "$raw_path" ]; then
          TPM_PATH="$raw_path"
        fi
      else
        log "TMUX_PLUGIN_MANAGER_PATH not configured; defaulting to $TPM_PATH"
        tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "$TPM_PATH" >/dev/null 2>&1 || true
      fi
    else
      log "Unable to start tmux server to read TPM path; using default $TPM_PATH"
    fi
  fi

  export TMUX_PLUGIN_MANAGER_PATH="$TPM_PATH"
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

  tmux start-server >/dev/null 2>&1 || true

  if ! tmux show-environment -g TMUX_PLUGIN_MANAGER_PATH >/dev/null 2>&1; then
    log "TMUX_PLUGIN_MANAGER_PATH is not configured in tmux; skipping plugin installation"
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

main() {
  resolve_tpm_path
  TPM_PATH="${TPM_PATH%/}"
  if [ -z "$TPM_PATH" ]; then
    TPM_PATH="/"
  fi
  TPM_DIR="$TPM_PATH/tpm"

  ensure_tpm
  install_plugins

  log "Done"
}

main
