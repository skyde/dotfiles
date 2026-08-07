#!/usr/bin/env python3
"""Unit tests for the lazygit config checker.

These run in CI through `python3 -m unittest discover -s tests -p 'test_*.py'`
and need nothing installed: the parts that need lazygit itself (the schema and
`lazygit --config`) live in tests/check-lazygit-config.sh, and the parts that
don't — the YAML subset parser and every semantic rule — are covered here.
"""

import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONFIG = ROOT / "common" / ".config" / "lazygit" / "config.yml"

_spec = importlib.util.spec_from_file_location(
    "lazygit_config_check", ROOT / "tests" / "lazygit_config_check.py"
)
checker = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(checker)


class YamlSubsetParser(unittest.TestCase):
    def test_matches_the_expected_structure(self):
        self.assertEqual(
            checker.mini_yaml_load(checker.SELFTEST_YAML), checker.SELFTEST_EXPECTED
        )

    def test_hash_inside_quotes_is_not_a_comment(self):
        parsed = checker.mini_yaml_load('a: "#7aa2f7" # trailing\nb: 1\n')
        self.assertEqual(parsed, {"a": "#7aa2f7", "b": 1})

    def test_unicode_escapes(self):
        """How lazygit's docs write Nerd Font glyphs, so gui.customIcons uses them."""
        parsed = checker.mini_yaml_load('icons: { a: "\\uf0c0", b: "\\U0001F600" }\n')
        self.assertEqual(parsed, {"icons": {"a": "\uf0c0", "b": "\U0001F600"}})
        with self.assertRaises(checker.YamlError):
            checker.mini_yaml_load('a: "\\uzzzz"\n')

    def test_rejects_constructs_it_cannot_read(self):
        for source in ("a: &anchor 1\n", "a: |\n  block\n", "a:\n\tb: 1\n"):
            with self.subTest(source=source), self.assertRaises(checker.YamlError):
                checker.mini_yaml_load(source)

    def test_agrees_with_pyyaml_on_the_real_config(self):
        yaml = None
        try:
            import yaml  # noqa: PLC0415
        except ImportError:
            self.skipTest("PyYAML not installed")
        text = CONFIG.read_text(encoding="utf-8")
        self.assertEqual(checker.mini_yaml_load(text), yaml.safe_load(text))


class KeyNames(unittest.TestCase):
    def test_accepts_the_forms_lazygit_documents(self):
        for key, canonical in [
            ("q", "q"),
            ("<esc>", "<esc>"),
            ("<c-n>", "<ctrl+n>"),
            ("<ctrl-n>", "<ctrl+n>"),
            ("<ctrl+shift+up>", "<ctrl+shift+up>"),
            ("<f12>", "<f12>"),
        ]:
            with self.subTest(key=key):
                self.assertEqual(checker.normalize_key(key), (canonical, None))

    def test_rejects_what_a_terminal_cannot_deliver(self):
        for key in ("<shift+a>", "<ctrl+A>", "<ctrl+nope>", "<c-n", "nope"):
            with self.subTest(key=key):
                canonical, error = checker.normalize_key(key)
                self.assertIsNone(canonical)
                self.assertTrue(error)


class SemanticRules(unittest.TestCase):
    def test_catches_every_known_bad_config(self):
        for config, expected in checker.SELFTEST_CASES:
            errors, _ = checker.check_semantics(config, None)
            if any(expected in error for error in errors):
                continue
            # The remaining cases are schema-level (unknown keys, wrong types),
            # which need lazygit's schema or defaults; check-lazygit-config.sh
            # covers those.
            self.assertTrue(
                any(key in config for key in ("git", "gui", "scrollOffBehavior")),
                f"{expected!r} was not reported for {config!r}",
            )

    def test_the_real_config_has_no_semantic_problems(self):
        config, mismatch = checker.load_yaml(str(CONFIG))
        self.assertIsNone(mismatch)
        errors, _ = checker.check_semantics(config, None)
        self.assertEqual(errors, [])

    def test_every_custom_command_key_is_reachable(self):
        """No custom command may take a key another one already claimed."""
        config, _ = checker.load_yaml(str(CONFIG))
        errors, _ = checker.check_semantics(config, None)
        self.assertEqual([e for e in errors if "already bound" in e], [])


if __name__ == "__main__":
    unittest.main()
