---
module: Debugging and contributing
part: Part V - Practice
---

## The bisection ladder

Every accessibility bug is "the user heard the wrong thing". The skill is turning
that into "layer N is wrong". Walk the ladder and stop at the first disagreement.

1. **The DOM** - is the markup what you think it is? (Elements panel.)
2. **Blink's tree** - DevTools Accessibility pane and full-page tree.
3. **The browser cache** - `chrome://accessibility`, Internal enabled.
4. **The platform node** - `ax_dump_tree`, Inspect, Accessibility Inspector,
   Accerciser.
5. **The AT** - the screen reader's own log or speech viewer.

Between each pair is exactly one component. The first mismatch names your bug.

KEY: Never debug two layers at once. Find the seam, then read the code that spans it.

## Tools per layer

| Layer | Tool |
| --- | --- |
| DOM | DevTools Elements |
| Blink tree | DevTools Accessibility pane, full-page tree |
| Serialization | `--force-renderer-accessibility`, tracing, `AXSerializationErrorFlag` |
| Browser cache | `chrome://accessibility` (Internal on) |
| Platform | `ax_dump_tree`, `ax_dump_events`, Inspect, Accessibility Inspector, Accerciser |
| AT | NVDA speech viewer + log, VoiceOver Utility, Orca debug, ChromeVox log page |

REF: `//tools/accessibility/inspect/README.md` - `ax_dump_tree` and `ax_dump_events` work against *any* application on Windows, macOS, and Linux, which makes cross-browser comparison easy.

## Reading a tree dump fluently

```text
rootWebArea name='Checkout' focusable
++banner
++++link name='Home' url='https://example.com/'
++main
++++heading name='Payment' hierarchicalLevel=1
++++textField name='Card number' nameFrom=relatedElement
      required invalid describedbyIds=[19] focused
++++++staticText name='4242 4242'
++++++++inlineTextBox name='4242 4242' characterOffsets=9,18,27,...
++++button name='Pay' restriction=disabled
```

Read it in this order: role, name, `nameFrom`, states, relations, then children.
Anything surprising is usually `nameFrom`, an unexpected `ignored`, or a node
that is not where you expect in the hierarchy.

TRY: Dump the same page from DevTools and from `chrome://accessibility` and diff them. The differences are the ignored-but-included nodes and the platform filtering - exactly what modules 14 and 16 described.

## Symptom to cause: a quick table

| Symptom | Look at |
| --- | --- |
| Control unnamed | ACCNAME sources; `nameFrom` in the dump |
| Named but wrong text | `aria-labelledby` order; hidden text contributing |
| Node missing from the tree | ignored computation; `aria-hidden` ancestor; `display:none` |
| Node present but AT cannot reach it | platform filtering; ignored-but-included |
| Correct on load, stale after interaction | missing `Handle*` call in Blink |
| New child never appears | parent not marked dirty; `child_ids` not re-serialized |
| Announced twice | duplicate events; missing `event_from` provenance |
| Never announced | live region added at announce time; event suppressed |
| Works in NVDA, silent in Narrator | UIA-only path; check the `uia-win` pass |
| Wrong element at a point | hit testing; stale bounds; clipping |
| Focus goes nowhere | global focus computation; focused node ignored |

KEY: Nine of these eleven can be confirmed or eliminated from a tree dump alone, without a build.

## Logging and DCHECKs

- `LOG(ERROR) << ax_object` works in Blink - `AXObject` has a stream operator,
  and `ax_debug_utils.h` has tree-printing helpers.
- `ui::AXNodeData::ToString()` and `AXTree::ToString()` produce readable dumps in
  browser-side code.
- `AX_FAIL_FAST_BUILD()` guards extra invariant checking, including serializer
  self-checks, in debug and ASAN builds.
- The `AXObjectCacheLifecycle` DCHECKs are your friend: if you touch layout in
  the wrong state, they tell you exactly which rule you broke.

WATCH: Accessibility DCHECKs fire in tests long before users are affected. A DCHECK-only failure in `AX_FAIL_FAST_BUILD` is a real bug, not noise to be silenced.

## Reproducing without an AT

You do not need a screen reader to make progress on most bugs.

```sh
# force accessibility on, no AT needed
out/Default/chrome --force-renderer-accessibility

# a specific mode bundle
out/Default/chrome --force-renderer-accessibility=form-controls

# dump another process's tree
tools/accessibility/inspect/ax_dump_tree --pid=<pid>
```

Plus: `chrome://accessibility` toggles per-tab modes at runtime, so you can flip
`kScreenReader` on and off and watch the tree change under a live page.

TRY: Toggle inline text boxes on and off in `chrome://accessibility` on a text-heavy page and dump both. The size difference is a visceral lesson in what modes cost.

## Writing the minimal repro

The single highest-leverage debugging skill.

1. Start from the failing page; delete half; retest. Repeat.
2. Inline everything - no frameworks, no CSS files, no network.
3. Reduce to the smallest HTML that still shows the wrong tree.
4. Confirm it in another browser: if Firefox and Safari agree with Chrome, you
   may be looking at a spec question or an AT bug rather than a Chromium bug.
5. Turn it into a `DumpAccessibilityTree` test - now it is a regression test, not
   just a repro.

KEY: A 10-line repro plus a tree dump makes a bug fixable by someone who has never seen your product. Anything larger competes for attention it will not get.

## Filing a good bug

- Component: `UI>Accessibility`, with the platform sub-component where it
  applies (`UI>Accessibility>ChromeVox`, `>SelectToSpeak`, and so on).
- Include: Chrome version and channel, OS, the AT and its version, the API
  surface (IA2 vs UIA matters), a minimal repro, the tree dump, expected versus
  actual announcement.
- Say whether it is a regression, and bisect if you can - a bisect range turns a
  week of triage into an hour.
- For UIA specifically, `//docs/accessibility/browser/bugs/uia_bug_reporting.md`
  describes what the team needs.

NOTE: "Reproduces with `--force-renderer-accessibility` and no AT installed" is a phrase that makes any triager's day, because it means they can reproduce it too.

## Contributing to Chromium accessibility

- `OWNERS` files in `ui/accessibility`, `content/browser/accessibility`, and
  `third_party/blink/renderer/modules/accessibility` list reviewers; they are a
  small, responsive group.
- Start with `//docs/accessibility/overview.md`, then the three-part
  `how_a11y_works` series, then `readme.md` in Blink's accessibility module.
- Good first changes: a missing mapping with a dump test, a filter fix in an
  existing test, an event that fires twice, documentation that has gone stale.
- Expect review to focus on: which `AXMode` this belongs to, what it costs, which
  platforms need expectations, and whether an existing mechanism already does it.

REF: DIR_METADATA and OWNERS in each directory tell you the component to file against and who to ask.

## Reviewing an accessibility change

What to look for when the patch is not yours:

1. **Expectation diffs** - do they say what the description claims? Every changed
   line should be explicable.
2. **Missing platforms** - a mapping change with only a `blink` expectation is
   incomplete.
3. **Mode discipline** - is an expensive attribute serialized unconditionally?
4. **Event churn** - does this add an event per keystroke or per frame?
5. **Cached values** - is anything cached that can go stale without invalidation?
6. **Bounds** - anything storing screen coordinates is wrong.
7. **Spec alignment** - does HTML-AAM or Core-AAM already say what this should do?

KEY: In this subsystem the tests are the specification. A change whose expectation diff a reviewer cannot interpret is not reviewable, however small the code change is.

## Staying current

The subsystem moves; documents go stale. How to keep your mental model honest:

- `//docs/accessibility/` is the canonical set - overview, the three-part
  architecture series, and per-feature docs.
- Blink's `modules/accessibility/readme.md` is the most current internals doc and
  is maintained alongside the code.
- `accessibility_features.h` is a live list of what the team is currently
  building - read it every few months.
- `ax_enums.mojom` is the source of truth for the vocabulary.
- `//docs/accessibility/relnotes.md` records notable changes over time.

WATCH: This deck names classes that exist today. `AXLayoutObject` disappearing into `AXNodeObject` is a reminder: verify against the tree you are building, not against any document - including this one.

## Your first week, concretely

A plan if you are new to this area of Chromium:

1. Read `overview.md` and the three `how_a11y_works` parts. One afternoon.
2. Build `accessibility_unittests` and run them. Read one serializer test.
3. Build `content_browsertests`; run `All/DumpAccessibilityTree*`. Watch what a
   pass looks like on your platform.
4. Write a tree test for a mapping you care about; deliberately break Blink and
   watch it fail.
5. Turn on a screen reader and use Chrome for an hour without looking at the
   screen. This is not sentimental - it recalibrates every judgement you will
   make about severity.
6. Pick a `Available` bug in `UI>Accessibility` and fix it.

KEY: Step 5 is the one people skip and the one that changes how they prioritize for the rest of their career.
