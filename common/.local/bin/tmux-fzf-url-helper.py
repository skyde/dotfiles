#!/usr/bin/env python3
import argparse
import re
import sys

ABSOLUTE_PATH = re.compile(r'/(?:[a-zA-Z0-9_.-]+/)+[a-zA-Z0-9_.-]+\.[a-zA-Z0-9_-]+')
URL = re.compile(r'(?:https?|ftp)://[^\s\'"`()<>]+')
WWW = re.compile(r'www\.[a-zA-Z0-9-]+\.[a-zA-Z]{2,}(?:/[^\s\'"`()<>]+)*')


def unique(items):
    seen = set()
    return [x for x in items if not (x in seen or seen.add(x))]


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '--paths-newest-first',
        action='store_true',
        help='print paths by their latest occurrence, newest first',
    )
    return parser.parse_args()


def main():
    args = parse_args()
    text = sys.stdin.read()

    paths = ABSOLUTE_PATH.findall(text)

    if args.paths_newest_first:
        print('\n'.join(unique(reversed(paths))))
        return

    paths = unique(paths)
    urls = unique(URL.findall(text) + [f'http://{w}' for w in WWW.findall(text)])

    html = [p for p in paths if p.endswith('.html')]
    other = [p for p in paths if not p.endswith('.html')]

    print('\n'.join(html + other + urls))


if __name__ == '__main__':
    main()
