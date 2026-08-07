#!/usr/bin/env python3
"""Validate the Chrome accessibility slide deck in docs/chrome-accessibility.

Checks the slide sources parse, that there are exactly 300 slides with unique
titles, that the committed index.html is in sync with them, and that the built
page keeps the accessibility properties the deck itself teaches.

    ./tests/check-a11y-deck.py
"""

from __future__ import annotations

import html.parser
import importlib.util
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DECK = ROOT / "docs" / "chrome-accessibility"
BUILD = DECK / "build.py"
INDEX = DECK / "index.html"

VOID = {
    "area", "base", "br", "col", "embed", "hr", "img", "input",
    "link", "meta", "source", "track", "wbr",
}

failures: list[str] = []
checks = 0


def check(condition: bool, message: str) -> None:
    global checks
    checks += 1
    if not condition:
        failures.append(message)


def load_builder():
    spec = importlib.util.spec_from_file_location("deck_build", BUILD)
    module = importlib.util.module_from_spec(spec)
    sys.modules["deck_build"] = module
    spec.loader.exec_module(module)
    return module


class TagBalance(html.parser.HTMLParser):
    """Minimal well-formedness check: every non-void tag is closed, in order."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[tuple[str, int]] = []
        self.errors: list[str] = []

    def handle_starttag(self, tag, attrs):
        if tag not in VOID:
            self.stack.append((tag, self.getpos()[0]))

    def handle_endtag(self, tag):
        if tag in VOID:
            return
        if not self.stack:
            self.errors.append(f"</{tag}> with no open tag at line {self.getpos()[0]}")
            return
        open_tag, line = self.stack.pop()
        if open_tag != tag:
            self.errors.append(
                f"</{tag}> at line {self.getpos()[0]} closes <{open_tag}> opened at line {line}"
            )


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def luminance(hex_color: str) -> float:
    hex_color = hex_color.lstrip("#")
    if len(hex_color) == 3:
        hex_color = "".join(ch * 2 for ch in hex_color)
    r, g, b = (int(hex_color[i : i + 2], 16) / 255 for i in (0, 2, 4))
    return (
        0.2126 * srgb_to_linear(r)
        + 0.7152 * srgb_to_linear(g)
        + 0.0722 * srgb_to_linear(b)
    )


def contrast(a: str, b: str) -> float:
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def main() -> int:
    check(BUILD.is_file(), f"missing {BUILD}")
    check(INDEX.is_file(), f"missing {INDEX} (run docs/chrome-accessibility/build.py)")
    if failures:
        report()
        return 1

    builder = load_builder()

    # --- sources parse, and the curriculum is the promised size -------------
    paths = sorted((DECK / "slides").glob("[0-9]*.md"))
    check(len(paths) >= 20, f"expected at least 20 slide modules, found {len(paths)}")

    modules = [builder.parse_module(p) for p in paths]
    slides = []
    for mod in modules:
        check(bool(mod.name), f"{mod.source}: empty module name")
        check(bool(mod.part), f"{mod.source}: empty part name")
        for slide in mod.slides:
            slide.number = len(slides) + 1
            slides.append(slide)

    check(
        len(slides) == builder.EXPECTED_SLIDES,
        f"expected {builder.EXPECTED_SLIDES} slides, found {len(slides)}",
    )

    seen: dict[str, str] = {}
    for slide in slides:
        key = slide.title.lower()
        check(key not in seen, f"duplicate slide title {slide.title!r} ({slide.source})")
        seen[key] = slide.source
        check(bool(slide.blocks), f"slide {slide.number} {slide.title!r} has no content")
        check(
            len(slide.title) <= 80,
            f"slide {slide.number} title is {len(slide.title)} chars: {slide.title!r}",
        )

    # every module should teach something and offer a takeaway or an exercise
    for mod in modules:
        kinds = {
            payload[0]
            for slide in mod.slides
            for kind, payload in slide.blocks
            if kind == "callout"
        }
        check(
            bool(kinds & {"key", "try"}),
            f"{mod.source}: no KEY or TRY callout anywhere in the module",
        )

    # --- the committed HTML is in sync -------------------------------------
    expected = builder.build_page(modules, slides)
    actual = INDEX.read_text(encoding="utf-8")
    check(
        expected == actual,
        "index.html is stale; re-run docs/chrome-accessibility/build.py",
    )

    # --- the built page is well formed and self-contained -------------------
    balance = TagBalance()
    balance.feed(actual)
    check(not balance.errors, "; ".join(balance.errors[:3]))
    check(not balance.stack, f"unclosed tags: {[t for t, _ in balance.stack[:5]]}")

    scripts = re.findall(r"<script[^>]*\ssrc=", actual)
    styles = re.findall(r"<link[^>]*\sstylesheet", actual)
    check(not scripts, "index.html loads an external script; it must be self-contained")
    check(not styles, "index.html loads an external stylesheet; it must be self-contained")

    # --- accessibility properties of the deck itself -----------------------
    check("<html lang=" in actual, "the page is missing a lang attribute")
    check(actual.count("<h1") == 1, "the page should have exactly one <h1>")
    check(
        actual.count("<h2") >= builder.EXPECTED_SLIDES,
        "every slide needs its own <h2> title",
    )
    check('class="skip"' in actual, "missing skip link")
    check('aria-live="polite"' in actual, "missing polite live region for slide changes")
    check(
        actual.count("aria-modal=\"true\"") >= 3,
        "dialogs should be marked aria-modal",
    )
    check(
        "prefers-reduced-motion" in actual,
        "the deck must honor prefers-reduced-motion",
    )
    check("prefers-color-scheme" in actual, "the deck must support a dark palette")
    check("@media print" in actual, "the deck must have a print stylesheet")
    check(
        actual.count("aria-labelledby='slide-") == builder.EXPECTED_SLIDES,
        "every slide section must be labelled by its heading",
    )
    css = "".join(re.findall(r"<style>(.*?)</style>", actual, re.S)).replace(" ", "")
    check(bool(css), "no inline stylesheet found")
    check(
        "outline:none" not in css and "outline:0" not in css,
        "the deck's own CSS must not remove focus outlines",
    )
    check(":focus-visible" in css, "the deck should style :focus-visible")

    # light and dark body text must clear WCAG AA
    light = contrast("#161a1f", "#ffffff")
    dark = contrast("#e6eaf0", "#151a21")
    muted_light = contrast("#525c66", "#ffffff")
    muted_dark = contrast("#9aa6b4", "#151a21")
    check(light >= 4.5, f"light body contrast is {light:.2f}:1, need 4.5")
    check(dark >= 4.5, f"dark body contrast is {dark:.2f}:1, need 4.5")
    check(muted_light >= 4.5, f"light muted text contrast is {muted_light:.2f}:1")
    check(muted_dark >= 4.5, f"dark muted text contrast is {muted_dark:.2f}:1")

    report()
    return 1 if failures else 0


def report() -> None:
    if failures:
        print(f"FAIL  {len(failures)} of {checks} checks failed:")
        for f in failures:
            print(f"  - {f}")
    else:
        print(f"ok    {checks} checks passed")


if __name__ == "__main__":
    raise SystemExit(main())
