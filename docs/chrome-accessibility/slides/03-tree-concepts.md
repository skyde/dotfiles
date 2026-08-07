---
module: The accessibility tree
part: Part I - Orientation
---

## The tree is not the DOM

The accessibility tree resembles the DOM tree, and beginners assume a 1:1
mapping. It is not, and the differences are where the bugs live.

Things that break the mapping:

- CSS **generated content** - `::before`, `::after`, list markers - creates
  accessibility nodes with no DOM node behind them.
- `display:none` subtrees are absent entirely.
- `visibility:hidden` hides a node, but a descendant can set
  `visibility:visible` and reappear.
- `aria-hidden="true"` removes a subtree that is still painted on screen.
- `role="presentation"` / `role="none"` removes a node but keeps its children.
- `aria-owns` re-parents a node somewhere else in the tree entirely.

KEY: The accessibility tree is derived from DOM *and* layout *and* ARIA. Any of the three can change its shape.

## Wrappers: what a node is made of

In Blink, an accessibility object is a *wrapper*. It holds almost no state of its
own; it computes answers from the thing it wraps.

- Most wrap a `blink::Node` (`AXNodeObject`).
- Many of those also have a `blink::LayoutObject`, which is required to answer
  questions about geometry, visibility, and line wrapping.
- Some wrap a layout object with **no** DOM node - anonymous blocks, generated
  content, list markers.

WHY: Keeping state in the DOM and computing accessibility on demand means DOM code does not have to know about accessibility. The cost is that accessibility must be re-computed whenever layout changes.

## The four questions every node answers

Whatever the platform, an AT asks a node roughly four things.

1. **Role** - what kind of thing is this? `button`, `textField`, `listBox`,
   `heading`, `rootWebArea`.
2. **Name** - what do we call it? "Next", "Age", "Search the site".
3. **State** - what is true about it right now? focused, focusable, checked,
   expanded, required, invisible, ignored.
4. **Value** - what does it currently hold? the text in a field, the position of
   a slider, the selected option.

Plus geometry (where is it) and relations (what is it connected to).

KEY: Role, name, state, value. If you can predict those four for every element you write, you can predict what a screen reader will say.

## Roles are promises

Setting a role is a promise about behavior, not just a label. An AT will tell the
user what interactions to expect based on it.

- `role="button"` promises: activates on Enter *and* Space, is focusable, has a
  name.
- `role="checkbox"` promises: has `aria-checked`, toggles on Space.
- `role="tablist"` promises: arrow keys move between tabs, one tab is selected,
  each tab controls a panel.
- `role="application"` promises: I have taken over the keyboard entirely; screen
  readers will stop offering their own navigation.

WATCH: An unfulfilled promise is worse than no role. A `<div role="button">` with no `tabindex` and no key handler is strictly worse for users than a plain `<div>`, because now it is announced as something the user cannot use.

## Included, ignored, invisible, offscreen

Four different "not really there" states, often confused.

- **Not in the tree** - `display:none`, `<head>` content: no node at all.
- **Ignored** - the node exists in Chromium's internal tree but is not exposed to
  the platform. Layout-only wrappers and `role="presentation"` end up here.
- **Invisible** - programmatically hidden (`display:none`, `visibility:hidden`).
  Chrome's definition: "a node or its ancestor is explicitly invisible".
- **Offscreen** - "fully clipped or scrolled out of view by any ancestor so that
  it is not rendered on the screen". It is still real, still reachable.

Note `opacity: 0` is explicitly **not** treated as invisible.

REF: `//docs/accessibility/browser/offscreen.md`, and `AXTree::RelativeToTreeBounds` in `ui/accessibility/ax_tree.cc`, which computes offscreen while walking bounds up the tree.

## Why screen readers still want offscreen nodes

Different tools want different subsets of the tree, and Chromium serves them all
from one structure.

- **Screen readers** want offscreen nodes: content below the fold is legitimate
  content, and visually-hidden-but-screen-reader-only text is a real technique.
- **Select-to-Speak and Switch Access** want to skip anything offscreen,
  invisible, or size (0,0) - it cannot be pointed at.

Hence Chromium exposes both `location` (clipped by ancestors) and
`unclippedLocation` (ignoring clipping) through the automation API.

KEY: "Visible" is not one boolean. Chromium keeps the distinctions so each client can pick the rule it needs.

## States and properties

States are the live, changing facts. In Chromium they are the `ax::mojom::State`
bits plus a pile of sparse attributes.

```text
kAutofillAvailable  kCollapsed   kDefault      kEditable     kExpanded
kFocusable          kHorizontal  kHovered      kIgnored      kInvisible
kLinked             kMultiline   kMultiselectable            kProtected
kRequired           kRichlyEditable            kVertical     kVisited
```

Things that feel like states but are stored as attributes instead: checked
(`ax::mojom::CheckedState`), invalid (`InvalidState`), restriction
(disabled / read-only, `Restriction`), current (`AriaCurrentState`),
has-popup (`HasPopup`).

WHY: The state bitmask is small and fixed; anything with more than two or three values gets its own enum stored in the sparse attribute map, which keeps `AXNodeData` compact.

## Relations

Relations are edges in a graph laid over the tree, and every one of them is a
place where IDs can dangle.

- `aria-labelledby` / `aria-describedby` - name and description from elsewhere.
- `aria-controls` - this thing controls that thing.
- `aria-owns` - re-parent that node under me in the accessibility tree.
- `aria-activedescendant` - focus stays here, but *that* item is the active one.
- `aria-details`, `aria-flowto`, `aria-errormessage` - richer pointers.

In Chromium these become `IntListAttribute` entries such as
`kLabelledbyIds`, `kControlsIds`, `kDetailsIds`, plus reverse maps so a node can
find who points at it.

WATCH: `aria-owns` is the most expensive attribute in the platform. It forces the tree to differ from the DOM, invalidates ancestor caches, and is a perennial source of cycles and crashes. Prefer fixing your DOM order.

## Text: the special case

Text is where accessibility APIs get genuinely hard, because ATs want to talk
about *ranges*, not nodes.

```text
Paragraph
    Static Text "The quick brown fox jumps over the lazy dog."
        Inline text box "The quick brown fox "
        Inline text box "jumps over the "
        Inline text box "lazy dog."
```

- A `staticText` node holds the whole string.
- Its **inline text box** children are one per rendered line, each with its own
  bounds, direction, and per-character offsets.
- Inline text boxes are internal - no platform API exposes them directly - but
  every "bounding box of characters 5..9" query is answered from them.

KEY: Character-level geometry is stored as line-level boxes plus character offsets. That is the compromise that makes caching the whole page affordable.

## Live regions

A live region is the mechanism for "something changed over there and the user
should hear about it without moving focus".

- `aria-live="polite"` - announce when the user is idle. `assertive` - interrupt.
- `role="status"`, `role="alert"`, `role="log"`, `role="progressbar"` carry
  implicit live semantics.
- `aria-atomic` - announce the whole region or just the changed part.
- `aria-relevant` - which mutations count.

Platforms disagree wildly about how to deliver this: macOS fires a single
`AXLiveRegionChanged`; Windows/IA2 needs `IA2_EVENT_TEXT_INSERTED` and
`TEXT_REMOVED` on each affected node with `container-live:polite` attributes.

REF: `AXEventGenerator` consolidates all of that into exactly one `LIVE_REGION_CHANGED` on the live root, plus `LIVE_REGION_NODE_CHANGED` on the descendants.

## The tree is a contract

Once you internalize this, a lot of API design decisions in Chromium make sense.

- The tree is **data**, not behavior. It can be snapshotted, diffed, replayed,
  and dumped to text.
- Because it is data, the *same* tree can be served to a screen reader, dumped
  into a test expectation file, replayed for Android's "freeze-dried tabs", or
  shipped to a `chrome.automation` extension.
- Because it is a contract, changing what Chromium exposes for a given HTML
  pattern is a compatibility change, on the level of changing rendering.

KEY: "It's all data" is the central architectural insight of Chromium accessibility, and it is why the test infrastructure is text-diff based.

## Exercise: read this dump

Here is a real-shaped fragment. What does the user hear when they tab to the
node marked `focused`?

```text
rootWebArea name="Checkout"
  ++navigation name="Breadcrumb"
  ++main
  ++++heading level=1 name="Payment"
  ++++group name="Card details"
  ++++++textField name="Card number" required invalid=true
        describedby=[19] focused
  ++++++staticText id=19 name="Enter 16 digits, no spaces"
  ++++button name="Pay" restriction=disabled
```

Expected announcement, roughly: *"Payment, heading level 1 ... Card details,
group ... Card number, required, edit, invalid data, Enter 16 digits no
spaces."* The Pay button is announced as dimmed/unavailable when reached.

TRY: Predict the announcement before reading the answer, then build the page and check with a real screen reader. Your prediction being wrong is the most useful data in this course.
