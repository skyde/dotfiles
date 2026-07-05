#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$root/common/.local/bin/tmux-fzf-url-helper.py"

failures=0

assert_extracts() {
  local name="$1"
  local input="$2"
  local expected="$3"
  local actual

  actual="$(printf '%s' "$input" | "$helper")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'not ok - %s\n' "$name" >&2
    printf 'expected:\n%s\n' "$expected" >&2
    printf 'actual:\n%s\n' "$actual" >&2
    failures=$((failures + 1))
    return
  fi

  printf 'ok - %s\n' "$name"
}

assert_extracts \
  "urls and localhost" \
  "Open https://example.com/docs), www.example.org/help, and localhost:3000/api." \
  $'https://example.com/docs\nhttp://www.example.org/help\nhttp://localhost:3000/api'

assert_extracts \
  "generic uri schemes" \
  "Use ssh://dev.example.com/repo.git, postgres://db.example.test/app?sslmode=disable, or mailto:ops@example.com." \
  $'ssh://dev.example.com/repo.git\npostgres://db.example.test/app?sslmode=disable\nmailto:ops@example.com'

assert_extracts \
  "www urls keep query fragment and port" \
  "Open www.example.org?x=1#top, www.example.net:8080/path?q=1, and www.example.edu#section." \
  $'http://www.example.org?x=1#top\nhttp://www.example.net:8080/path?q=1\nhttp://www.example.edu#section'

assert_extracts \
  "full urls do not duplicate bare www or local candidates" \
  "Open https://www.example.org/docs and https://127.0.0.1:8443/callback." \
  $'https://www.example.org/docs\nhttps://127.0.0.1:8443/callback'

assert_extracts \
  "urls keep balanced trailing brackets" \
  "Open https://example.test/wiki/Foo_(bar)), https://example.test/a[b]., and (https://example.test/path_(draft))." \
  $'https://example.test/wiki/Foo_(bar)\nhttps://example.test/a[b]\nhttps://example.test/path_(draft)'

assert_extracts \
  "traceback keeps only file line" \
  $'Traceback (most recent call last):\n  File "src/app.py", line 42, in main\n    run()' \
  "src/app.py:42"

assert_extracts \
  "osc8 hyperlink" \
  $'\e]8;;https://example.com/deep\aopen link\e]8;;\a' \
  "https://example.com/deep"

assert_extracts \
  "osc8 hyperlink label does not duplicate target" \
  $'\e]8;;https://www.example.com/deep\awww.example.com/deep\e]8;;\a and \e]8;;https://www.example.org/st\e\\www.example.org/st\e]8;;\e\\' \
  $'https://www.example.com/deep\nhttps://www.example.org/st'

assert_extracts \
  "osc8 hyperlink keeps balanced trailing bracket" \
  $'\e]8;;https://example.com/wiki/Foo_(bar)\alink\e]8;;\a' \
  "https://example.com/wiki/Foo_(bar)"

assert_extracts \
  "quoted path with spaces" \
  $'Open "src/my file.py":12:3 from the picker.' \
  "src/my file.py:12:3"

assert_extracts \
  "file url keeps line fragment" \
  "Open file:///tmp/example.py#L12 from the picker." \
  "file:///tmp/example.py#L12"

assert_extracts \
  "file-like urls sort before external urls" \
  "Open https://example.test/docs, file:///tmp/example.py#L12, vscode://file/tmp/app.py#L3C2, and vscode://vscode-remote/ssh-remote+devbox/tmp/remote.py?line=4." \
  $'file:///tmp/example.py#L12\nvscode://file/tmp/app.py#L3C2\nvscode://vscode-remote/ssh-remote+devbox/tmp/remote.py?line=4\nhttps://example.test/docs'

assert_extracts \
  "home-relative paths" \
  $'~/src/app.py:12\n~/tests/test_app.py::test_runs\n~/src/main.cpp(5,6)' \
  $'~/src/main.cpp:5:6\n~/tests/test_app.py\n~/src/app.py:12'

assert_extracts \
  "common file location formats" \
  $'tests/test_app.py::test_runs\nsrc/main.cpp(12,7): warning C4100\n::error file=lib/foo.py,line=9,col=2::bad\nmain.go:10:2\napp.py:12-14: warning' \
  $'src/main.cpp:12:7\nlib/foo.py:9:2\ntests/test_app.py\nmain.go:10:2\napp.py:12-14'

assert_extracts \
  "github annotation encoded range" \
  "::warning file=src/my%20file.py,line=2,col=1,endLine=4,endColumn=8::bad" \
  "src/my file.py:2:1"

assert_extracts \
  "javascript stack paths with spaces" \
  $'    at run (/tmp/my repo/src/app.ts:12:3)\n    at Object.<anonymous> (src/my app/server.ts:44:7)' \
  $'/tmp/my repo/src/app.ts:12:3\nsrc/my app/server.ts:44:7'

assert_extracts \
  "unquoted spaced file locations" \
  $'src/my file.py:12:3\n/tmp/my repo/src/app.ts:5:6\nError in src/my file.py:12:3' \
  $'src/my file.py:12:3\n/tmp/my repo/src/app.ts:5:6'

assert_extracts \
  "bare msvc file location" \
  $'main.cpp(12,7): warning C4100\nother text' \
  "main.cpp:12:7"

assert_extracts \
  "windows drive file locations" \
  $'C:\\Users\\sky\\repo\\src\\main.cpp(12,7): warning C4100\n    at run (C:\\Users\\sky\\repo\\src\\app.ts:5:6)\nC:/Users/sky/repo/src/my file.py:9:2' \
  $'C:\\Users\\sky\\repo\\src\\main.cpp:12:7\nC:\\Users\\sky\\repo\\src\\app.ts:5:6\nC:/Users/sky/repo/src/my file.py:9:2'

assert_extracts \
  "windows UNC file locations" \
  $'\\\\server\\share\\repo\\src\\main.cpp(12,7): warning C4100\n    at run (\\\\server\\share\\repo\\src\\app.ts:5:6)\n\\\\server/share/repo/src/my file.py:9:2' \
  $'\\\\server\\share\\repo\\src\\main.cpp:12:7\n\\\\server\\share\\repo\\src\\app.ts:5:6\n\\\\server/share/repo/src/my file.py:9:2'

assert_extracts \
  "windows slash UNC file locations" \
  $'//server/share/repo/src/main.cpp(12,7): warning C4100\n    at run (//server/share/repo/src/app.ts:5:6)\n//server/share/repo/src/my file.py:9:2' \
  $'//server/share/repo/src/main.cpp:12:7\n//server/share/repo/src/app.ts:5:6\n//server/share/repo/src/my file.py:9:2'

assert_extracts \
  "quoted Windows file locations" \
  $'Open "C:\\Users\\sky\\repo\\src\\main.cpp":12:7, "C:/Users/sky/repo/src/my file.py":9:2, "\\\\server\\share\\repo\\src\\app.ts":5:6, and "//server/share/repo/src/tool.ts":7:8.' \
  $'C:\\Users\\sky\\repo\\src\\main.cpp:12:7\nC:/Users/sky/repo/src/my file.py:9:2\n\\\\server\\share\\repo\\src\\app.ts:5:6\n//server/share/repo/src/tool.ts:7:8'

assert_extracts \
  "vim quickfix file locations" \
  $'src/app.py|12 col 3| unused value\nmain.go|9| missing return' \
  $'src/app.py:12:3\nmain.go:9'

assert_extracts \
  "shell line diagnostics" \
  $'./scripts/bootstrap.sh: line 42: missing command\n/tmp/my repo/run.zsh: line 7: command not found\nplain.sh: line 3: syntax error' \
  $'./scripts/bootstrap.sh:42\n/tmp/my repo/run.zsh:7\nplain.sh:3'

assert_extracts \
  "html files sort before other paths" \
  $'Read docs/readme.md, src/app.py:3, public/index.html:12, and public/range.html:12-14 before opening https://example.test.' \
  $'public/index.html:12\npublic/range.html:12-14\ndocs/readme.md\nsrc/app.py:3\nhttps://example.test'

assert_extracts \
  "git diff headers strip a and b prefixes" \
  $'diff --git a/src/app.py b/src/app.py\n--- a/src/app.py\n+++ b/src/app.py' \
  "src/app.py"

assert_extracts \
  "git diff hunks include new file line" \
  $'diff --git a/src/app.py b/src/app.py\n--- a/src/app.py\n+++ b/src/app.py\n@@ -10,2 +20,3 @@ def run():\n+changed' \
  $'src/app.py\nsrc/app.py:20'

assert_extracts \
  "git diff quoted paths with spaces" \
  $'diff --git "a/src/my file.py" "b/src/my file.py"\n--- "a/src/my file.py"\n+++ "b/src/my file.py"' \
  "src/my file.py"

assert_extracts \
  "git rename and copy headers" \
  $'rename from old name.py\nrename to src/new name.py\ncopy from lib/template.py\ncopy to lib/template copy.py' \
  $'old name.py\nsrc/new name.py\nlib/template.py\nlib/template copy.py'

if ((failures > 0)); then
  exit 1
fi
