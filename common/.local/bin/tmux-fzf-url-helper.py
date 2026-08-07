#!/usr/bin/env python3
import argparse
import os
import re
import sys

ABSOLUTE_PATH = re.compile(r'/(?:[a-zA-Z0-9_.-]+/)+[a-zA-Z0-9_.-]+\.[a-zA-Z0-9_-]+')
PATH_LINE_PREFIX = re.compile(r'[a-zA-Z0-9_./-]+')
PATH_LINE_SUFFIX = re.compile(r'/[a-zA-Z0-9_.-][a-zA-Z0-9_./-]*$')
URL = re.compile(r'(?:https?|ftp)://[^\s\'"`()<>]+')
# Every label, not just one: `www.foo.co.uk/bar` used to match only as far as
# `www.foo.co`, and the picker then offered `http://www.foo.co` — a different
# site, silently.
WWW = re.compile(r'www\.(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(?:/[^\s\'"`()<>]+)*')

# Sentence punctuation that follows a URL in prose and log output far more often
# than it ends one. Stripped from the tail so "see https://example.com/page."
# opens the page rather than a 404.
URL_TRAILING_PUNCTUATION = '.,;:!?'

MAX_WRAPPED_PATH_LENGTH = 4096
MAX_WRAPPED_PATH_LINES = 16


def unique(items):
    seen = set()
    return [x for x in items if not (x in seen or seen.add(x))]


def tidy_url(url):
    return url.rstrip(URL_TRAILING_PUNCTUATION)


def without_urls(text):
    """Blank out URL spans before scanning for filesystem paths.

    The path pattern happily matches the tail of a URL: `https://ex.com/a/b.txt`
    also yielded `/ex.com/a/b.txt`, so every URL in the scrollback put a second,
    bogus entry in the picker.

    Overwritten with spaces rather than removed, because `--paths-newest-first`
    orders its results by the offset each match ends at, and shifting the text
    would reorder the list.
    """
    masked = list(text)
    for pattern in (URL, WWW):
        for match in pattern.finditer(text):
            masked[match.start():match.end()] = ' ' * (match.end() - match.start())
    return ''.join(masked)


def split_lines_with_offsets(text):
    lines = []
    offset = 0
    for line_with_ending in text.splitlines(keepends=True):
        line = line_with_ending.rstrip('\r\n')
        lines.append((line, offset))
        offset += len(line_with_ending)

    if text and not lines:
        lines.append((text, 0))

    return lines


def wrapped_path_occurrences(text):
    occurrences = []
    lines = split_lines_with_offsets(text)

    for start_index, (line, _) in enumerate(lines):
        first_line = line.rstrip(' \t')
        first_fragment_match = PATH_LINE_SUFFIX.search(first_line)
        if not first_fragment_match:
            continue

        candidate = first_fragment_match.group()

        for end_index in range(
            start_index + 1,
            min(len(lines), start_index + MAX_WRAPPED_PATH_LINES),
        ):
            continuation_line, continuation_offset = lines[end_index]
            continuation = continuation_line.lstrip(' \t')
            indentation_length = len(continuation_line) - len(continuation)
            continuation_match = PATH_LINE_PREFIX.match(continuation)
            if not continuation_match:
                break

            fragment = continuation_match.group()

            # A complete absolute path on the next line is far more likely to be
            # a separate candidate than a continuation beginning with a slash.
            if (
                ABSOLUTE_PATH.fullmatch(fragment)
                and os.path.exists(fragment)
            ):
                break

            candidate += fragment
            if len(candidate) > MAX_WRAPPED_PATH_LENGTH:
                break

            if ABSOLUTE_PATH.fullmatch(candidate) and os.path.exists(candidate):
                end_offset = (
                    continuation_offset
                    + indentation_length
                    + continuation_match.end()
                )
                occurrences.append((end_offset, len(candidate), candidate))

            if continuation_match.end() != len(continuation.rstrip(' \t')):
                break

    return occurrences


def paths_newest_first(text):
    text = without_urls(text)
    occurrences = [
        (match.end(), len(match.group()), match.group())
        for match in ABSOLUTE_PATH.finditer(text)
    ]
    occurrences.extend(wrapped_path_occurrences(text))
    occurrences.sort(key=lambda occurrence: occurrence[:2], reverse=True)
    return unique(path for _, _, path in occurrences)


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

    if args.paths_newest_first:
        paths = paths_newest_first(text)
        if paths:
            print('\n'.join(paths))
        return

    paths = unique(ABSOLUTE_PATH.findall(without_urls(text)))
    urls = unique(
        [tidy_url(u) for u in URL.findall(text)]
        + [f'http://{tidy_url(w)}' for w in WWW.findall(text)]
    )

    html = [p for p in paths if p.endswith('.html')]
    other = [p for p in paths if not p.endswith('.html')]

    print('\n'.join(html + other + urls))


if __name__ == '__main__':
    main()
