---
module: Orientation
part: Part I - Orientation
---

## Chrome Accessibility, end to end

A 300-slide course on how accessibility actually works in Chrome and Chromium -
from the ARIA attribute an author types, through Blink's accessibility tree, the
serializer, the browser-process cache, and out to the screen reader talking to
the user.

- **Part I** - orientation, users, and the tree as a concept
- **Part II** - the web platform: HTML semantics, ARIA, names, focus, visuals
- **Part III** - the tools: Chrome's own features, DevTools, audits, automation
- **Part IV** - the Chromium pipeline: Blink to platform APIs
- **Part V** - testing, performance, debugging, and contributing

KEY: Accessibility in Chromium is one long data pipeline. Every hard bug you will ever file lives at a specific stage of it, and this course walks the whole thing.

NOTE: Everything here is grounded in `//docs/accessibility` and the real source in
    `ui/accessibility`, `content/browser/accessibility`, and
    `third_party/blink/renderer/modules/accessibility`. Where a slide names a class
    or a flag, it exists at head; the surrounding architecture changes slowly, but
    always confirm a specific line against the tree you are building.

## Who this course is for

Two audiences, one pipeline. You are probably both at different times of the week.

- **The web developer** - you write HTML, CSS, and JavaScript, and you want the
  browser to describe your UI correctly to assistive technology.
- **The Chromium engineer** - you write C++ in `//ui/accessibility` or Blink,
  and you want to know why the tree looks the way it does and what breaks if you
  change it.

The material is ordered so the web platform comes first. That is deliberate:
Chromium's internal design is a direct response to the semantics of the web
platform, and the internals make far more sense once the semantics are familiar.

WHY: Nearly every Chromium accessibility bug report starts as a web-facing symptom - "NVDA reads the wrong thing on this page". Tracking it down means walking backwards through the pipeline, so you need both ends.

## What you will be able to do at the end

1. Read an accessibility tree dump and say what it means for a screen reader user.
2. Predict the computed name and role of an element from its HTML and ARIA.
3. Use DevTools, `chrome://accessibility`, and the `ax_dump_tree` tooling to see
   the real tree at every layer.
4. Explain the Blink -> serializer -> browser cache -> platform node pipeline
   without looking anything up.
5. Write a `DumpAccessibilityTree` test, rebaseline it, and know which of the
   `blink` / `mac` / `ia2` / `uia` / `android` / `auralinux` passes matters.
6. Know why accessibility costs performance, what `AXMode` does about it, and how
   to measure it.

TRY: Before you go on, open a real page in Chrome, press F12, and find the Accessibility pane in the Elements sidebar. That pane is a view onto everything this course explains.

## The two meanings of "accessibility"

The word is doing double duty, and mixing them up is the single most common
source of confusion in a code review.

- **Design accessibility** - font sizes, color contrast, not conveying meaning by
  color alone, keyboard alternatives to pointer gestures. This is mostly a design
  and CSS concern.
- **Platform accessibility** - exposing the UI through the operating system's
  accessibility API so that assistive technology can build an alternative
  interface. This is what the word means when it appears in a Chromium directory
  name.

KEY: When you see `accessibility` in a Chromium path, it means the second one: the API surface that ATs consume.

REF: `//docs/accessibility/overview.md` opens with exactly this distinction, and it is worth re-reading once a year.

## Assistive technology, concretely

"Assistive technology" (AT) is any software or hardware that consumes the
accessibility API to build a different interface for the user.

- **Screen readers** - describe the screen with synthesized speech or braille
  (JAWS, NVDA, Narrator, VoiceOver, TalkBack, ChromeVox, Orca).
- **Magnifiers** - enlarge part of the screen and follow the caret and focus.
- **Voice control** - drive the UI by speaking control names (Voice Access,
  Dragon, Voice Control).
- **Switch access** - operate everything with one or two physical switches.
- **Literacy tools** - highlight and speak text for users who find print hard.

And, importantly, non-AT clients: password managers, UI automation frameworks,
and test harnesses all read the same tree, because it is the most convenient
universal description of an app's UI.

WATCH: A change that "only affects automation clients" still affects real users - the same API surface serves both, and automation clients often ship to millions of desktops.

## The three primitives

Every accessibility API on every platform is built from the same three ideas.
Learn them once; the rest is naming.

1. **The tree.** The entire interface, modelled as a tree of objects with roles,
   names, states, and bounds.
2. **Events.** Messages from the app to the AT: this changed, focus moved, that
   value is different now.
3. **Actions.** Messages from the AT to the app: click this, focus that, set this
   value, scroll there.

KEY: Tree, events, actions. Windows, macOS, Linux, Android, and ChromeOS differ only in spelling.

NOTE: A fourth concept, parameterized attributes (mostly for text - "give me the
    bounding box of characters 12 through 20"), shows up on every desktop platform
    and is the reason Chromium caches so much text geometry. Part IV covers it.

## The whole pipeline on one slide

Memorize this shape. Every later module is a zoom into one arrow.

```svg Blink builds an accessibility tree in the sandboxed renderer; the serializer sends incremental updates over Mojo; the browser process caches them and answers platform API calls from that cache; actions travel back the other way.
<svg viewBox="-12 26 949 164" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <marker id="p1-a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto">
      <path d="M0,0 L10,5 L0,10 z" class="d-fill-accent"/>
    </marker>
    <marker id="p1-b" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto">
      <path d="M0,0 L10,5 L0,10 z" class="d-fill-muted"/>
    </marker>
  </defs>
  <rect x="-8" y="50" width="465" height="100" rx="8" class="d-zone"/>
  <rect x="463" y="50" width="308" height="100" rx="8" class="d-zone"/>
  <text x="-8" y="43" class="d-t-sm">renderer process (sandboxed)</text>
  <text x="467" y="43" class="d-t-sm">browser process</text>
  <text x="785" y="43" class="d-t-sm">assistive technology</text>
  <rect x="0" y="70" width="135" height="60" rx="7" class="d-box"/>
  <text x="67" y="96" class="d-t" text-anchor="middle">DOM + CSS</text>
  <text x="67" y="114" class="d-t" text-anchor="middle">+ ARIA</text>
  <rect x="157" y="70" width="135" height="60" rx="7" class="d-box-accent"/>
  <text x="224" y="96" class="d-t-mono" text-anchor="middle">AXObject</text>
  <text x="224" y="114" class="d-t-mono" text-anchor="middle">AXObjectCache</text>
  <rect x="314" y="70" width="135" height="60" rx="7" class="d-box"/>
  <text x="381" y="96" class="d-t-mono" text-anchor="middle">AXTree</text>
  <text x="381" y="114" class="d-t-mono" text-anchor="middle">Serializer</text>
  <rect x="471" y="70" width="135" height="60" rx="7" class="d-box-key"/>
  <text x="538" y="96" class="d-t-mono" text-anchor="middle">ui::AXTree</text>
  <text x="538" y="114" class="d-t-mono" text-anchor="middle">cache</text>
  <rect x="628" y="70" width="135" height="60" rx="7" class="d-box"/>
  <text x="695" y="96" class="d-t-mono" text-anchor="middle">AXPlatform</text>
  <text x="695" y="114" class="d-t-mono" text-anchor="middle">Node</text>
  <rect x="785" y="70" width="135" height="60" rx="7" class="d-box-accent"/>
  <text x="852" y="96" class="d-t" text-anchor="middle">screen reader,</text>
  <text x="852" y="114" class="d-t" text-anchor="middle">magnifier, ...</text>
  <path d="M137,100 L153,100" class="d-line" marker-end="url(#p1-a)"/>
  <path d="M294,100 L310,100" class="d-line" marker-end="url(#p1-a)"/>
  <path d="M451,100 L467,100" class="d-line" marker-end="url(#p1-a)"/>
  <path d="M608,100 L624,100" class="d-line" marker-end="url(#p1-a)"/>
  <path d="M765,100 L781,100" class="d-line" marker-end="url(#p1-a)"/>
  <text x="459" y="63" class="d-t-sm" text-anchor="middle">Mojo</text>
  <path d="M852,134 L852,168 L232,168 L232,134" class="d-line-back" marker-end="url(#p1-b)"/>
  <text x="542" y="182" class="d-t-sm" text-anchor="middle">actions: PerformAction(AXActionData)</text>
</svg>
```

And back the other way, actions travel:

```text
screen reader -> AXPlatformNode -> AXActionData -> ax.mojom.RenderAccessibility.PerformAction
   -> RenderAccessibilityImpl -> Blink -> the DOM element
```

KEY: The renderer is sandboxed and cannot call an OS API; the browser process must answer OS calls synchronously. Everything odd about Chromium accessibility follows from those two facts.

## A worked example, all the way down

Eight lines of HTML, and the tree Chromium builds from it.

```html
<head><title>How old are you?</title></head>
<label for="age">Age</label>
<input id="age" type="number" name="age" value="42">
<div><button>Back</button><button>Next</button></div>
```

```text
id=1 role=WebArea name="How old are you?"
    id=2 role=Label name="Age"
    id=3 role=TextField labelledByIds=[2] value="42"
    id=4 role=Group
        id=5 role=Button name="Back"
        id=6 role=Button name="Next"
```

- The shape follows the DOM, simplified: `<head>` is gone, `<body>` is not a node.
- The text field has no name of its own; it points at the label with
  `labelledByIds`.
- The `<div>` became a `Group` - a real node, because it groups the buttons.

TRY: Paste this into a file, open it, and compare against the Accessibility pane in DevTools and against `chrome://accessibility`. Everything in this course is verifiable on your own machine.

## Vocabulary: the words this course uses

| Term | Meaning here |
| --- | --- |
| AT | Assistive technology - the client consuming the API |
| a11y | Numeronym for "accessibility" (a + 11 letters + y) |
| AX | Chromium's prefix for accessibility types (`AXNode`, `AXTree`) |
| Accessibility tree | The tree of nodes exposed to ATs, distinct from DOM and layout |
| Node ID | An ID unique within one frame's tree |
| Unique ID | An ID globally unique in the browser process |
| AXTreeID | An `UnguessableToken` naming a whole frame's tree |
| Serialization | Turning live objects into `AXTreeUpdate` data |
| AXMode | Bitmask deciding how much accessibility work is done at all |

NOTE: "a11y" is pronounced "ally" by most people in the field, which is a happy accident.

## How to use this deck

- **Arrow keys** or **space** move; type a number to jump to a slide; **o** opens
  the contents; **/** searches every word on every slide.
- **n** toggles speaker notes - they carry the caveats and the second-order
  details that would clutter the slide.
- **t** cycles theme, **?** lists the keys. Printing gives one slide per page.
- Callouts mean specific things:
  - **Key idea** - the sentence to remember.
  - **Try it** - do this at a real keyboard; the course assumes you will.
  - **Where to look** - a file, flag, or URL worth opening.
  - **Why it is like this** - the design rationale, usually historical.
  - **Watch out** - the mistake people actually make.

KEY: The deck is itself a keyboard-operable, screen-reader-labelled, contrast-checked document. Reading it with a screen reader on is a legitimate way to study it.
