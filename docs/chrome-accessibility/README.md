# Chrome Accessibility: a 300-slide course

A self-contained course on how accessibility works in Chrome and Chromium, from
the ARIA attribute an author types through Blink's accessibility tree, the
serializer, the browser-process cache, and out to the screen reader.

Open [`index.html`](index.html) in any browser - no server, no network, no
dependencies. With JavaScript off it degrades to one long readable document.

## Contents

| Part | Modules | Slides |
| --- | --- | --- |
| I - Orientation | orientation; users and assistive technology; the accessibility tree | 1-34 |
| II - The web platform | HTML semantics; ARIA; names and descriptions; keyboard and focus; visual design and user preferences | 35-94 |
| III - Tools | Chrome's own accessibility features; DevTools; audits and CI; automation and the protocol | 95-140 |
| IV - The Chromium pipeline | architecture 101; Blink's tree; serialization and AXMode; the browser-side cache; events; actions, hit testing and geometry; platform APIs; Views, WebUI, PDF and other trees; ChromeOS | 141-248 |
| V - Practice | testing in Chromium; performance; debugging and contributing; capstone | 249-300 |

## Using the deck

| Key | Action |
| --- | --- |
| `->` / `Space` / `j` | next slide |
| `<-` / `k` | previous slide |
| `Home` / `End` | first / last slide |
| digits | jump to that slide number |
| `o` | contents |
| `/` | search every word on every slide |
| `n` | speaker notes |
| `t` | theme: system / dark / light |
| `?` | keyboard help |
| `Esc` | close a dialog |

Printing (or "Save as PDF") gives one slide per page with the notes included.
The deck remembers where you were, and `#slide-142` in the URL links to a slide.

The deck is itself keyboard-operable, screen-reader-labelled, contrast-checked in
both themes, and honors `prefers-reduced-motion` - reading it with a screen
reader on is a legitimate way to study it.

## Editing

Slides live in [`slides/`](slides), one Markdown file per module, and are built
into `index.html`:

```sh
./build.py            # rebuild index.html
./build.py --check    # parse and validate without writing
```

The source format is documented in
[`slides/README-format.md`](slides/README-format.md).

`tests/check-a11y-deck.py` (from the repository root) validates the sources,
checks the committed `index.html` is in sync, and asserts the deck's own
accessibility properties. Run it after any edit:

```sh
./tests/check-a11y-deck.py
```

## Sources

The content is grounded in Chromium's own documentation and source at head:

- `//docs/accessibility/overview.md` and `browser/how_a11y_works{,_2,_3}.md`
- `//third_party/blink/renderer/modules/accessibility/readme.md`
- `//ui/accessibility/` - `ax_enums.mojom`, `ax_mode.h`, `ax_node_data.h`,
  `ax_tree.h`, `ax_tree_serializer.h`, `ax_event_generator.h`,
  `ax_action_data.h`
- `//content/test/data/accessibility/readme.md` - the dump test format
- `//docs/accessibility/browser/{tests,perf,offscreen,uiautomation,android}.md`
- `//docs/accessibility/os/` - ChromeOS features and ChromeVox

Chromium moves; classes get merged and renamed. Where a slide names a class or a
flag it existed at the time of writing - verify against the tree you are
building.
