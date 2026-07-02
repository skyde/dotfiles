#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
lua_file="$(mktemp)"
trap 'rm -rf "$tmp"; rm -f "$lua_file"' EXIT
nvim_path="$(command -v nvim)"

mkdir -p \
  "$tmp/path-bin" \
  "$tmp/path-home" \
  "$tmp/local-home/.local/bin" \
  "$tmp/repo-home/dotfiles/common/.local/bin" \
  "$tmp/tmux-bin" \
  "$tmp/windows-bin"

cat >"$tmp/tmux-bin/tmux" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "display-message" && "${2:-}" == "-p" ]]; then
  if [[ "${NVIM_CLIPBOARD_TMUX_FAIL:-0}" != "0" ]]; then
    exit "$NVIM_CLIPBOARD_TMUX_FAIL"
  fi
  printf '%%1\n'
  exit 0
fi

printf 'unexpected tmux command: %s\n' "$*" >&2
exit 2
SH
chmod +x "$tmp/tmux-bin/tmux"

write_helpers() {
  local dir="$1"

  cat >"$dir/osc-copy" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
SH
  chmod +x "$dir/osc-copy"

  cat >"$dir/osc-paste" <<'SH'
#!/usr/bin/env bash
printf 'paste'
SH
  chmod +x "$dir/osc-paste"
}

write_helpers "$tmp/path-bin"
write_helpers "$tmp/local-home/.local/bin"
write_helpers "$tmp/repo-home/dotfiles/common/.local/bin"

cat >"$tmp/windows-bin/win32yank.exe" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
SH
chmod +x "$tmp/windows-bin/win32yank.exe"

cat >"$lua_file" <<'LUA'
local root = assert(os.getenv("DOTFILES_ROOT"))
local helper_dir = assert(os.getenv("HELPER_DIR"))
local case_name = assert(os.getenv("CASE_NAME"))
local expect_provider = os.getenv("EXPECT_PROVIDER") ~= "0"
local expected_provider_name = os.getenv("EXPECTED_PROVIDER_NAME") or "osc-copy/osc-paste"
local uv = vim.uv or vim.loop

local function normalize(path)
  return uv.fs_realpath(path) or path
end

vim.env.TMUX = "fake"
local function env_value(name)
  local value = os.getenv(name) or ""
  if value == "__EMPTY__" then
    return ""
  end
  return value ~= "" and value or nil
end

vim.env.SSH_CLIENT = env_value("NVIM_CLIPBOARD_SSH_CLIENT")
vim.env.SSH_TTY = env_value("NVIM_CLIPBOARD_SSH_TTY")
vim.env.SSH_CONNECTION = env_value("NVIM_CLIPBOARD_SSH_CONNECTION")

if os.getenv("NVIM_CLIPBOARD_WINDOWS") == "1" then
  local original_has = vim.fn.has
  vim.fn.has = function(feature)
    if feature == "win32" then
      return 1
    end
    if feature == "win64" or feature == "win32unix" then
      return 0
    end
    return original_has(feature)
  end
end

if os.getenv("NVIM_CLIPBOARD_EXECUTABLE_ERROR") == "1" then
  vim.fn.executable = function()
    error("forced executable failure")
  end
end

if os.getenv("NVIM_CLIPBOARD_SYSTEM_ERROR") == "1" then
  vim.fn.system = function()
    error("forced system failure")
  end
end

if os.getenv("NVIM_CLIPBOARD_EXEPATH_ERROR") == "1" then
  vim.fn.exepath = function()
    error("forced exepath failure")
  end
end

dofile(root .. "/common/.config/nvim/lua/config/options.lua")

local clipboard = vim.g.clipboard
if not expect_provider then
  assert(clipboard == nil, "clipboard provider should not be configured for stale TMUX")
  print("nvim-clipboard-provider-" .. case_name .. "-ok")
  return
end

assert(type(clipboard) == "table", "clipboard provider not configured")
assert(clipboard.name == expected_provider_name, "unexpected clipboard provider " .. tostring(clipboard.name))
if expected_provider_name ~= "osc-copy/osc-paste" then
  print("nvim-clipboard-provider-" .. case_name .. "-ok")
  return
end

assert(normalize(clipboard.copy["+"][1]) == normalize(helper_dir .. "/osc-copy"), "wrong + copy helper")
assert(normalize(clipboard.copy["*"][1]) == normalize(helper_dir .. "/osc-copy"), "wrong * copy helper")
assert(normalize(clipboard.paste["+"][1]) == normalize(helper_dir .. "/osc-paste"), "wrong + paste helper")
assert(normalize(clipboard.paste["*"][1]) == normalize(helper_dir .. "/osc-paste"), "wrong * paste helper")
assert(clipboard.cache_enabled == 0, "clipboard cache should be disabled for helper provider")

print("nvim-clipboard-provider-" .. case_name .. "-ok")
LUA

run_provider_case() {
  local name="$1"
  local home="$2"
  local helper_dir="$3"
  local path_value="$4"
  local expect_provider="${5:-1}"
  local tmux_fail="${6:-0}"
  local ssh_client="${7:-}"
  local ssh_tty="${8:-}"
  local ssh_connection="${9:-}"
  local executable_error="${10:-0}"
  local system_error="${11:-0}"
  local exepath_error="${12:-0}"
  local expected_provider_name="${13:-osc-copy/osc-paste}"
  local windows="${14:-0}"

  CASE_NAME="$name" \
    DOTFILES_ROOT="$root" \
    HELPER_DIR="$helper_dir" \
    EXPECT_PROVIDER="$expect_provider" \
    NVIM_CLIPBOARD_TMUX_FAIL="$tmux_fail" \
    NVIM_CLIPBOARD_SSH_CLIENT="$ssh_client" \
    NVIM_CLIPBOARD_SSH_TTY="$ssh_tty" \
    NVIM_CLIPBOARD_SSH_CONNECTION="$ssh_connection" \
    NVIM_CLIPBOARD_EXECUTABLE_ERROR="$executable_error" \
    NVIM_CLIPBOARD_SYSTEM_ERROR="$system_error" \
    NVIM_CLIPBOARD_EXEPATH_ERROR="$exepath_error" \
    NVIM_CLIPBOARD_WINDOWS="$windows" \
    EXPECTED_PROVIDER_NAME="$expected_provider_name" \
    HOME="$home" \
    PATH="$path_value" \
    "$nvim_path" --headless -n -i NONE -u NONE -l "$lua_file"
}

system_path="/usr/bin:/bin:/usr/sbin:/sbin"

run_provider_case path "$tmp/path-home" "$tmp/path-bin" "$tmp/path-bin:$tmp/tmux-bin:$system_path"
run_provider_case home-local "$tmp/local-home" "$tmp/local-home/.local/bin" "$tmp/path-bin:$tmp/tmux-bin:$system_path"
run_provider_case home-dotfiles "$tmp/repo-home" "$tmp/repo-home/dotfiles/common/.local/bin" "$tmp/path-bin:$tmp/tmux-bin:$system_path"
run_provider_case stale-tmux "$tmp/path-home" "$tmp/path-bin" "$tmp/path-bin:$tmp/tmux-bin:$system_path" 0 1
run_provider_case tmux-executable-error "$tmp/path-home" "$tmp/path-bin" "$tmp/path-bin:$tmp/tmux-bin:$system_path" 0 0 "" "" "" 1
run_provider_case tmux-system-error "$tmp/path-home" "$tmp/path-bin" "$tmp/path-bin:$tmp/tmux-bin:$system_path" 0 0 "" "" "" 0 1
run_provider_case ssh-helper-executable-error "$tmp/path-home" "$tmp/path-bin" "$tmp/tmux-bin:$system_path" 1 1 "127.0.0.1 1000 22" "" "" 1 0 0 "OSC 52"
run_provider_case ssh-helper-exepath-error "$tmp/path-home" "$tmp/path-bin" "$tmp/tmux-bin:$system_path" 1 1 "127.0.0.1 1000 22" "" "" 0 0 1 "OSC 52"
run_provider_case ssh-stale-tmux "$tmp/path-home" "$tmp/path-bin" "$tmp/path-bin:$tmp/tmux-bin:$system_path" 1 1 "127.0.0.1 1000 22"
run_provider_case empty-ssh-stale-tmux "$tmp/path-home" "$tmp/path-bin" "$tmp/path-bin:$tmp/tmux-bin:$system_path" 0 1 "__EMPTY__" "__EMPTY__" "__EMPTY__"
run_provider_case windows-win32yank "$tmp/path-home" "$tmp/windows-bin" "$tmp/windows-bin:$tmp/tmux-bin:$system_path" 1 1 "__EMPTY__" "__EMPTY__" "__EMPTY__" 0 0 0 "win32yank-lf" 1
run_provider_case windows-missing-win32yank "$tmp/path-home" "$tmp/path-bin" "$tmp/tmux-bin:$system_path" 0 1 "__EMPTY__" "__EMPTY__" "__EMPTY__" 0 0 0 "osc-copy/osc-paste" 1
