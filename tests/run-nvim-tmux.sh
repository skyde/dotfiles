#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

pass() {
  printf 'ok - %s\n' "$1"
}

skip() {
  printf 'skip - %s\n' "$1"
}

run_if_available() {
  local command_name="$1"
  local description="$2"
  shift 2

  if command -v "$command_name" >/dev/null 2>&1; then
    "$@"
    pass "$description"
  else
    skip "$description ($command_name unavailable)"
  fi
}

lua_paths=(
  common/.config/nvim/init.lua
  common/.config/nvim/lua
)

shell_files=(
  tests/apply-sh.sh
  tests/bashrc-custom.sh
  tests/copy-clipboard-wrappers.sh
  tests/copy-download-command.sh
  tests/dotfiles-run.sh
  tests/kill-tmux.sh
  tests/keybinding-docs.sh
  tests/lazygit-clipboard.sh
  tests/nvim-clipboard-provider.sh
  tests/nvim-config-smoke.sh
  tests/osc-clipboard.sh
  tests/platform-helper.sh
  tests/project-markers-consistency.sh
  tests/search-tools.sh
  tests/tmux-env-edge-cases.sh
  tests/tmux-copy-helper.sh
  tests/tmux-fzf-switch-session.sh
  tests/tmux-fzf-url.sh
  tests/tmux-fzf-url-helper.sh
  tests/tmux-fzf-url-preview.sh
  tests/tmux-open-helper.sh
  tests/tmux-nvim-keys.sh
  tests/tmux-navigation.sh
  tests/tmux-pane-should-passthrough.sh
  tests/tmux-passthrough-consistency.sh
  tests/tmux-paste-helper.sh
  tests/tmux-popup-tool.sh
  tests/tmux-session-notify.sh
  tests/tmux-session-name.sh
  tests/tmux-session.sh
  tests/tmux-status-name.sh
  tests/vscode-tasks-jsonc.sh
  tests/yazi-wrapper.sh
  tests/zshenv.sh
  tests/zsh-file-managers.sh
  tests/zsh-fzf-ctrl-r.sh
  common/.bashrc-custom
  common/.local/bin/tmux-fzf-url.sh
  common/.local/bin/tmux-fzf-url-preview.sh
  common/.local/bin/tmux-open-helper.sh
  common/.local/bin/tmux-session
  common/.local/bin/tmux-copy-helper
  common/.local/bin/tmux-paste-helper
  common/.local/bin/tmux-popup-tool
  common/.local/bin/tmux-pane-key-router
  common/.local/bin/tmux-session-notify
  common/.local/bin/tmux-session-name
  common/.local/bin/tmux-session-default-layout
  common/.local/bin/tmux-pane-should-passthrough
  common/.local/bin/tmux-status-name.sh
  common/.local/bin/tmux-fzf-switch-session
  common/.local/bin/dotfiles-run
  common/.local/bin/kill-tmux
  common/.local/bin/osc-copy
  common/.local/bin/osc-paste
  common/.local/bin/copy-diff
  common/.local/bin/copy-download-command
  common/.local/bin/git-copy
  common/.local/bin/si
  common/.local/bin/st
  common/.local/bin/st-rg
  common/.local/bin/st-zoekt
  common/.local/bin/yazi
  apply.sh
  test-all-platforms.sh
)

test_scripts=(
  tests/apply-sh.sh
  tests/bashrc-custom.sh
  tests/copy-clipboard-wrappers.sh
  tests/copy-download-command.sh
  tests/dotfiles-run.sh
  tests/kill-tmux.sh
  tests/keybinding-docs.sh
  tests/lazygit-clipboard.sh
  tests/nvim-clipboard-provider.sh
  tests/nvim-config-smoke.sh
  tests/osc-clipboard.sh
  tests/platform-helper.sh
  tests/project-markers-consistency.sh
  tests/search-tools.sh
  tests/tmux-env-edge-cases.sh
  tests/tmux-copy-helper.sh
  tests/tmux-fzf-url.sh
  tests/tmux-fzf-url-helper.sh
  tests/tmux-open-helper.sh
  tests/tmux-fzf-url-preview.sh
  tests/tmux-nvim-keys.sh
  tests/tmux-navigation.sh
  tests/tmux-pane-should-passthrough.sh
  tests/tmux-passthrough-consistency.sh
  tests/tmux-paste-helper.sh
  tests/tmux-popup-tool.sh
  tests/tmux-session-notify.sh
  tests/tmux-session-name.sh
  tests/tmux-session.sh
  tests/tmux-fzf-switch-session.sh
  tests/tmux-status-name.sh
  tests/vscode-tasks-jsonc.sh
  tests/yazi-wrapper.sh
  tests/zshenv.sh
  tests/zsh-file-managers.sh
  tests/zsh-fzf-ctrl-r.sh
)

run_if_available stylua "stylua check" stylua --check "${lua_paths[@]}"
run_if_available shellcheck "shellcheck" shellcheck "${shell_files[@]}"

if [[ -x /bin/bash ]]; then
  /bin/bash -n "${shell_files[@]}"
  pass "macOS bash syntax check"
else
  skip "macOS bash syntax check (/bin/bash unavailable)"
fi

if command -v python3 >/dev/null 2>&1; then
  python3 - <<'PY'
from pathlib import Path

path = Path("common/.local/bin/tmux-fzf-url-helper.py")
compile(path.read_text(), str(path), "exec")
PY
  pass "python compile"
else
  skip "python compile (python3 unavailable)"
fi

for test_script in "${test_scripts[@]}"; do
  "$test_script"
done
pass "nvim/tmux smoke scripts"

git diff --check
pass "git diff whitespace check"

if command -v tmux >/dev/null 2>&1; then
  tmux -L "dotfiles-check-$$" -f common/.tmux.conf start-server \; \
    source-file common/.tmux.conf \; \
    display-message 'tmux-config-ok' \; \
    kill-server
  pass "tmux config parse"
else
  skip "tmux config parse (tmux unavailable)"
fi

if command -v nvim >/dev/null 2>&1; then
  nvim --headless -n '+lua require("lazy"); print("nvim-live-config-ok")' +qa
  printf '\n'
  pass "live nvim startup"
else
  skip "live nvim startup (nvim unavailable)"
fi
