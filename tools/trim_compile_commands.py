#!/usr/bin/env python3
"""Stream-adjust a large compile_commands.json for editor indexing.

Purpose:
    Chromium's root compile_commands.json can exceed 50MB and some editor
    environments or remote extension bridges refuse to expose it to language
    servers. By default this script now preserves ALL entries. You may supply
    --prefix arguments to explicitly filter if you want a reduced subset.
    It can also optionally remove -include <file> directives that reference
    missing precompiled header stubs (e.g. obj/.../precompile.h-cc) to avoid
    bogus diagnostics when the PCH file was cleaned.

Usage:
  From //src (default build dir out/Default assumed):

    python3 tools/dev/trim_compile_commands.py \
        --input compile_commands.json \
        --output out/Default/compile_commands.full.json

  (Optional subset filtering example):
    python3 tools/dev/trim_compile_commands.py \
        --input compile_commands.json \
        --output out/Default/compile_commands.cc_base.json \
        --prefix cc/ --prefix base/

  Optional flags:
    --strip-missing-pch   Remove -include <path> if the path doesn't exist.
    --create-symlink       After writing output, symlink it to compile_commands.json
                           IF the original exceeds a size threshold (default 50MB).
    --size-threshold 50    Size in MB for the above behavior.

  Then point your editor (VS Code C/C++ extension or clangd) at the trimmed file.

Notes:
  * The script performs a lightweight streaming scan; it does not fully parse
    JSON until it isolates each object. This keeps memory steady even for very
    large databases.
  * It preserves entries verbatim except for optional -include stripping.
  * Paths in the 'file' field that start with ../../ are normalized before
    prefix comparison.
"""
from __future__ import annotations
import argparse
import json
import os
import re
import shlex
import sys
from typing import List, Iterator

OBJ_START = '{'
OBJ_END = '}'

def iter_objects(stream) -> Iterator[str]:
    """Yield raw JSON object strings from a compile_commands.json stream.

    Assumes top-level structure is a JSON array of objects optionally
    separated by commas and whitespace (standard format produced by GN).
    """
    buf = []
    depth = 0
    in_string = False
    escape = False
    started = False
    while True:
        ch = stream.read(1)
        if not ch:
            break
        if not started:
            if ch == OBJ_START:
                started = True
                depth = 1
                buf = [ch]
            continue
        else:
            buf.append(ch)
            if escape:
                escape = False
                continue
            if ch == '\\':
                escape = True
                continue
            if ch == '"':
                in_string = not in_string
                continue
            if in_string:
                continue
            if ch == OBJ_START:
                depth += 1
            elif ch == OBJ_END:
                depth -= 1
                if depth == 0:
                    yield ''.join(buf)
                    started = False

def extract_file_field(obj_str: str) -> str:
    # Fast regex to find "file": "..." not caring about escaped quotes inside path (paths won't have them)
    m = re.search(r'"file"\s*:\s*"([^"]+)"', obj_str)
    if not m:
        return ''
    path = m.group(1)
    if path.startswith('../../'):
        path = path[6:]
    return path

def should_keep(path: str, prefixes: List[str]) -> bool:
    if not prefixes:
        return True
    return any(path.startswith(p) for p in prefixes)

def strip_missing_pch(obj: dict, build_dir: str) -> dict:
    cmd = obj.get('command')
    if not cmd:
        return obj
    try:
        tokens = shlex.split(cmd)
    except ValueError:
        # Fallback: don't modify if shlex fails
        return obj
    changed = False
    i = 0
    new_tokens: List[str] = []
    while i < len(tokens):
        if tokens[i] == '-include' and i + 1 < len(tokens):
            inc_path = tokens[i+1]
            abs_path = inc_path
            if not os.path.isabs(abs_path):
                abs_path = os.path.normpath(os.path.join(build_dir, inc_path))
            if not os.path.exists(abs_path):
                # Skip both tokens
                changed = True
                i += 2
                continue
        new_tokens.append(tokens[i])
        i += 1
    if changed:
        # Reconstruct with basic quoting where needed
        obj['command'] = ' '.join(shlex.quote(t) for t in new_tokens)
    return obj

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--input', default='compile_commands.json')
    ap.add_argument('--output', default='out/Default/compile_commands.trimmed.json')
    ap.add_argument('--prefix', action='append', dest='prefixes', default=[],
                   help='Path prefix to keep (relative to //src, e.g. cc/, base/, content/)')
    ap.add_argument('--strip-missing-pch', action='store_true', help='Remove -include lines if target file missing')
    ap.add_argument('--create-symlink', action='store_true', help='Symlink trimmed file over original if size threshold exceeded')
    ap.add_argument('--size-threshold', type=int, default=50, help='Threshold in MB for symlink replacement')
    args = ap.parse_args()

    # No default prefixes: absence means keep everything.

    src_root = os.getcwd()
    in_path = args.input
    if not os.path.exists(in_path):
        print(f'Input file {in_path} not found. If you have a GN build dir run: gn gen out/Default --export-compile-commands', file=sys.stderr)
        return 2

    build_dir_guess = 'out/Default'
    out_path = args.output
    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    size_mb = os.path.getsize(in_path) / (1024*1024)
    kept = 0
    total = 0
    with open(in_path, 'r', encoding='utf-8', errors='replace') as fin, open(out_path, 'w', encoding='utf-8') as fout:
        fout.write('[\n')
        first = True
        for raw_obj in iter_objects(fin):
            total += 1
            path = extract_file_field(raw_obj)
            if not path:
                continue
            if should_keep(path, args.prefixes):
                # Parse minimally to allow optional modification; fallback to raw if parse fails.
                if args.strip_missing_pch:
                    try:
                        obj = json.loads(raw_obj)
                        obj = strip_missing_pch(obj, os.path.abspath(build_dir_guess))
                        raw_obj = json.dumps(obj, separators=(',', ':'))
                    except Exception:
                        pass
                if not first:
                    fout.write(',\n')
                else:
                    first = False
                fout.write(raw_obj)
                kept += 1
        fout.write('\n]\n')

    print(f'Wrote trimmed DB: {out_path} (kept {kept} / {total} entries, input size {size_mb:.1f}MB)')

    if args.create_symlink and size_mb > args.size_threshold:
        backup = in_path + '.full'
        if not os.path.exists(backup):
            try:
                os.rename(in_path, backup)
                print(f'Renamed original to {backup}')
            except OSError as e:
                print(f'Warning: could not rename original ({e})')
        try:
            if os.path.islink(in_path) or os.path.exists(in_path):
                try:
                    os.remove(in_path)
                except OSError:
                    pass
            os.symlink(os.path.relpath(out_path, os.path.dirname(in_path)), in_path)
            print(f'Symlinked {in_path} -> {out_path}')
        except OSError as e:
            print(f'Warning: symlink failed ({e})')
    return 0

if __name__ == '__main__':
    sys.exit(main())
