---
module: Capstone
part: Part V - Practice
---

## Lab 1: read the tree of a page you own

Thirty minutes, no build required.

1. Open a real page from your product in Chrome.
2. DevTools > Elements > Accessibility pane. For each interactive element in the
   primary flow, record role, name, and `nameFrom`.
3. Switch on the full-page accessibility tree. Find three nodes you expected to
   be there that are ignored, and explain each one.
4. Open `chrome://accessibility`, enable Internal, and dump the same page.
   Diff it against what DevTools showed.

Deliverable: a list of every control whose name comes from `placeholder` or
`title`, and every focusable node that is ignored.

TRY: Do this before reading the rest of this module. Everything after here is easier with a concrete page in mind.

## Lab 2: predict, then verify

Write this file, predict the tree, then check.

```html
<div role="button" onclick="save()">Save</div>
<button><svg aria-hidden="true"></svg></button>
<label>Age <input type="number" value="42"></label>
<input type="text" placeholder="Search">
<a>Docs</a>
<div aria-hidden="true"><button>Hidden but focusable</button></div>
<ul><li>One</li><li>Two</li></ul>
```

Predict for each: role, name, `nameFrom`, focusable, ignored.

Answers worth checking carefully: the `role="button"` div is not focusable; the
icon button has no name; the `<a>` without `href` is generic, not a link; the
`aria-hidden` button is the rule-4 violation from module 5; and the list items
carry `kPosInSet` and `kSetSize`.

KEY: The point is not the answers, it is measuring the gap between your model and Chromium's. That gap is what this course exists to close.

## Lab 3: the keyboard and screen reader hour

The exercise most engineers skip, and the one that changes their judgement.

1. Unplug the mouse. Complete your product's primary flow with the keyboard only.
   Write down every place you got stuck.
2. Turn on a screen reader - NVDA on Windows, VoiceOver on macOS
   (`Cmd+F5`), Orca on Linux, ChromeVox on ChromeOS (`Ctrl+Alt+Z`).
3. Learn ten commands: start/stop, read all, next heading, next landmark, next
   form field, element list, browse/focus mode toggle.
4. Complete the same flow with the screen reader on and the monitor off or
   turned away.

TRY: Time yourself both ways. The ratio is the number to bring to your next planning meeting - it is far more persuasive than any audit score.

## Lab 4: build and break the pipeline

For Chromium engineers with a checkout.

1. `autoninja -C out/Default content_browsertests` and run
   `--gtest_filter="All/DumpAccessibilityTree*"` to see a green baseline.
2. Write a new tree test: an HTML file plus filters, and generate expectations
   with `--generate-accessibility-test-expectations`.
3. Break something deliberately in Blink - drop a `Handle*` call, or return the
   wrong role - and watch which expectation files change.
4. Do the same in the platform layer and observe that only the native passes move.
5. Revert, and write a unit test in `accessibility_unittests` that catches the
   same bug in seconds instead of minutes.

KEY: Step 3 and step 4 teach the layer split more convincingly than any diagram. Break it on purpose, once, in a safe place.

## Lab 5: instrument the cost

1. Run Chrome normally on a heavy page; note memory for the renderer and browser.
2. Restart with `--force-renderer-accessibility` and compare.
3. In `chrome://accessibility`, toggle inline text boxes and screen reader mode on
   and off; dump the tree each time and compare node counts and file sizes.
4. Run `tools/perf/run_benchmark blink_perf.accessibility` if you have a build.
5. Profile with the Performance panel while toggling a large subtree between
   `display:none` and visible.

Deliverable: your own numbers for what accessibility costs on the pages you care
about. Not someone else's benchmark - yours.

REF: `tools/perf/page_sets/system_health/accessibility_stories.py` if you want to make one of those pages a permanent Chromium benchmark.

## Quiz 1: concepts

1. Why can Chromium not answer accessibility API calls by querying the renderer?
2. What is the difference between *ignored* and *ignored but included in tree*?
3. Why are bounding boxes stored relative to an offset container?
4. What does `AXMode::kScreenReader` change that `kNativeAPIs` does not?
5. Why is a focused node never ignored?
6. What problem does `AXEventGenerator` solve that per-change events did not?
7. Why does a focus event get recomputed globally rather than fired directly?
8. Why does each iframe get its own accessibility tree even in the same process?

NOTE: Answers are on the next slide. Write yours down first - recognition is much easier than recall, and recall is what you will need in a code review.

## Quiz 1: answers

1. The renderer is sandboxed and the calls are synchronous; blocking IPCs cause
   jank and deadlock, and ATs make thousands of calls in a row.
2. Ignored means not exposed to platform APIs; included means still serialized
   into the internal tree - needed for naming, `aria-owns`, tables, and more.
3. So scrolling, moving, or animating a container updates one node instead of
   re-serializing its whole subtree.
4. It signals that a real screen reader is present, so Chromium stops pruning
   nodes only a screen reader would want and computes the full tree.
5. Otherwise focus could land on something the AT cannot describe - a dead end
   for the user.
6. Duplicate and platform-inconsistent events. Deriving events from tree diffs
   puts each platform's contract in one place.
7. Only one node on the desktop has focus and events from different processes can
   arrive out of order; only the browser knows which window is active.
8. So the same code path handles same-process and cross-process frames - if
   iframes break, they all break, and testing stays tractable.

## Quiz 2: debugging scenarios

For each, name the layer and the first thing you would check.

1. A button is announced correctly by NVDA and not at all by Narrator.
2. A menu is correct when the page loads and stale after it opens.
3. The tree looks right in DevTools but a node is missing in
   `chrome://accessibility`.
4. A magnifier highlights the wrong rectangle while the page is scrolled.
5. A live region announces four times for one update.
6. Voice control cannot activate a control that a screen reader reads fine.
7. A screen reader reads a text field's value but cannot navigate it by line.
8. Focus lands nowhere after closing a dialog.

KEY: Each of these maps to exactly one module of this course. If a scenario leaves you blank, that is the module to re-read.

## Quiz 2: answers

1. Platform layer, UIA path only - check the `uia-win` expectation and the
   control/content view properties.
2. Blink - a missing `Handle*`/`MarkAXObjectDirty` call for that state change.
3. Serialization - the node is ignored-but-included, or the parent was not
   re-serialized so the child never reached the browser.
4. Geometry - clipped versus unclipped bounds, or a stale scroll offset on an
   offset container.
5. Event generation or platform mapping - `AXEventGenerator` should have emitted
   one `LIVE_REGION_CHANGED` on the live root.
6. Actions - the element likely has no `kDoDefault`, or its name does not match
   the visible label so voice control cannot address it.
7. `AXMode::kInlineTextBoxes` is off; line structure is not being serialized.
8. Application code, not Chromium - focus was not restored to the trigger and
   fell to `<body>`.

## The pipeline, from memory

Cover the right column and reconstruct it.

| Stage | Owner |
| --- | --- |
| DOM + CSS + ARIA | Blink core |
| Accessibility objects | `AXObject`, `AXObjectCacheImpl` |
| Lifecycle and batching | `AXObjectCacheLifecycle`, `CommitAXUpdates` |
| Node data | `AXObject::Serialize` -> `ui::AXNodeData` |
| Delta computation | `BlinkAXTreeSource` + `AXTreeSerializer` |
| Transport | `ax.mojom.RenderAccessibilityHost::HandleAXEvents` |
| Cache | `ui::AXTree::Unserialize` |
| Composition and dispatch | `BrowserAccessibilityManager`, `AXTreeManagerMap` |
| Event derivation | `AXEventGenerator` |
| Platform objects | `AXPlatformNode`, `BrowserAccessibility` |
| Platform APIs | IA2 / UIA / NSAccessibility / ATK / ANI |
| The user | a screen reader, magnifier, switch, or braille display |

KEY: If you can produce this table from memory, you can debug anything in this subsystem by elimination.

## Twenty things to remember

1. Accessibility means the platform API, not just design.
2. Tree, events, actions - everywhere, forever.
3. Native HTML gives you the mapping for free.
4. ARIA changes semantics, never behavior.
5. A wrong role is worse than no role.
6. The name is the interface; know where it came from.
7. One tab stop per composite widget.
8. Never remove focus indicators.
9. Honor the preference media queries.
10. The renderer is sandboxed; the OS API is synchronous. Everything follows.
11. The tree is data - snapshot it, diff it, replay it.
12. `AXNodeData` is sparse on purpose.
13. The serializer never emits an invalid update.
14. `AXMode` decides what is computed at all.
15. Bounds are relative so that scrolling is cheap.
16. Line boxes plus character offsets make text geometry affordable.
17. Events are derived from tree diffs, not fired by hand.
18. Focus is recomputed globally, always.
19. Expectation files are the specification.
20. Work must be proportional to what changed, not to page size.

NOTE: Twenty is the number that fits on a slide. If you keep only five, keep 4, 6, 10, 14, and 20.

## Cheat sheet: flags, pages, and commands

Everything worth keeping within reach.

```sh
# force accessibility on without an AT
chrome --force-renderer-accessibility[=basic|form-controls|complete]
chrome --disable-renderer-accessibility

# inspect any app's platform tree / events
tools/accessibility/inspect/ax_dump_tree --pid=<pid>
tools/accessibility/inspect/ax_dump_events --pid=<pid>

# tests
out/release/accessibility_unittests
out/release/content_browsertests --gtest_filter="All/DumpAccessibility*"
out/Debug/content_browsertests --generate-accessibility-test-expectations \
    --gtest_filter="All/DumpAccessibilityTreeTest.<Name>/*"
tools/accessibility/rebase_dump_accessibility_tree_tests.py

# performance
tools/perf/run_benchmark blink_perf.accessibility --browser=exact \
    --browser-executable=out/Release/chrome
```

Internal pages: `chrome://accessibility` (enable Internal), `chrome://histograms`
for `Accessibility.*`, `chrome://flags` for feature toggles.

KEY: Three things cover most days: `--force-renderer-accessibility`, `chrome://accessibility`, and a dump test. Everything else is specialization.

## Where to go next

**Chromium**

- `//docs/accessibility/overview.md`, then `browser/how_a11y_works.md` parts 1-3.
- `third_party/blink/renderer/modules/accessibility/readme.md`.
- `ui/accessibility/ax_enums.mojom`, `ax_mode.h`, `ax_tree_serializer.h`.
- `content/test/data/accessibility/readme.md` for the test format.
- `//docs/accessibility/browser/tests.md` and `perf.md`.

**Web platform**

- WCAG 2.2, and the Understanding documents behind each criterion.
- WAI-ARIA, ARIA Authoring Practices, ACCNAME, HTML-AAM, Core-AAM.
- The WAI-ARIA WPT suite, where mapping conformance is settled between engines.

**Practice**

- One screen reader, learned properly.
- One real user session watched, with permission.

REF: Bookmark `ax_enums.mojom` and `ax_mode.h`. Between them they answer most "can Chromium express this?" questions in under a minute.

## Closing

Three ideas hold this whole subsystem together.

- **It is a pipeline.** Author intent becomes semantics, semantics become a tree,
  the tree becomes data, the data becomes a platform object, the platform object
  becomes speech, braille, magnification, or a click. Every bug lives at one
  stage.
- **It is a contract.** The tree is a promise to software you did not write,
  serving users you will never meet, on platforms whose conventions predate your
  code. Honesty in that contract is the whole job.
- **It is ordinary engineering.** Sparse data structures, delta encoding, cache
  invalidation, atomic updates, golden tests. Nothing here is charity work; it is
  some of the most carefully designed code in the browser.

KEY: You now know where every stage lives, what it costs, how to observe it, and how to test it. That is enough to fix real bugs - which is the only measure that matters.
