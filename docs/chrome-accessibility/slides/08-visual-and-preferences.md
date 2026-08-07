---
module: Visual design and user preferences
part: Part II - The web platform
---

## Contrast, concretely

WCAG contrast is a ratio between relative luminances, from 1:1 (identical) to
21:1 (black on white).

- **4.5:1** - normal text, AA.
- **3:1** - large text (18.66px bold or 24px), and *non-text* elements: icons,
  input borders, focus indicators, chart lines.
- **7:1** - AAA, and a reasonable target for body text on a product you expect
  people to read all day.

Chrome DevTools shows the ratio in the color picker with a checkbox-style pass
mark, and can draw the contrast line on the color spectrum so you can pick a
passing shade directly.

TRY: Open DevTools, inspect any text node, click the color swatch in Styles, and expand the contrast ratio section. The white line across the spectrum is the pass/fail boundary.

## Do not use color alone

The oldest rule in the book, and still the most-violated in dashboards.

- Red text for errors -> add an icon and the word "Error".
- Green/red status dots -> add a shape difference or a label.
- Chart series distinguished only by hue -> add markers, dashes, or direct
  labels.
- Required fields marked only by a red asterisk color -> mark them with text and
  `aria-required`.

Roughly 1 in 12 men has some form of color vision deficiency. DevTools can
emulate protanopia, deuteranopia, tritanopia, and achromatopsia from the
Rendering panel.

KEY: "Would this still work in grayscale?" is a question you can answer in five seconds and it catches almost every instance.

## Text sizing, zoom, and reflow

Three different user actions, three different failure modes.

- **Page zoom** (Ctrl +) scales everything. Layout must reflow at 400% zoom in a
  1280px viewport without a second scrollbar (WCAG 1.4.10) - which is the same
  requirement as being responsive down to 320px.
- **Text-only resize** to 200% must not clip or overlap (1.4.4). Fixed-height
  containers with `overflow:hidden` are the usual culprit.
- **User font size** set in Chrome's settings changes the default font size;
  layouts built entirely in `px` ignore it.

```css
/* respects the user's font size preference */
html { font-size: 100%; }
.card { padding: 1rem; max-width: 60ch; }
```

WATCH: `rem` respects the user's base font size; `px` does not. A design system built on `px` opts every user out of their own preference.

## Motion, animation, and vestibular safety

Large-area motion can cause nausea, dizziness, and migraine. This is not a
metaphor - it is a documented physical response.

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```

- Parallax, auto-playing carousels, and full-page transitions are the worst
  offenders.
- Anything that moves, blinks, or scrolls for more than 5 seconds needs a pause
  control (WCAG 2.2.2).
- Nothing may flash more than three times per second (2.3.1) - a seizure risk.

NOTE: This deck honors `prefers-reduced-motion` - the slide fade is removed entirely rather than shortened.

## The preference media queries

The browser exposes the user's system settings to CSS. Use them.

| Query | Means |
| --- | --- |
| `prefers-reduced-motion: reduce` | animations make me ill |
| `prefers-color-scheme: dark` | I want dark UI |
| `prefers-contrast: more / less / custom` | I need stronger or softer contrast |
| `prefers-reduced-transparency: reduce` | blur and translucency hurt |
| `prefers-reduced-data: reduce` | send me less |
| `forced-colors: active` | the OS is overriding colors |
| `inverted-colors: inverted` | the OS is inverting |

```js
const mq = matchMedia('(prefers-reduced-motion: reduce)');
mq.addEventListener('change', update);
```

KEY: These queries are the user telling you what they need, in a machine-readable form, for free. Ignoring them is a choice.

## Forced colors mode

Windows High Contrast (now "Contrast themes") replaces your palette with the
user's, and Chromium implements it as `forced-colors: active`.

```css
@media (forced-colors: active) {
  .card { border: 1px solid CanvasText; }        /* keep boundaries visible */
  .icon { forced-color-adjust: auto; }
  .brand-logo { forced-color-adjust: none; }     /* opt out, sparingly */
}
```

- System color keywords: `Canvas`, `CanvasText`, `LinkText`, `VisitedText`,
  `ButtonFace`, `ButtonText`, `Highlight`, `HighlightText`, `GrayText`,
  `AccentColor`.
- Background *images* survive; background *colors* do not. UI that depends on a
  background color to convey state disappears.
- Borders are your friend: they are drawn in the user's text color.

WATCH: Custom checkboxes and toggles built from styled divs typically vanish entirely in forced colors. Test them; use `Highlight`/`ButtonText` to redraw the state.

## Dark mode is an accessibility feature

Not merely a style. For users with photophobia or migraine it is the difference
between usable and unusable.

```css
:root { color-scheme: light dark; }
```

- `color-scheme` tells the browser to render form controls, scrollbars, and the
  default canvas in the right scheme - a one-line fix that avoids a white flash
  and unreadable native widgets.
- Do not just invert: pure white on pure black causes halation for many readers.
  Slightly softened values are easier on the eye.
- Contrast requirements apply equally in both themes, and dark themes often fail
  them because saturated colors lose contrast on dark backgrounds.

TRY: Toggle this deck's theme with `t`. The palette is defined once on `:root` and only re-declared under the dark queries - the pattern that avoids the "half-themed" bug.

## Spacing, and the user stylesheet

WCAG 1.4.12 says a user must be able to override text spacing without losing
content:

- line height 1.5x font size, paragraph spacing 2x, letter spacing 0.12em, word
  spacing 0.16em.

Users with dyslexia routinely apply exactly these via extensions or user
stylesheets. Layouts that assume a fixed text height break.

```css
/* resilient: content boxes grow */
.card { min-height: 4rem; }       /* not height: 4rem */
```

KEY: Anything with a fixed height that contains text is a bug waiting for a user stylesheet.

## Readability

Not directly WCAG-testable, but it dominates real comprehension.

- Line length around 45-75 characters (`max-width: 65ch`).
- Left-aligned, not justified - justification creates rivers of whitespace that
  are hard to track.
- Real paragraph breaks and headings, not walls of text.
- Plain language: short sentences, expand acronyms once, put the point first.
- Do not rely on italics for emphasis over long spans.

NOTE: `ch` units are a good approximation for measure. This deck caps body text at 62-70ch for the same reason.

## Zoom, viewport, and the meta tag

```html
<!-- allows the user to pinch zoom -->
<meta name="viewport" content="width=device-width, initial-scale=1">

<!-- forbids it: a WCAG failure -->
<meta name="viewport" content="width=device-width, initial-scale=1,
      maximum-scale=1, user-scalable=no">
```

Chrome (and Safari) ignore `user-scalable=no` in many contexts precisely because
it was so widely abused, but do not rely on the browser to correct your markup.

WATCH: `user-scalable=no` still appears in framework boilerplate and starter templates. Grep for it.

## Charts, data visualization, and complex graphics

Where visual design and semantics meet.

- Give the chart a role and a name: `role="img" aria-label="Revenue by quarter,
  peaking in Q3"`.
- Provide the underlying data as a table - visually hidden if necessary. The
  table is the accessible version, not a chore.
- Do not rely on tooltips alone; hover-only data is unreachable by keyboard.
- Use patterns as well as colors for fills; check the palette against color
  vision deficiency simulation.
- Keep line weights and label text above the 3:1 non-text contrast bar.

TRY: Take one chart in your product and add a `<table>` behind a "view as table" toggle. It usually takes an hour and it serves screen reader users, print users, and anyone who wanted the numbers.

## Visual checklist

1. Body text at 4.5:1, large text and UI components at 3:1.
2. Nothing conveyed by color alone.
3. 400% zoom reflows without horizontal scrolling.
4. `rem`-based sizing that respects the user's font preference.
5. `prefers-reduced-motion` honored; nothing flashes.
6. `forced-colors` tested - borders and states still visible.
7. `color-scheme` declared; both themes meet contrast.
8. Focus indicators visible against every background they land on.
9. Text spacing overrides do not clip content.
10. Line length constrained; text left-aligned.

KEY: Everything on this list is verifiable without a screen reader, in a browser you already have open. There is no excuse for these to reach users.
