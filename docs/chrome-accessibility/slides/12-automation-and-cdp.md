---
module: Automation and the protocol
part: Part III - Tools
---

## Three ways to read the tree programmatically

Depending on where your code runs, you have three doors into the same data.

1. **Chrome DevTools Protocol** - the `Accessibility` domain, over a WebSocket.
   Used by DevTools itself, Puppeteer, Playwright, and every crawler.
2. **`chrome.automation`** - a JavaScript API for extensions, backed by the same
   `AXTree` machinery, with events and actions.
3. **Platform APIs** - `ax_dump_tree`, `inspect.exe`, Accessibility Inspector,
   AT-SPI tools: what the AT itself sees, one layer further out.

KEY: All three read the same underlying tree at different stages. Picking the right door tells you which layer a bug lives in.

## CDP: the Accessibility domain

```js
const client = await page.createCDPSession();
await client.send('Accessibility.enable');

const { nodes } = await client.send('Accessibility.getFullAXTree');
// each node: nodeId, ignored, role, name, description, value,
//            properties[], childIds[], backendDOMNodeId
```

Useful commands:

- `getFullAXTree` - the whole tree, including ignored nodes.
- `getPartialAXTree` - a node and its ancestors; what the DevTools pane uses.
- `getRootAXNode`, `getChildAXNodes`, `getAXNodeAndAncestors` - lazy traversal for
  large pages.
- `queryAXTree` - find nodes by accessible name and/or role.

WATCH: `Accessibility.enable` turns accessibility on for that target - which changes performance and can change behavior relative to a normal browsing session. That is fine for testing; be aware of it when measuring.

## Puppeteer

```js
const snapshot = await page.accessibility.snapshot();
// { role: 'RootWebArea', name: 'Checkout', children: [ ... ] }

const button = await page.$('button.pay');
const partial = await page.accessibility.snapshot({ root: button });
```

- By default the snapshot is *interesting nodes only* - Puppeteer prunes the
  uninteresting ones. Pass `interestingOnly: false` for everything.
- It is a snapshot, not a live view: no events, no actions.
- Great for golden-file testing: serialize the snapshot and diff it in CI, which
  gives you Chromium's own `DumpAccessibilityTree` idea at the application level.

TRY: Add an accessibility snapshot golden test to one component. Any change to your markup that changes what users hear now shows up as a reviewable diff.

## Playwright

Playwright leans on roles and names as its primary locator strategy, which makes
accessibility a first-class part of ordinary testing.

```js
await page.getByRole('button', { name: 'Pay' }).click();
await expect(page.getByRole('alert')).toHaveText('Payment failed');

// ARIA snapshot: a YAML-ish view of the accessible tree
await expect(page.locator('nav')).toMatchAriaSnapshot(`
  - navigation "Primary":
    - link "Home"
    - link "Docs"
`);
```

- `getByRole` computes the accessible name the same way the browser does, so a
  test that passes is evidence the name is right.
- ARIA snapshots make structural regressions visible in review.

KEY: Tests written against roles and names are simultaneously functional tests and accessibility tests. This is the highest-leverage change most teams can make.

## chrome.automation

The extension API. On ChromeOS it can see the whole desktop; this is the
substrate ChromeVox, Select-to-Speak, and Switch Access are built on.

```js
chrome.automation.getDesktop(desktop => {
  desktop.addEventListener('focus', e => {
    console.log(e.target.role, e.target.name, e.target.location);
  }, false);

  const next = desktop.find({ role: 'button', attributes: { name: 'Next' } });
  next.doDefault();                 // the kDoDefault action
  next.setSequentialFocusNavigationStartingPoint();
});
```

- Node properties mirror `AXNodeData`: `role`, `name`, `nameFrom`, `state`,
  `location`, `unclippedLocation`, `htmlAttributes`.
- Events mirror `AXEventGenerator` events.

REF: The API surface is defined by `extensions/common/api/automation.webidl`, which must be kept in sync with `ui/accessibility/ax_enums.mojom` - a real constraint when you add an enum value.

## The Automation API is the tree, exposed

Because `chrome.automation` is a thin JavaScript veneer over `AXTree`, it is an
excellent teaching tool for the internals.

- `location` is the clipped bounding box; `unclippedLocation` ignores ancestor
  clipping - exactly the distinction from the offscreen documentation.
- Actions map one-to-one onto `ax::mojom::Action` values: `doDefault`, `focus`,
  `setValue`, `scrollBackward`, `hitTest`, `setSelection`.
- Tree changes arrive as observers: `chrome.automation.addTreeChangeObserver`.

TRY: Write a ten-line extension that logs every focus event's role and name desktop-wide on a ChromeOS device. You will learn more about event ordering in an hour than from any document.

## Building a crawler that is not a liar

If you are auditing at scale, the traps are always the same.

- **Wait for quiescence.** A tree read at `load` misses everything hydrated
  after. Wait for network idle *and* a frame or two.
- **Audit states.** Crawlers see the initial DOM only. Script the important
  interactions.
- **Respect iframes.** Cross-origin frames are separate accessibility trees; CDP
  gives you separate targets. A crawl that ignores them under-reports badly.
- **Dedupe by rule + selector**, not by URL, or a component in a template
  generates ten thousand "issues".

WATCH: A crawler that reports zero problems on a single-page app usually means it audited the loading spinner.

## Screen reader automation

Actually driving a real AT in CI, in rough order of maturity:

- **Guidepup** drives NVDA and VoiceOver from Node, capturing spoken phrases as
  strings you can assert on.
- **NVDA's own remote/log** interfaces can be scripted on Windows agents.
- **Chromium's `DumpAccessibilityEvents` tests** are the in-tree equivalent for
  browser engineers: assert on the *events* fired, not on speech.

These are flaky by nature - speech output changes between AT versions. Assert on
the presence of key phrases, not on exact strings.

KEY: Asserting on the accessibility tree is stable; asserting on synthesized speech is not. Prefer the tree unless the announcement itself is the feature.

## The platform inspectors

When you need to see what the AT sees, use the platform's own tools.

| Platform | Tool |
| --- | --- |
| Cross-platform (Chromium) | `ax_dump_tree`, `ax_dump_events` in `//tools/accessibility/inspect` |
| Windows | Inspect (Windows SDK), Accessibility Insights, AViewer, accProbe |
| macOS | Accessibility Inspector (Xcode) |
| Linux | Accerciser (AT-SPI browser) |
| Android | UIAutomatorViewer, Accessibility Scanner |

`ax_dump_tree` is particularly useful because it can dump *any* application's
tree, not just Chrome - so you can compare Chrome to a native app or to another
browser on the same machine.

REF: `//tools/accessibility/inspect/README.md` documents the selectors: dump by pid, by window title, or the active tab.

## Snapshot testing your application's tree

A pattern worth stealing from Chromium: text dumps plus diffs.

```text
RootWebArea "Checkout"
  navigation "Breadcrumb"
    link "Cart"
  main
    heading "Payment" level=1
    textField "Card number" required
    button "Pay" disabled
```

- Store one of these per critical flow, per state.
- A markup refactor that changes nothing visually but drops a landmark shows up
  immediately as a diff.
- Keep them small and focused; a whole-page dump changes for unrelated reasons
  and gets rubber-stamped.

KEY: Small, targeted expectation files get read in review. Giant ones get blessed blindly - and that is true inside Chromium too.

## Where automation fits

A realistic split for a team that ships weekly:

- **Lint** on every commit - mechanical mistakes.
- **Unit/component tests by role and name** - the widest coverage per second.
- **axe on key states** in CI - the machine-checkable third.
- **Tree snapshots** on critical flows - structural regressions.
- **Manual keyboard sweep** per release - traps, order, visibility.
- **Screen reader pass** on the top flows per release - the ground truth.

WATCH: Every layer above is cheap except the last one, and the last one is the only one that finds "technically correct but unusable". Do not let the cheap layers crowd it out.
