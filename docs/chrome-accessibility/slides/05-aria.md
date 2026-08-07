---
module: ARIA
part: Part II - The web platform
---

## What ARIA is, and is not

ARIA is a vocabulary for overriding what the accessibility tree says about an
element. That is all it is.

- ARIA **changes semantics**. It never changes behavior, appearance, or focus.
- `role="button"` does not make Enter activate anything.
- `aria-hidden="true"` does not hide anything visually.
- `aria-disabled="true"` does not stop clicks.
- `tabindex` is the only accessibility-adjacent attribute that changes behavior,
  and it is not ARIA.

KEY: ARIA is a promise to the AT that you have implemented the behavior yourself. Nothing enforces it.

## The five rules of ARIA

Written into the spec because everyone gets these wrong.

1. Use a native element instead, if one exists.
2. Do not change native semantics unless you really must
   (`<h2 role="tab">` is worse than `<div role="tab"><h2>...`).
3. All interactive ARIA controls must be usable from the keyboard.
4. Do not put `role="presentation"` or `aria-hidden="true"` on a focusable
   element - you create a control the AT cannot describe but the user can reach.
5. Every interactive element needs an accessible name.

WATCH: Rule 4 produces the worst class of bug: a focusable node that is hidden from the tree. The user tabs into a void with no announcement. Chromium reports this as a focusable-but-ignored node, and DevTools flags it.

## Roles: the categories

There are around 90 ARIA roles; Chromium's `ax::mojom::Role` enum has roughly
220 values because it also covers native and internal roles.

- **Widget roles** - `button`, `checkbox`, `combobox`, `slider`, `tab`, `menuitem`.
- **Composite widgets** - `combobox`, `grid`, `listbox`, `menu`, `radiogroup`,
  `tablist`, `tree` - these manage their own children and focus.
- **Document structure** - `article`, `list`, `table`, `heading`, `separator`,
  `figure`, `code`, `mark`.
- **Landmarks** - `banner`, `navigation`, `main`, `complementary`,
  `contentinfo`, `search`, `form`, `region`.
- **Live regions** - `alert`, `status`, `log`, `marquee`, `timer`.
- **Window** - `dialog`, `alertdialog`.

REF: `ui/accessibility/ax_enums.mojom`, the `Role` enum, is the single best index of what Chromium can express. Read it once, top to bottom - it takes ten minutes and pays for itself.

## ARIA states versus ARIA properties

ARIA attributes split into two kinds, and the difference matters when you decide
what to update dynamically.

- **States** change as the user interacts: `aria-checked`, `aria-expanded`,
  `aria-selected`, `aria-pressed`, `aria-current`, `aria-busy`, `aria-invalid`,
  `aria-disabled`.
- **Properties** are mostly static structure: `aria-label`, `aria-labelledby`,
  `aria-describedby`, `aria-controls`, `aria-haspopup`, `aria-level`,
  `aria-live`, `aria-orientation`, `aria-required`.

Chromium maps these into `AXNodeData` attributes; each one that changes causes
the node to be marked dirty, re-serialized, and diffed by `AXEventGenerator` into
an event such as `CHECKED_STATE_CHANGED` or `EXPANDED`.

KEY: Every ARIA attribute you toggle costs a re-serialization of that node. This is cheap - but toggling 5,000 of them per frame is not.

## aria-label and aria-labelledby

The two big hammers. Prefer neither if a visible `<label>` will do.

```html
<button aria-label="Close">x</button>

<div role="dialog" aria-labelledby="dlg-title">
  <h2 id="dlg-title">Delete 3 files?</h2>
</div>

<!-- concatenation: name becomes "Delete 3 files" -->
<button aria-labelledby="verb count noun">...</button>
```

- `aria-labelledby` wins over `aria-label`, which wins over contents.
- `aria-labelledby` takes a *list* of IDs and concatenates their text, in the
  order given, with spaces.
- The referenced element does not need to be visible - but it must be in the DOM
  and reachable by ID (no crossing shadow boundaries).

WATCH: `aria-label` on a container silently *replaces* the name of everything inside for some ATs' heuristics, and it is ignored entirely on many generic elements per ARIA 1.2. Put it on the interactive element, not the wrapper.

## aria-hidden, presentation, and none

Three ways to remove things, with different scopes.

| Attribute | Removes | Keeps children |
| --- | --- | --- |
| `aria-hidden="true"` | node and entire subtree | no |
| `role="presentation"` | the node's semantics only | yes |
| `role="none"` | identical to presentation | yes |
| `display:none` | node and subtree, everywhere | no |

Legitimate uses of `aria-hidden`: decorative icons next to real text, duplicated
content that is announced elsewhere, the rest of the page while a modal is open
(though `<dialog>` and `aria-modal` do this better).

WATCH: `aria-hidden="true"` on an element containing a focusable descendant is a spec violation and a real user-facing bug. Chromium and axe both flag it.

## Relationships and IDREFs

```html
<input aria-describedby="hint err" aria-invalid="true">
<p id="hint">Between 8 and 64 characters.</p>
<p id="err">That password is too short.</p>

<button aria-expanded="false" aria-controls="menu1">File</button>
<ul id="menu1" hidden>...</ul>

<div role="listbox" aria-activedescendant="opt3" tabindex="0">
  <div role="option" id="opt3" aria-selected="true">Blue</div>
</div>
```

- IDREF attributes are resolved at serialization time; a dangling ID is silently
  dropped, so a typo produces no error and no name.
- `aria-activedescendant` keeps DOM focus on the container while telling the AT
  which child is "active" - the pattern for comboboxes and grids.

TRY: Break one IDREF deliberately - change `aria-labelledby="dlg-title"` to `dlg-titel` - and watch the name vanish in the DevTools Accessibility pane. That silence is what a typo looks like in production.

## Live regions in practice

```html
<div role="status" aria-live="polite" aria-atomic="true">
  3 results found
</div>
```

Rules that people learn the hard way:

- The live region container must exist in the DOM **before** the change. Adding a
  node that already has `aria-live` on it may announce nothing.
- Change the *text inside*, do not replace the container.
- `assertive` interrupts the user mid-sentence. Reserve it for errors.
- `role="alert"` is `aria-live="assertive" aria-atomic="true"` in one word.
- Do not put live regions on things that update constantly. A polite region
  updated 10 times a second is a denial-of-service attack on your user.

REF: Chromium's `AXEventGenerator` guarantees exactly one `LIVE_REGION_CHANGED` per atomic update on the live root - dedup you do not have to implement yourself.

## Widget patterns: what you sign up for

Choosing `role="combobox"` means implementing the whole ARIA Authoring Practices
keyboard contract. An abbreviated tab widget:

- `role="tablist"` container, `role="tab"` children, `role="tabpanel"` panels.
- Exactly one tab has `tabindex="0"`; the rest are `-1` (roving tabindex).
- Left/Right arrows move between tabs and move focus; Home/End jump to ends.
- The active tab has `aria-selected="true"`, and `aria-controls` its panel.
- The panel has `aria-labelledby` pointing back at its tab.

KEY: If you are not going to implement the keyboard contract, do not claim the role. A wrong role is a lie the user cannot detect until it fails.

## Bad ARIA is worse than no ARIA

Ranked by how often it shows up in real audits:

1. `role="button"` with no `tabindex` and no key handler.
2. `aria-label` on a `<div>` that is not interactive and has no role - ignored per
   ARIA 1.2 on generic elements, so the "fix" does nothing.
3. `aria-expanded` on the wrong element (the panel, not the trigger).
4. `aria-live` regions that are added to the DOM at announcement time.
5. `role="presentation"` on a focusable element.
6. Redundant roles: `<nav role="navigation">`, `<button role="button">`.
7. `aria-hidden="true"` on the whole `<body>` after a modal closes.

WATCH: Redundant roles are harmless today but they freeze the mapping. If HTML-AAM later refines what `<nav>` maps to, the explicit role opts you out of the improvement.

## Debugging ARIA in Chrome

The workflow, in order of speed:

1. **Elements > Accessibility pane** - computed name with its source, role, and
   the ancestor chain of the accessibility tree.
2. **Full-page accessibility tree** in DevTools - toggle in the Accessibility
   pane; it shows the tree as Chromium sees it, including ignored nodes.
3. `chrome://accessibility` - enable *Internal*, then "show accessibility tree"
   for a tab; this is the browser-process tree, one layer closer to the AT.
4. A real screen reader. Nothing else tells you what the user hears.

TRY: For one component, do all four in order. The places where the answers differ are where the interesting bugs live - the DevTools view and the browser-process view are built from different data.

## ARIA that Chromium implements beyond the basics

Useful, less-known things Chromium supports today:

- `aria-details` - points at rich supplementary content (a chart description, a
  footnote). Exposed via `kDetailsIds`; `DetailsFrom` records where it came from.
- `aria-errormessage` - the error text for an invalid field.
- `aria-keyshortcuts` - announced so users know the shortcut exists
  (`KEY_SHORTCUTS_CHANGED`).
- `aria-braillelabel` / `aria-brailleroledescription` - override what braille
  users read, for when speech and braille want different text.
- `aria-description` - a description without an IDREF.
- ARIA notifications (`ariaNotify`) - a queued announcement API that avoids the
  live-region-must-pre-exist trap; `ARIA_NOTIFICATIONS_POSTED` is its event.

REF: Grep `ax_enums.mojom` for `kAria` and `kBraille` to see exactly which of these have landed in the tree you are building.
