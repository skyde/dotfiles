---
module: The browser-side cache
part: Part IV - The Chromium pipeline
---

## AXTree and AXNode

The browser process's copy of a frame's accessibility tree is a `ui::AXTree`,
built out of `ui::AXNode` wrappers around `AXNodeData`.

```cpp
class AXNode {
  const AXNodeData& data() const;
  AXNode* GetParent() const;
  const std::vector<AXNode*>& GetAllChildren() const;
  AXNodeID id() const;
};

class AXTree {
  explicit AXTree(const AXTreeUpdate& initial_state);
  bool Unserialize(const AXTreeUpdate& update);   // false if malformed
  AXNode* root() const;
  AXNode* GetFromId(AXNodeID id) const;
};
```

`AXNode` is a thin accessor: the data is the truth, the node is a convenient
handle with tree-walking helpers.

KEY: `AXTree` is the data model that every platform API call is ultimately answered from. If it is wrong, everything downstream is wrong.

## Unserialize: the atomic update

`AXTree::Unserialize()` applies an `AXTreeUpdate` as one atomic transaction.

- Either the whole update applies or it fails and returns false - the tree is
  never left half-updated in a way clients can observe.
- Old and new node data are both kept alive during the update so observers can
  compare them.
- Structural changes (creation, deletion, reparenting) are computed and reported,
  not merely applied.

WHY: Atomicity is what lets the browser answer synchronous OS calls at any moment. An AT calling in the middle of an update must never see half a tree.

## AXTreeObserver: how everything hooks in

`AXTreeObserver` is the extension point. `AXEventGenerator`, platform managers,
and various features are all observers.

```cpp
void OnNodeDataWillChange(AXTree*, const AXNodeData& old, const AXNodeData& neu);
void OnRoleChanged(AXTree*, AXNode*, ax::mojom::Role old, ax::mojom::Role neu);
void OnStateChanged(AXTree*, AXNode*, ax::mojom::State, bool new_value);
void OnStringAttributeChanged(AXTree*, AXNode*, ax::mojom::StringAttribute, ...);
void OnNodeWillBeDeleted(AXTree*, AXNode*);
void OnSubtreeWillBeReparented(AXTree*, AXNode*);
void OnNodeCreated(AXTree*, AXNode*);
void OnChildTreeConnectionChanged(AXNode* host_node);
void OnAtomicUpdateStarting(...);
void OnAtomicUpdateFinished(AXTree*, bool root_changed, const std::vector<Change>&);
```

REF: `ui/accessibility/ax_tree_observer.h`. The `OnAtomicUpdateFinished` change list is what event generation consumes - the diff, not the raw update.

## AXTreeManager and the map

One tree is not enough: a window can contain a main frame, several iframes, the
Views UI, a PDF plugin, and on ChromeOS an entire Android app.

- `AXTreeManager` owns one `AXTree` and knows its `AXTreeID`, its parent tree,
  and its child trees.
- `AXTreeManagerMap` is the process-wide registry from `AXTreeID` to manager.
- Given any node, you can walk *up* out of a frame into its embedder, and *down*
  into a child tree, purely through tree IDs.

```cpp
AXTreeManager* AXTreeManager::FromID(const AXTreeID&);
AXNode* GetParentNodeFromParentTree() const;
```

KEY: The "one big tree" an AT sees is composed on the fly from many trees by following tree IDs. There is no single stitched data structure to corrupt.

## BrowserAccessibilityManager

The layer that turns `AXTree` into something a platform can talk to. It lives in
`ui/accessibility/platform/` with one subclass per platform.

Its three jobs, from the architecture docs:

1. **Merge** trees into one tree of `BrowserAccessibility` objects by linking to
   other managers - because each page has a tree, but each *window* must present
   exactly one.
2. **Dispatch outgoing events** to the platform, in the per-platform
   `NotifyAccessibilityEvent` override.
3. **Dispatch incoming actions** to the right recipient via
   `AXPlatformTreeManagerDelegate`.

```cpp
BrowserAccessibility* GetBrowserAccessibilityRoot() const;
BrowserAccessibility* GetFromID(int32_t id) const;
virtual bool OnAccessibilityEvents(AXUpdatesAndEvents& details);
```

WATCH: On ChromeOS, `RenderFrameHostImpl` does not route events to a `BrowserAccessibilityManager` at all - there is no external platform screen reader to integrate with. ChromeOS goes through the automation API instead.

## The per-platform subclasses

Same shape, different output.

| Subclass | Fires |
| --- | --- |
| `BrowserAccessibilityManagerWin` | MSAA/IA2 events, UIA property-changed events |
| `BrowserAccessibilityManagerMac` | `NSAccessibilityPostNotification` |
| `BrowserAccessibilityManagerAuraLinux` | ATK signals |
| `BrowserAccessibilityManagerAndroid` | `AccessibilityEvent` to the Java layer |
| `BrowserAccessibilityManagerFuchsia` | Fuchsia semantics API |

Each one takes the platform-independent event list produced by
`AXEventGenerator` and decides which native notifications to emit, in which
order, on which node.

KEY: All the platform *quirk* knowledge - which AT needs which event when - is concentrated in these files. That is the point of the design.

## BrowserAccessibility: the per-node object

For each `AXNode` that is exposed, there is a `BrowserAccessibility` - the
browser-process object platform code holds on to.

- It implements `AXPlatformNodeDelegate`, so the platform layer can ask it for
  everything it needs in a cross-platform way.
- It hides ignored nodes: the platform-facing parent/child walk skips them, so
  `PlatformChildCount()` differs from the internal child count.
- Platform subclasses add API surface: `BrowserAccessibilityComWin`
  (IAccessible2/UIA), `BrowserAccessibilityCocoa` (NSAccessibility),
  `BrowserAccessibilityAuraLinux` (ATK), `BrowserAccessibilityAndroid`.

WHY: Keeping "internal tree" and "platform tree" separate lets Chromium keep nodes it needs internally (module 14's ignored-but-included) without inflicting them on ATs.

## Composing frames into one tree

Walking from a parent frame into a child:

1. The AT asks a node in the main frame for its children.
2. One of them is the iframe's node, which carries a child `AXTreeID` in
   `IntAttribute::kChildTreeId`.
3. `AXTreeManagerMap` resolves that ID to the child frame's manager.
4. The child tree's root becomes the iframe node's platform child.

Walking up is the mirror: the child manager knows its parent tree ID and the node
ID within it (`GetParentNodeFromParentTree`).

TRY: In `chrome://accessibility`, dump a page with a cross-origin iframe. The parent tree ends at the iframe node with a child tree ID; the child tree starts at its own root. The AT never sees the seam.

## Focus, globally

The browser process is the only place global focus can be computed, because it is
the only place that knows which window is active.

```svg Global focus is recomputed by starting at the active window, taking that tree's focused node, and recursing into any child tree it hosts until the deepest focused node is found; a platform focus event fires only if that node changed.
<svg viewBox="-10 20 940 175" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <marker id="fo-a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto">
      <path d="M0,0 L10,5 L0,10 z" class="d-fill-accent"/>
    </marker>
  </defs>
  <rect x="0" y="40" width="170" height="48" rx="7" class="d-box-accent"/>
  <text x="85" y="62" class="d-t" text-anchor="middle">active window</text>
  <text x="85" y="79" class="d-t-sm" text-anchor="middle">the browser knows this</text>
  <rect x="200" y="40" width="180" height="48" rx="7" class="d-box"/>
  <text x="290" y="62" class="d-t" text-anchor="middle">its focused tree</text>
  <text x="290" y="79" class="d-t-mono" text-anchor="middle">AXTreeData::focus_id</text>
  <rect x="410" y="40" width="170" height="48" rx="7" class="d-box"/>
  <text x="495" y="62" class="d-t" text-anchor="middle">focused node</text>
  <text x="495" y="79" class="d-t-sm" text-anchor="middle">hosts a child tree?</text>
  <rect x="610" y="40" width="170" height="48" rx="7" class="d-box-key"/>
  <text x="695" y="62" class="d-t" text-anchor="middle">deepest</text>
  <text x="695" y="79" class="d-t" text-anchor="middle">focused node</text>
  <rect x="770" y="118" width="150" height="46" rx="7" class="d-box"/>
  <text x="845" y="140" class="d-t" text-anchor="middle">fire the platform</text>
  <text x="845" y="156" class="d-t" text-anchor="middle">focus event</text>
  <path d="M172,64 L194,64" class="d-line" marker-end="url(#fo-a)"/>
  <path d="M382,64 L404,64" class="d-line" marker-end="url(#fo-a)"/>
  <path d="M582,64 L604,64" class="d-line" marker-end="url(#fo-a)"/>
  <path d="M495,90 L495,110 L290,110 L290,92" class="d-line" marker-end="url(#fo-a)"/>
  <text x="392" y="126" class="d-t-sm" text-anchor="middle">yes: recurse into the child tree</text>
  <path d="M782,88 L820,88 L820,112" class="d-line" marker-end="url(#fo-a)"/>
  <text x="700" y="152" class="d-t-sm" text-anchor="end">only if it differs from the last one</text>
</svg>
```

Any time focus changes in any tree, or the focused window or iframe changes, the
manager recomputes this and fires a platform focus event only if the result
differs from last time.

KEY: This is why a focus event is never fired straight from a tree update. Module 17 walks the race condition it prevents.

## Hit testing from the browser side

An AT asks "what is at (x, y)?" synchronously. The browser answers from the
cache, then improves the answer asynchronously.

1. First call: approximate hit test using cached bounding boxes. Usually right;
   can be wrong with layering or non-rectangular shapes.
2. Simultaneously, send `ax::mojom::Action::kHitTest` to the renderer for a real
   hit test, and record the result plus that element's visible bounds.
3. Next call: if the point is inside the last real result's bounds, return it.
   Otherwise, fall back to step 1 again.

With dozens of hit tests per second during mouse movement or touch exploration,
the user perceives it as accurate.

WHY: A synchronous, blocking hit test into the renderer risks deadlock and jank. This two-tier scheme trades a few milliseconds of error at object edges for never blocking.

## Bounds, clipping, and screen coordinates

Nodes store `AXRelativeBounds`; the browser computes absolute rectangles on
demand.

```cpp
struct AXRelativeBounds {
  AXNodeID offset_container_id;   // any ancestor, or -1 for the root
  gfx::RectF bounds;
  std::optional<gfx::Transform> transform;   // 4x4
};
```

- Walk up the offset container chain, applying transforms and adding origins.
- Apply scroll offsets (`kScrollX`, `kScrollY`) and clipping
  (`kClipsChildren`) along the way.
- `AXTree::RelativeToTreeBounds()` does this, and computes `offscreen` as a side
  effect: if an ancestor that clips its children fully clips this node, it is
  offscreen.
- Fully clipped nodes are pushed to the nearest ancestor edge with width or
  height 1 - deliberately not 0, so "clipped" is distinguishable from "unknown".

REF: `//docs/accessibility/browser/offscreen.md` is short and worth reading in full before you touch bounds code.

## Serving a platform API call

Put it together. A screen reader calls `IAccessible2::get_attributes` on a node:

1. The call arrives on the browser process main thread, on a
   `BrowserAccessibilityComWin`.
2. That object finds its `BrowserAccessibility`, and thus its `AXNode`.
3. `AXNodeData`'s sparse attributes are read, translated into IA2 attribute
   strings, and returned.
4. No IPC, no blocking, no layout, no renderer involvement. Microseconds.

If the renderer is hung, the answer is stale but instant. If the renderer has
crashed, the tree is torn down and the AT is told the object is gone.

KEY: "Answer from the cache, never block" is the invariant. Any change that would introduce a synchronous renderer round trip into this path will be rejected in review, and now you know why.
