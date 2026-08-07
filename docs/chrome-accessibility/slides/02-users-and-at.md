---
module: Users and assistive technology
part: Part I - Orientation
---

## Disability as a mismatch

The useful model for an engineer: a disability is not a property of a person, it
is a mismatch between a person and an environment. The environment is the part
you can change.

- **Permanent** - a blind user, a user with one arm.
- **Temporary** - an eye infection, a broken wrist.
- **Situational** - bright sunlight, holding a baby, a noisy train.

The same fix serves all three columns. Captions serve deaf users, and also the
person watching in a quiet office. A keyboard path through your UI serves a
switch user, and also a power user, and also every automated test you will ever
write.

KEY: The audience for accessibility work is always much larger than the population that identifies as disabled.

## What a screen reader actually does

It is easy to picture a screen reader as "reads the screen aloud". What it
really does is closer to a database query engine over your accessibility tree.

1. Builds an internal model of the document from the accessibility API - on
   Windows, JAWS and NVDA historically walked the entire page top to bottom on
   load to build a *virtual buffer*.
2. Lets the user navigate that model by structure: next heading, next link,
   next form field, next table cell, list of landmarks.
3. Announces changes as events arrive: focus moved, value changed, live region
   updated.
4. Sends actions back: click this, focus that, set the value.

WHY: That "walk the whole page on load" behavior is precisely why Chromium abandoned the proxy-object design - thousands of blocking IPCs made medium pages take ten seconds to load.

## Browse mode and focus mode

The single most misunderstood screen reader concept among web developers.

- **Browse / virtual mode** - the screen reader intercepts arrow keys and moves a
  *virtual cursor* through its own buffer. The page is a document. Keystrokes
  mostly never reach your JavaScript.
- **Focus / forms mode** - keys pass through to the page, because the user is in
  a text field or an application widget. The DOM focus is what matters.

Screen readers switch automatically, driven by role: entering a text field or a
node with `role="application"` typically flips to focus mode.

WATCH: A widget that works when you test with the keyboard can still fail with a screen reader because the user never left browse mode. Test in both modes, deliberately.

## Magnifiers and low vision

Magnification is not just zoom; it is a moving viewport that has to follow the
user's attention.

- The magnifier follows **focus events** and **caret bounds**, so it needs
  accurate, up-to-date bounding boxes for nodes and for text ranges.
- It issues **scroll actions** to bring things into view.
- Low-vision users also lean on OS-level contrast and color inversion, on browser
  zoom, and on `prefers-contrast` / forced colors.

KEY: Magnifiers are the reason text bounding boxes must be queryable for arbitrary character ranges, not just whole nodes. That requirement shapes Chromium's cache.

## Voice control

Voice control users say the name of a control - "click Next" - and the software
finds it and activates it.

- Voice control is **action-heavy and event-light**: it barely cares about
  notifications, and cares enormously about the accessible *name* matching the
  visible label, and about `kDoDefault`, `kSetValue`, `kFocus` working.
- If your button's accessible name is "Submit form 2 of 3" but it visibly reads
  "Next", the user has no way to say the right thing.

REF: WCAG 2.5.3 "Label in Name" exists for exactly this: the accessible name must contain the visible label text.

## Switch access and scanning

A switch user may have exactly one button. The software scans the interface -
highlighting groups, then items - and the user hits the switch when the target
is highlighted.

- Everything must be reachable by *sequential* traversal; nothing can require a
  pointer gesture or a hover.
- Scanning depends on knowing what is actually on screen, which is why the
  `offscreen`, `invisible`, and zero-size distinctions matter so much: a scan
  that stops on an invisible node wastes the user's time.
- ChromeOS ships Switch Access as a component extension built on
  `chrome.automation`.

## Braille

Braille output is a second, silent rendering of the same tree.

- A refreshable braille display shows 14-80 cells; the user pans through the
  document. Chromium on ChromeOS drives displays via **BRLTTY**.
- Braille needs *structure*, not prose: roles and states get abbreviated into
  cells, so a mislabeled role is worse in braille than in speech.
- Deafblind users may be reading braille only - no audio fallback at all when
  something is announced but not exposed.

NOTE: `//docs/accessibility/os/brltty.md` covers how ChromeOS packages BRLTTY and how to
    debug a display that is not being detected.

## Reading, literacy, and cognitive tools

A large group of users are not blind and do not use a screen reader, but rely on
the same API.

- **Select-to-Speak** (ChromeOS) speaks a selected region and highlights each
  word as it goes - it needs word-level text geometry.
- **Reading Mode / Read Anything** distills a page into clean text using the
  accessibility tree as its source.
- Highlighting-as-it-reads needs the same inline text box data that magnifiers
  need.

KEY: Text geometry - which word is where - is load-bearing for a whole class of tools that have nothing to do with blindness.

## The non-AT clients

The accessibility API is the only universal, cross-app description of a UI, so
plenty of software uses it that has nothing to do with disability.

- Password managers finding the username and password fields.
- UI automation and QA frameworks driving apps.
- Enterprise tooling, screen scrapers, and voice assistants.

Chromium tracks this: `AXMode::kNativeAPIs` merely means *some* client is
present, while `AXMode::kScreenReader` is only set when a known screen reader
(ChromeVox, TalkBack, JAWS, NVDA, Narrator, ...) is detected, so the expensive
work can be skipped for a password manager.

WATCH: "Accessibility is enabled" and "a screen reader is running" are different questions, and Chromium deliberately keeps them apart.

## Which AT runs where

| Platform | Common ATs | API they consume |
| --- | --- | --- |
| Windows | JAWS, NVDA, Narrator, Dragon, ZoomText | IAccessible (MSAA), IAccessible2, UI Automation |
| macOS | VoiceOver, Voice Control, Zoom | NSAccessibility |
| Linux | Orca | ATK / AT-SPI |
| Android | TalkBack, Voice Access, Switch Access | AccessibilityNodeInfo / AccessibilityNodeProvider |
| ChromeOS | ChromeVox, Select-to-Speak, Switch Access, Dictation | `chrome.automation` (Chromium's own tree) |
| iOS | VoiceOver | UIAccessibility |

NOTE: Narrator is UIA-only - it does not use MSAA or IA2 at all. That is why a UIA-only regression can be invisible to NVDA testing and still break Narrator completely.

## The failure modes you will actually see

In roughly the order they show up in bug reports:

1. **Unlabeled controls** - icon buttons with no accessible name.
2. **Wrong or missing roles** - a `<div>` with a click handler.
3. **Keyboard traps and unreachable controls** - focus goes in and never comes out.
4. **Focus lost on DOM change** - a dialog opens and focus stays behind it.
5. **Silent updates** - content changes with no live region, so nothing is announced.
6. **Name/label mismatch** - visible text differs from the accessible name.
7. **Contrast and text sizing** - unreadable before any API is involved.
8. **Custom widgets that lie** - ARIA claims a listbox that behaves like nothing.

KEY: Most real-world breakage is boring. The exotic pipeline bugs are the fun ones, but they are a small fraction of user pain.

## The standards, and which one answers what

- **WCAG** (2.0 / 2.1 / 2.2, AA is the usual legal bar) - user-facing success
  criteria: contrast, keyboard, focus visibility, labels.
- **WAI-ARIA** - the vocabulary of roles, states, and properties.
- **ACCNAME** - the algorithm for computing an accessible name and description.
  Blink implements this in `AXObject`.
- **HTML-AAM** - what each HTML element maps to in the accessibility tree.
- **Core-AAM** - how a role maps to each platform API (MSAA/IA2, UIA,
  NSAccessibility, ATK, AccessibilityNodeInfo).
- **ARIA in HTML** - which ARIA is allowed on which element.

REF: When a Chromium reviewer asks "what does the spec say", they almost always mean HTML-AAM or Core-AAM: these are the mapping tables Chromium is judged against.
