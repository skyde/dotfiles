import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
PRETTY = REPO_ROOT / 'common/.local/bin/json-pretty'
VIEW = REPO_ROOT / 'common/.local/bin/json-view'


class JsonPrettyTest(unittest.TestCase):
    def render(self, text, *args, expect_status=0):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / 'input.json'
            path.write_text(text, encoding='utf-8')
            result = subprocess.run(
                [sys.executable, str(PRETTY), '--color=never', *args, str(path)],
                text=True,
                capture_output=True,
            )
        self.assertEqual(expect_status, result.returncode, result.stderr)
        return result.stdout.splitlines()

    def test_escaped_newlines_become_real_lines(self):
        lines = self.render('{"log": "first\\nsecond\\nthird"}')

        # One row per line of the string, the hard breaks marked, and the
        # closing quote on its own row lined up with the key.
        self.assertEqual(
            [
                '{',
                '  "log": "',
                '  │ first⏎',
                '  │ second⏎',
                '  │ third',
                '  "',
                '}',
            ],
            lines,
        )

    def test_raw_strings_keeps_escapes_on_one_line(self):
        lines = self.render('{"log": "first\\nsecond"}', '--raw-strings')

        self.assertEqual(['{', '  "log": "first\\nsecond"', '}'], lines)

    def test_plain_raw_output_round_trips_as_json(self):
        source = {
            'text': 'a\nb\tc',
            'nested': {'list': [1, 2, {'deep': True, 'none': None}]},
            'embedded': '{"inner": [1, 2]}',
            'empty': {},
            'unicode': 'héllo 日本語',
        }
        lines = self.render(json.dumps(source), '--plain', '--raw-strings')

        self.assertEqual(source, json.loads('\n'.join(lines)))

    def test_embedded_json_string_is_expanded(self):
        lines = self.render('{"payload": "{\\"id\\": 7}"}')

        self.assertEqual(
            [
                '{',
                '  "payload": " ⟨json⟩',
                '  │ {',
                '  │   "id": 7',
                '  │ }',
                '  "',
                '}',
            ],
            lines,
        )

    def test_embedded_expansion_can_be_turned_off(self):
        lines = self.render('{"payload": "{\\"id\\": 7}"}', '--no-embedded')

        self.assertEqual(['{', '  "payload": "{\\"id\\": 7}"', '}'], lines)

    def test_string_that_only_looks_like_a_number_stays_a_string(self):
        # Expanding "123" into a number would misreport the document.
        self.assertEqual(['{', '  "n": "123"', '}'], self.render('{"n": "123"}'))

    def test_numbers_keep_the_text_from_the_file(self):
        lines = self.render('{"a": 1.50, "b": 1e3, "c": 123456789012345678901234567890}')

        self.assertEqual(
            ['{', '  "a": 1.50,', '  "b": 1e3,', '  "c": 123456789012345678901234567890', '}'],
            lines,
        )

    def test_duplicate_keys_are_both_shown(self):
        lines = self.render('{"k": 1, "k": 2}')

        self.assertEqual(['{', '  "k": 1,', '  "k": 2', '}'], lines)

    def test_long_value_wraps_without_a_break_glyph(self):
        # A soft wrap must be distinguishable from a real \n, which is what the
        # glyph is for: no glyph here, glyphs in test_escaped_newlines.
        value = 'word ' * 40
        lines = self.render(json.dumps({'long': value}), '--width', '40')

        body = [line for line in lines if line.startswith('  │ ')]
        self.assertGreater(len(body), 1)
        self.assertFalse(any('⏎' in line for line in body))
        for line in lines:
            self.assertLessEqual(len(line), 40)
        # Every word survives the wrap.
        rejoined = ' '.join(line[len('  │ '):] for line in body)
        self.assertEqual(value.split(), rejoined.split())

    def test_tabs_inside_strings_do_not_shear_the_layout(self):
        lines = self.render('{"t": "a\\tb\\nc"}')

        self.assertNotIn('\t', '\n'.join(lines))
        self.assertIn('  │ a  b⏎', lines)

    def test_json_lines_are_rendered_as_separate_records(self):
        lines = self.render('{"a": 1}\n{"a": 2}\n')

        self.assertEqual('{', lines[0])
        self.assertTrue(
            any(line.startswith('── record 2 ') for line in lines),
            lines,
        )
        self.assertEqual(2, sum(1 for line in lines if line == '{'))

    def test_line_numbers_are_contiguous_across_records(self):
        lines = self.render('{"a": 1}\n{"a": 2}\n', '--numbers')

        numbered = [line for line in lines if line[:4].strip().isdigit()]
        self.assertEqual(
            list(range(1, len(numbered) + 1)),
            [int(line[:4]) for line in numbered],
        )

    def test_broken_json_reports_where_and_still_shows_the_file(self):
        lines = self.render('{"a": 1,\n "b" 2}\n', expect_status=1)

        self.assertIn('line 2 column 6', lines[0])
        self.assertIn(' "b" 2}', lines)  # the file itself, unparsed

    def test_max_rows_truncates(self):
        lines = self.render(json.dumps({str(n): n for n in range(50)}), '--max-rows', '5')

        self.assertEqual(6, len(lines))  # 5 rows plus the truncation note
        self.assertIn('truncated', lines[-1])

    def test_colour_is_off_for_a_pipe_and_on_when_asked(self):
        source = '{"a": "b"}'
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / 'input.json'
            path.write_text(source, encoding='utf-8')

            auto = subprocess.run(
                [sys.executable, str(PRETTY), str(path)],
                text=True,
                capture_output=True,
                check=True,
            ).stdout
            forced = subprocess.run(
                [sys.executable, str(PRETTY), '--color=always', str(path)],
                text=True,
                capture_output=True,
                check=True,
            ).stdout

        self.assertNotIn('\033[', auto)
        self.assertIn('\033[38;2;156;220;254m', forced)  # #9cdcfe, the key colour

    def test_stdin_is_accepted(self):
        result = subprocess.run(
            [sys.executable, str(PRETTY), '--color=never'],
            input='{"a": [1, 2]}',
            text=True,
            capture_output=True,
            check=True,
        )

        self.assertEqual(['{', '  "a": [', '    1,', '    2', '  ]', '}'], result.stdout.splitlines())


class JsonViewTest(unittest.TestCase):
    def run_view(self, *args, **kwargs):
        return subprocess.run(
            ['bash', str(VIEW), *args],
            text=True,
            capture_output=True,
            **kwargs,
        )

    def test_a_single_named_file_needs_no_picker(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / 'one.json'
            path.write_text('{"a": "x\\ny"}', encoding='utf-8')

            # stdout is a pipe here, so the pager path is skipped and the
            # rendering is written straight out — no fzf involved.
            result = self.run_view(str(path), stdin=subprocess.DEVNULL)

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn('one.json', result.stdout)  # the header names the file
        self.assertIn('"a": "', result.stdout)
        self.assertIn('x⏎', result.stdout)

    def test_stdin_is_rendered(self):
        result = self.run_view(input='{"a": 1}')

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(['{', '  "a": 1', '}'], result.stdout.splitlines())

    def test_directory_without_json_files_says_so(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            (Path(temp_dir) / 'notes.txt').write_text('nope', encoding='utf-8')

            result = self.run_view(temp_dir, stdin=subprocess.DEVNULL)

        self.assertEqual(1, result.returncode)
        self.assertIn('no JSON files found', result.stderr)

    def test_missing_path_is_reported_without_failing_the_rest(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / 'one.json'
            path.write_text('{"a": 1}', encoding='utf-8')

            result = self.run_view(
                str(path), str(Path(temp_dir) / 'gone'), stdin=subprocess.DEVNULL
            )

        self.assertIn('no such file or directory', result.stderr)
        self.assertIn('"a": 1', result.stdout)  # the file that does exist still renders
        self.assertEqual(0, result.returncode, result.stderr)


if __name__ == '__main__':
    unittest.main()
