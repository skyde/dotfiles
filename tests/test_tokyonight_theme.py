from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8").lower()


class TokyoNightThemeTest(unittest.TestCase):
    def test_terminal_palettes_match(self) -> None:
        kitty = read("common/.config/kitty/themes/tokyonight_night.conf")
        wezterm = read("common/.config/wezterm/wezterm.lua")

        ansi = (
            "#15161e",
            "#f7768e",
            "#9ece6a",
            "#e0af68",
            "#7aa2f7",
            "#bb9af7",
            "#7dcfff",
            "#a9b1d6",
            "#414868",
            "#ff899d",
            "#9fe044",
            "#faba4a",
            "#8db0ff",
            "#c7a9ff",
            "#a4daff",
            "#c0caf5",
        )
        for color in ansi:
            with self.subTest(color=color):
                self.assertIn(color, kitty)
                self.assertIn(color, wezterm)

        for config in (kitty, wezterm):
            self.assertIn("#1a1b26", config)
            self.assertIn("#283457", config)
            self.assertIn("#ff5000", config)

    def test_interactive_accent_is_consistent(self) -> None:
        for relative_path in (
            "common/.config/kitty/themes/tokyonight_night.conf",
            "common/.config/wezterm/wezterm.lua",
            "common/.config/nvim/lua/plugins/tokyonight.lua",
            "common/.config/fzf/tokyonight.sh",
        ):
            with self.subTest(relative_path=relative_path):
                self.assertIn("#ff5000", read(relative_path))

    def test_fzf_theme_is_shared_by_both_shells(self) -> None:
        theme_path = ".config/fzf/tokyonight.sh"
        self.assertIn(theme_path, read("common/.zshenv"))
        self.assertIn(theme_path, read("common/.bashrc-custom"))

    def test_fzf_options_remain_compatible_with_packaged_versions(self) -> None:
        for relative_path in (
            "common/.config/fzf/tokyonight.sh",
            "common/.zshenv",
            "common/.zshrc",
            "common/.bashrc-custom",
        ):
            content = read(relative_path)
            with self.subTest(relative_path=relative_path):
                self.assertNotIn("--highlight-line", content)
                self.assertNotIn("--style=minimal", content)
                self.assertNotIn("--wrap ", content)

    def test_tui_theme_assets_are_committed(self) -> None:
        btop = read("common/.config/btop/themes/tokyo-night.theme")
        yazi = read("common/.config/yazi/theme.toml")
        lazygit = read("common/.config/lazygit/config.yml")

        self.assertIn('color_theme = "tokyo-night.theme"', read("common/.config/btop/btop.conf"))
        self.assertIn('theme[main_bg]="#1a1b26"', btop)
        self.assertIn('hovered         = { bg = "#292e42" }', yazi)
        self.assertIn('selectedlinebgcolor: ["#283457"]', lazygit)

    def test_legacy_palette_values_do_not_return(self) -> None:
        files = (
            "common/.tmux.conf",
            "common/.zshenv",
            "common/.bashrc-custom",
            "common/.config/fzf/tokyonight.sh",
            "common/.config/kitty/themes/tokyonight_night.conf",
            "common/.config/wezterm/wezterm.lua",
            "common/.config/lazygit/config.yml",
        )
        legacy_colors = (
            "#2e3c64",
            "#1d202f",
            "#85899c",
            "#82aaff",
            "#444a73",
            "#2d3f76",
            "#c8d3f5",
            "#88c0d0",
            "#516e7b",
            "#3c425f",
            "#80a0ff",
            "#afff5f",
        )

        for relative_path in files:
            content = read(relative_path)
            for color in legacy_colors:
                with self.subTest(relative_path=relative_path, color=color):
                    self.assertNotIn(color, content)


if __name__ == "__main__":
    unittest.main()
