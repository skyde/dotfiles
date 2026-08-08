#!/usr/bin/env python3
"""stream-adjust a large compile_commands.json for editor indexing.

purpose:
    chromium's root compile_commands.json can exceed 50mb and some editor
    environments or remote extension bridges refuse to expose it to language
    servers. by default this script now preserves all entries. you may supply
    --prefix arguments to explicitly filter if you want a reduced subset.
    it can also optionally remove -include <file> directives that reference
    missing precompiled header stubs (e.g. obj/.../precompile.h-cc) to avoid
    bogus diagnostics when the pch file was cleaned.

usage:
  from //src (default build dir out/default assumed):

    python3 tools/dev/trim_compile_commands.py \
        --input compile_commands.json \
        --output out/default/compile_commands.full.json

  (optional subset filtering example):
    python3 tools/dev/trim_compile_commands.py \
        --input compile_commands.json \
        --output out/default/compile_commands.cc_base.json \
        --prefix cc/ --prefix base/

  optional flags:
    --strip-missing-pch   remove -include <path> if the path doesn't exist.
    --create-symlink       after writing output, symlink it to compile_commands.json
                           if the original exceeds a size threshold (default 50mb).
    --size-threshold 50    size in mb for the above behavior.

  then point your editor (vs code c/c++ extension or clangd) at the trimmed file.

notes:
  * the script performs a lightweight streaming scan; it does not fully parse
    json until it isolates each object. this keeps memory steady even for very
    large databases.
  * it preserves entries verbatim except for optional -include stripping.
  * paths in the 'file' field that start with ../../ are normalized before
    prefix comparison.
"""
from __future__ import annotations
import argparse
import json
import os
import re
import shlex
import sys
from typing import Iterator

obj_start = '{'
obj_end = '}'

def iter_objects(stream) -> Iterator[str]:
    """yield raw json object strings from a compile_commands.json stream.

    assumes top-level structure is a json array of objects optionally
    separated by commas and whitespace (standard format produced by gn).
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
            if ch == obj_start:
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
            if ch == obj_start:
                depth += 1
            elif ch == obj_end:
                depth -= 1
                if depth == 0:
                    yield ''.join(buf)
                    started = False

def extract_file_field(obj_str: str) -> str:
    # fast regex to find "file": "..." not caring about escaped quotes inside path (paths won't have them)
    m = re.search(r'"file"\s*:\s*"([^"]+)"', obj_str)
    if not m:
        return ''
    path = m.group(1)
    if path.startswith('../../'):
        path = path[6:]
    return path

def should_keep(path: str, prefixes: list[str]) -> bool:
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
        # fallback: don't modify if shlex fails
        return obj
    changed = False
    i = 0
    new_tokens: list[str] = []
    while i < len(tokens):
        if tokens[i] == '-include' and i + 1 < len(tokens):
            inc_path = tokens[i+1]
            abs_path = inc_path
            if not os.path.isabs(abs_path):
                abs_path = os.path.normpath(os.path.join(build_dir, inc_path))
            if not os.path.exists(abs_path):
                # skip both tokens
                changed = True
                i += 2
                continue
        new_tokens.append(tokens[i])
        i += 1
    if changed:
        # reconstruct with basic quoting where needed
        obj['command'] = ' '.join(shlex.quote(t) for t in new_tokens)
    return obj

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--input', default='compile_commands.json')
    ap.add_argument('--output', default='out/default/compile_commands.trimmed.json')
    ap.add_argument('--prefix', action='append', dest='prefixes', default=[],
                   help='path prefix to keep (relative to //src, e.g. cc/, base/, content/)')
    ap.add_argument('--strip-missing-pch', action='store_true', help='remove -include lines if target file missing')
    ap.add_argument('--create-symlink', action='store_true', help='symlink trimmed file over original if size threshold exceeded')
    ap.add_argument('--size-threshold', type=int, default=50, help='threshold in mb for symlink replacement')
    args = ap.parse_args()

    # no default prefixes: absence means keep everything.

    src_root = os.getcwd()
    in_path = args.input
    if not os.path.exists(in_path):
        print(f'input file {in_path} not found. if you have a gn build dir run: gn gen out/default --export-compile-commands', file=sys.stderr)
        return 2

    build_dir_guess = 'out/default'
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
                # parse minimally to allow optional modification; fallback to raw if parse fails.
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

    print(f'wrote trimmed db: {out_path} (kept {kept} / {total} entries, input size {size_mb:.1f}mb)')

    if args.create_symlink and size_mb > args.size_threshold:
        backup = in_path + '.full'
        if not os.path.exists(backup):
            try:
                os.rename(in_path, backup)
                print(f'renamed original to {backup}')
            except OSError as e:
                print(f'warning: could not rename original ({e})')
        try:
            if os.path.islink(in_path) or os.path.exists(in_path):
                try:
                    os.remove(in_path)
                except OSError:
                    pass
            os.symlink(os.path.relpath(out_path, os.path.dirname(in_path)), in_path)
            print(f'symlinked {in_path} -> {out_path}')
        except OSError as e:
            print(f'warning: symlink failed ({e})')
    return 0

if __name__ == '__main__':
    sys.exit(main())
