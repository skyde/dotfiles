-- Run with: nvim --headless -u NONE -i NONE -l tests/nvim_clipboard_spec.lua

local source = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fn.fnamemodify(source, ":p:h:h")
local osc_copy = repo .. "/common/.local/bin/osc-copy"
local osc_paste = repo .. "/common/.local/bin/osc-paste"
local temp_dir = vim.fn.tempname()
local fake_clipboard = temp_dir .. "/clipboard.bin"
local copy_temp_dir = temp_dir .. "/copy-temp"

local function assert_equal(expected, actual, context)
  if not vim.deep_equal(expected, actual) then
    error(string.format("%s\nexpected: %s\nactual:   %s", context, vim.inspect(expected), vim.inspect(actual)))
  end
end

local function read_bytes(path)
  local file = assert(io.open(path, "rb"))
  local bytes = file:read("*a")
  file:close()
  return bytes
end

local function write_bytes(path, bytes)
  local file = assert(io.open(path, "wb"))
  file:write(bytes)
  file:close()
end

local function keys(value)
  return vim.api.nvim_replace_termcodes(value, true, false, true)
end

local function normal(sequence)
  vim.api.nvim_feedkeys(keys(sequence), "nx", false)
end

local function reset(lines, cursor)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, cursor or { 1, 0 })
end

local function snapshot()
  return {
    lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
    cursor = vim.api.nvim_win_get_cursor(0),
    register = vim.fn.getreg('"', 1, true),
    regtype = vim.fn.getregtype('"'),
  }
end

local function clipboard_bytes(register, regtype)
  local bytes = table.concat(register, "\n")
  if regtype ~= "v" then
    bytes = bytes .. "\n"
  end
  return bytes
end

local function create_fake_tmux(path)
  vim.fn.writefile({
    "#!/usr/bin/env bash",
    "set -euo pipefail",
    "case \"${1:-}\" in",
    "  load-buffer) cat >\"${FAKE_CLIPBOARD:?}\" ;;",
    "  save-buffer)",
    "    [[ \"${FAKE_TMUX_FAIL_SAVE:-0}\" != 1 ]] || exit 1",
    "    [[ ! -f \"${FAKE_CLIPBOARD:?}\" ]] || cat \"$FAKE_CLIPBOARD\"",
    "    ;;",
    "  refresh-client)",
    "    if [[ -n \"${FAKE_EXTERNAL_CLIPBOARD:-}\" ]]; then",
    "      cp \"$FAKE_EXTERNAL_CLIPBOARD\" \"$FAKE_CLIPBOARD\"",
    "    fi",
    "    ;;",
    "  -V) printf '%s\\n' 'tmux 3.4' ;;",
    "  *) exit 2 ;;",
    "esac",
  }, path)
  assert(vim.fn.setfperm(path, "rwx------") == 1)
end

local cases = {
  { "yy then p", { "one", "two" }, { 1, 0 }, "yyp" },
  { "yy then P", { "one", "two" }, { 2, 0 }, "yyP" },
  { "yy then repeated p", { "one", "two" }, { 1, 0 }, "yypp" },
  { "yy then counted p", { "one", "two" }, { 1, 0 }, "yy2p" },
  { "yw then p", { "alpha beta" }, { 1, 0 }, "ywp" },
  { "visual charwise then p", { "abcdef" }, { 1, 0 }, "vllyp" },
  { "visual charwise then P", { "abcdef" }, { 1, 0 }, "vllyP" },
  { "visual linewise then p", { "one", "two" }, { 1, 0 }, "Vyp" },
  { "visual linewise then P", { "one", "two" }, { 2, 0 }, "VyP" },
  { "visual blockwise then p", { "abcd", "efgh", "tail" }, { 1, 0 }, "<C-v>jlyp" },
  { "visual blockwise then P", { "abcd", "efgh", "tail" }, { 1, 0 }, "<C-v>jlyP" },
  { "multiline charwise", { "abc", "def", "tail" }, { 1, 1 }, "vjlyp" },
  { "multiline linewise", { "one", "two", "three" }, { 1, 0 }, "Vjyp" },
  { "linewise with blank", { "one", "", "three", "tail" }, { 1, 0 }, "V2jyp" },
  { "empty line", { "", "tail" }, { 1, 0 }, "yyp" },
  { "dd then p", { "one", "two", "three" }, { 1, 0 }, "ddp" },
  { "dd then P", { "one", "two", "three" }, { 1, 0 }, "ddP" },
  { "Unicode word", { "日本語 test" }, { 1, 0 }, "ywp" },
}

vim.fn.mkdir(copy_temp_dir, "p")
create_fake_tmux(temp_dir .. "/tmux")
vim.env.PATH = temp_dir .. ":" .. vim.env.PATH
vim.env.TMUX = "clipboard-test"
vim.env.FAKE_CLIPBOARD = fake_clipboard
vim.env.TMPDIR = copy_temp_dir

vim.g.clipboard = {
  name = "osc-copy/osc-paste test",
  copy = {
    ["+"] = { osc_copy },
    ["*"] = { osc_copy },
  },
  paste = {
    ["+"] = { osc_paste },
    ["*"] = { osc_paste },
  },
  cache_enabled = 0,
}

local ok, err = xpcall(function()
  for _, case in ipairs(cases) do
    vim.opt.clipboard = ""
    reset(case[2], case[3])
    normal(case[4])
    local expected = snapshot()

    vim.opt.clipboard = "unnamedplus"
    reset(case[2], case[3])
    normal(case[4])
    local actual = snapshot()

    assert_equal(expected, actual, case[1])
    assert_equal(
      clipboard_bytes(expected.register, expected.regtype),
      read_bytes(fake_clipboard),
      case[1] .. " bytes"
    )
    print("PASS " .. case[1])
  end

  for _, value in ipairs({ "plain", "one\n", "two\n\n", "a\0b\n" }) do
    local result = vim.system({ osc_copy }, { stdin = value }):wait()
    assert_equal(0, result.code, "osc-copy exit code")
    assert_equal(value, read_bytes(fake_clipboard), "osc-copy exact bytes")
    assert_equal({}, vim.fn.readdir(copy_temp_dir), "osc-copy temporary-file cleanup")
  end

  write_bytes(fake_clipboard, "external")
  assert_equal("v", vim.fn.getregtype("+"), "external characterwise type")
  reset({ "base" }, { 1, 3 })
  normal('"+p')
  assert_equal({ "baseexternal" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "external characterwise paste")

  write_bytes(fake_clipboard, "external\n")
  assert_equal("V", vim.fn.getregtype("+"), "external linewise type")
  reset({ "base" }, { 1, 0 })
  normal('"+p')
  assert_equal({ "base", "external" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "external linewise paste")

  write_bytes(fake_clipboard, "")
  reset({ "base" }, { 1, 0 })
  normal('"+p')
  assert_equal({ "base" }, vim.api.nvim_buf_get_lines(0, 0, -1, false), "empty clipboard paste")

  local external_clipboard = temp_dir .. "/external.bin"
  write_bytes(fake_clipboard, "stale")
  write_bytes(external_clipboard, "fresh")
  vim.env.FAKE_EXTERNAL_CLIPBOARD = external_clipboard
  assert_equal("fresh", vim.fn.system({ osc_paste }), "tmux external clipboard refresh")
  write_bytes(external_clipboard, "first\r\nsecond\r\n")
  assert_equal("first\nsecond\n", vim.fn.system({ osc_paste }), "CRLF normalization")
  vim.env.FAKE_EXTERNAL_CLIPBOARD = nil
end, debug.traceback)

vim.fn.delete(temp_dir, "rf")

if not ok then
  error(err)
end

print(string.format("PASS %d Neovim clipboard behavior cases", #cases))
