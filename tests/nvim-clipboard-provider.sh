#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
lua_file="$(mktemp)"
runtime_lua_file="$(mktemp)"
multiline_runtime_lua_file="$(mktemp)"
linewise_runtime_lua_file="$(mktemp)"
empty_runtime_lua_file="$(mktemp)"
live_socket=""
real_clipboard_backup=""

cleanup() {
  if [[ -n "$live_socket" ]] && command -v tmux >/dev/null 2>&1; then
    tmux -L "$live_socket" kill-server >/dev/null 2>&1 || true
  fi
  if [[ -n "$real_clipboard_backup" && -f "$real_clipboard_backup" ]] &&
    command -v pbcopy >/dev/null 2>&1; then
    pbcopy <"$real_clipboard_backup" || true
  fi
  rm -rf "$tmp"
  rm -f "$lua_file" "$runtime_lua_file" "$multiline_runtime_lua_file" "$linewise_runtime_lua_file" "$empty_runtime_lua_file"
}
trap cleanup EXIT
nvim_path="$(command -v nvim)"

mkdir -p \
  "$tmp/path-bin" \
  "$tmp/copy-only-bin" \
  "$tmp/paste-only-bin" \
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
if [[ -n "${NVIM_CLIPBOARD_COPY_APPEND_LOG:-}" ]]; then
  {
    printf '%s\n' '---copy---'
    cat
  } >>"$NVIM_CLIPBOARD_COPY_APPEND_LOG"
elif [[ -n "${NVIM_CLIPBOARD_COPY_LOG:-}" ]]; then
  cat >"$NVIM_CLIPBOARD_COPY_LOG"
else
  cat >/dev/null
fi
SH
  chmod +x "$dir/osc-copy"

  cat >"$dir/osc-paste" <<'SH'
#!/usr/bin/env bash
if [[ -n "${NVIM_CLIPBOARD_PASTE_SOURCE:-}" ]]; then
  cat "$NVIM_CLIPBOARD_PASTE_SOURCE"
else
  printf 'paste'
fi
SH
  chmod +x "$dir/osc-paste"
}

write_helpers "$tmp/path-bin"
write_helpers "$tmp/local-home/.local/bin"
write_helpers "$tmp/repo-home/dotfiles/common/.local/bin"
write_helpers "$tmp/copy-only-bin"
rm -f "$tmp/copy-only-bin/osc-paste"
write_helpers "$tmp/paste-only-bin"
rm -f "$tmp/paste-only-bin/osc-copy"

wait_for_file() {
  local path="$1"

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -s "$path" ]] && return 0
    sleep 0.1
  done

  printf 'timed out waiting for %s\n' "$path" >&2
  return 1
}

assert_files_equal() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if ! cmp -s "$expected" "$actual"; then
    printf 'not ok - %s\n' "$name" >&2
    printf 'expected bytes:\n' >&2
    od -An -tx1 "$expected" >&2
    printf 'actual bytes:\n' >&2
    od -An -tx1 "$actual" >&2
    exit 1
  fi

  printf 'ok - %s\n' "$name"
}

assert_file_absent() {
  local name="$1"
  local path="$2"

  if [[ -e "$path" ]]; then
    printf 'not ok - %s\nunexpected file: %s\n' "$name" "$path" >&2
    exit 1
  fi

  printf 'ok - %s\n' "$name"
}

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
local expected_copy_kind = os.getenv("EXPECTED_COPY_KIND")
local expected_paste_kind = os.getenv("EXPECTED_PASTE_KIND")
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

if expected_copy_kind == "" then
  expected_copy_kind = "function"
end
if expected_paste_kind == "" then
  expected_paste_kind = "function"
end

local function assert_provider(kind, provider, helper_name, label)
  if kind == "any" then
    return
  end

  if kind == "helper" then
    assert(type(provider) == "table", label .. " provider should be a helper command")
    assert(normalize(provider[1]) == normalize(helper_dir .. "/" .. helper_name), "wrong " .. label .. " helper")
    return
  end

  if kind == "function" then
    assert(type(provider) == "function", label .. " provider should be a function")
    return
  end

  error("unknown expected provider kind " .. tostring(kind))
end

assert_provider(expected_copy_kind, clipboard.copy["+"] or {}, "osc-copy", "+ copy")
assert_provider(expected_copy_kind, clipboard.copy["*"] or {}, "osc-copy", "* copy")
assert_provider(expected_paste_kind, clipboard.paste["+"] or {}, "osc-paste", "+ paste")
assert_provider(expected_paste_kind, clipboard.paste["*"] or {}, "osc-paste", "* paste")

if expected_provider_name ~= "OSC 52" then
  assert(clipboard.cache_enabled == 0, "clipboard cache should be disabled for custom provider")
end

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
  local expected_copy_kind="${15:-}"
  local expected_paste_kind="${16:-}"
  local -a env_args

  env_args=(
    "CASE_NAME=$name"
    "DOTFILES_ROOT=$root"
    "HELPER_DIR=$helper_dir"
    "EXPECT_PROVIDER=$expect_provider"
    "NVIM_CLIPBOARD_TMUX_FAIL=$tmux_fail"
    "NVIM_CLIPBOARD_SSH_CLIENT=$ssh_client"
    "NVIM_CLIPBOARD_SSH_TTY=$ssh_tty"
    "NVIM_CLIPBOARD_SSH_CONNECTION=$ssh_connection"
    "NVIM_CLIPBOARD_EXECUTABLE_ERROR=$executable_error"
    "NVIM_CLIPBOARD_SYSTEM_ERROR=$system_error"
    "NVIM_CLIPBOARD_EXEPATH_ERROR=$exepath_error"
    "NVIM_CLIPBOARD_WINDOWS=$windows"
    "EXPECTED_PROVIDER_NAME=$expected_provider_name"
    "EXPECTED_COPY_KIND=$expected_copy_kind"
    "EXPECTED_PASTE_KIND=$expected_paste_kind"
    "PATH=$path_value"
    "XDG_CACHE_HOME=$tmp/xdg-cache"
    "XDG_CONFIG_HOME=$tmp/xdg-config"
    "XDG_DATA_HOME=$tmp/xdg-data"
    "XDG_STATE_HOME=$tmp/xdg-state"
  )

  if [[ "$home" == "__UNSET__" ]]; then
    env -u HOME "${env_args[@]}" \
      "$nvim_path" --headless -n -i NONE -u NONE -l "$lua_file"
    return
  fi

  env "${env_args[@]}" "HOME=$home" \
    "$nvim_path" --headless -n -i NONE -u NONE -l "$lua_file"
}

system_path="/usr/bin:/bin:/usr/sbin:/sbin"

run_provider_case path "$tmp/path-home" "$tmp/path-bin" "$tmp/path-bin:$tmp/tmux-bin:$system_path"
run_provider_case home-unset "__UNSET__" "$tmp/path-bin" "$tmp/path-bin:$tmp/tmux-bin:$system_path"
run_provider_case home-empty "" "$tmp/path-bin" "$tmp/path-bin:$tmp/tmux-bin:$system_path"
run_provider_case copy-helper-only "$tmp/path-home" "$tmp/copy-only-bin" "$tmp/copy-only-bin:$tmp/tmux-bin:$system_path" 1 0 "" "" "" 0 0 0 "osc-copy/OSC 52" 0 "function" "function"
run_provider_case paste-helper-only "$tmp/path-home" "$tmp/paste-only-bin" "$tmp/paste-only-bin:$tmp/tmux-bin:$system_path" 1 0 "" "" "" 0 0 0 "OSC 52/osc-paste" 0 "function" "function"
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

cat >"$runtime_lua_file" <<'LUA'
local root = assert(os.getenv("DOTFILES_ROOT"))

dofile(root .. "/common/.config/nvim/lua/config/options.lua")

assert(type(vim.g.clipboard) == "table", "clipboard provider not configured")
assert(vim.g.clipboard.name == "osc-copy/osc-paste", "unexpected provider: " .. tostring(vim.g.clipboard.name))

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha", "beta" })
vim.cmd([[normal! gg"+yy]])
vim.cmd([[normal! G"+p]])
vim.cmd([[normal! 2gg"*yy]])
vim.cmd([[normal! G"*p]])

local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(lines[3] == "from paste", vim.inspect(lines))
assert(lines[4] == "from paste", vim.inspect(lines))

print("nvim-clipboard-provider-runtime-copy-paste-ok")
LUA

runtime_copy_log="$tmp/runtime-copy.log"
runtime_copy_expected="$tmp/runtime-copy.expected"
runtime_paste_source="$tmp/runtime-paste.txt"
printf '%s\nalpha\n%s\nbeta\n' '---copy---' '---copy---' >"$runtime_copy_expected"
printf 'from paste\n' >"$runtime_paste_source"

DOTFILES_ROOT="$root" \
  NVIM_CLIPBOARD_COPY_APPEND_LOG="$runtime_copy_log" \
  NVIM_CLIPBOARD_PASTE_SOURCE="$runtime_paste_source" \
  HOME="$tmp/path-home" \
  PATH="$tmp/path-bin:$tmp/tmux-bin:$system_path" \
  SSH_CLIENT="127.0.0.1 1000 22" \
  "$nvim_path" --headless -n -i NONE -u NONE -l "$runtime_lua_file"

if ! cmp -s "$runtime_copy_expected" "$runtime_copy_log"; then
  printf 'not ok - nvim clipboard runtime copy writes expected bytes\n' >&2
  printf 'expected bytes:\n' >&2
  od -An -tx1 "$runtime_copy_expected" >&2
  printf 'actual bytes:\n' >&2
  od -An -tx1 "$runtime_copy_log" >&2
  exit 1
fi
printf 'ok - nvim clipboard runtime copy writes expected bytes\n'

cat >"$multiline_runtime_lua_file" <<'LUA'
local root = assert(os.getenv("DOTFILES_ROOT"))

dofile(root .. "/common/.config/nvim/lua/config/options.lua")

assert(type(vim.g.clipboard) == "table", "clipboard provider not configured")
assert(vim.g.clipboard.name == "osc-copy/osc-paste", "unexpected provider: " .. tostring(vim.g.clipboard.name))

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "copy-one $HOME", "copy-two ; $(no)", "tail" })
vim.cmd([[normal! ggVj"+y]])

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "anchor" })
vim.cmd([[normal! gg"+p]])

local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(vim.inspect(lines) == vim.inspect({ "anchor", "paste-one $HOME", "paste-two ; $(no)" }), vim.inspect(lines))

print("nvim-clipboard-provider-multiline-runtime-copy-paste-ok")
LUA

multiline_runtime_copy_log="$tmp/multiline-runtime-copy.log"
multiline_runtime_copy_expected="$tmp/multiline-runtime-copy.expected"
multiline_runtime_paste_source="$tmp/multiline-runtime-paste.txt"
# shellcheck disable=SC2016
printf 'copy-one $HOME\ncopy-two ; $(no)\n' >"$multiline_runtime_copy_expected"
# shellcheck disable=SC2016
printf 'paste-one $HOME\npaste-two ; $(no)\n' >"$multiline_runtime_paste_source"

DOTFILES_ROOT="$root" \
  NVIM_CLIPBOARD_COPY_LOG="$multiline_runtime_copy_log" \
  NVIM_CLIPBOARD_PASTE_SOURCE="$multiline_runtime_paste_source" \
  HOME="$tmp/path-home" \
  PATH="$tmp/path-bin:$tmp/tmux-bin:$system_path" \
  SSH_CLIENT="127.0.0.1 1000 22" \
  "$nvim_path" --headless -n -i NONE -u NONE -l "$multiline_runtime_lua_file"

assert_files_equal "nvim clipboard multiline runtime copy writes exact bytes" \
  "$multiline_runtime_copy_expected" \
  "$multiline_runtime_copy_log"

cat >"$linewise_runtime_lua_file" <<'LUA'
local root = assert(os.getenv("DOTFILES_ROOT"))
local paste_source = assert(os.getenv("NVIM_CLIPBOARD_PASTE_SOURCE"))

dofile(root .. "/common/.config/nvim/lua/config/options.lua")

assert(type(vim.g.clipboard) == "table", "clipboard provider not configured")
assert(vim.g.clipboard.name == "osc-copy/osc-paste", "unexpected provider: " .. tostring(vim.g.clipboard.name))

local function write_clipboard_bytes(text)
  local file = assert(io.open(paste_source, "wb"))
  file:write(text)
  file:close()
end

local function assert_lines(label, expected)
  local actual = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  assert(vim.inspect(actual) == vim.inspect(expected), label .. ": " .. vim.inspect(actual))
end

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha", "beta" })
vim.cmd([[normal! ggyyp]])
assert_lines("unnamed linewise yyp", { "alpha", "alpha", "beta" })

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "plus one", "plus two" })
vim.cmd([[normal! gg"+yy"+p]])
assert_lines("explicit plus linewise paste", { "plus one", "plus one", "plus two" })

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc" })
vim.cmd([[normal! gg0ylp]])
assert_lines("characterwise ylp", { "aabc" })

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "visual one", "visual two", "tail" })
vim.cmd([[normal! ggVjyGp]])
assert_lines("visual linewise paste", { "visual one", "visual two", "tail", "visual one", "visual two" })

write_clipboard_bytes("external")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "ab" })
vim.cmd([[normal! gg0p]])
assert_lines("external characterwise paste stays characterwise", { "aexternalb" })

write_clipboard_bytes("external line\n")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "anchor" })
vim.cmd([[normal! gg0p]])
assert_lines("external newline paste keeps helper bytes", { "anchor", "external line" })

print("nvim-clipboard-provider-linewise-runtime-copy-paste-ok")
LUA

linewise_runtime_clipboard="$tmp/linewise-runtime-clipboard.txt"
: >"$linewise_runtime_clipboard"
DOTFILES_ROOT="$root" \
  NVIM_CLIPBOARD_COPY_LOG="$linewise_runtime_clipboard" \
  NVIM_CLIPBOARD_PASTE_SOURCE="$linewise_runtime_clipboard" \
  HOME="$tmp/path-home" \
  PATH="$tmp/path-bin:$tmp/tmux-bin:$system_path" \
  SSH_CLIENT="127.0.0.1 1000 22" \
  "$nvim_path" --headless -n -i NONE -u NONE -l "$linewise_runtime_lua_file"
printf 'ok - nvim clipboard linewise runtime copy-paste preserves register type\n'

cat >"$empty_runtime_lua_file" <<'LUA'
local root = assert(os.getenv("DOTFILES_ROOT"))
local case_name = assert(os.getenv("NVIM_CLIPBOARD_EMPTY_PASTE_CASE"))

dofile(root .. "/common/.config/nvim/lua/config/options.lua")

assert(type(vim.g.clipboard) == "table", "clipboard provider not configured")
assert(vim.g.clipboard.name == "osc-copy/osc-paste", "unexpected provider: " .. tostring(vim.g.clipboard.name))

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "anchor", "tail" })
local ok, err = pcall(vim.cmd, [[normal! gg"+p]])
assert(not ok, "empty clipboard paste should report an empty register")
assert(tostring(err):find("E353", 1, true), tostring(err))

local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(vim.inspect(lines) == vim.inspect({ "anchor", "tail" }), vim.inspect(lines))

print("nvim-clipboard-provider-empty-paste-" .. case_name .. "-ok")
LUA

runtime_empty_paste_source="$tmp/runtime-empty-paste.txt"
: >"$runtime_empty_paste_source"
DOTFILES_ROOT="$root" \
  NVIM_CLIPBOARD_EMPTY_PASTE_CASE=ssh \
  NVIM_CLIPBOARD_PASTE_SOURCE="$runtime_empty_paste_source" \
  HOME="$tmp/path-home" \
  PATH="$tmp/path-bin:$tmp/tmux-bin:$system_path" \
  SSH_CLIENT="127.0.0.1 1000 22" \
  "$nvim_path" --headless -n -i NONE -u NONE -l "$empty_runtime_lua_file"
printf 'ok - nvim clipboard empty paste is a no-op over mock ssh\n'

if real_tmux="$(command -v tmux 2>/dev/null)"; then
  live_socket="dotfiles-nvim-clipboard-$$"
  live_tmux_env="$tmp/live-tmux-env.txt"
  live_runtime_copy_log="$tmp/live-runtime-copy.log"
  live_runtime_copy_expected="$tmp/live-runtime-copy.expected"
  live_runtime_paste_source="$tmp/live-runtime-paste.txt"
  live_multiline_runtime_copy_log="$tmp/live-multiline-runtime-copy.log"
  live_multiline_runtime_copy_expected="$tmp/live-multiline-runtime-copy.expected"
  live_multiline_runtime_paste_source="$tmp/live-multiline-runtime-paste.txt"
  live_linewise_runtime_clipboard="$tmp/live-linewise-runtime-clipboard.txt"
  live_runtime_empty_paste_source="$tmp/live-runtime-empty-paste.txt"
  live_session="nvim-clipboard-live"

  printf '%s\nalpha\n%s\nbeta\n' '---copy---' '---copy---' >"$live_runtime_copy_expected"
  printf 'from paste\n' >"$live_runtime_paste_source"
  # shellcheck disable=SC2016
  printf 'copy-one $HOME\ncopy-two ; $(no)\n' >"$live_multiline_runtime_copy_expected"
  # shellcheck disable=SC2016
  printf 'paste-one $HOME\npaste-two ; $(no)\n' >"$live_multiline_runtime_paste_source"
  : >"$live_linewise_runtime_clipboard"
  : >"$live_runtime_empty_paste_source"
  # shellcheck disable=SC2016
  printf -v live_env_command 'printf %%s "$TMUX" > %q; sleep 60' "$live_tmux_env"

  "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
  HOME="$tmp/path-home" "$real_tmux" -L "$live_socket" new-session -d -s "$live_session" 'sleep 60'
  HOME="$tmp/path-home" "$real_tmux" -L "$live_socket" split-window -d "$live_env_command"
  wait_for_file "$live_tmux_env"

  DOTFILES_ROOT="$root" \
    NVIM_CLIPBOARD_COPY_APPEND_LOG="$live_runtime_copy_log" \
    NVIM_CLIPBOARD_PASTE_SOURCE="$live_runtime_paste_source" \
    HOME="$tmp/path-home" \
    PATH="$tmp/path-bin:$PATH" \
    TMUX="$(cat "$live_tmux_env")" \
    SSH_CLIENT="" \
    SSH_TTY="" \
    SSH_CONNECTION="" \
    "$nvim_path" --headless -n -i NONE -u NONE -l "$runtime_lua_file"

  if ! cmp -s "$live_runtime_copy_expected" "$live_runtime_copy_log"; then
    printf 'not ok - nvim clipboard runtime copy writes expected bytes inside live tmux\n' >&2
    printf 'expected bytes:\n' >&2
    od -An -tx1 "$live_runtime_copy_expected" >&2
    printf 'actual bytes:\n' >&2
    od -An -tx1 "$live_runtime_copy_log" >&2
    exit 1
  fi
  printf 'ok - nvim clipboard runtime copy writes expected bytes inside live tmux\n'

  DOTFILES_ROOT="$root" \
    NVIM_CLIPBOARD_COPY_LOG="$live_multiline_runtime_copy_log" \
    NVIM_CLIPBOARD_PASTE_SOURCE="$live_multiline_runtime_paste_source" \
    HOME="$tmp/path-home" \
    PATH="$tmp/path-bin:$PATH" \
    TMUX="$(cat "$live_tmux_env")" \
    SSH_CLIENT="" \
    SSH_TTY="" \
    SSH_CONNECTION="" \
    "$nvim_path" --headless -n -i NONE -u NONE -l "$multiline_runtime_lua_file"

  assert_files_equal "nvim clipboard multiline runtime copy writes exact bytes inside live tmux" \
    "$live_multiline_runtime_copy_expected" \
    "$live_multiline_runtime_copy_log"

  DOTFILES_ROOT="$root" \
    NVIM_CLIPBOARD_COPY_LOG="$live_linewise_runtime_clipboard" \
    NVIM_CLIPBOARD_PASTE_SOURCE="$live_linewise_runtime_clipboard" \
    HOME="$tmp/path-home" \
    PATH="$tmp/path-bin:$PATH" \
    TMUX="$(cat "$live_tmux_env")" \
    SSH_CLIENT="" \
    SSH_TTY="" \
    SSH_CONNECTION="" \
    "$nvim_path" --headless -n -i NONE -u NONE -l "$linewise_runtime_lua_file"
  printf 'ok - nvim clipboard linewise runtime copy-paste preserves register type inside live tmux\n'

  DOTFILES_ROOT="$root" \
    NVIM_CLIPBOARD_EMPTY_PASTE_CASE=tmux \
    NVIM_CLIPBOARD_PASTE_SOURCE="$live_runtime_empty_paste_source" \
    HOME="$tmp/path-home" \
    PATH="$tmp/path-bin:$PATH" \
    TMUX="$(cat "$live_tmux_env")" \
    SSH_CLIENT="" \
    SSH_TTY="" \
    SSH_CONNECTION="" \
    "$nvim_path" --headless -n -i NONE -u NONE -l "$empty_runtime_lua_file"
  printf 'ok - nvim clipboard empty paste is a no-op inside live tmux\n'

  "$real_tmux" -L "$live_socket" kill-server >/dev/null 2>&1 || true
  live_socket=""
else
  printf 'skip - nvim clipboard runtime copy-paste inside live tmux (tmux unavailable)\n'
fi

if command -v pbcopy >/dev/null 2>&1 && command -v pbpaste >/dev/null 2>&1; then
  real_clipboard_backup="$tmp/real-clipboard-backup.txt"
  if pbpaste >"$real_clipboard_backup"; then
    real_clipboard_lua="$tmp/real-clipboard.lua"
    real_clipboard_expected="$tmp/real-clipboard.expected"
    real_clipboard_actual="$tmp/real-clipboard.actual"

    cat >"$real_clipboard_lua" <<'LUA'
local root = assert(os.getenv("DOTFILES_ROOT"))
local mode = assert(os.getenv("NVIM_REAL_CLIPBOARD_MODE"))
local line = assert(os.getenv("NVIM_REAL_CLIPBOARD_LINE"))
local expect_helper = os.getenv("NVIM_REAL_CLIPBOARD_EXPECT_HELPER") == "1"
local lines_file = os.getenv("NVIM_REAL_CLIPBOARD_LINES_FILE") or ""

dofile(root .. "/common/.config/nvim/lua/config/options.lua")

if expect_helper then
  assert(type(vim.g.clipboard) == "table", "helper clipboard provider not configured")
  assert(vim.g.clipboard.name == "osc-copy/osc-paste", "unexpected helper provider " .. tostring(vim.g.clipboard.name))
else
  assert(vim.g.clipboard == nil, "local non-tmux should use Neovim native clipboard provider")
end

local expected_lines = { line }
if lines_file ~= "" then
  expected_lines = vim.fn.readfile(lines_file)
end

if mode == "copy" then
  local buffer_lines = vim.deepcopy(expected_lines)
  table.insert(buffer_lines, "other")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, buffer_lines)
  if #expected_lines == 1 then
    vim.cmd([[normal! gg"+yy]])
  else
    vim.cmd("normal! ggV" .. string.rep("j", #expected_lines - 1) .. "\"+y")
  end
elseif mode == "paste" then
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "anchor" })
  local expected_register = table.concat(expected_lines, "\n") .. "\n"
  assert(vim.fn.getreg("+") == expected_register, "clipboard register did not read expected text")
  vim.cmd([[normal! gg"+p]])
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for index, expected_line in ipairs(expected_lines) do
    assert(lines[index + 1] == expected_line, vim.inspect(lines))
  end
else
  error("unknown real clipboard mode " .. tostring(mode))
end

print("nvim-real-clipboard-" .. mode .. "-ok")
LUA

    real_local_copy_line="nvim-real-local-copy"
    printf '%s\n' "$real_local_copy_line" >"$real_clipboard_expected"
    DOTFILES_ROOT="$root" \
      NVIM_REAL_CLIPBOARD_MODE=copy \
      NVIM_REAL_CLIPBOARD_LINE="$real_local_copy_line" \
      NVIM_REAL_CLIPBOARD_EXPECT_HELPER=0 \
      HOME="$tmp/path-home" \
      PATH="$root/common/.local/bin:$PATH" \
      "$nvim_path" --headless -n -i NONE -u NONE -l "$real_clipboard_lua"
    pbpaste >"$real_clipboard_actual"
    assert_files_equal "nvim real local clipboard copy writes macOS pasteboard" \
      "$real_clipboard_expected" \
      "$real_clipboard_actual"

    real_local_paste_line="nvim-real-local-paste"
    printf '%s\n' "$real_local_paste_line" | pbcopy
    DOTFILES_ROOT="$root" \
      NVIM_REAL_CLIPBOARD_MODE=paste \
      NVIM_REAL_CLIPBOARD_LINE="$real_local_paste_line" \
      NVIM_REAL_CLIPBOARD_EXPECT_HELPER=0 \
      HOME="$tmp/path-home" \
      PATH="$root/common/.local/bin:$PATH" \
      "$nvim_path" --headless -n -i NONE -u NONE -l "$real_clipboard_lua"
    printf 'ok - nvim real local clipboard paste reads macOS pasteboard\n'

    if real_tmux_path="$(command -v tmux 2>/dev/null)"; then
      real_tmux_env="$tmp/real-tmux-env.txt"
      real_tmux_session="nvim-real-clipboard"

      live_socket="dotfiles-nvim-real-clipboard-$$"
      "$real_tmux_path" -L "$live_socket" kill-server >/dev/null 2>&1 || true
      HOME="$tmp/path-home" "$real_tmux_path" -L "$live_socket" new-session -d -s "$real_tmux_session" 'sleep 60'
      # shellcheck disable=SC2016
      printf -v real_tmux_env_command 'printf %%s "$TMUX" > %q; sleep 60' "$real_tmux_env"
      HOME="$tmp/path-home" "$real_tmux_path" -L "$live_socket" split-window -d "$real_tmux_env_command"
      wait_for_file "$real_tmux_env"

      printf 'stale tmux buffer\n' | HOME="$tmp/path-home" "$real_tmux_path" -L "$live_socket" load-buffer -
      real_tmux_paste_line="nvim-real-tmux-host-paste"
      printf '%s\n' "$real_tmux_paste_line" | pbcopy
      DOTFILES_ROOT="$root" \
        NVIM_REAL_CLIPBOARD_MODE=paste \
        NVIM_REAL_CLIPBOARD_LINE="$real_tmux_paste_line" \
        NVIM_REAL_CLIPBOARD_EXPECT_HELPER=1 \
        HOME="$tmp/path-home" \
        PATH="$root/common/.local/bin:$PATH" \
        TMUX="$(cat "$real_tmux_env")" \
        SSH_CLIENT="" \
        SSH_TTY="" \
        SSH_CONNECTION="" \
        "$nvim_path" --headless -n -i NONE -u NONE -l "$real_clipboard_lua"
      printf 'ok - nvim real tmux clipboard paste reads macOS pasteboard\n'

      real_tmux_copy_line="nvim-real-tmux-host-copy"
      printf '%s\n' "$real_tmux_copy_line" >"$real_clipboard_expected"
      DOTFILES_ROOT="$root" \
        NVIM_REAL_CLIPBOARD_MODE=copy \
        NVIM_REAL_CLIPBOARD_LINE="$real_tmux_copy_line" \
        NVIM_REAL_CLIPBOARD_EXPECT_HELPER=1 \
        HOME="$tmp/path-home" \
        PATH="$root/common/.local/bin:$PATH" \
        TMUX="$(cat "$real_tmux_env")" \
        SSH_CLIENT="" \
        SSH_TTY="" \
        SSH_CONNECTION="" \
        "$nvim_path" --headless -n -i NONE -u NONE -l "$real_clipboard_lua"
      pbpaste >"$real_clipboard_actual"
      assert_files_equal "nvim real tmux clipboard copy writes macOS pasteboard" \
        "$real_clipboard_expected" \
        "$real_clipboard_actual"

      real_tmux_ssh_host_bin="$tmp/real-tmux-ssh-host-bin"
      real_tmux_ssh_pbcopy_log="$tmp/real-tmux-ssh-pbcopy.log"
      real_tmux_ssh_pbpaste_log="$tmp/real-tmux-ssh-pbpaste.log"
      real_tmux_ssh_buffer_actual="$tmp/real-tmux-ssh-buffer.actual"
      mkdir -p "$real_tmux_ssh_host_bin"
      cat >"$real_tmux_ssh_host_bin/pbcopy" <<SH
#!/usr/bin/env bash
cat >"$real_tmux_ssh_pbcopy_log"
SH
      chmod +x "$real_tmux_ssh_host_bin/pbcopy"
      cat >"$real_tmux_ssh_host_bin/pbpaste" <<SH
#!/usr/bin/env bash
printf 'pbpaste invoked\n' >"$real_tmux_ssh_pbpaste_log"
printf 'unexpected host paste\n'
SH
      chmod +x "$real_tmux_ssh_host_bin/pbpaste"

      real_tmux_ssh_paste_line="nvim-real-tmux-ssh-buffer-paste"
      printf '%s\n' "$real_tmux_ssh_paste_line" >"$real_clipboard_expected"
      HOME="$tmp/path-home" "$real_tmux_path" -L "$live_socket" load-buffer - <"$real_clipboard_expected"
      rm -f "$real_tmux_ssh_pbpaste_log"
      DOTFILES_ROOT="$root" \
        NVIM_REAL_CLIPBOARD_MODE=paste \
        NVIM_REAL_CLIPBOARD_LINE="$real_tmux_ssh_paste_line" \
        NVIM_REAL_CLIPBOARD_EXPECT_HELPER=1 \
        HOME="$tmp/path-home" \
        PATH="$real_tmux_ssh_host_bin:$root/common/.local/bin:$PATH" \
        TMUX="$(cat "$real_tmux_env")" \
        SSH_CLIENT="127.0.0.1 1000 22" \
        SSH_TTY="" \
        SSH_CONNECTION="" \
        "$nvim_path" --headless -n -i NONE -u NONE -l "$real_clipboard_lua"
      printf 'ok - nvim real tmux mock ssh clipboard paste reads tmux buffer\n'
      assert_file_absent "nvim real tmux mock ssh clipboard paste skips host pbpaste" \
        "$real_tmux_ssh_pbpaste_log"

      real_tmux_ssh_copy_line="nvim-real-tmux-ssh-buffer-copy"
      printf '%s\n' "$real_tmux_ssh_copy_line" >"$real_clipboard_expected"
      printf 'stale tmux buffer\n' | HOME="$tmp/path-home" "$real_tmux_path" -L "$live_socket" load-buffer -
      rm -f "$real_tmux_ssh_pbcopy_log"
      DOTFILES_ROOT="$root" \
        NVIM_REAL_CLIPBOARD_MODE=copy \
        NVIM_REAL_CLIPBOARD_LINE="$real_tmux_ssh_copy_line" \
        NVIM_REAL_CLIPBOARD_EXPECT_HELPER=1 \
        HOME="$tmp/path-home" \
        PATH="$real_tmux_ssh_host_bin:$root/common/.local/bin:$PATH" \
        TMUX="$(cat "$real_tmux_env")" \
        SSH_CLIENT="127.0.0.1 1000 22" \
        SSH_TTY="" \
        SSH_CONNECTION="" \
        "$nvim_path" --headless -n -i NONE -u NONE -l "$real_clipboard_lua"
      HOME="$tmp/path-home" "$real_tmux_path" -L "$live_socket" save-buffer - >"$real_tmux_ssh_buffer_actual"
      assert_files_equal "nvim real tmux mock ssh clipboard copy writes tmux buffer" \
        "$real_clipboard_expected" \
        "$real_tmux_ssh_buffer_actual"
      assert_file_absent "nvim real tmux mock ssh clipboard copy skips host pbcopy" \
        "$real_tmux_ssh_pbcopy_log"

      real_tmux_ssh_multiline_expected="$tmp/real-tmux-ssh-multiline.expected"
      real_tmux_ssh_multiline_actual="$tmp/real-tmux-ssh-multiline.actual"
      # shellcheck disable=SC2016
      printf 'nvim-real-tmux-ssh-buffer-paste-one $HOME\nnvim-real-tmux-ssh-buffer-paste-two ; $(no)\n' \
        >"$real_tmux_ssh_multiline_expected"
      HOME="$tmp/path-home" "$real_tmux_path" -L "$live_socket" load-buffer - <"$real_tmux_ssh_multiline_expected"
      rm -f "$real_tmux_ssh_pbpaste_log"
      DOTFILES_ROOT="$root" \
        NVIM_REAL_CLIPBOARD_MODE=paste \
        NVIM_REAL_CLIPBOARD_LINE="nvim-real-tmux-ssh-buffer-paste-one \$HOME" \
        NVIM_REAL_CLIPBOARD_LINES_FILE="$real_tmux_ssh_multiline_expected" \
        NVIM_REAL_CLIPBOARD_EXPECT_HELPER=1 \
        HOME="$tmp/path-home" \
        PATH="$real_tmux_ssh_host_bin:$root/common/.local/bin:$PATH" \
        TMUX="$(cat "$real_tmux_env")" \
        SSH_CLIENT="127.0.0.1 1000 22" \
        SSH_TTY="" \
        SSH_CONNECTION="" \
        "$nvim_path" --headless -n -i NONE -u NONE -l "$real_clipboard_lua"
      printf 'ok - nvim real tmux mock ssh multiline clipboard paste reads tmux buffer\n'
      assert_file_absent "nvim real tmux mock ssh multiline clipboard paste skips host pbpaste" \
        "$real_tmux_ssh_pbpaste_log"

      # shellcheck disable=SC2016
      printf 'nvim-real-tmux-ssh-buffer-copy-one $HOME\nnvim-real-tmux-ssh-buffer-copy-two ; $(no)\n' \
        >"$real_tmux_ssh_multiline_expected"
      printf 'stale tmux buffer\n' | HOME="$tmp/path-home" "$real_tmux_path" -L "$live_socket" load-buffer -
      rm -f "$real_tmux_ssh_pbcopy_log"
      DOTFILES_ROOT="$root" \
        NVIM_REAL_CLIPBOARD_MODE=copy \
        NVIM_REAL_CLIPBOARD_LINE="nvim-real-tmux-ssh-buffer-copy-one \$HOME" \
        NVIM_REAL_CLIPBOARD_LINES_FILE="$real_tmux_ssh_multiline_expected" \
        NVIM_REAL_CLIPBOARD_EXPECT_HELPER=1 \
        HOME="$tmp/path-home" \
        PATH="$real_tmux_ssh_host_bin:$root/common/.local/bin:$PATH" \
        TMUX="$(cat "$real_tmux_env")" \
        SSH_CLIENT="127.0.0.1 1000 22" \
        SSH_TTY="" \
        SSH_CONNECTION="" \
        "$nvim_path" --headless -n -i NONE -u NONE -l "$real_clipboard_lua"
      HOME="$tmp/path-home" "$real_tmux_path" -L "$live_socket" save-buffer - >"$real_tmux_ssh_multiline_actual"
      assert_files_equal "nvim real tmux mock ssh multiline clipboard copy writes tmux buffer" \
        "$real_tmux_ssh_multiline_expected" \
        "$real_tmux_ssh_multiline_actual"
      assert_file_absent "nvim real tmux mock ssh multiline clipboard copy skips host pbcopy" \
        "$real_tmux_ssh_pbcopy_log"

      "$real_tmux_path" -L "$live_socket" kill-server >/dev/null 2>&1 || true
      live_socket=""
    else
      printf 'skip - nvim real tmux clipboard copy-paste (tmux unavailable)\n'
    fi
  else
    real_clipboard_backup=""
    printf 'skip - nvim real macOS clipboard copy-paste (pbpaste failed)\n'
  fi
else
  printf 'skip - nvim real macOS clipboard copy-paste (pbcopy/pbpaste unavailable)\n'
fi
