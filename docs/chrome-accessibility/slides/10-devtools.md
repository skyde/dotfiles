---
module: DevTools
part: Part III - Tools
---

## The DevTools accessibility surface

Accessibility tooling in DevTools is spread across five places. Knowing which
one answers which question saves hours.

| Question | Where |
| --- | --- |
| What is this element's name/role/state? | Elements > Accessibility pane |
| What does the whole tree look like? | Accessibility pane > full-page tree |
| Is this text readable? | Styles > color swatch > contrast ratio |
| What would a color-blind user see? | Rendering > Emulate vision deficiencies |
| What does the audit say? | Lighthouse panel, Issues panel |
| What is the raw protocol data? | Protocol monitor, `Accessibility.*` |

TRY: Dock DevTools to the bottom and keep the Accessibility pane open for a whole day of normal work. You will start noticing missing names before you go looking for them.

## The Accessibility pane

Select an element in Elements; the Accessibility pane (in the sidebar, next to
Styles and Computed) shows:

- **Computed Properties** - the resolved role, name, and the states Chromium
  computed.
- The **name source list** - every candidate the ACCNAME algorithm considered,
  with the winner highlighted and the losers struck through. This is the single
  most educational widget in the browser.
- **ARIA Attributes** - what is authored, versus what was computed.
- The **accessibility tree ancestry** for that node.

KEY: The name-source list turns name computation from folklore into something you can watch happen. Use it every time a name surprises you.

## The full-page accessibility tree

Toggle the full-page tree in the Accessibility pane, and the Elements tree is
replaced by the accessibility tree.

- Nodes show role and name; selecting a node selects the corresponding DOM node.
- Ignored nodes are shown as such - which is how you discover that your
  beautifully labelled wrapper is not in the tree at all.
- This is Blink's view of the tree, computed in the renderer. It is *not* byte-
  for-byte the browser process's tree, and not the platform's view.

WATCH: Three trees exist: Blink's (DevTools), the browser process cache (`chrome://accessibility`), and the platform's (`ax_dump_tree`, Accessibility Inspector, NVDA's viewer). When they disagree, you have found the layer with the bug.

## The inspect-mode badge

Hover with the element picker active and the tooltip shows a compact
accessibility summary: role, name, contrast ratio for text, and whether the
element is keyboard-focusable.

- The contrast readout does the WCAG math for you against the *computed*
  background, including gradients and images where it can.
- The "keyboard-focusable" line catches `role="button"` divs without `tabindex`
  instantly.

TRY: Turn on the element picker (Ctrl+Shift+C) and sweep across a toolbar of icon buttons. Missing names show up as blank in the badge - a two-second audit.

## Contrast in the color picker

Click any color swatch in Styles:

- The picker shows the contrast ratio against the computed background, with AA
  and AAA thresholds.
- Expanding it draws a **contrast line** across the color spectrum: everything on
  one side passes. Drag your color to the line and you have the closest passing
  shade to what the designer wanted.
- For text over images or gradients, Chromium falls back to an approximation and
  says so.

KEY: You can fix a contrast failure without leaving the browser and without guessing, in about fifteen seconds.

## The Rendering panel

`More tools > Rendering` is where the user-preference emulation lives.

- **Emulate vision deficiencies**: blurred vision, reduced contrast,
  protanopia, deuteranopia, tritanopia, achromatopsia.
- **Emulate CSS media**: `prefers-color-scheme`, `prefers-reduced-motion`,
  `prefers-contrast`, `prefers-reduced-transparency`, `forced-colors`.
- **Highlight ad frames**, paint flashing, layout shift regions - useful for the
  motion-related criteria.

TRY: Turn on `forced-colors: active` emulation on your own app. Every custom control built out of styled divs will show you exactly how it fails.

## The Issues panel

The Issues panel surfaces accessibility problems Chromium detects while the page
runs, with a link to the offending node and a short explanation.

Typical entries:

- Form elements without associated labels.
- Contrast failures on text.
- `aria-hidden` on a focusable element.
- Table structure problems.

Unlike a Lighthouse run, this updates live as you interact, so it catches issues
in states that only exist after a click.

NOTE: The Issues panel and Lighthouse overlap but are not the same engine; treat them as two opinions rather than one.

## Lighthouse from the panel

Lighthouse's accessibility category runs axe-core against the loaded page.

- It is a **subset**: roughly 30-40% of WCAG issues are machine-detectable at all,
  and a perfect 100 means only "no automated check failed".
- It is excellent at: missing names, contrast, invalid ARIA, document structure,
  duplicate IDs, tab order attributes.
- It cannot judge: whether a name is *meaningful*, whether focus order makes
  sense, whether a live region announces at the right moment, whether your
  widget's keyboard contract is honored.

KEY: Treat a Lighthouse score of 100 as the starting line. The remaining 60% of issues need a human and a keyboard.

## The Elements panel tricks that matter

- **Force element state** (`:hov`) - inspect `:focus` and `:focus-visible` styles
  without fighting the blur.
- **Break on attribute modifications** - right-click a node, and catch the code
  that removes your `aria-expanded`.
- **Copy > Copy styles / Copy JS path** - fast repros.
- The **badges** next to nodes: `flex`, `grid`, `scroll`, and `slot` - the `slot`
  badge tells you where shadow content actually lands, which is where the
  accessibility tree puts it.

TRY: Set a breakpoint on attribute modifications for a node whose `aria-expanded` goes stale. It is usually a framework re-render clobbering it.

## The Console as an accessibility tool

```js
// what is focused right now?
document.activeElement

// every focusable element, in tab order (approximately)
[...document.querySelectorAll('a[href],button,input,select,textarea,[tabindex]')]
  .filter(el => el.tabIndex >= 0)

// find aria-hidden containing focusable descendants
[...document.querySelectorAll('[aria-hidden="true"]')]
  .filter(el => el.querySelector('a[href],button,input,[tabindex]'))

// dangling IDREFs
[...document.querySelectorAll('[aria-labelledby],[aria-describedby]')]
  .flatMap(el => [...['aria-labelledby','aria-describedby']
    .flatMap(a => (el.getAttribute(a)||'').split(/\s+/).filter(Boolean)
      .filter(id => !document.getElementById(id))
      .map(id => ({el, a, id})))])
```

KEY: Four snippets in a bookmarklet catch the majority of the mechanical mistakes in any codebase.

## Emulating a screen reader (badly) is not enough

DevTools can show you the tree, but it cannot show you the *experience*.

What only a real AT reveals:

- Browse vs focus mode transitions.
- How verbose the announcement is in practice, and whether the user gets
  interrupted.
- Whether an update was announced at all, or arrived while the user was
  mid-sentence elsewhere.
- Whether the reading order matches the visual order.

NOTE: Budget one hour to learn the ten commands of one screen reader. For NVDA: start/stop, Insert+Down (read all), H (next heading), D (landmark), Tab, F (form field), Insert+F7 (element list), Insert+Space (browse/focus toggle).

## Chrome's other internal pages

- `chrome://accessibility` - per-tab tree dumps and mode toggles (module 9).
- `chrome://flags` - `#enable-experimental-web-platform-features` and various
  accessibility-specific flags.
- `chrome://gpu`, `chrome://histograms` - `Accessibility.*` histograms record
  which modes are on in the wild and how long serialization takes.
- `chrome://tracing` / the Performance panel with the `accessibility` category -
  where you see serialization work on the timeline.

REF: `ui/accessibility/ax_mode_histogram_logger.h` is what populates the mode histograms. It is a short, readable file that shows exactly what the team measures.

## A DevTools workflow for a real bug

Something is announced wrong. The fastest route:

1. Element picker over the control - is the name blank or wrong in the badge?
2. Accessibility pane - which name source won? Is it `placeholder` or `title`?
3. Full-page tree - is the node ignored? Is it where you expect in the tree?
4. `chrome://accessibility` - does the browser-process tree agree with DevTools?
5. Platform inspector (`ax_dump_tree`, Accessibility Inspector, `inspect.exe`) -
   does the platform node agree with the browser tree?
6. The AT itself - does the AT agree with the platform node?

The first place two views disagree is the layer that owns the bug.

KEY: This ladder is the core debugging skill of this entire course. Modules 13-19 explain what each rung is made of.
