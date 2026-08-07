---
module: Views, WebUI, PDF, and other trees
part: Part IV - The Chromium pipeline
---

## Chrome's own UI is not web content

The tab strip, the omnibox, menus, bubbles, and dialogs are **Views** - Chromium's
own C++ UI toolkit, drawn with Skia. Nothing about them is HTML.

They still have to be accessible, and they have to appear in the *same*
accessibility tree as the page, because a window presents exactly one tree to the
platform.

- Each `View` has a `ViewAccessibility` that supplies its `AXNodeData`.
- `ViewAXPlatformNodeDelegate` bridges it to an `AXPlatformNode`.
- `BrowserAccessibilityManager` composes the Views tree with the web content
  trees.

KEY: A screen reader walking from the tab strip into a page crosses from Views into web content without noticing. Making that seam invisible is a substantial amount of engineering.

## The Views accessibility API

```cpp
// ui/views/accessibility/view_accessibility.h - conceptually
void SetRole(ax::mojom::Role);
void SetName(const std::string&, ax::mojom::NameFrom);
void SetDescription(const std::string&);
void SetIsIgnored(bool);
void SetIsEnabled(bool);
```

Modern Views code sets accessibility properties on `ViewAccessibility` directly
rather than overriding a "fill in the node data" method - which means changes can
fire events immediately and be cached.

Supporting cast in `ui/views/accessibility/`:

- `AXVirtualView` - virtual children for custom-drawn controls that are not Views
  (a table row inside a canvas-like control).
- `AXAuraObjCache` and the `AXTreeSourceViews` family - the tree source that lets
  the standard serializer walk the Views hierarchy.
- `AXUpdateNotifier` / `AXUpdateObserver` - the change notification plumbing.
- `AtomicViewAXTreeManager` - a manager for a single-view tree.

REF: The `IsAccessibilityTreeForViewsEnabled()` and `IsViewsAccessibilitySerializeOnDataChangeEnabled()` feature flags in `accessibility_features.h` track the ongoing move to serialize Views like everything else.

## accessibility_paint_checks

A neat piece of engineering discipline: `ui/views/accessibility/accessibility_paint_checks.cc`
runs in debug builds and fails loudly when a focusable View paints without an
accessible name or role.

```text
DCHECK: View is focusable but has no accessible name.
```

That single check has caught a very large number of unlabeled buttons before they
ever shipped.

TRY: If you work on Chrome's UI, add a focusable custom View with no name and run a debug build. The failure tells you exactly what to fix, at the moment you create the problem.

## WebUI: web content wearing a browser hat

Settings, History, Downloads, the New Tab Page, and `chrome://accessibility`
itself are WebUI - real web pages in real renderer processes.

- They travel the normal Blink -> content -> platform pipeline. Nothing special.
- Accessibility for WebUI is therefore ordinary web accessibility: ARIA
  attributes, focus management, and semantics in TypeScript and HTML.
- Shared behaviors live in the WebUI resource libraries so that every surface
  gets the same keyboard and ARIA handling.

WATCH: Because WebUI is web content, it inherits every web accessibility bug class - including the ones this course's Part II covers. Chrome's own UI is not exempt from unlabeled icon buttons.

## PDF

The PDF viewer is a plugin rendering into a page, and it builds its own
accessibility tree.

- PDFium extracts text runs, characters, images, links, and any **structure tags**
  the document carries, and hands them to the plugin's accessibility code.
- That produces `AXNodeData` which is stitched into the host page's tree via the
  child-tree mechanism.
- **Tagged PDFs** have real structure - headings, lists, tables, alt text.
  Untagged PDFs have only positioned text runs, so the reading order is a
  heuristic.
- `AXMode::kPDFPrinting` exists so printing to PDF can carry accessibility
  structure out with it.
- PDF OCR (`IsAccessibilityPdfOcrForSelectToSpeakEnabled`) runs recognition on
  scanned, image-only PDFs so their text exists at all.

REF: PDF accessibility tests run under `browser_tests` as `PDFExtensionAccessibilityTreeDumpTest*`, not `content_browsertests`.

## Child trees and stitching, generalized

The `AXTreeID` mechanism is not just for iframes. Anything that owns its own tree
plugs in the same way.

- Out-of-process iframes.
- `<webview>` and other browser plugins.
- The PDF viewer.
- On ChromeOS: Android apps (ARC++), the Views UI, Lacros surfaces.
- `ax::mojom::Action::kStitchChildTree` lets a node adopt a child tree explicitly.

```text
hostNode (role=iframe|embeddedObject|pdfRoot)
    kChildTreeId = <UnguessableToken>
        -> the embedded tree's root becomes this node's platform child
```

KEY: One embedding mechanism for every kind of embedded content is why an AT can walk from Chrome's UI, into a page, into a PDF, into an Android app, without special cases.

## Snapshots and offline trees

Because a tree is data, Chromium can produce one without a live consumer.

- **Freeze-dried tabs** on Android: a snapshot of the page's accessibility tree is
  displayed - and is fully accessible - while the real page loads over a slow
  connection.
- **Distillation / Reading Mode**: a snapshot feeds the distiller.
- **Assistant / structure extraction**: `ax_assistant_structure.cc` in
  `ui/accessibility` converts a snapshot into a structure other features can
  consume.
- **PDF export** and print-to-PDF tagging use snapshot mode.

`AXTreeSerializer::set_max_node_count()` and `set_timeout()` exist for exactly
these one-shot uses: a snapshot of a pathological page must terminate.

WHY: Every one of these features would need bespoke page-scraping code if the accessibility tree were not a plain serializable value.

## Automatic annotations

Where Chromium adds information the page did not provide - carefully, and behind
explicit modes.

- **Image descriptions**: `AXMode::kLabelImages` plus the
  `kAnnotatePageImages` action; results arrive as
  `kImageAnnotation` with an `ImageAnnotationStatus` recording whether it
  succeeded, is pending, or was ineligible.
- **Main node annotation**: `AXMode::kAnnotateMainNode` and
  `IsMainNodeAnnotationsEnabled()` - inferring the main landmark when a page has
  none.
- **Tree fixing**: `IsAXTreeFixingEnabled()` - experimental repair of badly
  structured pages.

WATCH: Annotation is a policy minefield. Guessing wrong is worse than staying silent, which is why every one of these is behind a mode flag, a feature flag, and usually a user setting.

## Other consumers inside the browser

Features that read the tree without being an AT:

- **Autofill and password manager** - `kAXModeFormControls` was created for them.
- **Reading Mode / Read Anything** - distillation from the tree.
- **Select-to-Speak** and **Live Caption** on ChromeOS.
- **Find-in-page** and text fragment features interact with the same text
  machinery.
- **Automation extensions** - anything on `chrome.automation`.

Each of these is a reason the tree must be correct even when no screen reader is
present - and a reason accessibility work is not "for a minority of users".

KEY: The accessibility tree is quietly one of the most reused data structures in the browser. Breaking it breaks features nobody associates with accessibility.

## When you add a new UI surface

A checklist for Chromium engineers shipping something new:

1. Is it Views, WebUI, or custom-drawn? That decides which layer you work in.
2. Every focusable thing has a role and a name -
   `accessibility_paint_checks` will tell you if not.
3. Custom-drawn compound controls need `AXVirtualView` children, not one opaque
   node.
4. If it owns its own tree, wire up an `AXTreeID` and the child-tree attribute.
5. Fire the right events - or better, make the state change visible in the tree
   and let `AXEventGenerator` do it.
6. Add a dump test with expectations on at least the platforms you ship to.

TRY: Pick a recent Chrome UI feature and find its accessibility code. If you cannot find any, that is a bug report waiting to be filed - with a patch attached.
