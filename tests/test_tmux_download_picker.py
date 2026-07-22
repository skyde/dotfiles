import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import textwrap
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
HELPER = REPO_ROOT / 'common/.local/bin/tmux-fzf-url-helper.py'
PICKER = REPO_ROOT / 'common/.local/bin/tmux-copy-download-command.sh'


def make_executable(path):
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


class TmuxDownloadPickerTest(unittest.TestCase):
    def run_helper(self, text, *args):
        result = subprocess.run(
            [sys.executable, str(HELPER), *args],
            input=text,
            text=True,
            capture_output=True,
            check=True,
        )
        return result.stdout.splitlines()

    def test_newest_path_occurrence_wins(self):
        scrollback = textwrap.dedent(
            '''\
            first /tmp/old.txt
            then /tmp/middle.txt
            repeated later /tmp/old.txt
            newest /tmp/newest.txt
            '''
        )

        self.assertEqual(
            ['/tmp/newest.txt', '/tmp/old.txt', '/tmp/middle.txt'],
            self.run_helper(scrollback, '--paths-newest-first'),
        )

    def test_default_helper_order_is_unchanged(self):
        scrollback = textwrap.dedent(
            '''\
            /tmp/notes.txt https://example.com
            /tmp/index.html /tmp/notes.txt
            '''
        )

        self.assertEqual(
            ['/tmp/index.html', '/tmp/notes.txt', 'https://example.com'],
            self.run_helper(scrollback),
        )

    def test_picker_shows_and_selects_newest_path(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            bin_dir = root / 'bin'
            bin_dir.mkdir()

            picker = bin_dir / PICKER.name
            helper = bin_dir / HELPER.name
            shutil.copy2(PICKER, picker)
            shutil.copy2(HELPER, helper)
            make_executable(picker)
            make_executable(helper)

            old_path = root / 'old.txt'
            middle_path = root / 'middle.txt'
            newest_path = root / 'newest.txt'
            for path in (old_path, middle_path, newest_path):
                path.touch()

            scrollback = root / 'scrollback.txt'
            scrollback.write_text(
                '\n'.join(
                    [
                        f'old {old_path}',
                        f'middle {middle_path}',
                        f'old repeated later {old_path}',
                        f'newest {newest_path}',
                    ]
                )
                + '\n',
                encoding='utf-8',
            )

            fzf_input = root / 'fzf-input.txt'
            fzf_args = root / 'fzf-args.txt'
            copied_path = root / 'copied-path.txt'

            fake_tmux = bin_dir / 'tmux'
            fake_tmux.write_text(
                textwrap.dedent(
                    '''\
                    #!/usr/bin/env bash
                    set -euo pipefail
                    case "${1:-}" in
                      capture-pane) cat "$FAKE_SCROLLBACK" ;;
                      display-message) ;;
                      *) exit 2 ;;
                    esac
                    '''
                ),
                encoding='utf-8',
            )

            fake_fzf = bin_dir / 'fzf'
            fake_fzf.write_text(
                textwrap.dedent(
                    '''\
                    #!/usr/bin/env bash
                    set -euo pipefail
                    printf '%s\n' "$@" > "$FAKE_FZF_ARGS"
                    cat > "$FAKE_FZF_INPUT"
                    head -n 1 "$FAKE_FZF_INPUT"
                    '''
                ),
                encoding='utf-8',
            )

            fake_copy_download = bin_dir / 'copy-download-command'
            fake_copy_download.write_text(
                textwrap.dedent(
                    '''\
                    #!/usr/bin/env bash
                    set -euo pipefail
                    printf '%s' "${1:?}" > "$FAKE_COPIED_PATH"
                    '''
                ),
                encoding='utf-8',
            )

            for path in (fake_tmux, fake_fzf, fake_copy_download):
                make_executable(path)

            env = os.environ.copy()
            env.update(
                {
                    'PATH': f'{bin_dir}:{env["PATH"]}',
                    'FAKE_SCROLLBACK': str(scrollback),
                    'FAKE_FZF_INPUT': str(fzf_input),
                    'FAKE_FZF_ARGS': str(fzf_args),
                    'FAKE_COPIED_PATH': str(copied_path),
                }
            )

            result = subprocess.run(
                [str(picker)],
                text=True,
                capture_output=True,
                env=env,
                check=False,
            )

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(
                [str(newest_path), str(old_path), str(middle_path)],
                fzf_input.read_text(encoding='utf-8').splitlines(),
            )
            self.assertEqual(str(newest_path), copied_path.read_text(encoding='utf-8'))

            arguments = fzf_args.read_text(encoding='utf-8').splitlines()
            self.assertIn('--no-sort', arguments)
            self.assertIn('--layout=reverse', arguments)


if __name__ == '__main__':
    unittest.main()
