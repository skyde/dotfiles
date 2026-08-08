#!/usr/bin/env bash
set -euo pipefail

URL="${1:-https://example.test/}"
OUT_FILE="${2:-.vscode/.renderer_pid}"
PROFILE_DIR="${3:-.vscode/chrome-native-profile}"
CHROME_BIN="${CHROME:-${PWD}/out/Default/chrome}"
TIMEOUT_SECONDS="${GRAB_RENDERER_TIMEOUT:-120}"

if [[ ! -x "$CHROME_BIN" ]]; then
  echo "error: chrome binary not found or not executable: $CHROME_BIN" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_FILE")" "$PROFILE_DIR"
: > "$OUT_FILE"

python3 - "$CHROME_BIN" "$URL" "$OUT_FILE" "$PROFILE_DIR" "$TIMEOUT_SECONDS" <<'PY'
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

chrome_bin, url, out_file, profile_dir, timeout_str = sys.argv[1:6]
timeout = int(timeout_str)

out_path = Path(out_file).resolve()
profile_path = Path(profile_dir).resolve()

log_dir = out_path.parent
log_dir.mkdir(parents=True, exist_ok=True)
log_file = log_dir / ".renderer_launch.log"

unbuffer = None
for candidate in ("unbuffer", "stdbuf"):
    found = shutil.which(candidate)
    if not found:
        continue
    if candidate == "stdbuf":
        unbuffer = [found, "-oL", "-eL"]
    else:
        unbuffer = [found]
    break

cmd = []
if unbuffer:
    cmd.extend(unbuffer)
cmd.extend([
    str(chrome_bin),
    f"--user-data-dir={profile_path}",
    "--no-first-run",
    "--no-default-browser-check",
    "--allow-sandbox-debugging",
    "--site-per-process",
    "--wait-for-debugger-on-navigation",
    "--enable-logging=stderr",
    f"--log-file={log_file}",
    url,
])

proc = subprocess.Popen(
    cmd,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    cwd=os.getcwd(),
)

pattern = re.compile(r'Renderer url="([^"]+)".*\(([0-9]+)\) paused waiting for debugger')
start = time.time()
released = set()

handle = None
offset = 0
try:
    while True:
        if time.time() - start > timeout:
            proc.terminate()
            raise SystemExit(f"timed out waiting for renderer for {url}")
        if handle is None:
            if not log_file.exists():
                time.sleep(0.1)
                continue
            handle = log_file.open('r', encoding='utf-8', errors='replace')
        handle.seek(offset)
        line = handle.readline()
        if not line:
            if proc.poll() is not None:
                raise SystemExit(f"chrome exited before renderer for {url} was found")
            time.sleep(0.1)
            continue
        offset = handle.tell()
        match = pattern.search(line)
        if not match:
            continue
        found_url, pid_str = match.group(1), match.group(2)
        pid = int(pid_str)
        if found_url == url:
            out_path.write_text(f"{pid}\n", encoding='utf-8')
            break
        if pid not in released:
            try:
                os.kill(pid, signal.SIGUSR1)
                released.add(pid)
            except ProcessLookupError:
                pass
finally:
    if handle is not None:
        handle.close()

sys.exit(0)
PY
