---
module: ChromeOS accessibility
part: Part IV - The Chromium pipeline
---

## A different architecture, same data

On ChromeOS, Chromium *is* the operating system, so there is no external platform
API to implement and no third-party screen reader process to serve.

Three layers, per the ChromeOS architecture doc:

1. **Renderers** - anything that draws: Blink, ARC++ (Android apps), the Views/Aura
   UI in the Ash process. Each produces an accessibility tree.
2. **Frameworks** - extension APIs (`chrome.automation`, `chrome.tts`,
   `chrome.accessibilityPrivate`), plus native libraries like BRLTTY and the
   text-to-speech engines.
3. **Features** - the assistive technologies themselves, written mostly in
   JavaScript as component extensions.

KEY: On ChromeOS the accessibility cache effectively lives in the AT's own process. Same tree, same serializer, different delivery.

## chrome.automation as the platform API

Where other platforms have IAccessible2 or NSAccessibility, ChromeOS has a
JavaScript API.

```js
chrome.automation.getDesktop(desktop => {
  desktop.addEventListener('focus', onFocus, false);
  const node = desktop.find({ role: 'button', attributes: { name: 'Send' } });
  node.doDefault();
});
```

- Nodes mirror `AXNodeData`; events mirror `AXEventGenerator`; actions mirror
  `ax::mojom::Action`.
- The API is defined by `extensions/common/api/automation.webidl`, which must be
  kept in sync with `ui/accessibility/ax_enums.mojom`.
- `AutomationInternalCustomBindings` is the renderer-side C++ that backs it.

WATCH: Adding an enum value to `ax_enums.mojom` without updating `automation.webidl` breaks the ChromeOS ATs silently. Presubmit catches most cases; review catches the rest.

## Everything embeds into one desktop tree

The `AXTreeID` embedding mechanism is used far more aggressively here.

```text
desktop (Views/Aura)
  browser window -> web contents tree -> iframe trees -> PDF tree
  ARC++ container -> Android app tree
  system UI, shelf, notifications (Views)
```

One AT walk covers Chrome's UI, web pages, PDFs, and Android apps.

KEY: The generalized child-tree mechanism is what makes a single screen reader work across radically different renderers on ChromeOS.

## ChromeVox

The built-in screen reader. `Ctrl+Alt+Z` toggles it.

- Lives in `chrome/browser/resources/chromeos/accessibility/chromevox`, built and
  shipped as part of ChromeOS (the old webstore "ChromeVox Classic" is a
  different, loosely related thing).
- Structure by execution context:
  - `background/` - the bulk of the logic: `braille/`, `editing/`, `event/`,
    `output/`, `panel/`, `logging/`.
  - `injected/` - a content script, now only for a Google Docs workaround.
  - `learn_mode/`, `log_page/` - learn mode and the log viewer.
- Tests are in `browser_tests` with `--gtest_filter=ChromeVox*`, and require
  `target_os = "chromeos"` in GN args.

REF: `background/output/` has its own README describing how spoken and braille output is composed from the tree. It is the clearest example anywhere of turning a tree into speech.

## Developing ChromeVox on Linux

You do not need a Chromebook.

- `//docs/accessibility/os/chromevox_on_desktop_linux.md` explains running
  ChromeVox in a ChromeOS-on-Linux build.
- The whole extension is JavaScript, so the iteration loop is fast once the build
  exists.
- The log page (`chromevox/log_page/`) shows the events, speech, and braille it
  produced - the equivalent of NVDA's speech viewer.

TRY: If you have a ChromeOS build, turn on ChromeVox logging and interact with a page. Reading its log next to a tree dump connects "the tree says X" to "the user hears Y" better than anything else in this course.

## Select-to-Speak

For the many users who want *some* text spoken but not a full screen reader -
low vision, dyslexia, neurodivergence, or simple preference.

- Enable it in Accessibility settings; then hold Search and drag over a region,
  use the tray icon, or select text and press `Search+S`.
- It reads the selection aloud with word-level highlighting - which is why it
  needs inline text boxes and character offsets.
- Implemented as a component extension plus supporting C++ and shared
  accessibility libraries.
- It deliberately skips nodes that are offscreen, invisible, or zero-sized -
  the distinction module 3 introduced.

KEY: Select-to-Speak is the clearest example of why "visible" needs three different definitions in the tree.

## Switch Access

Control the entire device with one or two switches.

- Nodes are organized into **nested groups** by proximity and semantics, because
  there are far too many actionable nodes to scan linearly.
- **Manual scanning** advances on a switch press; **auto-scan** advances on a
  timer at a configurable speed.
- The focused node gets a focus ring of two concentric rounded rectangles; a
  dashed ring previews what would be focused if you selected the current group.
- Text entry uses an on-screen keyboard with its own scanning, plus prediction.

WHY: Grouping is not a nicety. With 200 actionable nodes on screen and a 1-second scan interval, flat scanning would take minutes to reach anything.

## Dictation, FaceGaze, and voice input

- **Dictation** - speech to text into any editable field, using
  `chrome.speechRecognitionPrivate`, with on-device or network recognition, and
  editing commands ("delete the last word", "select all").
- **FaceGaze** - head and face gestures drive the cursor and trigger actions; a
  camera replaces the pointing device.
- Both are extensions issuing accessibility **actions** into the same tree.

REF: `//docs/accessibility/os/dictation.md` and `facegaze.md` cover the architecture and the gesture-to-action mapping.

## Magnification, autoclick, and the rest

The long tail, all built on the same primitives:

- **Fullscreen and docked magnifier** - follow focus and caret bounds.
- **Automatic clicks** - dwell to click; needs accurate hit testing and bounds.
- **Sticky keys, mouse keys, on-screen keyboard, cursor size and color,
  highlight focus/caret/mouse** - input and visual accommodations.
- **Reduced animations, flash screen notifications, inverted cursor** - newer
  features visible as flags in `accessibility_features.h`.
- **Disable internal touchpad**, **shake to locate the cursor** - small features
  that matter enormously to specific users.

NOTE: Grepping `accessibility_features.h` for `IsAccessibility...Enabled` is a fast way to see what the ChromeOS accessibility team is currently shipping.

## Text-to-speech on ChromeOS

Speech is a system service, not a feature of one AT.

- `chrome.tts` for consumers; `chrome.ttsEngine` for engines.
- Engines shipped as component extensions: **Google TTS** (`googletts`) and
  **eSpeak-NG** for the long tail of languages.
- PATTS is the on-device engine documented in
  `//docs/accessibility/os/patts.md`.
- Voice, rate, pitch, and language selection are user preferences that every AT
  honors.

WATCH: Speech quality and latency are accessibility features in themselves. A screen reader with a 400ms speech latency is measurably slower to use, regardless of how correct the tree is.

## Braille on ChromeOS

- **BRLTTY** is packaged as a ChromeOS component and handles the USB and Bluetooth
  display protocols.
- `chrome.brailleDisplayPrivate` connects it to ChromeVox.
- ChromeVox's `background/braille/` composes braille output - which is not just
  translated speech: it abbreviates roles and states into cells and supports
  contracted braille tables per language.
- Braille input (chord typing on the display) routes back as text input.

REF: `//docs/accessibility/os/brltty.md`, including how to debug a display that is not detected.

## What transfers to other platforms

If you work on desktop Chromium, the ChromeOS layer still teaches you three
things:

1. **The cache is portable.** Nothing about the architecture requires the tree to
   live in the browser process; ChromeOS proves it by putting it elsewhere.
2. **An AT is a normal client.** ChromeVox consumes exactly the tree, events, and
   actions this course describes - so a tree bug looks identical there.
3. **Actions matter as much as events.** ChromeOS ATs are action-heavy, and they
   surface missing or broken actions faster than desktop screen readers do.

KEY: If a feature works with ChromeVox but not with NVDA, the tree is probably right and the platform mapping is probably wrong. That is a genuinely useful bisection.
