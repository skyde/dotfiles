---
module: Events
part: Part IV - The Chromium pipeline
---

## What an event is, in Chromium's terminology

An accessibility **event** is always a message from the application to the
assistive technology: something changed. (Actions go the other way; that is
module 18.)

Common events on nearly every platform:

- focus changed
- control value changed
- bounding box changed
- children changed - a node added, removed, or reordered
- load complete - a document finished loading

Names and semantics differ wildly. macOS has separate events for expanding a
table row versus expanding a popup menu; Android has a dedicated checked-state
event where other platforms have a generic state change; Windows needs explicit
SHOW and HIDE events when subtrees appear and disappear.

KEY: The event contract is real but almost entirely undocumented, because it was co-designed between each OS toolkit and the ATs of that era.

## The explicit-event era, and why it ended

Chromium's first design had Blink fire the superset of every event any platform
might want.

It went badly:

- Duplicate events, because two code paths both fired for one change.
- Missing events, because a new feature forgot one platform's requirement.
- Fixes for one platform broke another - the events were all in one stream.

The replacement, called **implicit events**: Blink only marks nodes and subtrees
dirty. The infrastructure diffs the resulting tree mutation and generates the
right events per client.

WHY: Moving event generation to where the client contract lives means each platform's quirks are implemented once, in one file, instead of being smeared across Blink.

## AXEventGenerator

`AXEventGenerator` is an `AXTreeObserver`. It watches atomic updates and derives
events from what actually changed.

- It sees old and new `AXNodeData` for every changed node.
- It accumulates candidate events for the whole atomic update, then consolidates
  before emitting - so duplicates collapse.
- It is per client: each consumer of a tree gets its own generator, and thus its
  own consistent event stream.

```cpp
AXEventGenerator generator(&tree);
tree.Unserialize(update);
for (const auto& targeted_event : generator) {
  // targeted_event.event_params->event, targeted_event.node
}
```

REF: `ui/accessibility/ax_event_generator.h`. Reading its `Event` enum tells you exactly what Chromium can notice about a tree change.

## The generated event vocabulary

Around 90 values. A representative slice:

```text
ACTIVE_DESCENDANT_CHANGED   ALERT              ARIA_CURRENT_CHANGED
ARIA_NOTIFICATIONS_POSTED   BUSY_CHANGED       CARET_BOUNDS_CHANGED
CHECKED_STATE_CHANGED       CHILDREN_CHANGED   COLLAPSED / EXPANDED
DESCRIPTION_CHANGED         DOCUMENT_SELECTION_CHANGED
DOCUMENT_TITLE_CHANGED      ENABLED_CHANGED    FOCUS_CHANGED
IGNORED_CHANGED             IMAGE_ANNOTATION_CHANGED
INVALID_STATUS_CHANGED      LAYOUT_INVALIDATED LIVE_REGION_CHANGED
LIVE_REGION_CREATED         LIVE_REGION_NODE_CHANGED
MENU_POPUP_START / END      NAME_CHANGED       PARENT_CHANGED
POSITION_IN_SET_CHANGED     RANGE_VALUE_CHANGED
ROLE_CHANGED                SCROLL_VERTICAL_POSITION_CHANGED
SELECTED_CHANGED            SELECTED_CHILDREN_CHANGED
SPELLING_MARKER_CHANGED     SUBTREE_CREATED    TEXT_ATTRIBUTE_CHANGED
TEXT_SELECTION_CHANGED      VALUE_IN_TEXT_FIELD_CHANGED
WIN_IACCESSIBLE_STATE_CHANGED
```

Note the last one: an event computed here purely because it is convenient, whose
only consumer is Windows MSAA state mapping. Pragmatism over purity.

NOTE: `LAYOUT_INVALIDATED` fires when `aria-busy` goes from true to false - the "I have finished rebuilding, re-read me" signal.

## Live regions, consolidated

A worked example of what the generator buys you.

A live region updates: five text nodes change inside one `aria-live="polite"`
container, in one atomic update.

- Naive approach: five change events, and the AT announces five times.
- `AXEventGenerator`: exactly one `LIVE_REGION_CHANGED` on the *root* of the live
  region, plus `LIVE_REGION_NODE_CHANGED` on each affected descendant, plus
  `LIVE_REGION_CREATED` if the region itself is new.

Platform layers then translate: macOS emits one `AXLiveRegionChanged`; Windows
IA2 emits per-node text insert/remove events with `container-live:polite`
attributes, because that is what JAWS and NVDA expect.

KEY: One tree-level truth, many platform-level renderings. That separation is the whole architecture in miniature.

## The exceptions: events that cannot be inferred

A handful of events carry information that simply is not present in the tree
diff, so they are still fired explicitly.

- **Autocorrection occurred** - the text changed, but the *reason* (the browser
  corrected you) is invisible in the diff, and the AT wants to announce it.
- **Hit test result** - a response to a request, not a change.
- **End of test** - the sentinel used by event tests to know when to stop
  recording.
- Media start/stop, tooltip opened/closed, and a few other intent-carrying
  notifications.

REF: The `ax::mojom::Event` enum in `ax_enums.mojom` is the explicit-event list; `AXEventGenerator::Event` is the derived list. Two enums, two purposes - do not confuse them in review.

## EventFrom and intents

Events carry provenance, which platform layers and ATs use to decide how loud to
be.

```cpp
struct AXEvent {
  AXNodeID id;
  ax::mojom::Event event_type;
  ax::mojom::EventFrom event_from;        // kUser, kAction, kPage
  ax::mojom::Action event_from_action;    // which action caused it
  std::vector<AXEventIntent> event_intents;
};
```

- `event_from = kAction` plus `event_from_action = kSetValue` means "this changed
  because the AT asked" - so the AT can suppress its own echo.
- `AXEventIntent` describes editing intent: what command, what text boundary,
  which direction - the raw material for good editing announcements.

WATCH: Missing provenance produces double-speaking screen readers: the AT announces its own action, then announces the resulting change as if the user had done it.

## Focus, and the race it must not lose

The problem: only one element on the desktop has focus, but each frame only knows
about its own.

Scenario: the user clicks a button which, two seconds later, opens a dialog and
focuses OK. Meanwhile the user clicks another window, focusing its text field.
Two focus events, from two processes, arriving in either order.

The rule: **the browser is the only source of truth for which window has focus**;
each tree only says which node is focused within itself.

```text
on any focus change in any tree, or focused window/iframe change:
    node = focused node of the focused window's tree
    while node hosts a child tree:
        node = focused node of that child tree
    if node != last_focused:
        fire the platform focus event
```

KEY: Focus events are recomputed globally, never forwarded blindly. No other event type has this problem - value changes and selection changes are safe to fire from background windows.

## Ordering and coalescing

What the platform layer has to get right after the generator has spoken.

- **Order matters**: Windows expects HIDE before SHOW for a replaced subtree;
  focus should follow structural changes, not precede them.
- **Coalescing**: a hundred `CHILDREN_CHANGED` events in one update become one
  per parent.
- **Suppression**: events on nodes that are ignored, detached, or in an inactive
  document are dropped rather than translated.
- **Ancestor-relative events**: some platforms want the event on the container,
  some on the leaf.

NOTE: This is where "works in NVDA, silent in JAWS" bugs live. Both consume IA2, but they react to different events in the same stream.

## What ATs do with events

Understanding the consumer makes the ordering rules make sense.

- **Screen readers** rebuild parts of their virtual buffer on structural events,
  announce on focus and value events, and queue live region announcements.
- **Magnifiers** pan on focus and caret bounds changes.
- **Voice control** mostly ignores events, but refreshes its label index when the
  tree changes.
- **Braille displays** re-render the current line.

An event storm is genuinely harmful: it can make a screen reader unusable even
though every individual event is correct.

WATCH: "Correct but too many" is a real bug class. A page with a 1-second timer in a live region can drown out everything else the user is trying to hear.

## Events in tests

Chromium tests events directly with `DumpAccessibilityEvents` tests.

```html
<!--
@WIN-ALLOW:FOCUS*
@MAC-ALLOW:AXFocused*
-->
<button id="b">Go</button>
<script>
  function go() { document.getElementById('b').focus(); }
</script>
```

- The page defines `go()`; the harness calls it after load and dumps every event
  fired until a sentinel event arrives.
- Expectation files are per platform, exactly like tree tests.
- Android's event tests are driven from Java in
  `WebContentsAccessibilityEventsTest.java` and must be added separately - a
  presubmit warns you if you forget.

TRY: Write an events test for a live region update. The expectation file will teach you more about platform event semantics than any prose, including this slide.

## Debugging an event problem

The ladder, from cheapest to most expensive:

1. Does the tree change at all? Dump before and after - if the data is identical,
   no event can be generated. Look for a missing `Handle*` in Blink.
2. Does `AXEventGenerator` produce an event? A unit test on `AXTree` +
   `AXEventGenerator` reproduces this with no browser at all.
3. Does the platform manager translate it? Check the `NotifyAccessibilityEvent`
   override for your platform.
4. Does the AT receive it? Use `ax_dump_events`, or the AT's own logging (NVDA's
   speech viewer and log, VoiceOver's utility, Accerciser's event monitor).

KEY: Steps 1 and 2 need no assistive technology and no platform - they are unit-testable, fast, and where most event bugs actually are.
