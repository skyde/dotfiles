---
module: Names and descriptions
part: Part II - The web platform
---

## The accessible name is the user interface

For a screen reader user, the accessible name *is* the button. If it is wrong,
the control does not exist as far as they are concerned.

- Voice control users must be able to *say* the name.
- Braille users read the name, abbreviated.
- Automation clients find controls by name.
- Search-by-text in a screen reader matches the name.

The algorithm that produces it is called **ACCNAME** (Accessible Name and
Description Computation), and Blink implements it in `AXObject`, mostly in
`AXNodeObject::TextAlternative` and friends.

KEY: Name computation is a specified algorithm, not a heuristic. You can predict its output exactly, and Chromium can be wrong in ways you can file bugs about.

## The name computation, in order

For most elements, walk this list and stop at the first hit:

1. `aria-labelledby` - concatenate the referenced elements' text.
2. `aria-label`.
3. The **native** host-language label: `<label for>`, `<caption>`, `<legend>`,
   `<figcaption>`, SVG `<title>`, `alt` on an image, the `<title>` of the page
   for the root.
4. **Contents** - the flattened text of descendants, but only for roles where
   "name from contents" is allowed (button, link, heading, cell, menuitem,
   option, tab...).
5. `title` attribute (tooltip).
6. `placeholder`, for text inputs, as a last resort.

WATCH: Steps 5 and 6 are fallbacks, not features. A control named by its tooltip is a control with no visible label; a control named by its placeholder loses its name the moment the user types.

## NameFrom: how Chromium records the answer

Chromium does not just store the name; it stores *where the name came from*, in
`ax::mojom::NameFrom`:

```text
kNone            kAttribute      kAttributeExplicitlyEmpty  kCaption
kContents        kCssAltText     kPlaceholder               kRelatedElement
kProhibited      kProhibitedAndRedundant                    kTitle
kValue           kPopoverTarget  kInterestFor
```

- `kRelatedElement` means `aria-labelledby` or a `<label>` - a pointer.
- `kAttributeExplicitlyEmpty` is `alt=""` or `aria-label=""` - "deliberately
  nameless", which is different from "we found nothing".
- `kProhibited` records that a name was authored on a role where ARIA 1.2
  forbids naming (generic, paragraph, and similar) - so the name was dropped.

REF: In a tree dump this shows up as `nameFrom=placeholder` or `nameFrom=title`. Those two strings are a free bug-finding grep across a codebase's expectation files.

## Name from contents

Only some roles compute their name from what is inside them. This is why the
same markup names one element and not another.

```html
<button>Save <span class="icon" aria-hidden="true">*</span></button>
<!-- name = "Save" : button allows name-from-contents, icon is hidden -->

<div role="region">Save</div>
<!-- name = "" : region does not take name from contents -->
```

Allowed (abbreviated): button, checkbox, columnheader, gridcell, heading, link,
menuitem, option, radio, row, rowheader, switch, tab, tooltip, treeitem.

Not allowed: most landmarks, `article`, `document`, `form`, `img`, `list`,
`region`, `textbox` - these need an explicit name.

KEY: If a role does not take a name from contents, visible text inside it is invisible to the naming algorithm. Name it explicitly.

## Descriptions

The description is the second string, announced after the name, usually after a
pause and often only in verbose modes.

Sources, in Chromium's `ax::mojom::DescriptionFrom`:

```text
kAriaDescription  kButtonLabel     kRelatedElement  kRubyAnnotation
kSummary          kSvgDescElement  kTableCaption    kTitle
kPopoverTarget    kInterestFor     kProhibitedNameRepair
```

- `aria-describedby` (`kRelatedElement`) is the usual route.
- `aria-description` gives a description without an IDREF.
- `kProhibitedNameRepair` is a nice detail: when a name is authored on a role
  where naming is prohibited, Chromium repairs the situation by demoting the
  string to a description rather than silently discarding the author's intent.

WATCH: Descriptions are skipped by many users and some modes. Never put essential information there - if it must be heard, it belongs in the name or in the content.

## Worked example 1: the icon button

```html
<button>
  <svg aria-hidden="true" focusable="false">...</svg>
</button>
```

Name: **empty**. The SVG is hidden and there is no text. The user hears "button".

Fixes, best to worst:

```html
<button><svg aria-hidden="true"></svg><span class="visually-hidden">Delete</span></button>
<button aria-label="Delete"><svg aria-hidden="true"></svg></button>
<button title="Delete"><svg aria-hidden="true"></svg></button>
```

The first keeps the name in the DOM as real text: it survives translation, it is
findable by browser find-in-page, and it is what `nameFrom=contents` expects.

NOTE: `focusable="false"` on inline SVG matters on some older engines because SVG elements could otherwise be focusable; it costs nothing to keep.

## Worked example 2: labelled by many

```html
<h2 id="t">Delete project</h2>
<p id="d">This cannot be undone.</p>
<div role="alertdialog" aria-labelledby="t" aria-describedby="d">
  <button>Cancel</button>
  <button>Delete</button>
</div>
```

Announced roughly as: *"Delete project, alert dialog. This cannot be undone.
Cancel, button."*

- The dialog takes its name from the heading and its description from the
  paragraph - both `kRelatedElement`.
- Do not also put `aria-label` on the dialog; it would win and hide the heading.

TRY: Add `aria-label="Confirm"` to that dialog and watch the announcement change to "Confirm" - the heading text vanishes from the announcement entirely.

## Worked example 3: the table cell

```html
<table>
  <caption>Servers</caption>
  <tr><th scope="col">Host</th><th scope="col">Status</th></tr>
  <tr><th scope="row">web-1</th><td>Healthy</td></tr>
</table>
```

The cell "Healthy" has name `Healthy` from contents, and inherits *context* from
its headers, which the AT announces as "Status, web-1, Healthy" when the user
navigates into it.

That context is not part of the name - it comes from the header relations
Chromium computes and exposes (`kTableCellColumnHeaderIds` and friends), which is
why `scope` matters even though the cell text is unchanged.

KEY: Names are per-node; context is computed by the AT from relations. Do not try to stuff context into the name.

## Translation, internationalization, and names

- A name in `aria-label` is a string in your JavaScript, not in your DOM. Machine
  translation, browser translate, and many localization pipelines will miss it.
- Visually hidden real text is translated like any other text.
- Concatenated `aria-labelledby` lists produce word order that may be wrong in
  other languages - "3 unread messages" cannot be assembled from three
  independently translated fragments.
- Names inherit `lang` from their element, which selects the voice.

WATCH: "Name assembled from fragments" is a localization bug waiting to happen. Prefer one complete, translatable string.

## Names in Chromium: where the code lives

- `AXObject::GetName()` and `AXNodeObject::TextAlternative()` -
  `third_party/blink/renderer/modules/accessibility/`. This is the ACCNAME
  implementation, complete with the recursion guard and the visited set.
- The result lands in `ax::mojom::StringAttribute::kName` with
  `IntAttribute::kNameFrom`.
- Description: `kDescription` + `kDescriptionFrom`.
- Changes fire `AXEventGenerator::Event::NAME_CHANGED` /
  `DESCRIPTION_CHANGED`, plus `LABELED_BY_CHANGED` when the relation itself
  changes.

REF: The name computation is recursive and can traverse a lot of the tree. It is one of the hottest paths in Blink accessibility, and a frequent subject of caching work.

## Testing names

```text
# a DumpAccessibilityTree test that isolates naming
<!--
@BLINK-ALLOW:name*
@BLINK-ALLOW:nameFrom*
@MAC-ALLOW:AXTitle*
@MAC-ALLOW:AXDescription*
-->
```

- The `content/test/data/accessibility/aria` and `.../html` directories are full
  of name computation tests - `name-calc-*.html` in web tests too.
- For a quick check without a build: `document.querySelector('button')` in
  DevTools, then read the Accessibility pane's "Computed Properties".
- `getComputedAccessibleNode()` and CDP's `Accessibility.getPartialAXTree`
  expose the name programmatically.

TRY: Write a five-line HTML file with a control named four different ways and dump the tree with all four passes. It is the fastest way to internalize the precedence order.

## Naming checklist

1. Does every interactive element have a non-empty name?
2. Does the name contain the visible label text (WCAG 2.5.3)?
3. Is `nameFrom` one of contents / relatedElement / attribute - not placeholder
   or title?
4. Is the name unique enough to distinguish it from its siblings? Ten "Read more"
   links are ten identical names in a link list.
5. Is the name stable? A name that changes on hover breaks voice control.
6. Are decorative images `alt=""` rather than unnamed?
7. Do descriptions carry only supplementary information?

KEY: Ten links named "Read more" pass every automated audit and fail every real user. Automation cannot check names for meaning - only you can.
