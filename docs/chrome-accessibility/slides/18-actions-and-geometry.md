---
module: Actions, hit testing, and geometry
part: Part IV - The Chromium pipeline
---

## Actions: the other direction

An **action** is a request from assistive technology to change or interact with
the application. Events flow out; actions flow in.

Who relies on them:

- **Voice control** - almost entirely actions. Click this, set that value, scroll.
- **Screen readers** - a mix: mostly keyboard and events, but they warp the mouse
  and invoke default actions too.
- **Magnifiers** - scroll actions, to bring things into view.
- **Switch access** - default action on the scanned item.

KEY: A tree that describes everything perfectly but implements no actions is unusable for voice control users. Actions are not optional.

## The action vocabulary

`ax::mojom::Action`, abbreviated:

```text
kBlur                 kClearAccessibilityFocus  kCollapse    kCustomAction
kDecrement            kDoDefault                kExpand      kFocus
kGetImageData         kGetTextLocation          kHideTooltip kHitTest
kIncrement            kInternalInvalidateTree   kLoadInlineTextBoxes
kLongClick            kReplaceSelectedText      kResumeMedia
kScrollBackward       kScrollForward            kScrollUp/Down/Left/Right
kScrollToMakeVisible  kScrollToPoint            kScrollToPositionAtRowColumn
kSetAccessibilityFocus  kSetScrollOffset        kSetSelection
kSetSequentialFocusNavigationStartingPoint      kSetValue
kShowContextMenu      kShowTooltip              kStitchChildTree
kAnnotatePageImages   kSignalEndOfTest          kSuspendMedia
```

`kDoDefault` is "click", named that way because it is the default action for any
control - a checkbox toggles, a link navigates, a button activates.

NOTE: `kLoadInlineTextBoxes` is how a client asks for line-level text geometry on one node when `AXMode::kInlineTextBoxes` is globally off - lazy loading for an expensive feature.

## AXActionData

```cpp
struct AXActionData {
  ax::mojom::Action action;
  AXTreeID target_tree_id;
  AXNodeID target_node_id;
  std::string value;                    // for kSetValue
  gfx::Point target_point;              // for kHitTest, kScrollToPoint
  gfx::Rect target_rect;
  AXNodeID anchor_node_id, focus_node_id;   // for kSetSelection
  int anchor_offset, focus_offset;
  ax::mojom::ScrollAlignment horizontal_scroll_alignment;
  ax::mojom::ScrollBehavior scroll_behavior;
  int request_id;
};
```

Note the pair `target_tree_id` + `target_node_id`: node IDs are only unique
within a tree, so every cross-process action names both.

REF: `ui/accessibility/ax_action_data.h`, and the mojo mirror in `ui/accessibility/mojom/ax_action_data.mojom`.

## The path an action takes

```text
AT calls IAccessible2::doAction / NSAccessibilityPress / atk_action_do_action
  -> BrowserAccessibilityComWin / Cocoa / AuraLinux
  -> BrowserAccessibility::AccessibilityPerformAction(AXActionData)
  -> BrowserAccessibilityManager -> AXPlatformTreeManagerDelegate
  -> RenderFrameHostImpl
  == ax.mojom.RenderAccessibility::PerformAction(AXActionData) ==>
  -> RenderAccessibilityManager -> RenderAccessibilityImpl
  -> WebAXObject / AXObject -> the DOM element (click, focus, setValue)
```

Then the resulting change flows back out as a tree update and an event, tagged
`event_from = kAction`.

WATCH: The return value lies, and has to. Platform APIs want a synchronous success/failure code; the action is asynchronous. Chromium returns success if the request looks valid - it cannot know the outcome yet.

## Actions and user gestures

An action from an AT is a user gesture. That has consequences all over Blink.

- `kDoDefault` on a button must be able to open a popup, start media playback,
  and satisfy transient activation checks - otherwise voice control users are
  blocked by anti-abuse heuristics.
- Actions must respect the same security rules as real input: no cross-origin
  reach, no bypassing user-activation gating.
- `kSetValue` on a file input is (rightly) not a way to set a file path.

WHY: The AT is acting on behalf of a real user who really did just say "click Next". Treating it as synthetic input would break the platform's accessibility promise; treating it as fully trusted would be a security hole. The compromise is careful plumbing of activation state.

## Hit testing

"What object is at these screen coordinates?" - used by touch exploration, mouse
hover description, and every accessibility inspector.

The problem: on several platforms this API is synchronous, but a correct answer
needs the renderer's real hit-test machinery.

Chromium's three-step compromise:

1. **First call**: approximate hit test from cached bounding boxes in the browser
   process. Fast, usually correct, can fail on complex layering or
   non-rectangular shapes.
2. **In parallel**: send `kHitTest` to the renderer; when the result arrives,
   cache the node *and* its visible bounds.
3. **Next call**: if the point falls inside the cached result's bounds, return
   that node - it is authoritative. Otherwise, back to step 1.

KEY: During a drag or a mouse sweep, dozens of hit tests per second arrive, so the correct answer is nearly always already cached. Errors last milliseconds and only at object edges.

## AXRelativeBounds

```cpp
struct AXRelativeBounds {
  AXNodeID offset_container_id;   // any ancestor; -1 means the tree root
  gfx::RectF bounds;              // relative to that container
  std::optional<gfx::Transform> transform;   // full 4x4
};
```

Plus three sparse attributes that participate: `clips_children`, `x_scroll_offset`,
`y_scroll_offset`.

Why relative and not absolute: if bounds were in screen coordinates, dragging a
window or scrolling a div would invalidate every descendant's bounds and force a
re-serialization of the whole subtree.

KEY: Relative bounds mean scrolling and animating a container costs one node update, not a thousand. It is the single most important performance decision in the data format.

## Computing a global rectangle

```text
rect = node.bounds
container = node.offset_container_id
while container is valid:
    if container.transform: rect = container.transform * rect
    rect += container.bounds.origin
    rect -= (container.x_scroll_offset, container.y_scroll_offset)
    if container.clips_children: rect = intersect(rect, container.bounds)
    container = container.offset_container_id
```

- Implemented in `AXTree::RelativeToTreeBounds()`.
- The same walk computes `offscreen`: if a clipping ancestor fully clips the node,
  it is offscreen.
- Fully clipped nodes are pushed to the nearest ancestor edge with width or
  height 1, so "clipped" is distinguishable from "no size known".
- A node with no intrinsic size takes the union of its children; if still empty,
  it borrows the nearest sized ancestor's bounds and is marked offscreen.

REF: `//docs/accessibility/browser/offscreen.md` documents each of these edge cases with the HTML that produces it.

## Clipped versus unclipped

Two different rectangles, exposed separately because two different clients need
different answers.

- **`location`** - clipped by ancestors. Use it to *draw* a highlight: the box
  stays inside its container, which keeps focus rings from floating outside
  windows.
- **`unclippedLocation`** - ignores clipping. Use it to decide *how far to
  scroll* to bring something into view.

Both are exposed through `chrome.automation`, and both are computed by the same
walk with a flag.

WATCH: Using the clipped rect for scroll math produces the classic "scrolls to the wrong place, or not at all" bug for offscreen content.

## Text geometry

Platform APIs ask for the bounding box of arbitrary character ranges. Storing a
rectangle per character would be enormous, so:

- Text is split into **inline text boxes** - one per rendered line, same
  direction, contiguous characters.
- Each box stores its own bounds plus `kCharacterOffsets`: the x-offset of each
  character's edge within the box.

```svg A wrapped static text node becomes one inline text box per rendered line; each box stores its own bounds plus the x-offset of every character edge, so any character or range rectangle is arithmetic.
<svg viewBox="-10 20 940 200" xmlns="http://www.w3.org/2000/svg">
  <rect x="0" y="34" width="430" height="150" rx="8" class="d-zone"/>
  <text x="14" y="54" class="d-t-mono">staticText "Hello world"</text>
  <text x="14" y="72" class="d-t-sm">location=(8,8) size=(38,36)</text>
  <rect x="24" y="86" width="180" height="34" rx="5" class="d-box-accent"/>
  <text x="114" y="108" class="d-t-mono" text-anchor="middle">inlineTextBox "Hello "</text>
  <text x="24" y="136" class="d-t-sm">location=(0,0) size=(36,18)</text>
  <rect x="24" y="144" width="180" height="34" rx="5" class="d-box-accent"/>
  <text x="114" y="166" class="d-t-mono" text-anchor="middle">inlineTextBox "world"</text>
  <text x="220" y="108" class="d-t-sm">one box per</text>
  <text x="220" y="124" class="d-t-sm">rendered line</text>
  <text x="490" y="54" class="d-t-sm">characterOffsets = 12, 19, 23, 28, 36</text>
  <rect x="490" y="66" width="360" height="46" rx="5" class="d-box"/>
  <text x="502" y="98" class="d-t-mono">H  e  l  l  o</text>
  <path d="M490,112 L490,132" class="d-line"/>
  <path d="M562,112 L562,132" class="d-line"/>
  <path d="M634,112 L634,132" class="d-line"/>
  <path d="M706,112 L706,132" class="d-line"/>
  <path d="M778,112 L778,132" class="d-line"/>
  <path d="M850,112 L850,132" class="d-line"/>
  <text x="490" y="148" class="d-t-sm" text-anchor="middle">0</text>
  <text x="562" y="148" class="d-t-sm" text-anchor="middle">12</text>
  <text x="634" y="148" class="d-t-sm" text-anchor="middle">19</text>
  <text x="706" y="148" class="d-t-sm" text-anchor="middle">23</text>
  <text x="778" y="148" class="d-t-sm" text-anchor="middle">28</text>
  <text x="850" y="148" class="d-t-sm" text-anchor="middle">36</text>
  <text x="490" y="176" class="d-t-sm">the rectangle for characters 1-3 is the box</text>
  <text x="490" y="192" class="d-t-sm">origin plus offsets 12 and 23 - no extra storage</text>
</svg>
```

`kWordStarts` and `kWordEnds` ride along, so word-boundary navigation needs no
text analysis in the browser process.

KEY: Line-level boxes plus per-character offsets is the compression scheme that makes caching every character's position affordable.

## AXPosition and AXRange

The abstraction that turns all of that into an API.

- An **`AXPosition`** is a location in the tree: a node plus an offset, in tree
  position, text position, or "null" form, with an affinity for line boundaries.
- **`AXRange`** is a pair of positions, and knows how to compute its text and its
  screen rectangles.
- Both handle crossing node and frame boundaries, so "the next word" can walk out
  of one element and into the next.

Platform text APIs - IA2 `IAccessibleText`, UIA `ITextRangeProvider`, ATK
`AtkText`, macOS `AXTextMarker` - are all implemented on top of these.

REF: `ui/accessibility/ax_node_position.h` and `ax_range.h`. `AXTextMarker` on macOS is essentially a serialized `AXPosition`.

## Selection and the caret

Selection is a tree-level fact, stored in `AXTreeData`.

```cpp
AXTreeID sel_anchor_tree_id, sel_focus_tree_id;
AXNodeID sel_anchor_object_id, sel_focus_object_id;
int32_t sel_anchor_offset, sel_focus_offset;
ax::mojom::TextAffinity sel_anchor_affinity, sel_focus_affinity;
```

- The AT sets it with `kSetSelection`, giving anchor and focus node/offset pairs.
- Changes surface as `DOCUMENT_SELECTION_CHANGED` and `TEXT_SELECTION_CHANGED`,
  and drive `CARET_BOUNDS_CHANGED` for magnifiers.
- Selection can span frames, which is why the anchor and focus each carry a tree
  ID.

TRY: Turn on caret browsing (F7), arrow through a paragraph, and watch `CARET_BOUNDS_CHANGED` and the selection fields update in a tree dump. It is the clearest way to see positions in motion.
