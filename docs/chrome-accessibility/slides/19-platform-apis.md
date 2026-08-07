---
module: Platform APIs
part: Part IV - The Chromium pipeline
---

## One tree, five APIs

The last mile: turning `AXNodeData` into whatever the operating system's
accessibility API expects.

| Platform | API(s) | Native handle type |
| --- | --- | --- |
| Windows | IAccessible (MSAA), IAccessible2, UI Automation | `IAccessible*` |
| macOS | NSAccessibility (informal protocol) | `id` |
| Linux | ATK, consumed over AT-SPI | `AtkObject*` |
| Android | `AccessibilityNodeInfo` via `AccessibilityNodeProvider` | virtual view IDs |
| ChromeOS | `chrome.automation` (Chromium's own) | node objects in JS |

`gfx::NativeViewAccessible` is the typedef that stands for "the platform's
accessible object type" throughout Chromium.

KEY: Chromium does not implement an abstraction over these APIs. It implements all of them, honestly, including their quirks - because ATs depend on the quirks.

## AXPlatformNode

The class that made cross-platform accessibility code possible in Chromium.

```cpp
// ui/accessibility/platform/ax_platform_node.h
static AXPlatformNode* Create(AXPlatformNodeDelegate& delegate);
virtual gfx::NativeViewAccessible GetNativeViewAccessible() = 0;
virtual void NotifyAccessibilityEvent(ax::mojom::Event) = 0;
```

- `Create()` returns the right subclass for the current platform:
  `AXPlatformNodeWin`, `AXPlatformNodeCocoa` / `AXPlatformNodeMac`,
  `AXPlatformNodeAuraLinux`.
- You supply an `AXPlatformNodeDelegate`; the platform subclass asks it for
  everything.

So any Chromium UI - web contents, Views, PDF, whatever - becomes accessible on
three desktop platforms by implementing one cross-platform delegate.

REF: `ui/accessibility/platform/` is where all of this lives. It is the most reusable code in Chromium accessibility, and it is used outside the browser too.

## AXPlatformNodeDelegate

The interface you implement to describe a node without knowing the platform.

```cpp
const AXNodeData& GetData() const;
size_t GetChildCount() const;
gfx::NativeViewAccessible ChildAtIndex(size_t index);
gfx::NativeViewAccessible GetParent() const;
gfx::Rect GetBoundsRect(AXCoordinateSystem, AXClippingBehavior, ...) const;
gfx::NativeViewAccessible HitTestSync(int x, int y);
bool AccessibilityPerformAction(const AXActionData&);
```

`BrowserAccessibility` implements it for web content; `ViewAXPlatformNodeDelegate`
implements it for Views.

```cpp
MyButtonDelegate delegate;
AXPlatformNode* accessible = AXPlatformNode::Create(delegate);
```

KEY: Write one delegate, get Windows, macOS, and Linux accessibility. This is the payoff for all the abstraction in the previous modules.

## Windows: MSAA and IAccessible2

The old API and its extension, still the workhorse for JAWS and NVDA.

- **MSAA / `IAccessible`** (1997): `get_accRole`, `get_accName`, `get_accValue`,
  `get_accState`, `accLocation`, `accDoDefaultAction`, `accNavigate`. Roles are
  `ROLE_SYSTEM_*` constants; a web page's root is `ROLE_SYSTEM_DOCUMENT`.
- **IAccessible2**: everything MSAA lacks for documents - `IAccessibleText`,
  `IAccessibleHypertext`, `IAccessibleTable2`, `IAccessibleValue`,
  `IAccessibleAction`, plus object attributes as a string
  (`"tag:input;xml-roles:textbox;"`).
- Events are `NotifyWinEvent` with `EVENT_OBJECT_*` and `IA2_EVENT_*` constants.

In Chromium: `BrowserAccessibilityComWin` and `AXPlatformNodeWin` implement these;
`ui/accessibility/platform/ax_platform_node_win.cc` is one of the largest files in
the directory for good reason.

NOTE: IA2 was designed to extend MSAA for documents in a way that mirrors ATK, so that products could implement both with shared logic. That is why the Linux and Windows layers look similar.

## Windows: UI Automation

The modern Windows API, and the only one Narrator uses.

- **Provider vs client**: Chromium implements the *provider* side. Clients never
  talk to providers directly - the OS aggregates providers into one tree.
- **Control view and content view**: a node's `IsControlElement` and
  `IsContentElement` properties decide which filtered views it appears in.
  Narrator uses these to skip structural noise. The litmus test from the
  Chromium docs: if there is any reason a screen reader might care about a node,
  it belongs in the control view.
- **Patterns** instead of interfaces: `InvokePattern`, `ValuePattern`,
  `SelectionPattern`, `GridPattern`, `TextPattern`.
- **TextPattern** gives a linear reading view - characters, words, sentences,
  paragraphs, pages - independent of tree structure. Narrator leans on it
  heavily.

REF: `//docs/accessibility/browser/uiautomation.md`, and `ax_platform_node_textrangeprovider_win.cc` for the `ITextRangeProvider` implementation.

## Windows: bridging IA2 and UIA

ATs migrating from IA2 to UIA do not want a flag day, so Chromium supports
runtime conversion between an IA2 element and a UIA element.

- IA2 to UIA: a **custom UIA property** carries the element's unique id; the AT
  registers the property GUID once and then calls
  `IUIAutomationItemContainerPattern::FindItemByProperty()` with it.
- UIA to IA2: `IUIAutomationLegacyIAccessiblePattern::GetIAccessible()`, then
  `QueryInterface` for `IAccessible2`.

WHY: The Windows AT ecosystem is decades old and migrations take years. Supporting both APIs simultaneously - and letting a single AT straddle them - is the only workable path, and it is a lot of the reason `ax_platform_node_win.cc` is so large.

## macOS: NSAccessibility

An informal protocol: any object can be accessible by implementing the right
methods.

- Attributes: `accessibilityRole`, `accessibilityLabel`, `accessibilityValue`,
  `accessibilityChildren`, `AXRoleDescription`.
- A web page's root is `@"AXWebArea"`; the label is the page title.
- Events are notifications: `NSAccessibilityPostNotification` with
  `@"AXFocusedUIElementChanged"`, `@"AXValueChanged"`, `@"AXLiveRegionChanged"`,
  `@"AXLayoutComplete"`.
- Text uses **`AXTextMarker`** and **`AXTextMarkerRange`** - opaque tokens that
  are essentially serialized `AXPosition`s, plus a large family of parameterized
  attributes for moving by word, line, and paragraph.

In Chromium: `BrowserAccessibilityCocoa` and `AXPlatformNodeCocoa`.

NOTE: Chromium's internal role and attribute names historically match macOS closely, because the accessibility code came from WebKit, where Apple wrote most of it. The gradual renaming toward ARIA terminology is still in progress.

## Linux: ATK and AT-SPI

- Chromium implements **ATK** (`AtkObject`, `AtkText`, `AtkAction`,
  `AtkComponent`, `AtkTable`, `AtkHypertext`) in
  `AXPlatformNodeAuraLinux` and `BrowserAccessibilityAuraLinux`.
- ATs (mainly **Orca**) consume the **AT-SPI** D-Bus interface; the bridge from
  ATK to AT-SPI is provided by the platform.
- Events are GObject signals: `state-changed:focused`, `text-caret-moved`,
  `children-changed`, `property-change:accessible-name`.
- `AXEventGenerator::Event::ATK_TEXT_OBJECT_ATTRIBUTE_CHANGED` exists purely
  because ATK treats alignment and indentation as *text* attributes and has no
  event for object attribute changes.

WATCH: ATK versions differ across Ubuntu LTS releases, which is why the test infrastructure supports version-specific expectation files such as `-expected-auralinux-xenial.txt`.

## Android: a different shape entirely

Android's model forces a different implementation.

- `WebContentsAccessibilityImpl.java` acts as the `AccessibilityNodeProvider` for
  a tab, and represents **the entire page including all frames** in one virtual
  view hierarchy.
- The IDs used in Java are **unique IDs**, not frame-local node IDs; the
  framework calls them `virtualViewId`.
- Nodes are created **on demand**: an `AccessibilityNodeInfo` is only built when a
  service asks for it - but when it is built, every possible attribute must be
  populated at once.
- Roles are class names: `android.widget.Button`, `android.webkit.WebView`; the
  name is a "content description".

Roughly 7% of Android users have some accessibility service running - password
managers and automation tools included - so this path is far from a niche.

REF: `//docs/accessibility/browser/android.md` is unusually detailed, including the event and action mapping tables.

## ChromeOS: no platform API at all

ChromeOS is the odd one out, and understanding why clarifies the rest.

- There is no third-party screen reader process to integrate with, so
  `RenderFrameHostImpl` does not route events to a `BrowserAccessibilityManager`.
- Instead the tree is exposed through `chrome.automation` to component
  extensions, and the accessibility cache effectively lives in the AT's own
  process.
- ChromeVox, Select-to-Speak, Switch Access, Dictation, and FaceGaze are all
  extensions on that API.
- Android apps (ARC++) and Views UI are embedded into the same tree using
  `AXTreeID`s - the same mechanism that stitches iframes.

KEY: ChromeOS proves the "the cache can live anywhere" claim from module 13. It is the same data, delivered to a different process.

## The mapping problem

Concrete examples of why "just map the role" is never just mapping the role.

- A live region change is one notification on macOS, and a series of per-node
  text insert/remove events with `container-live` attributes on Windows/IA2.
- macOS distinguishes row expand/collapse from popup expand/collapse; other
  platforms have one event.
- Android has a checked-state event; others have a generic state-changed.
- Windows requires SHOW/HIDE events for appearing and disappearing subtrees;
  other platforms infer from children-changed.
- UIA needs `IsControlElement`/`IsContentElement` decisions that no other API has.

WHY: Each API co-evolved with the ATs of its platform, and those ATs were tested against one toolkit's exact event sequence. Chromium has to match the sequence, not just the semantics.

## Parameterized attributes

The category that forces the cache to be rich.

- "What is the bounding box of characters 12 through 20?"
- "What are the text attributes at character offset 40?"
- "Give me the range for the word at this position."
- "What is at screen point (x, y)?"

All synchronous, all answered from the browser process cache, all impossible
without inline text boxes, character offsets, word boundaries, and `AXPosition`.

KEY: Parameterized text attributes are the reason Chromium caches text geometry at all. Remove that requirement and half of the data format could disappear.

## Testing the platform layer

- `DumpAccessibilityTree` runs each test in several passes: `blink` (internal),
  plus native - `win` (IA2), `uia-win`, `mac`, `auralinux`, `android`.
- Test names carry the pass: `DumpAccessibilityTreeTest.TestName/uia-win`.
- Expectation files are per platform:
  `foo-expected-mac.txt`, `foo-expected-uia-win.txt`, and so on.
- Filters (`@MAC-ALLOW:AXTitle*`, `@WIN-DENY:name='X*`) keep the dumps focused so
  unrelated changes do not churn every file.

TRY: Pick one small ARIA feature and read its expectation files across all platforms side by side. That is the fastest way to see how differently the same tree is rendered by each API.

## When the platform layer is the bug

Symptoms that point here rather than at Blink:

- The `blink` expectation is right but a native one is wrong.
- One AT is broken and another on the same platform is fine (different events, or
  different interfaces consumed).
- The tree in `chrome://accessibility` looks correct, but `ax_dump_tree` or
  Inspect shows something different.
- Something works on Windows and not macOS with identical HTML.

The fix is almost always in `ui/accessibility/platform/` or in a
`BrowserAccessibilityManager*` subclass - and it almost always needs a new
platform-specific expectation file.

KEY: Ninety percent of platform-layer bugs are event ordering or a missing property mapping. Reproduce them in a dump test before touching the code.
