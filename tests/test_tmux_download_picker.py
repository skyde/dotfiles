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

    def test_wrapped_path_is_reconstructed_across_multiple_lines(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            path = root / 'nested' / 'artifact.txt'
            path.parent.mkdir()
            path.touch()

            path_string = str(path)
            first_split = path_string.index('nested') + len('nest')
            second_split = path_string.index('.txt') + len('.t')
            scrollback = '\n'.join(
                [
                    f'created {path_string[:first_split]}',
                    f'  {path_string[first_split:second_split]}',
                    f'\t{path_string[second_split:]})',
                ]
            )

            self.assertEqual(
                [path_string],
                self.run_helper(scrollback, '--paths-newest-first'),
            )

    def test_wrapped_path_handles_splits_on_either_side_of_a_slash(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / 'nested' / 'artifact.txt'
            path.parent.mkdir()
            path.touch()

            path_string = str(path)
            slash = path_string.index('/artifact.txt')

            for split in (slash, slash + 1):
                with self.subTest(split=split):
                    self.assertEqual(
                        [path_string],
                        self.run_helper(
                            f'{path_string[:split]}\n  {path_string[split:]})\n',
                            '--paths-newest-first',
                        ),
                    )

    def test_wrapped_repeat_uses_its_last_fragment_for_recency(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            repeated_path = root / 'repeated.txt'
            middle_path = root / 'middle.txt'
            repeated_path.touch()
            middle_path.touch()

            repeated = str(repeated_path)
            split = repeated.index('repeated') + len('repeat')
            scrollback = '\n'.join(
                [
                    f'first {repeated}',
                    f'middle {middle_path}',
                    f'newest {repeated[:split]}',
                    f'  {repeated[split:]}',
                ]
            )

            self.assertEqual(
                [repeated, str(middle_path)],
                self.run_helper(scrollback, '--paths-newest-first'),
            )

    def test_adjacent_complete_paths_are_not_joined(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            first_path = root / 'first.txt'
            second_path = root / 'second.txt'
            first_path.touch()
            second_path.touch()

            self.assertEqual(
                [str(second_path), str(first_path)],
                self.run_helper(
                    f'{first_path}\n{second_path}\n',
                    '--paths-newest-first',
                ),
            )

    def test_adjacent_paths_are_not_joined_even_when_joined_path_exists(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            first_path = root / 'first.txt'
            second_path = root / 'second.txt'
            first_path.mkdir()
            second_path.touch()

            joined_path = Path(f'{first_path}{second_path}')
            joined_path.parent.mkdir(parents=True)
            joined_path.touch()

            self.assertEqual(
                [str(second_path), str(first_path)],
                self.run_helper(
                    f'{first_path}\n{second_path}\n',
                    '--paths-newest-first',
                ),
            )

    def test_blank_line_is_not_treated_as_a_path_continuation(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / 'artifact.txt'
            path.touch()
            path_string = str(path)
            split = path_string.index('artifact') + len('arti')

            self.assertEqual(
                [],
                self.run_helper(
                    f'{path_string[:split]}\n\n{path_string[split:]}\n',
                    '--paths-newest-first',
                ),
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

            newest = str(newest_path)
            newest_split = newest.index('newest') + len('new')
            scrollback = root / 'scrollback.txt'
            scrollback.write_text(
                '\n'.join(
                    [
                        f'old {old_path}',
                        f'middle {middle_path}',
                        f'old repeated later {old_path}',
                        f'newest {newest[:newest_split]}',
                        f'  {newest[newest_split:]}',
                    ]
                )
                + '\n',
                encoding='utf-8',
            )

            fzf_input = root / 'fzf-input.txt'
            fzf_args = root / 'fzf-args.txt'
            tmux_args = root / 'tmux-args.txt'
            copied_path = root / 'copied-path.txt'

            fake_tmux = bin_dir / 'tmux'
            fake_tmux.write_text(
                textwrap.dedent(
                    '''\
                    #!/usr/bin/env bash
                    set -euo pipefail
                    printf '%s\n' "$@" > "$FAKE_TMUX_ARGS"
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
                    'FAKE_TMUX_ARGS': str(tmux_args),
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
            self.assertEqual(
                ['capture-pane', '-J', '-p', '-S', '-2000'],
                tmux_args.read_text(encoding='utf-8').splitlines(),
            )

            arguments = fzf_args.read_text(encoding='utf-8').splitlines()
            self.assertIn('--no-sort', arguments)
            self.assertIn('--layout=reverse', arguments)


if __name__ == '__main__':
    unittest.main()
