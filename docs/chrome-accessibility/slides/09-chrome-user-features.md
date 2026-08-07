---
module: Chrome's own accessibility features
part: Part III - Tools
---

## Accessibility is off until someone asks

Chrome does not build accessibility trees by default. That is a deliberate,
load-bearing performance decision.

- Nothing happens until a client appears: an AT attaching to the platform API, a
  Chrome feature that needs the tree, or a command-line flag.
- What gets built is controlled by `AXMode` flags, so a password manager gets a
  cheaper tree than a screen reader.
- Turning it on has a real cost: extra memory for the cache, extra work on every
  layout.

```sh
chrome --force-renderer-accessibility                    # complete, still adjustable
chrome --force-renderer-accessibility=basic              # kNativeAPIs|kWebContents
chrome --force-renderer-accessibility=form-controls
chrome --force-renderer-accessibility=complete
chrome --disable-renderer-accessibility
```

KEY: "Accessibility on demand" is why Chromium can afford a full cached tree at all. Module 23 is the whole story.

## chrome://accessibility

The single most useful internal page in this entire course.

- Lists every renderer, and lets you toggle accessibility modes globally and
  per-tab: native APIs, web contents, inline text boxes, extended properties,
  HTML, screen reader mode, label images.
- "show accessibility tree" dumps the **browser process** tree for that tab - the
  cache that ATs actually read.
- Enable the *Internal* checkbox to see internal-only fields.
- There is experimental support for recording a page's accessibility changes and
  replaying them, which follows directly from "it's all data".

TRY: Open `chrome://accessibility`, tick Internal, and dump the tree for a tab you have open right now. Compare it to the DevTools tree for the same page.

## The desktop settings that matter

`chrome://settings/accessibility`, and the OS underneath it:

- **Live Caption** - on-device speech recognition captions any audio playing in
  the browser.
- **Caret browsing** (F7) - a text cursor you can move through the page with
  arrow keys, with selection. Useful for motor and low-vision users, and
  excellent for debugging text geometry.
- **Show quick highlight on the focused object** - draws a focus ring Chrome
  itself controls.
- **Get image descriptions from Google** - sends unlabeled images for automatic
  description; the plumbing is `AXMode::kLabelImages` and the
  `kAnnotatePageImages` action.
- **Page zoom** and **font size** defaults, per site or globally.

NOTE: On ChromeOS these live in the OS settings and the list is far longer - see module 21.

## Reading mode

Chrome's Reading Mode (the "Read Anything" feature internally) distills a page
into clean text in the side panel.

- Its source is the **accessibility tree**, not the DOM - so the same semantics
  you expose to screen readers determine whether Reading Mode works on your page.
- It supports read-aloud with word highlighting, font and spacing controls, and
  themes.
- Feature flags in `accessibility_features.h` show the shape of the work:
  `IsReadAnythingImprovedUiEnabled`, `IsReadAnythingReadAloudPhraseHighlightingEnabled`,
  `IsReadAnythingLineFocusEnabled`, `IsAXTreeFixingEnabled`.

KEY: Reading mode is a direct consumer of your semantics. If your article is a soup of divs, it distills badly - a visible, non-screen-reader symptom of a semantics bug.

## Zoom, and what it actually changes

- **Page zoom** (Ctrl +/-) scales layout: CSS pixels get bigger, layout reflows,
  and the accessibility tree's bounding boxes change accordingly.
- **Full-page zoom vs pinch zoom**: pinch zoom is a visual viewport transform; it
  does not reflow, and it does not change layout coordinates.
- Chromium accessibility bounds are in CSS/DIP coordinates and get transformed to
  screen coordinates as needed - a common source of "the magnifier highlights the
  wrong rectangle" bugs when device scale factor is involved.

REF: Bounds are stored relative to an offset container with an optional 4x4 transform. Module 18 covers `AXRelativeBounds` and the coordinate walk in detail.

## Extensions as assistive technology

Extensions are a first-class AT platform in Chrome.

- `chrome.automation` gives an extension read access to the accessibility tree of
  the whole desktop (on ChromeOS) or of tabs, plus events and actions.
- `chrome.tts` and `chrome.ttsEngine` for speech; `chrome.speechRecognitionPrivate`
  and `chrome.accessibilityPrivate` for component extensions.
- ChromeVox, Select-to-Speak, Switch Access, and Dictation are all extensions
  built on these APIs - which is why ChromeOS accessibility looks so different
  from desktop internally.

```js
chrome.automation.getDesktop(desktop => {
  const button = desktop.find({ role: 'button', attributes: { name: 'Next' } });
  button.doDefault();
});
```

WATCH: `chrome.automation` is the same tree this course describes, exposed to JavaScript. Bugs you see there are usually bugs in the tree, not in the API.

## Third-party AT on the desktop

What Chrome has to coexist with:

- **Windows**: JAWS and NVDA (MSAA + IAccessible2, with vendor-specific extras),
  Narrator (UIA only), Dragon, ZoomText, Magnifier.
- **macOS**: VoiceOver, Voice Control, Zoom, Switch Control - all NSAccessibility.
- **Linux**: Orca over ATK/AT-SPI.
- **Android**: TalkBack, Switch Access, Voice Access, Select to Speak, plus
  BrailleBack.

Chromium detects which is present and sets `AXMode::kScreenReader` only for known
screen readers - see `ui/accessibility/platform/assistive_tech.h`.

KEY: Chromium does not implement "an accessibility API". It implements five of them, plus the vendor quirks each AT depends on.

## Live Caption and media

- Live Caption runs speech recognition on-device (a downloaded model) and
  displays captions for any media element, including video calls in the browser.
- It is a good example of an accessibility feature that is not tree-based at all -
  it taps the audio pipeline.
- For authors: `<track kind="captions">` is still the right answer for your own
  media. Auto-captions are a fallback, not a substitute, and they are unreliable
  for names, jargon, and multiple speakers.

NOTE: Captions serve far more than deaf users - noisy rooms, second-language viewers, and anyone watching without sound.

## Autofill, passwords, and the a11y tree

An underappreciated consumer: Chrome's own features read the accessibility tree.

- The `kAXModeFormControls` bundle - native APIs plus web contents, with the
  `kFormsAndLabelsOnly` filter - exists precisely so that tools
  needing only form structure - autofill and password managers - can turn on a
  cheap subset instead of the full tree.
- `State::kAutofillAvailable` and
  `AXEventGenerator::Event::AUTOFILL_AVAILABILITY_CHANGED` are how the tree
  advertises that a field has suggestions.

WHY: Before mode bundles existed, any client at all forced the full expensive tree. Splitting the modes let Chrome ship features that use the tree without paying screen-reader-grade costs on every page.

## Reporting a Chrome accessibility bug well

A good bug is worth ten vague ones. Include:

1. **Which AT and version** - "NVDA 2024.1" not "a screen reader".
2. **Which API surface** - IA2 vs UIA matters enormously on Windows; there is a
   dedicated `//docs/accessibility/browser/bugs/uia_bug_reporting.md`.
3. A **minimal HTML repro** - ideally a data: URL or a gist.
4. The **tree dump** from `chrome://accessibility` (Internal on).
5. What you expected the AT to say, and what it said.
6. Whether it reproduces in another browser - that tells triage whether it is a
   Chromium bug or a spec/AT question.

TRY: File one. The Chromium accessibility team is small and responsive, and a bug with a repro and a tree dump gets triaged fast.

## What Chrome deliberately does not do

Boundaries worth knowing before you file:

- Chrome does not fix bad pages. Heuristics that guess semantics break more than
  they fix - though `IsAXTreeFixingEnabled` and main-node annotation show the
  team does experiment carefully in this space.
- Chrome does not implement AT behavior. If NVDA announces something oddly from a
  correct tree, that is an NVDA bug, and the tree dump is your evidence.
- Chrome cannot make a `<canvas>` accessible on its own.
- Chrome will not expose an API surface no AT uses; every mapping has a client.

KEY: The browser's job is to expose an honest tree. Interpretation belongs to the AT, and semantics belong to the author.
