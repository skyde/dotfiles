---
module: Testing in Chromium
part: Part V - Practice
---

## The five test suites

Know which one to reach for, and you will save hours per change.

| Suite | Layer | Speed |
| --- | --- | --- |
| `accessibility_unittests` | `ui/accessibility` core: trees, serializer, events, positions | seconds |
| Blink web tests | Blink's tree computation, no platform, no serialization | fast |
| `DumpAccessibility*` in `content_browsertests` | full pipeline: serialize, unserialize, platform mapping | slow |
| Other `content_browsertests` | anything needing a real browser | slow |
| `browser_tests` | ChromeVox, Select-to-Speak, PDF a11y | slowest |

KEY: Push tests down the stack. A serializer bug reproduced in `accessibility_unittests` takes seconds to iterate; the same bug chased through a browser test takes minutes per run.

## accessibility_unittests

The core suite, next to the code it tests - every `*_unittest.cc` in
`ui/accessibility`.

```sh
autoninja -C out/release accessibility_unittests
out/release/accessibility_unittests
out/release/accessibility_unittests --gtest_filter='AXTreeTest.*'
```

What lives here:

- `AXTree` unserialize semantics, including malformed updates.
- `AXTreeSerializer` - serialize from one `AXTree` into another and assert the
  result, which tests the whole delta algorithm with no browser.
- `AXEventGenerator` - apply an update, assert the exact event set.
- `AXPosition` / `AXRange` text navigation.
- `AXNodeData`, `AXMode`, enum utilities.

TRY: Read one `ax_tree_serializer_unittest.cc` case. The pattern - build tree A, build tree B, serialize the delta, assert - is a beautiful way to test a stateful algorithm.

## Blink web tests

```sh
autoninja -C out/release blink_tests
third_party/blink/tools/run_web_tests.py --build-directory=out --target=release accessibility/

# one test, no wrapper script
out/release/content_shell --run-web-tests \
  third_party/blink/web_tests/accessibility/name-calc-inputs.html
```

- Test files: `third_party/blink/web_tests/accessibility/`.
- Support code: `AccessibilityController` and `WebAXObjectProxy` in
  `content/web_test/renderer/`.
- Use these when there is interesting *web platform* logic, or when you need to
  query synchronously from the renderer thread.
- Do **not** add them for trivial pass-through of an ARIA attribute; test that a
  layer up where it actually reaches an API.

NOTE: Many of these tests are inherited from WebKit and show their age. Copy a recent one as your template, not an old one.

## DumpAccessibilityTree: the workhorse

An HTML file, a few directives, and one expectation file per platform. Almost no
test code.

```html
<!--
@BLINK-ALLOW:name*
@MAC-ALLOW:AXTitle*
@WIN-ALLOW:name*
-->
<button aria-label="Save">x</button>
```

```text
rootWebArea
++button name='Save'
```

- Indentation in expectations uses **two plus signs per level**.
- Blank lines and `#` lines are ignored; a first line starting with `#<skip`
  passes the test unconditionally (with a bug link, ideally).
- If no expectation file exists for a platform, that pass simply passes.

REF: `content/test/data/accessibility/readme.md` is the complete reference, and it is excellent.

## The four dump test types

- **Tree tests** - load, dump the whole tree, compare
  (`DumpAccessibilityTreeTest`).
- **Node tests** - dump a single node, the one whose `id` or `class` is `test`
  (`DumpAccessibilityNodeTest`); expectations get a `-node` qualifier:
  `foo-node-expected-mac.txt`.
- **Script tests** - run a small script against platform APIs and dump the
  results (`DumpAccessibilityScriptTest`; macOS only today).
- **Event tests** - call the page's `go()` function and dump the events that
  follow (`DumpAccessibilityEventsTest`).

KEY: One HTML file can serve as both a tree test and a node test. Node tests keep expectations tiny, which keeps reviews honest.

## The test passes

Each test runs several times, once per output format:

```text
DumpAccessibilityTreeTest.AccessibilityAriaAtomic/blink
                                                /mac
                                                /ia2      (Windows MSAA/IA2)
                                                /uia      (Windows UI Automation)
                                                /linux    (ATK)
                                                /android
```

Expectation file suffixes: `-expected-blink.txt`, `-expected-mac.txt`,
`-expected-win.txt` (IA2), `-expected-uia-win.txt`, `-expected-auralinux.txt`,
`-expected-android.txt`, plus version-specific variants like
`-expected-uia-win7.txt`, `-expected-auralinux-xenial.txt`, and
`-expected-blink-cros.txt`.

WATCH: Windows runs three passes - blink, ia2, uia. A change that looks fine in two can regress the third, and Narrator only uses the third.

## Filters

By default only a few attributes are dumped, so unrelated changes do not churn
every file. Filters opt in to what your test is about.

```text
@WIN-ALLOW:name              include name when non-empty
@WIN-ALLOW-EMPTY:name        include name even when empty
@WIN-DENY:name='X*           exclude names starting with X
@MAC-ALLOW:AXValue*          wildcards only, not regexes
@BLINK-ALLOW:*               dump everything (debugging only)
```

Prefixes: `@WIN-`, `@UIA-WIN-`, `@MAC-`, `@BLINK-`, `@ANDROID-`, `@AURALINUX-`.

KEY: A tight filter is what makes a dump test readable in review. `@ALLOW:*` in a landed test is a smell.

## Timing directives

Tests that need the page to do something first:

```text
@WAIT-FOR:done                   block until "done" appears in the dump
@EXECUTE-AND-WAIT-FOR: foo()     run foo(), wait for its returned string
@NO-LOAD-EXPECTED:broken.jpg     do not wait for that resource to load
@DEFAULT-ACTION-ON:button        invoke the default action on a node
@EVENTS-TREE-DUMP                in event tests, dump the tree before/after go()
```

Plus `@NO_DUMP` and `@NO_CHILDREN_DUMP` as class names to prune noisy subtrees,
and `cross-site/HOSTNAME/` URLs to force an iframe into another process.

TRY: Write a test for a dynamic ARIA change using `@EXECUTE-AND-WAIT-FOR`. It is far more robust than a `setTimeout` plus a `@WAIT-FOR` string.

## Running and rebaselining

```sh
autoninja -C out/release content_browsertests
out/release/content_browsertests --gtest_filter="All/DumpAccessibilityTree*"

# regenerate expectations for the current platform
out/Debug/content_browsertests \
  --generate-accessibility-test-expectations \
  --gtest_filter="All/DumpAccessibilityTreeTest.AccessibilityAriaAtomic/*"

# regenerate for every OS
tools/accessibility/rebase_dump_accessibility_tree_tests.py
```

WATCH: Rebaselining is how you bless a regression by accident. Read every line of the diff - a rebaseline that changes files you did not expect is telling you something.

## Event tests in detail

```html
<!--
@WIN-ALLOW:FOCUS*
-->
<div id="live" aria-live="polite"></div>
<script>
  function go() {
    document.getElementById('live').textContent = 'Saved';
  }
</script>
```

- The harness loads the page, waits for `@WAIT-FOR` if present, calls `go()`, and
  dumps events until a sentinel event arrives.
- There is no way to test events that fire after an arbitrary delay - only those
  caused directly by `go()`.
- On Windows, expect duplicate Focus, MenuOpened, and MenuClosed events in the UIA
  pass: Windows translates some IA2 events to UIA and this cannot be turned off.

REF: New event tests must also be registered in `dump_accessibility_events_browsertest.cc`, and for Android in `WebContentsAccessibilityEventsTest.java`.

## Android is different

Android event tests are driven from Java so they exercise the real
`AccessibilityEvent`s delivered to services.

```java
@Test
@SmallTest
public void test_exampleTest() {
    performTest("example-test.html", "example-test-expected-android.txt");
}

// when the test legitimately produces no events:
performTest("example-test.html", EMPTY_EXPECTATIONS_FILE);
```

- Generated expectations land on the device, under
  `/storage/emulated/0/chromium_tests_root/content/test/data/accessibility/...`.
- A presubmit emits a non-blocking warning when you add, rename, or delete an
  events test without a matching Android change.

NOTE: The fastest way to get the right Android expectation text is to run with `EMPTY_EXPECTATIONS_FILE` and copy the exact text out of the failure message.

## ChromeVox and feature tests

```sh
# ChromeVox (requires target_os = "chromeos")
autoninja -C out/release browser_tests
out/release/browser_tests --test-launcher-jobs=20 --gtest_filter=ChromeVox*

# Select-to-Speak
out/Default/unit_tests   --gtest_filter=*SelectToSpeak*
out/Default/browser_tests --gtest_filter=*SelectToSpeak*

# PDF accessibility
out/Default/browser_tests --gtest_filter=PDFExtensionAccessibilityTreeDumpTest*
```

Useful across all suites: `--test-launcher-jobs=10` to run in parallel and shake
out flakes, `--gtest_filter` to narrow, `--gtest_repeat` to hunt flakiness.

KEY: ChromeVox tests are the only place the full ChromeOS chain - tree, events, output composition, speech - is asserted end to end.

## Manual testing that actually matters

When you change what a platform API returns, automated tests cannot tell you
whether the AT still works. The Chromium docs call out specific things to check.

For **Narrator** (UIA only - it does not use MSAA or IA2):

- Scan Mode on and off.
- Navigation by every text unit: character, word, line, sentence, paragraph,
  item, heading, link, form field, landmark, table.
- Search (`Narrator+Ctrl+F`), list of links (`F7`), headings (`F6`), landmarks
  (`F5`).
- Caret navigation in a text field: the character after the caret is read;
  "blank" at the end; spelling and grammar errors announced - and test both the
  `aria-invalid` and the CSS-highlight implementations, because Chromium's UIA
  code paths for them differ.

REF: `//docs/accessibility/browser/tests.md` maintains this list and invites additions. If you find a regression an AT check would have caught, add it there.

## Test strategy for a change

A practical decision procedure:

1. **Pure `ui/accessibility` logic?** Unit test. Done in seconds.
2. **Blink computes something new?** Web test for the computation, plus a dump
   tree test for the mapping.
3. **New attribute exposed to platforms?** Dump tree tests with expectations on
   every platform you affect, plus filters that isolate the attribute.
4. **New event?** Event test, and check the Android registration.
5. **Behavior change in an existing mapping?** Rebaseline carefully, and manually
   verify with at least one AT per affected platform.
6. **Performance-sensitive?** Add or update a Telemetry story (module 23).

KEY: The expectation diff is the design review. If a reviewer cannot tell from your expectation changes what users will now hear, your test is too broad.
