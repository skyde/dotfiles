---
module: Blink's accessibility tree
part: Part IV - The Chromium pipeline
---

## AXObject: the wrapper

`AXObject` is the abstract base class for one node in Blink's accessibility tree.
Everything web-specific lives here or in the cache.

- Each `AXObject` wraps a `blink::Node`, a `blink::LayoutObject`, or both.
- It has an **AXID** (`AXObject::AXObjectID()`), which matches the DOM node ID
  when there is a node behind it, and is negative when there is not.
- It holds very little state: role, parent/child links, and a small set of
  *cached values*. Everything else is computed on demand.

```cpp
// third_party/blink/renderer/modules/accessibility/ax_object.h
ax::mojom::blink::Role RoleValue() const;
AXObject* ParentObjectIncludedInTree() const;
const AXObjectVector& ChildrenIncludingIgnored() const;
bool IsIgnored() const;
bool IsDetached() const;
void Serialize(ui::AXNodeData*, ui::AXMode) const;
```

KEY: `AXObject` is a view onto the DOM and layout trees, not a copy of them. Its job is to answer questions, and to fill in an `AXNodeData` when asked.

## The subclasses that remain

Blink has been deliberately shrinking this hierarchy for years.

- **`AXNodeObject`** - the workhorse. Wraps a `Node`, a `LayoutObject`, or both,
  in its `node_` and `layout_object_` members. Almost everything is one of these.
  - Pseudo-element descendants have a layout object and no node.
  - `display:none` and `display:contents` elements have a node and no layout object.
- **`AXInlineTextBox`** - one rendered line of text; always a leaf.
- A few specialized ones remain: `AXImageMapLink`, `AXSlider`,
  `AXValidationMessage`, `AXMediaControl`, `AXProgressIndicator`.

WATCH: Older documents (and older slides in other courses) describe `AXLayoutObject` as the main concrete class. It is gone - folded into `AXNodeObject`. If a document mentions it, check its date before trusting the rest.

## Cached values

A handful of properties are expensive enough, or needed often enough, that
`AXObject` caches them and invalidates on change.

```cpp
cached_is_ignored_
cached_is_ignored_but_included_in_tree_
cached_is_aria_hidden_
cached_can_set_focus_attribute_
cached_local_bounding_box_
```

They share a pattern: they need clean layout, they are read repeatedly, or they
are inherited from the parent - so a change can force a recursive refresh of a
whole subtree's cached values.

WHY: These are the properties that would otherwise be recomputed dozens of times per serialization pass. They are also the properties most likely to go stale in a bug, which is why "did you update cached values?" is a standard review question.

## AXObjectCacheImpl

The cache owns the whole tree for one document. It exists only when accessibility
is enabled, and the `Document` owns it.

Responsibilities:

1. Map `Node`/`LayoutObject` to `AXObject`, creating lazily.
2. Receive `Handle*` notifications from all over Blink.
3. Defer work into a queue, then process it when layout is clean.
4. Own the relation cache (`AXRelationCache`) for `aria-owns`, `aria-labelledby`,
   and the reverse maps.
5. Drive serialization and hand updates to the content layer.

```cpp
void HandleAttributeChanged(const QualifiedName& attr_name, Element*);
void HandleValueChanged(Node*);
void HandleFocusedUIElementChanged(Element* old_focus, Element* new_focus);
void ChildrenChanged(Node*);
void MarkAXObjectDirty(AXObject*);
bool CommitAXUpdates(Document&, bool force);
```

REF: `ax_object_cache_impl.h` is long but skimmable. Read the list of `Handle*` methods once - it is effectively the list of everything in Blink that accessibility reacts to.

## Instrumentation, not observation

Blink does not have general-purpose listeners for everything accessibility cares
about. Instead, accessibility calls are sprinkled through Blink by hand.

```cpp
// somewhere in core/, on a value change:
if (AXObjectCache* cache = GetDocument().ExistingAXObjectCache())
  cache->HandleValueChanged(this);
```

Consequences you will meet:

- Adding a new HTML feature means finding every state change and notifying the
  cache. Miss one and the tree silently goes stale.
- The `ExistingAXObjectCache()` guard is everywhere, because the cache usually
  does not exist.
- A missing notification is invisible in tests that dump the tree once after load -
  it only shows up in event tests or in dynamic scenarios.

WATCH: "The tree is correct on load but wrong after interaction" is almost always a missing `Handle*` call.

## The accessibility lifecycle

`AXObjectCacheLifecycle` mirrors `DocumentLifecycle` and enforces what may happen
when. The states, in order:

```svg The four active lifecycle states in order: defer tree updates while layout is dirty, process the deferred updates once layout is clean, finalize the tree structure, then freeze it and serialize.
<svg viewBox="-10 20 940 150" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <marker id="lc-a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto">
      <path d="M0,0 L10,5 L0,10 z" class="d-fill-accent"/>
    </marker>
  </defs>
  <text x="0" y="35" class="d-t-sm">kUninitialized</text>
  <text x="920" y="35" class="d-t-sm" text-anchor="end">kDisposing / kDisposed</text>
  <rect x="0" y="45" width="205" height="46" rx="7" class="d-box-warn"/>
  <text x="102" y="73" class="d-t-mono" text-anchor="middle">kDeferTreeUpdates</text>
  <rect x="238" y="45" width="205" height="46" rx="7" class="d-box"/>
  <text x="340" y="73" class="d-t-mono" text-anchor="middle">kProcessDeferredUpdates</text>
  <rect x="476" y="45" width="205" height="46" rx="7" class="d-box"/>
  <text x="578" y="73" class="d-t-mono" text-anchor="middle">kFinalizingTree</text>
  <rect x="714" y="45" width="206" height="46" rx="7" class="d-box-key"/>
  <text x="817" y="73" class="d-t-mono" text-anchor="middle">kSerialize</text>
  <path d="M207,68 L232,68" class="d-line" marker-end="url(#lc-a)"/>
  <path d="M445,68 L470,68" class="d-line" marker-end="url(#lc-a)"/>
  <path d="M683,68 L708,68" class="d-line" marker-end="url(#lc-a)"/>
  <text x="102" y="112" class="d-t-sm" text-anchor="middle">layout is dirty:</text>
  <text x="102" y="128" class="d-t-sm" text-anchor="middle">queue work only</text>
  <text x="340" y="112" class="d-t-sm" text-anchor="middle">layout clean: update structure</text>
  <text x="340" y="128" class="d-t-sm" text-anchor="middle">and cached values</text>
  <text x="578" y="112" class="d-t-sm" text-anchor="middle">structure final,</text>
  <text x="578" y="128" class="d-t-sm" text-anchor="middle">nothing orphaned</text>
  <text x="817" y="112" class="d-t-sm" text-anchor="middle">tree frozen: no creation,</text>
  <text x="817" y="128" class="d-t-sm" text-anchor="middle">no cached-value updates</text>
  <path d="M0,150 L920,150" class="d-zone"/>
  <text x="460" y="166" class="d-t-sm" text-anchor="middle">one pass per frame, after the document lifecycle is clean</text>
</svg>
```

Helper predicates make the rules explicit: `StateAllowsImmediateTreeUpdates()`,
`StateAllowsRemovingAXObjects()`, `StateAllowsReparentingAXObjects()`,
`StateAllowsSerialization()`.

KEY: If you are writing Blink accessibility code and are unsure whether you may touch layout, the answer is in the lifecycle state - and there is a DCHECK waiting for you if you guess wrong.

## Defer, then process with clean layout

The naming convention that runs through the file:

- `ChildrenChanged()` is called from anywhere, at any time. It **defers**.
- `ChildrenChangedWithCleanLayout()` runs later, during
  `kProcessDeferredUpdates`, when layout is guaranteed clean.

```cpp
void AXObjectCacheImpl::ChildrenChanged(Node* node) {
  DeferTreeUpdate(TreeUpdateReason::kChildrenChanged, node);
}
```

`CommitAXUpdates()` is the entry point that drains the queue, finalizes, and
serializes. It runs after the document lifecycle completes, in parallel with GPU
rendering.

WHY: Querying accessibility properties with dirty layout gives inconsistent answers or crashes. Batching also collapses many changes into one serialization, which is the single biggest performance lever in the renderer.

## Ignored, included, and both

Three states, and the distinction that confuses every newcomer.

- **Ignored** - not exposed to platform APIs. The AT cannot see it.
- **Included in tree** - present in Blink's internal tree and serialized, even if
  ignored.
- **Ignored but included** - the interesting case: invisible to the AT, but kept
  because Chromium needs it internally.

Computed by `AXObject::ComputeIsIgnored()` (and `AXTree::ComputeNodeIsIgnored()`
on the browser side), cached as `cached_is_ignored_` and
`cached_is_ignored_but_included_in_tree_`.

KEY: "In the tree" and "exposed to the AT" are different questions. The serializer ships ignored-but-included nodes; the platform layer filters them out.

## Why something is ignored

The common reasons, roughly in frequency order:

- `role="none"` / `role="presentation"`.
- Hidden by CSS: `display:none`, `visibility:hidden` (`IsHiddenViaStyle()`).
- `aria-hidden="true"` (`IsAriaHidden()`) - hides the whole subtree.
- `inert`, or inert by context (`IsInert()`).
- Uninteresting content: whitespace nodes, bare `<span>`s, `<label>`s already used
  to name a control, and typically `<html>` and `<body>` themselves.
- Structural noise: SVG `<symbol>`, a 1x1 canvas.

**The exception that saves users**: a focused node is *never* ignored, even with
`aria-hidden` or `display:none` on it. Otherwise focus could land somewhere the
AT cannot describe at all.

TRY: Put `aria-hidden="true"` on a button and focus it with script. Watch it reappear in the tree. That special case is one `if` in `ComputeIsIgnored()` and it prevents a whole class of dead ends.

## Why an ignored node is still included

Keeping ignored nodes in the internal tree buys correctness elsewhere:

- **`aria-owns` targets** are always included - they must be re-parentable.
- **Name and description sources** (`IsUsedForLabelOrDescription()`) - a hidden
  `<label>` still has to contribute text.
- **Flat-tree parents that differ from DOM parents** - shadow DOM slotting, where
  DOM traversal alone is unsafe.
- **Media controls** - their ignored state can flip without a layout update.
- **Menus** - kept so events can be generated when they open.
- **Table parts** - role and ignored status depend heavily on ancestry.
- **`<br>` when visible** - needed to detect paragraph edges in text navigation.
- **Pseudo-element content and its ancestors** - so all generated content is
  reachable.

REF: `third_party/blink/renderer/modules/accessibility/readme.md` enumerates these with links. It is the best single document about Blink accessibility that exists.

## Relations: AXRelationCache

`aria-owns`, `aria-labelledby`, `aria-describedby`, and friends are IDREFs, which
means both forward and *reverse* lookups are needed - when a target appears or
changes, whoever points at it must be invalidated.

`AXRelationCache` maintains:

- ID to element maps for pending and resolved relations.
- Reverse maps (who labels me, who owns me).
- The `aria-owns` bookkeeping that guarantees a node has exactly one parent and
  no cycles.

WATCH: `aria-owns` is the most expensive and most crash-prone attribute in this file. Every cycle check, every "already owned" case, and every reparenting invalidation lives here.

## Text, positions, and ranges

Blink's text-side classes, which the platform layer mirrors:

- **`AXInlineTextBox`** - one rendered line, with character offsets, direction,
  and word boundaries. Built only when `AXMode::kInlineTextBoxes` is on (or
  requested on demand via the `kLoadInlineTextBoxes` action).
- **`AXPosition`** and **`AXRange`** - positions within the accessibility tree,
  the abstraction behind selection, caret, and text-boundary queries.
- **`AXSelection`** - maps DOM selection to accessibility positions and back.
- **`AXBlockFlowIterator`** - newer machinery for walking text in block flow;
  gated by `IsAccessibilityBlockFlowIteratorEnabled()`.

KEY: Every "read the next word", "where is the caret", "highlight this sentence" feature bottoms out in these classes.

## Serialization from Blink's side

The hand-off, precisely:

1. `AXObject::Serialize(ui::AXNodeData*, ui::AXMode)` fills a node's data,
   consulting the mode so expensive attributes are skipped when not requested.
2. `BlinkAXTreeSource` implements `AXTreeSource` over Blink's tree, so
   `AXTreeSerializer` can walk it without knowing anything about Blink.
3. `AXObjectCacheImpl::GetUpdatesAndEventsForSerialization()` collects the
   the `AXTreeUpdate` batch and its events.
4. `RenderAccessibilityImpl` sends them over Mojo.

During `kSerialize` the tree is frozen: `const AXObject*` only, no creation, no
cached-value updates. That freeze is what makes the batch internally consistent.

TRY: Set a breakpoint in `AXObject::Serialize` on a page with a simple button and step out through the serializer. One walk through this path is worth ten readings of the docs.
