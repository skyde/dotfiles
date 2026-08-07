---
module: Keyboard and focus
part: Part II - The web platform
---

## Focus is shared state

Exactly one node on the entire desktop has focus. Everything about focus
handling follows from that scarcity.

- The **browser** owns which window is active; the **document** owns which
  element within it is focused; the **AT** must be told, reliably, whenever the
  combination changes.
- Focus drives keyboard input routing, screen reader announcement, magnifier
  panning, and voice control's "what did I just act on".

Chromium therefore refuses to fire a focus event straight from a tree change:
it recomputes global focus and only then fires. Module 17 covers the algorithm
and the race it prevents.

KEY: Focus is the single most important accessibility event. Everything else can be a little late; focus cannot be wrong.

## Tabbable, focusable, neither

Three tiers, and the attribute that selects them.

| Markup | Tabbable | Focusable by script/click |
| --- | --- | --- |
| `<button>`, `<a href>`, `<input>` | yes | yes |
| `tabindex="0"` | yes, in DOM order | yes |
| `tabindex="-1"` | no | yes |
| `tabindex="3"` | yes, *before* everything else | yes |
| plain `<div>` | no | no |

- `tabindex="-1"` is the workhorse: it makes things script-focusable so you can
  move focus to a heading, a dialog, or an error summary.
- Positive `tabindex` creates a second, higher-priority tab order that almost
  nobody maintains correctly.

WATCH: A single `tabindex="1"` anywhere on the page moves that element ahead of every natural control in the tab order. Treat positive tabindex as a bug.

## The tab order contract

- Tab order follows DOM order, not visual order. CSS `order`, `grid-area`, and
  absolute positioning can make the two disagree, and the user experiences the
  DOM one.
- Everything interactive must be reachable, and reachable in an order that makes
  sense with the visual layout.
- `inert` (and a `<dialog>` opened with `showModal()`) removes a subtree from the
  tab order entirely - the correct, modern way to implement a modal.

```html
<div id="page" inert>...</div>   <!-- nothing inside is focusable or clickable -->
<dialog open>...</dialog>
```

TRY: Tab through your app with the mouse physically unplugged. Not metaphorically - actually unplug it. Ten minutes of this finds more real bugs than any audit tool.

## Focus visibility

If a keyboard user cannot see where focus is, the tab order might as well not
exist.

```css
/* never do this */
:focus { outline: none; }

/* do this: keep a visible indicator, style it if you must */
:focus-visible {
  outline: 3px solid Highlight;
  outline-offset: 2px;
}
```

- `:focus-visible` shows the ring for keyboard interaction and suppresses it for
  mouse clicks - the compromise designers actually wanted.
- WCAG 2.2 adds *Focus Appearance*: the indicator needs sufficient size and
  contrast, not just existence.
- Use system colors (`Highlight`, `CanvasText`) so the ring survives forced-colors
  mode.

KEY: Removing outlines without replacing them is the most common single accessibility defect on the web, and it is a one-line fix.

## Managing focus on DOM change

The rules for when *you* must move focus:

- **Opening a dialog** - move focus into it (the dialog itself, its heading, or
  the first control). `<dialog>.showModal()` does this for you.
- **Closing a dialog** - restore focus to the element that opened it.
- **Deleting the focused element** - focus something adjacent and meaningful, not
  `<body>`. Focus falling to `<body>` sends the screen reader user back to the
  top of the page.
- **Route change in an SPA** - move focus to the new view's heading and announce
  the new page title.
- **Revealing content** - focus it only if the user asked for it.

WATCH: Focus that lands on `document.body` is invisible in most debugging but catastrophic for the user. Log `document.activeElement` on route changes and see how often it is `<body>`.

## Roving tabindex and activedescendant

Composite widgets have *one* tab stop, not one per item. Two ways to do it.

**Roving tabindex** - real DOM focus moves; exactly one child has
`tabindex="0"`, the rest `-1`:

```js
function move(items, from, to) {
  items[from].tabIndex = -1;
  items[to].tabIndex = 0;
  items[to].focus();
}
```

**aria-activedescendant** - DOM focus stays on the container; the container's
`aria-activedescendant` names the active child:

```html
<ul role="listbox" tabindex="0" aria-activedescendant="opt-2">
  <li role="option" id="opt-2" aria-selected="true">Blue</li>
</ul>
```

Roving tabindex is easier to get right and works better with browser scrolling.
Activedescendant is required when focus must remain in a text input - comboboxes.

REF: In Chromium these are `AXEventGenerator::Event::FOCUS_CHANGED` versus `ACTIVE_DESCENDANT_CHANGED`; platform layers translate the latter into a focus-like event for ATs.

## Keyboard interaction patterns

The conventions ATs and users expect, from the ARIA Authoring Practices:

| Widget | Keys |
| --- | --- |
| button | Enter, Space |
| link | Enter |
| checkbox / switch | Space |
| radio group | Arrows move *and* select; Tab enters/leaves the group |
| listbox | Arrows, Home/End, type-ahead |
| tablist | Arrows between tabs; Tab goes to the panel |
| menu | Arrows, Escape closes, Enter activates, type-ahead |
| combobox | Down opens, arrows move, Enter commits, Escape reverts |
| dialog | Escape closes, Tab cycles within |
| grid | Arrows by cell, Ctrl+Home to first cell |

KEY: These are not suggestions. A screen reader tells the user "listbox" and they will press arrows. If arrows do nothing, the widget is broken regardless of what your mouse testing showed.

## Keyboard traps

A keyboard trap is a place focus can enter but not leave. WCAG treats it as a
failure at the highest severity, because the user's only escape is to close the
tab.

Classic sources:

- Custom modals that cycle focus but never handle Escape.
- Embedded plugins, iframes, or editors that swallow Tab.
- `keydown` handlers that `preventDefault()` on Tab unconditionally.
- Focus-restoring loops: two elements that each focus the other.

The legitimate version - a modal that *contains* focus - must always offer
Escape and a visible close control.

TRY: In any modal you own, press Tab twenty times and then Escape. If you cannot get out, or if focus escapes into the page behind, it is broken.

## Skip links and bypass mechanisms

Keyboard and screen reader users should not have to tab through 60 nav links on
every page.

```html
<a class="skip" href="#main">Skip to main content</a>
...
<main id="main" tabindex="-1">...</main>
```

- The link must be the first focusable element, and must become **visible** when
  focused - a permanently hidden skip link helps only screen reader users.
- `tabindex="-1"` on the target ensures focus really lands there in every engine.
- Landmarks and headings are the other bypass mechanisms; a skip link serves
  sighted keyboard users who have neither.

NOTE: This deck implements exactly this pattern - press Tab as soon as it loads and the skip link appears.

## Pointer, touch, and gesture alternatives

- Anything achievable by a **path-based gesture** (swipe, drag, pinch) needs a
  single-pointer alternative (WCAG 2.5.1).
- **Drag and drop** needs a keyboard path: a "move up / move down" menu, or cut
  and paste semantics.
- **Hover-only** disclosure (tooltips, menus) must also work on focus, and must
  be dismissible with Escape and hoverable without disappearing (WCAG 1.4.13).
- **Target size** (WCAG 2.5.8): 24x24 CSS pixels minimum, with exceptions.

WATCH: Touch screen readers change gestures entirely - with TalkBack or VoiceOver on, a single tap explores instead of activating, and your `touchstart` handlers may never fire. Test on a device with the screen reader on.

## Focus and the accessibility tree

What Chromium actually does when focus moves:

1. Blink updates DOM focus and marks nodes dirty.
2. The serializer sends an `AXTreeUpdate` where the focused node's state includes
   `kFocused`, and `AXTreeData` records the focused node ID.
3. The browser process recomputes *global* focus: focused window -> focused tree
   -> if that node is an iframe, recurse into the child tree.
4. If the resulting deepest focused node differs from the last one, fire the
   platform focus event (`EVENT_OBJECT_FOCUS`,
   `AXFocusedUIElementChanged`, `ATK state-changed:focused`, ...).

KEY: The browser process is the only source of truth for focus. This is why a focus event can never be fired directly from inside one frame's tree update.

## Keyboard checklist

1. Every interactive element reachable by Tab, in a sensible order.
2. A visible focus indicator everywhere, with adequate contrast.
3. No positive `tabindex`.
4. Escape closes every overlay; focus returns to the trigger.
5. Composite widgets implement their arrow-key contract with one tab stop.
6. No keyboard traps, including inside iframes and embeds.
7. A skip link, visible on focus.
8. Focus never silently lands on `<body>`.
9. Hover-only affordances also work on focus.
10. Custom shortcuts can be remapped or turned off (WCAG 2.1.4).

TRY: Turn this list into a code review checklist. Eight of the ten are visible in a diff without running anything.
