#!/usr/bin/env python3
import re
import shlex
import sys
import urllib.parse

ANSI_ESCAPE = re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]')
OSC_ESCAPE = re.compile(r'\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)')
OSC8_URL = re.compile(r'\x1b\]8;[^;]*;([^\x07\x1b]*)(?:\x07|\x1b\\)')
OSC8_SPAN = re.compile(r'\x1b\]8;[^;]*;[^\x07\x1b]*(?:\x07|\x1b\\).*?\x1b\]8;[^;]*;(?:\x07|\x1b\\)', re.DOTALL)
ABSOLUTE_PATH = re.compile(r'(?<![\w.:-~])/(?!/)[^\s\'"`<>|]+')
RELATIVE_PATH = re.compile(r'(?<![\w./~:-])(?:~/|\.{1,2}/|[A-Za-z0-9_.-]+/)[^\s\'"`<>|]+')
BARE_FILE_LOCATION = re.compile(r'(?<![\w./~:-])([A-Za-z0-9_.-]+\.[A-Za-z0-9_+.-]{1,12}:[0-9]+(?:-[0-9]+)?(?::[0-9]+)?)')
URL = re.compile(r'(?:[A-Za-z][A-Za-z0-9+.-]*://|mailto:)[^\s\'"`<>]+')
WWW = re.compile(r'www\.[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*\.[a-zA-Z]{2,}(?::[0-9]{2,5})?(?:[/?#][^\s\'"`<>]*)?')
LOCAL_URL = re.compile(
    r'(?<![\w./-])(?:localhost|127(?:\.[0-9]{1,3}){3}|0\.0\.0\.0|\[::1\]):[0-9]{2,5}(?:[/?#][^\s\'"`<>]*)?'
)
PYTHON_TRACEBACK = re.compile(r'File "([^"\n]+)", line ([0-9]+)')
PYTEST_NODEID = re.compile(r'(?<![\w./~:-])((?:/(?!/)|~/|\.{1,2}/|[A-Za-z0-9_.-]+/)[^\n\'"`<>|]*?\.py)::[^\s\'"`<>|]+')
WINDOWS_DRIVE_PATH_PREFIX = r'[A-Za-z]:[\\/]'
WINDOWS_BACKSLASH_UNC_PATH_PREFIX = r'\\\\[^\\/\s\'"`<>|]+[\\/]'
WINDOWS_SLASH_UNC_PATH_PREFIX = r'//[^/\s\'"`<>|]+/[^/\s\'"`<>|]+/'
WINDOWS_UNC_PATH_PREFIX = r'(?:' + WINDOWS_BACKSLASH_UNC_PATH_PREFIX + r'|' + WINDOWS_SLASH_UNC_PATH_PREFIX + r')'
WINDOWS_DRIVE_PATH_BODY = WINDOWS_DRIVE_PATH_PREFIX + r'[^\n\'"`<>|]+?\.[A-Za-z0-9_+.-]{1,12}'
WINDOWS_UNC_PATH_BODY = WINDOWS_UNC_PATH_PREFIX + r'[^\n\'"`<>|]+?\.[A-Za-z0-9_+.-]{1,12}'
WINDOWS_PATH_BODY = r'(?:' + WINDOWS_DRIVE_PATH_BODY + r'|' + WINDOWS_UNC_PATH_BODY + r')'
WINDOWS_FILE_LOCATION = re.compile(r'(?<![\w./~:-])(' + WINDOWS_PATH_BODY + r')(:[0-9]+(?:-[0-9]+)?(?::[0-9]+)?)')
WINDOWS_MSVC_LOCATION = re.compile(r'(?<![\w./~:-])(' + WINDOWS_PATH_BODY + r')\(([0-9]+)(?:,([0-9]+))?\)')
QUOTED_PATH_PREFIX = r'(?:' + WINDOWS_DRIVE_PATH_PREFIX + r'|' + WINDOWS_UNC_PATH_PREFIX + r'|/(?!/)|~/|\.{1,2}/|[A-Za-z0-9_.-]+/)'
QUOTED_PATH = re.compile(r'["\'](' + QUOTED_PATH_PREFIX + r'[^"\'\n<>|]+?)["\'](?::([0-9]+)(?::([0-9]+))?)?')
PAREN_FILE_LOCATION = re.compile(
    r'\(((?:/(?!/)|~/|\.{1,2}/|[A-Za-z0-9_.-]+/)[^\n\'"`<>|]*?\.[A-Za-z0-9_+.-]{1,12}):([0-9]+)(?::([0-9]+))?\)'
)
SPACED_FILE_LOCATION = re.compile(
    r'(?<![\w./~:-])((?:/(?!/)|~/|\.{1,2}/|[A-Za-z0-9_.-]+/)[^\n,\'"`<>|]*[^\S\n][^\n,\'"`<>|]*?\.[A-Za-z0-9_+.-]{1,12}):([0-9]+)(?::([0-9]+))?'
)
MSVC_LOCATION = re.compile(
    r'(?<![\w./~:-])((?:(?:/(?!/)|~/|\.{1,2}/|[A-Za-z0-9_.-]+/)[^\n\'"`<>|]*?|[A-Za-z0-9_.-]+)\.[A-Za-z0-9_+.-]{1,12})\(([0-9]+)(?:,([0-9]+))?\)'
)
VIM_QUICKFIX = re.compile(
    r'(?<![\w./~:-])((?:(?:/(?!/)|~/|\.{1,2}/|[A-Za-z0-9_.-]+/)[^\n\'"`<>|]*?|[A-Za-z0-9_.-]+)\.[A-Za-z0-9_+.-]{1,12})\|([0-9]+)(?:\s+col\s+([0-9]+))?\|'
)
SHELL_LINE_LOCATION = re.compile(
    r'(?<![\w./~:-])((?:(?:/(?!/)|~/|\.{1,2}/|[A-Za-z0-9_.-]+/)[^\n\'"`<>|:]*?|[A-Za-z0-9_.-]+)\.[A-Za-z0-9_+.-]{1,12}):\s+line\s+([0-9]+)\b'
)
GITHUB_ACTIONS_ANNOTATION = re.compile(r'::(?:debug|notice|warning|error)\s+([^\n]*?)::')
GIT_DIFF_LINE = re.compile(r'(?m)^(?:diff --git .+|(?:---|\+\+\+) .+|@@ .+ @@.*|(?:rename|copy) (?:from|to) .+)$')
GIT_HUNK = re.compile(r'^@@ -[0-9]+(?:,[0-9]+)? \+([0-9]+)(?:,[0-9]+)? @@')
TRAILING_SEPARATOR_PUNCTUATION = ':.,;!?'
TRAILING_BRACKETS = {
    ')': '(',
    ']': '[',
    '}': '{',
}


def unique(items):
    seen = set()
    return [x for x in items if not (x in seen or seen.add(x))]


def clean(value):
    value = value.rstrip(TRAILING_SEPARATOR_PUNCTUATION)

    while value:
        original = value
        for closer, opener in TRAILING_BRACKETS.items():
            while value.endswith(closer) and value.count(closer) > value.count(opener):
                value = value[:-1]
                value = value.rstrip(TRAILING_SEPARATOR_PUNCTUATION)

        if value == original:
            return value

    return value


def file_part(value):
    return re.sub(r':[0-9]+(?:-[0-9]+)?(?::[0-9]+)?$', '', value)


def is_html_path(value):
    return file_part(value).endswith('.html')


def is_file_like_url(value):
    return value.startswith('file://') or re.match(
        r'^(?:vscode|vscode-insiders|cursor|windsurf)://(?:file/|vscode-remote/)',
        value,
        re.IGNORECASE,
    )


def quoted_path(match):
    path = clean(match.group(1))
    line = match.group(2)
    column = match.group(3)

    if not path or '://' in path:
        return ''

    has_line = re.search(r':[0-9]+(?::[0-9]+)?$', path)
    has_extension = re.search(r'\.[A-Za-z0-9_+.-]{1,12}(?::[0-9]+(?::[0-9]+)?)?$', path)
    if not (line or has_line or has_extension):
        return ''

    if line and not has_line:
        path = f'{path}:{line}'
        if column:
            path = f'{path}:{column}'

    return path


def msvc_location(match):
    path = clean(match.group(1))
    line = match.group(2)
    column = match.group(3)

    if not path or '://' in path:
        return ''

    if column:
        return f'{path}:{line}:{column}'
    return f'{path}:{line}'


def windows_file_location(match):
    path = clean(match.group(1))
    suffix = match.group(2)

    if not path:
        return ''

    return f'{path}{suffix}'


def paren_file_location(match):
    path = clean(match.group(1))
    line = match.group(2)
    column = match.group(3)

    if not path or '://' in path:
        return ''

    if column:
        return f'{path}:{line}:{column}'
    return f'{path}:{line}'


def spaced_file_location(match):
    path = clean(match.group(1))
    line = match.group(2)
    column = match.group(3)

    if not path or '://' in path:
        return ''

    if column:
        return f'{path}:{line}:{column}'
    return f'{path}:{line}'


def vim_quickfix_location(match):
    path = clean(match.group(1))
    line = match.group(2)
    column = match.group(3)

    if not path or '://' in path:
        return ''

    if column:
        return f'{path}:{line}:{column}'
    return f'{path}:{line}'


def shell_line_location(match):
    path = clean(match.group(1))
    line = match.group(2)

    if not path or '://' in path:
        return ''

    return f'{path}:{line}'


def github_actions_annotation(match):
    props = {}
    for part in match.group(1).split(','):
        key, sep, value = part.partition('=')
        if sep:
            props[key.strip()] = urllib.parse.unquote(value.strip())

    path = clean(props.get('file', ''))
    line = props.get('line') or props.get('startLine')
    column = props.get('col') or props.get('column') or props.get('startColumn')

    if not path or '://' in path:
        return ''

    if line and line.isdigit():
        if column and column.isdigit():
            return f'{path}:{line}:{column}'
        return f'{path}:{line}'

    return path


def clean_git_diff_path(path):
    path = clean(path.strip())
    if path in {'', '/dev/null'}:
        return ''

    if path.startswith('a/') or path.startswith('b/'):
        path = path[2:]

    return path


def first_shell_token(value):
    try:
        parts = shlex.split(value)
    except ValueError:
        parts = value.split()

    return parts[0] if parts else ''


def git_diff_paths(text):
    paths = []
    current_new_path = ''

    for line in text.splitlines():
        if line.startswith('diff --git '):
            try:
                parts = shlex.split(line)
            except ValueError:
                parts = line.split()

            for path in parts[2:4]:
                path = clean_git_diff_path(path)
                if path:
                    paths.append(path)
            if len(parts) >= 4:
                current_new_path = clean_git_diff_path(parts[3])
            continue

        if line.startswith('--- ') or line.startswith('+++ '):
            path = first_shell_token(line[4:].split('\t', 1)[0])
            path = clean_git_diff_path(path)
            if path:
                paths.append(path)
            if line.startswith('+++ '):
                current_new_path = path
            continue

        hunk = GIT_HUNK.match(line)
        if hunk and current_new_path:
            paths.append(f'{current_new_path}:{hunk.group(1)}')
            continue

        if line.startswith('rename from ') or line.startswith('rename to '):
            path = clean_git_diff_path(line.split(' ', 2)[2])
            if path:
                paths.append(path)
            continue

        if line.startswith('copy from ') or line.startswith('copy to '):
            path = clean_git_diff_path(line.split(' ', 2)[2])
            if path:
                paths.append(path)

    return paths


def main():
    raw_text = sys.stdin.read()
    osc_urls = [clean(url) for url in OSC8_URL.findall(raw_text) if url]
    text = ANSI_ESCAPE.sub('', OSC_ESCAPE.sub('', OSC8_SPAN.sub(' ', raw_text)))

    bare_url_text = URL.sub(' ', text)
    local_urls = [f'http://{clean(url)}' for url in LOCAL_URL.findall(bare_url_text)]
    urls = unique(
        osc_urls
        + [clean(url) for url in URL.findall(text)]
        + [f'http://{clean(w)}' for w in WWW.findall(bare_url_text)]
        + local_urls
    )
    path_text = URL.sub(' ', text)
    path_text = WWW.sub(' ', path_text)
    path_text = LOCAL_URL.sub(' ', path_text)
    traceback_paths = [
        f'{path}:{line}'
        for path, line in PYTHON_TRACEBACK.findall(path_text)
        if path and not path.startswith('<') and '://' not in path
    ]
    path_text = PYTHON_TRACEBACK.sub(' ', path_text)
    git_paths = git_diff_paths(path_text)
    path_text = GIT_DIFF_LINE.sub(' ', path_text)
    windows_msvc_paths = [path for path in (msvc_location(match) for match in WINDOWS_MSVC_LOCATION.finditer(path_text)) if path]
    windows_file_paths = [
        path for path in (windows_file_location(match) for match in WINDOWS_FILE_LOCATION.finditer(path_text)) if path
    ]
    path_text = WINDOWS_MSVC_LOCATION.sub(' ', path_text)
    path_text = WINDOWS_FILE_LOCATION.sub(' ', path_text)
    quoted_paths = [path for path in (quoted_path(match) for match in QUOTED_PATH.finditer(path_text)) if path]
    paren_paths = [path for path in (paren_file_location(match) for match in PAREN_FILE_LOCATION.finditer(path_text)) if path]
    spaced_paths = [path for path in (spaced_file_location(match) for match in SPACED_FILE_LOCATION.finditer(path_text)) if path]
    msvc_paths = [path for path in (msvc_location(match) for match in MSVC_LOCATION.finditer(path_text)) if path]
    vim_quickfix_paths = [path for path in (vim_quickfix_location(match) for match in VIM_QUICKFIX.finditer(path_text)) if path]
    shell_line_paths = [path for path in (shell_line_location(match) for match in SHELL_LINE_LOCATION.finditer(path_text)) if path]
    github_actions_paths = [
        path for path in (github_actions_annotation(match) for match in GITHUB_ACTIONS_ANNOTATION.finditer(path_text)) if path
    ]
    pytest_paths = [clean(path) for path in PYTEST_NODEID.findall(path_text)]
    path_text = QUOTED_PATH.sub(' ', path_text)
    path_text = PAREN_FILE_LOCATION.sub(' ', path_text)
    path_text = SPACED_FILE_LOCATION.sub(' ', path_text)
    path_text = MSVC_LOCATION.sub(' ', path_text)
    path_text = VIM_QUICKFIX.sub(' ', path_text)
    path_text = SHELL_LINE_LOCATION.sub(' ', path_text)
    path_text = GITHUB_ACTIONS_ANNOTATION.sub(' ', path_text)
    path_text = PYTEST_NODEID.sub(' ', path_text)
    bare_file_locations = [clean(path) for path in BARE_FILE_LOCATION.findall(path_text)]
    path_text = BARE_FILE_LOCATION.sub(' ', path_text)
    paths = unique(
        traceback_paths
        + windows_msvc_paths
        + windows_file_paths
        + quoted_paths
        + paren_paths
        + spaced_paths
        + msvc_paths
        + vim_quickfix_paths
        + shell_line_paths
        + github_actions_paths
        + git_paths
        + pytest_paths
        + bare_file_locations
        + [clean(path) for path in ABSOLUTE_PATH.findall(path_text) + RELATIVE_PATH.findall(path_text)]
    )
    paths = [path for path in paths if path]

    html = [p for p in paths if is_html_path(p)]
    other = [p for p in paths if not is_html_path(p)]
    file_like_urls = [url for url in urls if is_file_like_url(url)]
    other_urls = [url for url in urls if not is_file_like_url(url)]

    print('\n'.join(html + other + file_like_urls + other_urls))


if __name__ == '__main__':
    main()
