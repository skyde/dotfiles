#!/bin/sh
set -eu

# Convenience wrapper around trim_compile_commands.py.
#
# Typical use:
#   tools/dev/setup_lightweight_compile_db.sh \ \
#       --prefix cc/ --prefix base/ --prefix content/ --strip-missing-pch
#
# If compile_commands.json is missing, attempts to generate it with GN.

SCRIPT_DIR=`cd "\`dirname "$0"\`" && pwd`
SRC_ROOT=`cd "${SCRIPT_DIR}/../.." && pwd`
cd "${SRC_ROOT}" || exit 1

INPUT=compile_commands.json
BUILD_DIR=out/Default
if [ ! -f "${INPUT}" ]; then
  echo "[info] ${INPUT} not found; generating via gn (requires prior gn args setup)." >&2
  if ! command -v gn >/dev/null 2>&1; then
    echo "[error] gn not on PATH; run 'gn gen out/Default --export-compile-commands' manually." >&2
    exit 1
  fi
  gn gen ${BUILD_DIR} --export-compile-commands
  ln -sf ${BUILD_DIR}/compile_commands.json ${INPUT} || true
fi

PY=python3
if ! command -v "$PY" >/dev/null 2>&1; then
  # Try vpython3 (Chromium build env) fallback
  if command -v vpython3 >/dev/null 2>&1; then
    PY=vpython3
  else
    echo "[error] python3 (or vpython3) not found on PATH." >&2
    exit 2
  fi
fi

OUT=${BUILD_DIR}/compile_commands.trimmed.json

echo "[info] Trimming ${INPUT} -> ${OUT}" >&2
${PY} tools/dev/trim_compile_commands.py --output "${OUT}" "$@"

echo "[info] Done. Point your editor to ${OUT} (or pass --create-symlink to auto-link)." >&2
