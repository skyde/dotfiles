---
module: HTML semantics
part: Part II - The web platform
---

## The free eighty percent

Every native HTML element arrives with a role, a name computation, keyboard
behavior, focus behavior, and platform mappings that Chromium has already
implemented and tested on five platforms.

```html
<button type="submit">Pay</button>
```

That one line gives you: role `button`, name from contents, focusable, activates
on Enter and Space, exposed as `ROLE_SYSTEM_PUSHBUTTON` / `AXButton` /
`ATK_ROLE_PUSH_BUTTON` / `android.widget.Button`, a `kDoDefault` action, a
disabled state that ATs understand, and forced-colors styling that survives high
contrast mode.

KEY: The first rule of ARIA is not to use ARIA. Native elements are not merely easier - they are the specification's reference behavior, and everything else is measured against them.

## The HTML-AAM mapping table

`HTML Accessibility API Mappings` is the spec that says what each element becomes
in the accessibility tree. A sample of what Chromium implements:

| HTML | Role | Name comes from |
| --- | --- | --- |
| `<button>` | button | contents, `aria-label`, `title` |
| `<a href>` | link | contents |
| `<a>` (no href) | generic | - |
| `<input type=text>` | textField | `<label>`, `aria-label`, `placeholder` |
| `<input type=checkbox>` | checkBox | `<label>` |
| `<h1>`-`<h6>` | heading, level 1-6 | contents |
| `<nav>` | navigation | `aria-label` |
| `<main>` | main | - |
| `<table>` | table | `<caption>` |
| `<img alt="x">` | image | `alt` |
| `<img alt="">` | ignored | - |

WATCH: `<a>` without `href` is not a link. It is generic and not focusable. This is the single most common "why is my link not announced" bug.

## Landmarks: the page skeleton

Screen reader users navigate long pages by landmark, often before reading a word
of content.

```html
<header>            <!-- role=banner (when a direct child of body) -->
<nav aria-label="Primary">     <!-- role=navigation -->
<main>              <!-- role=main -->
<aside>             <!-- role=complementary -->
<form aria-label="Search">     <!-- role=form, only when named -->
<footer>            <!-- role=contentinfo (when a direct child of body) -->
<section aria-label="Results"> <!-- role=region, only when named -->
```

- Exactly one `<main>`. More than one `<nav>` is fine - name them.
- `<section>` and `<form>` only become landmarks when they have an accessible
  name; unnamed they are generic, which is usually what you want.

TRY: On any page you own, list the landmarks with a screen reader's landmark list (NVDA `d`, VoiceOver rotor). If it does not read like a table of contents, your structure is wrong.

## Headings are the outline

Headings are how users skim. They are also the most abused element on the web.

- Levels express nesting, not font size. `h1` then `h3` is a broken outline.
- One `h1` per page, matching the page's subject.
- Every screen reader offers "next heading" (`h` in NVDA/JAWS) and a heading
  list. If your page has three headings, the user has no map.
- `role="heading" aria-level="2"` exists, but `<h2>` is better in every way.

In Chromium the level lands in `ax::mojom::IntAttribute::kHierarchicalLevel`, and
`AXEventGenerator::Event::HIERARCHICAL_LEVEL_CHANGED` fires when it changes.

KEY: Headings, landmarks, and lists are the three structures users navigate by. Get them right and half of "accessibility" is done.

## Lists, tables, and structure that means something

- A list tells the AT how many items there are: "list, 5 items". That count is
  `kSetSize`, and each item carries `kPosInSet`.
- A data table needs `<th>` with `scope`, and a `<caption>`. Then the user can
  ask "what column am I in" and get a real answer.
- A layout table (still out there) should be `role="presentation"` so the AT does
  not announce a 40x12 grid.

```html
<table>
  <caption>Q3 revenue by region</caption>
  <thead><tr><th scope="col">Region</th><th scope="col">Revenue</th></tr></thead>
  <tbody><tr><th scope="row">EMEA</th><td>4.1M</td></tr></tbody>
</table>
```

REF: Chromium computes table geometry - row/column indices, spans, header cell relations - in `AXTable*` code and exposes it via `kTableRowIndex`, `kTableCellColumnSpan`, and friends.

## Forms: labels are the whole game

```html
<!-- best: explicit association -->
<label for="age">Age</label><input id="age" type="number">

<!-- also fine: wrapping -->
<label>Age <input type="number"></label>

<!-- acceptable when there is genuinely no visible label -->
<input type="search" aria-label="Search products">

<!-- broken: placeholder is not a label -->
<input type="text" placeholder="Age">
```

- `placeholder` disappears when the user types, and is often too low-contrast -
  yet Chromium falls back to it for the name, which is why the bug survives
  review.
- Group related controls with `<fieldset>` + `<legend>` - radio groups especially.
- Errors: `aria-invalid="true"` plus `aria-describedby`, or `aria-errormessage`.

WATCH: A name that comes from `placeholder` shows up in the tree as `nameFrom=placeholder`. Grep for that in a tree dump and you will find real bugs in minutes.

## Images and alternative text

Three cases, three answers.

1. **Informative** - `alt` describes the information: `alt="Line chart: revenue
   doubled in Q3"`.
2. **Decorative** - `alt=""`. The node is dropped from the tree entirely. This is
   correct and good; silence is better than "IMG_0421.jpg".
3. **Functional** - the image is the label of a control: the `alt` describes the
   *action*, not the picture: `alt="Search"` on a magnifier icon inside a button.

Complex images (charts, diagrams) need a short `alt` plus a longer description in
the page, referenced with `aria-describedby` or `aria-details`.

NOTE: Chromium can also generate image descriptions on demand - `AXMode::kLabelImages`, the `kAnnotatePageImages` action, and `ImageAnnotationStatus` in `ax_enums.mojom` are that feature's plumbing.

## The elements people forget

- `<label>` - covered, still forgotten.
- `<fieldset>` / `<legend>` - the only good way to name a radio group.
- `<caption>`, `<th scope>`, `<colgroup>` - table semantics.
- `<time datetime>`, `<abbr title>`, `<code>`, `<mark>`, `<del>`, `<ins>` -
  Chromium exposes many of these as text attributes or as roles like
  `ax::mojom::Role::kCode` and `kMark`.
- `<details>` / `<summary>` - a free disclosure widget with expanded state.
- `<dialog>` - a free modal with focus containment and `aria-modal` semantics.
- `<output>` - an implicit live region.

TRY: Replace one hand-rolled disclosure widget in your codebase with `<details>`. Count the lines of JavaScript and ARIA you delete.

## Language, direction, and the document

Boring attributes that change everything about how a page is spoken.

```html
<html lang="en">
  ...
  <p>The French for hello is <span lang="fr">bonjour</span>.</p>
  <p dir="rtl" lang="ar">...</p>
```

- `lang` selects the speech synthesizer's voice and pronunciation rules. Without
  it, an English screen reader reads French text as gibberish.
- `<title>` becomes the accessible name of the root web area - it is the first
  thing announced on navigation, and the tab list entry.
- `dir` affects text direction in inline text boxes, which affects caret
  geometry.

KEY: `lang` on `<html>` is a one-line fix with an outsized effect. Chromium exposes it as `kLanguage` and fires `LANGUAGE_CHANGED`.

## Shadow DOM and custom elements

- The accessibility tree flattens shadow trees: slotted content appears where it
  is rendered, not where it was authored. This is what you want.
- A custom element with no role is `generic` - it contributes nothing.
- `ElementInternals` lets a custom element declare semantics without ARIA
  attributes in the DOM:

```js
#internals = this.attachInternals();
connectedCallback() {
  this.#internals.role = 'switch';
  this.#internals.ariaChecked = 'false';
}
```

- Cross-root ARIA (referencing an ID across a shadow boundary) is the long-standing
  gap; `aria-labelledby` cannot see into or out of a shadow root, which is why
  the Reference Target proposal exists.

WATCH: Encapsulation and ARIA IDREFs fundamentally conflict. If you are designing a component library on shadow DOM, decide your naming strategy early.

## Canvas, SVG, and the drawn web

Pixels have no semantics. If you draw the UI, you supply the tree.

- **Canvas**: put real DOM elements inside the `<canvas>` element as fallback
  content, keep them focusable, and keep their bounds in sync with
  `context.drawFocusIfNeeded()`. Chromium exposes that fallback subtree.
- **SVG**: use `<title>` as the first child for a name, `<desc>` for a
  description, and `role="img"` on a decorative-but-meaningful graphic. SVG
  `<g>` elements are kept in Chromium's internal tree on ChromeOS specifically to
  support Select-to-Speak.
- WebGL: there is no fallback tree at all unless you build one.

REF: `ax_enums.mojom` has dedicated roles - `kCanvas`, `kSvgRoot`, `kGraphicsDocument`, `kGraphicsObject`, `kGraphicsSymbol` - because SVG has its own accessibility mapping spec.

## Checklist: semantics review

Before any of the ARIA in the next module, run this list over a page:

1. One `<h1>`; heading levels nest without skipping.
2. `<main>`, `<nav>`, `<header>`, `<footer>` present; multiple same-type
   landmarks are named.
3. Every input has a programmatically associated label.
4. Every image has an intentional `alt` (including the empty one).
5. Every interactive thing is a `<button>`, `<a href>`, or a real form control.
6. Tables have `<caption>` and `<th scope>`.
7. `lang` on `<html>`, and on any foreign-language passage.
8. `<title>` describes the page, not the site.

KEY: A page that passes this list needs remarkably little ARIA. Most ARIA in the wild is compensating for a failure on this list.
