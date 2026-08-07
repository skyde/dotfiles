---
module: Chromium architecture 101
part: Part IV - The Chromium pipeline
---

## The processes that matter here

Accessibility touches three of Chromium's processes, and the boundaries between
them explain the entire design.

- **Browser process** - one per Chrome. Owns the windows, talks to the operating
  system, and is the *only* process allowed to implement OS accessibility APIs.
- **Renderer processes** - many, sandboxed. Each hosts one or more frames: DOM,
  CSS, layout, JavaScript. Cannot call OS APIs at all.
- **GPU process** - draws. Not involved in accessibility, but it is why the
  renderer's output is already asynchronous.

KEY: OS accessibility APIs are synchronous and live in the browser process. The page's data lives in a sandboxed renderer. Every design decision in this half of the course is a consequence of that sentence.

## Frames, not tabs

The unit of accessibility is the **frame**, not the tab.

- Site isolation puts cross-site iframes in different renderer processes.
- Each frame builds its own independent accessibility tree, whether or not it is
  in a separate process - deliberately, so there is only one code path.
- Each tree has a globally unique `AXTreeID` (an `UnguessableToken`), and an
  iframe node in a parent tree carries the `AXTreeID` of its child tree.
- The browser process keeps a map of tree ID to tree, and stitches them into one
  virtual tree on the fly when an AT walks it.

WHY: One code path for same-process and cross-process iframes means "if iframes break, they all break". That is a testing argument, and it has held up for a decade.

## Node IDs, unique IDs, and tree IDs

Three different identifiers, routinely confused in review comments.

| Name | Scope | Type |
| --- | --- | --- |
| Node ID (`AXNodeID`) | unique within one frame's tree | `int32_t` |
| Unique ID | globally unique in the browser process | `AXPlatformNodeId` |
| `AXTreeID` | names a whole tree | `UnguessableToken` |

- Blink's `AXObject` ID matches the DOM node ID when there is one; objects with no
  DOM node get negative IDs.
- Platform APIs need a globally unique handle per object, hence the second kind.

WATCH: A node ID is meaningless without knowing which tree it belongs to. Any API that takes a bare node ID across a process boundary is a bug waiting to happen; look for the `AXTreeID` beside it.

## Mojo: the interfaces you will meet

Accessibility crosses the renderer/browser boundary over Mojo, defined in
`content/common/render_accessibility.mojom`.

- `ax.mojom.RenderAccessibilityHost::HandleAXEvents()` - renderer to browser:
  a batch of `AXTreeUpdate`s plus events. This is the main pipe.
- `ax.mojom.RenderAccessibility::PerformAction()` - browser to renderer: an
  `AXActionData` describing what the AT wants done.
- `SetMode`, snapshot requests, and hit-test plumbing round it out.

On the browser side these land in `RenderFrameHostImpl`, which forwards to the
accessibility machinery; on the renderer side, `RenderAccessibilityManager`
receives and delegates to `RenderAccessibilityImpl`.

REF: `content/renderer/accessibility/render_accessibility_impl.h` is where renderer-side batching, throttling, and serialization scheduling live.

## The directories

Where the code actually is, and what each layer is allowed to know.

| Path | Contents |
| --- | --- |
| `third_party/blink/renderer/modules/accessibility` | `AXObject`, `AXObjectCacheImpl`, `BlinkAXTreeSource` - all web semantics |
| `content/renderer/accessibility` | `RenderAccessibilityImpl` - batching, IPC, snapshots |
| `ui/accessibility` | `AXNodeData`, `AXTree`, `AXTreeSerializer`, `AXEventGenerator`, enums |
| `ui/accessibility/platform` | `AXPlatformNode`, `BrowserAccessibility(Manager)`, per-OS glue |
| `content/browser/accessibility` | browser-side wiring, tree formatters, browser tests |
| `ui/views/accessibility` | `ViewAccessibility` for Chrome's own UI |
| `chrome/browser/ash/accessibility` | ChromeOS features |

KEY: `ui/accessibility` knows nothing about the web. That is what lets Views, PDF, ChromeOS, and Blink all feed the same machinery.

## Blink in one slide

Blink is the renderer's engine: DOM, CSS, layout, paint, and V8 embedding.

The pieces accessibility cares about:

- **DOM tree** - `blink::Node`. Authoritative for structure and attributes.
- **Layout tree** - `blink::LayoutObject`. Knows geometry, line boxes, and
  whether something is rendered at all.
- **Document lifecycle** - style -> layout -> paint, with well-defined "clean"
  points. Reading layout while dirty is forbidden.
- **Accessibility tree** - `AXObject`s wrapping nodes, layout objects, or both.

WATCH: Accessibility is instrumented into Blink by hand. There is no general observer that fires for everything accessibility cares about, so new DOM features need explicit `AXObjectCache` calls - a recurring source of "this new element is not exposed" bugs.

## The dead end: proxying

Worth knowing because it explains why the current design looks unusual.

The first attempt: keep lightweight proxy objects in the browser process; on each
API call, make a blocking IPC to the renderer and return the answer.

It failed for two reasons:

1. Blocking IPCs from browser to renderer cause jank and deadlock risk, and there
   is no non-blocking way to answer a synchronous OS API.
2. JAWS and NVDA scanned the entire page on load to build their virtual buffers -
   thousands of sequential calls. At ~1ms each, medium pages took ten seconds.

Plus: a call could block not just on the renderer's main thread being free, but
on layout being clean - and a hung renderer meant a hung screen reader.

KEY: The proxy design is the natural one, and it is unusable. Remember this the next time a design review proposes "just ask the renderer".

## The push model

So Chromium inverted it: the renderer *pushes* the whole tree, and the browser
answers every API call from its cache.

- Every OS accessibility call is answered locally, with no IPC and no blocking.
- The cache is updated atomically, so a client always sees a complete and
  consistent snapshot - possibly a fraction of a second stale.
- API calls are faster than in a single-process browser, because there is no
  DOM/layout query behind them.

Costs: memory duplication, and no laziness - the tree must be computed eagerly
even when nothing is consuming it.

WHY: A slightly stale but consistent tree is fine. The screen is also 10-20ms behind the DOM; users already live with that.

## It's all data

The consequence that keeps paying off.

- The tree is a serializable value, so it can be snapshotted, diffed, replayed,
  stored, and dumped to text.
- Text dumps are the entire testing strategy (`DumpAccessibilityTree`).
- A saved tree plus a stream of updates can be replayed with no page behind it -
  which is exactly how Android's "freeze-dried tabs" show an accessible snapshot
  while the real page loads.
- The cache does not have to live in the browser process: on ChromeOS it lives in
  the process running the AT.

KEY: Because the tree is data, accessibility gets record/replay, golden tests, and cross-process flexibility for free. Very few subsystems in Chromium have that.

## The complete pipeline, named

Every arrow, with the class that owns it. This is the map for modules 14-19.

```text
blink::Node + LayoutObject
  -> AXObject (+ AXObjectCacheImpl)          modules/accessibility
  -> AXObject::Serialize() -> ui::AXNodeData
  -> BlinkAXTreeSource + AXTreeSerializer    -> AXTreeUpdate
  -> RenderAccessibilityImpl                 content/renderer/accessibility
  == ax.mojom.RenderAccessibilityHost::HandleAXEvents ==>
  -> RenderFrameHostImpl                     content/browser
  -> ui::AXTree::Unserialize()               ui/accessibility
  -> BrowserAccessibilityManager (+ AXEventGenerator)
  -> BrowserAccessibility / AXPlatformNode   ui/accessibility/platform
  -> IAccessible2 | UIA | NSAccessibility | ATK | AccessibilityNodeInfo
  -> the assistive technology
```

TRY: Copy this into a scratch file and annotate it as you work through the next six modules. By module 19 you should be able to reproduce it from memory.
