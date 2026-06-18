#!/usr/bin/env python3
import re
import sys

ABSOLUTE_PATH = re.compile(r'/(?:[a-zA-Z0-9_.-]+/)+[a-zA-Z0-9_.-]+\.[a-zA-Z0-9_-]+')
URL = re.compile(r'(?:https?|ftp)://[^\s\'"`()<>]+')
WWW = re.compile(r'www\.[a-zA-Z0-9-]+\.[a-zA-Z]{2,}(?:/[^\s\'"`()<>]+)*')


def unique(items):
    seen = set()
    return [x for x in items if not (x in seen or seen.add(x))]


def main():
    text = sys.stdin.read()

    paths = unique(ABSOLUTE_PATH.findall(text))
    urls = unique(URL.findall(text) + [f'http://{w}' for w in WWW.findall(text)])

    html = [p for p in paths if p.endswith('.html')]
    other = [p for p in paths if not p.endswith('.html')]

    print('\n'.join(html + other + urls))


if __name__ == '__main__':
    main()
