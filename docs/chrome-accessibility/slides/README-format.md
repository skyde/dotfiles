# Slide source format

One Markdown file per module, named `NN-slug.md`. `build.py` reads them in
filename order and concatenates them into the deck.

## Front matter

Every file starts with a fenced key/value block:

```
---
module: Serialization and AXMode
part: Part IV - The Chromium pipeline
---
```

`module` names the module in the eyebrow line and the contents grid; `part`
groups modules. An optional `slug` overrides the generated anchor.

## Slides

A slide starts at a `## ` heading and runs to the next one. Titles must be
unique across the whole deck - the build fails otherwise, because titles are
what search and the contents grid show.

```markdown
## The mode bundles

Named combinations, used throughout the codebase:

- `kAXModeBasic` - native APIs plus web contents
- `kAXModeComplete` - what a screen reader gets
  - nested bullets indent by two spaces
  wrapped continuation lines indent by two or more

1. ordered lists work the same way
2. and may wrap too

| Flag | Meaning |
| --- | --- |
| `kWebContents` | build a tree at all |

```cpp
inline constexpr AXMode kAXModeBasic(AXMode::kNativeAPIs | AXMode::kWebContents);
```

KEY: the sentence to remember
TRY: something to do at a real keyboard
REF: a file, flag, or URL worth opening
WHY: the design rationale
WATCH: the mistake people actually make

NOTE: a speaker note - hidden until `n`, always printed
```

## Rules the builder enforces

- No content before the first `## ` heading.
- Code fences must be closed; the language selects highlighting
  (`cpp`, `js`, `py`, `sh`, `html`, `text`).
- Callouts and notes continue onto following lines indented by four spaces.
- Inline markup: `` `code` ``, `**bold**`, `*italic*`, `[text](url)`. A link
  whose target is not `http(s):`, `mailto:`, `chrome://`, `about:`, or `#` is
  rendered as plain monospace text rather than an anchor, so file paths can be
  written naturally.
- Everything is HTML-escaped; slide text containing `</script>` is safe.

## Slide budget

The deck is exactly 300 slides (`EXPECTED_SLIDES` in `build.py`). Adding a
slide means removing one, or updating that constant and the counts in the
README and in `tests/check-a11y-deck.py`.
