---
module: Performance
part: Part V - Practice
---

## Accessibility is not free

The push model buys instant API responses at the cost of eager work in the
renderer and memory in the browser.

Where the cost lands:

- **Renderer CPU** - computing the tree, recomputing cached values, serializing.
  It runs inside the document lifecycle, so it can cause jank.
- **Browser memory** - the entire tree of every frame of every tab, cached.
- **IPC** - update batches, proportional to how much changes.
- **Browser CPU** - unserializing, event generation, platform event dispatch.

KEY: The tree must be computed eagerly even when nothing consumes it. That is the fundamental cost of never blocking on the renderer.

## The jank scenario

The canonical bad case, straight from Blink's own README: a subtree flips from
`display:none` to `display:block`.

- Every descendant needs an `AXObject`.
- Every one needs cached values computed, which needs clean layout.
- Every one gets serialized into `AXNodeData`.
- All of it happens inside the lifecycle, before the frame can be presented.

A 10,000-node subtree appearing at once is a dropped frame, maybe several.

WATCH: This is why "just add `aria-hidden` and toggle it" is not a cheap operation, and why virtualized lists are as good for accessibility performance as they are for rendering.

## AXMode as the throttle

The mode flags exist to make the browser pay only for what a client needs.

- `kNativeAPIs` alone - a client attached, but web contents not exposed at all.
- `+ kWebContents` - basic tree: role, name, value, state, location.
- `+ kInlineTextBoxes` - line boxes and character offsets. Expensive: every text
  node gains children.
- `+ kExtendedProperties` - screen-reader-grade attributes: text style, table
  details, live region properties, relations, plus HTML tag/id/class.
- `+ kHTML` - every HTML attribute. Very expensive in memory.
- `kScreenReader` - only when a real screen reader is detected; without it,
  Chromium may prune nodes only a screen reader would want.

Filter flags prune instead of add: `kFormsAndLabelsOnly`, `kOnScreenOnly`.

REF: The long-term direction, per Blink's readme, is to start with the most minimal mode and escalate only when a client demonstrably needs more.

## On-screen mode

`kAXModeOnScreen` (with the `kOnScreenOnly` filter) is the newer answer to the
"huge page, tiny viewport" problem: serialize what is on screen, not what exists.

- Gated by `IsAccessibilityOnScreenAXModeEnabled()`.
- Trades completeness for cost: perfect for tools that only act on what is
  visible, wrong for a screen reader that navigates below the fold.
- Requires solid offscreen computation, which is why the bounds and clipping
  rules in module 18 matter so much here.

WHY: A news site's DOM can be enormous while the viewport shows 40 nodes. Serializing the other 20,000 for a client that will never read them is pure waste.

## Lazy loading inside the tree

Selective escalation instead of a global mode change:

- `ax::mojom::Action::kLoadInlineTextBoxes` - ask for line-level text geometry for
  *one* node, on demand, when `kInlineTextBoxes` is globally off.
- `kGetImageData` - fetch image pixels only when something wants them.
- `kAnnotatePageImages` - run image annotation only when requested.
- Snapshot limits - `set_max_node_count()` and `set_timeout()` bound one-shot
  serializations.

KEY: The general pattern is "cheap by default, escalate per node on request". Any new expensive attribute should be designed to fit it.

## What Blink does to keep the cost down

- **Batching** - all changes in a task collapse into one serialization pass at
  frame cadence.
- **Deferred updates** - `DeferTreeUpdate` queues work until layout is clean, so
  nothing is computed twice.
- **Cached values** - the handful of expensive properties (`cached_is_ignored_`,
  `cached_can_set_focus_attribute_`, `cached_local_bounding_box_`, ...) are
  computed once per update.
- **Sparse data** - `AXNodeData` allocates nothing for unset attributes.
- **Dirty-node serialization** - only changed nodes are re-serialized, and the
  serializer skips clean nodes entirely.
- **Parallelism** - accessibility processing runs in parallel with GPU rendering,
  after the lifecycle completes.

NOTE: `IsAccessibilityPruneRedundantInlineConnectivityEnabled` and `IsAccessibilityBlockFlowIteratorEnabled` are examples of ongoing, measurable optimizations in this area.

## Measuring: Telemetry stories

Chromium measures accessibility performance with Telemetry.

```sh
tools/perf/run_benchmark system_health.common_desktop \
  --story-filter="accessibility.*" \
  --browser canary

tools/perf/run_benchmark system_health.common_desktop \
  --story-filter="accessibility.*" \
  --browser=exact --browser-executable=out/Release/chrome
```

- Stories live in `tools/perf/page_sets/system_health/accessibility_stories.py`;
  if a page is slow with accessibility on, add it there.
- Metrics are defined in
  `third_party/catapult/tracing/tracing/metrics/accessibility_metric.html`.
- Results land on chromeperf.

TRY: Add a story for a page in your product that feels slow with a screen reader running. A reproducible number is the difference between a fixed bug and a closed one.

## Measuring: Blink perf microbenchmarks

```sh
tools/perf/run_benchmark blink_perf.accessibility \
  --browser=exact --browser-executable=out/Release/chrome
```

- Tests in `third_party/blink/perf_tests/accessibility/`.
- These isolate one operation - building a large tree, computing names, walking
  text - with no page noise.
- Use them when optimizing a specific function; use system_health stories when
  you care about the end-to-end experience.

KEY: Microbenchmarks tell you whether your optimization worked. Stories tell you whether it mattered.

## Measuring in the field

- `Accessibility.*` histograms record which `AXMode` bundles are active in the
  wild - populated by `ui/accessibility/ax_mode_histogram_logger.cc`, which is why
  every new mode flag requires a histogram enum update.
- `IsAccessibilityPerformanceMeasurementExperimentEnabled()` gates the
  experimental measurement work.
- `chrome://histograms` locally, plus tracing with the accessibility category, to
  see serialization timings on a real page.

WATCH: Field data is what distinguishes "expensive on a synthetic page" from "expensive for users". Modes are turned on by real clients in patterns you would not predict.

## Cost by page pattern

Rough intuitions, useful when triaging:

| Pattern | Cost |
| --- | --- |
| Static article, 2,000 nodes | negligible |
| Infinite scroll appending 500 nodes/scroll | steady serialization pressure |
| Live region updating every 100ms | event storm; hurts the AT more than the CPU |
| `display:none` -> `block` on a large subtree | spike; possible dropped frames |
| Canvas app with a 50,000-node fallback tree | expensive to build, expensive to keep |
| A table with 100,000 cells | large memory, slow initial serialization |
| Animation that moves a container | cheap - relative bounds mean one node updates |

KEY: The last row is the payoff for relative bounds. The rows above it are where you should look first when something is slow.

## Advice for web developers

Concrete things that make a page cheaper with accessibility on:

- **Virtualize long lists** - keep the DOM small; it is the same fix as for
  rendering performance.
- **Do not toggle huge subtrees** between `display:none` and visible; prefer
  swapping smaller regions.
- **Throttle live regions.** Announcing ten times a second helps nobody.
- **Avoid `aria-owns`** unless the DOM genuinely cannot be reordered - it
  invalidates ancestor caches.
- **Avoid gratuitous ARIA attribute churn** in animation frames; each change
  dirties a node.
- **Prefer native elements** - their serialization paths are the most optimized.

TRY: Profile your app with `--force-renderer-accessibility` on. Anything that gets dramatically slower is something a screen reader user experiences every day.

## Advice for Chromium engineers

- Adding an attribute? Ask which `AXMode` it belongs to, and whether it can be
  loaded on demand instead.
- Adding a `Handle*` call? Confirm it defers rather than doing work immediately.
- Computing something expensive? Check whether it belongs in cached values, and
  what invalidates it.
- Touching bounds? Preserve relative coordinates; never store screen coordinates
  in the tree.
- Changing serialization? Run `blink_perf.accessibility` before and after, and
  check the mode histograms are still coherent.
- Anything that makes serialization O(page) rather than O(change) is a regression,
  no matter how fast it looks on a small test page.

KEY: The performance rule of this subsystem is one sentence: work must be proportional to what changed, not to how big the page is.
