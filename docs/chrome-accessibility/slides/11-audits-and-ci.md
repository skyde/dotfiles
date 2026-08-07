---
module: Audits and CI
part: Part III - Tools
---

## What automation can and cannot find

The number quoted in the industry is that automated tools catch roughly a third
of accessibility issues. That is about right, and the split is not random.

**Machine-checkable** - missing `alt`, missing labels, contrast ratios, invalid
ARIA attribute values, duplicate IDs, empty headings, missing `lang`, ARIA
attributes on wrong roles, focusable elements inside `aria-hidden`.

**Not machine-checkable** - whether a name is meaningful, whether focus order is
logical, whether a live region fires at the right time, whether the keyboard
contract of a widget is complete, whether alt text describes the right thing,
whether the reading order matches the visual one.

KEY: Automation is a spellchecker. It finds typos, not bad writing - but you would still never ship without one.

## axe-core

The engine behind Lighthouse's accessibility category, the axe DevTools
extension, and most CI integrations.

```js
import { AxeBuilder } from '@axe-core/playwright';

const results = await new AxeBuilder({ page })
  .withTags(['wcag2a', 'wcag2aa', 'wcag21aa'])
  .analyze();

expect(results.violations).toEqual([]);
```

- Rules carry tags (`wcag2aa`, `best-practice`, `experimental`) so you can pick a
  policy rather than accept the default.
- Each violation names the rule, the impact (minor/moderate/serious/critical),
  the nodes, and a fix summary.
- It is deliberately conservative: it reports only what it is confident about,
  plus "incomplete" results a human should check.

REF: The `incomplete` bucket is where most real problems hide. Teams that only assert on `violations` are throwing away half the value.

## Lighthouse in CI

```sh
npx lighthouse https://example.com \
  --only-categories=accessibility \
  --output=json --output-path=./a11y.json --chrome-flags="--headless=new"
```

- Deterministic enough for CI if you pin the Chrome version and control the page
  state.
- Use `lighthouse-ci` to store history and assert on regressions rather than on
  absolute scores.
- Score is a weighted average; a single critical failure and ten trivial ones can
  produce the same number, so assert on individual audits.

WATCH: A score threshold is a weak gate. Assert "these audits must pass" rather than "the number must be above 90".

## Testing the states, not just the page

The most common gap in automated accessibility testing: the tool audits the
initial render, and every bug lives in state 4 of your component.

```js
test('menu is accessible when open', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: 'File' }).click();
  await expect(page.getByRole('menu')).toBeVisible();
  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});
```

- Audit each *state*: open menus, expanded accordions, error states, loading
  states, empty states, modals.
- Component-level tests (Storybook + axe) get much better coverage per second
  than whole-page crawls.

KEY: Audit states, not pages. Most accessibility bugs are transitions, and a page-level crawl never sees them.

## Unit-testing semantics

The best accessibility tests do not mention accessibility at all - they simply
query the way a user would.

```js
// Testing Library: queries by role and name
const save = screen.getByRole('button', { name: 'Save' });
await user.tab();
expect(save).toHaveFocus();
await user.keyboard('{Enter}');
```

If `getByRole` cannot find your control, neither can a screen reader user, and
the test fails for the right reason with no extra assertion.

TRY: Convert one component test suite from `getByTestId` to `getByRole` + name. Every failure you have to fix is a real accessibility defect.

## Linting

Catch the mechanical class before the code even runs.

- `eslint-plugin-jsx-a11y` for React: missing `alt`, invalid ARIA, click handlers
  on non-interactive elements, missing keyboard handlers.
- `vue-a11y`, `angular-eslint` equivalents.
- Template linters for missing form labels.
- A grep-level rule that catches `outline: none`, `user-scalable=no`, positive
  `tabindex`, and `aria-hidden="true"` on interactive elements pays for itself in
  a week.

WATCH: Linters produce false positives on wrapper components. Configure the component mapping instead of disabling rules wholesale, or the whole plugin gets turned off by the first frustrated developer.

## Manual test scripts that scale

A short, repeatable manual protocol beats an occasional heroic audit.

1. **Keyboard sweep** - Tab through the flow, mouse unplugged. Note focus
   visibility, order, traps.
2. **Zoom to 400%** at 1280px wide - does it reflow?
3. **Forced colors** emulation - is everything still visible?
4. **Screen reader pass** on the primary flow only - not the whole app.
5. **Reflow the text spacing** with a user stylesheet.

Fifteen minutes per flow, run every release, will outperform an annual audit.

KEY: The goal is a routine cheap enough to actually run, not a perfect one nobody does twice.

## Chromium's own CI, briefly

For engineers working in the browser rather than on it:

- `DumpAccessibilityTree` browser tests run on every platform bot, so a mapping
  change shows up as a diff in dozens of expectation files. That is by design -
  the diff *is* the review artifact.
- `accessibility_unittests` covers `ui/accessibility` core logic.
- Blink web tests in `third_party/blink/web_tests/accessibility` cover
  platform-independent behavior.
- Web Platform Tests cover cross-browser interoperability, and the WAI-ARIA WPT
  suite is where mapping conformance gets settled between engines.

REF: Module 22 is the full tour, including how to rebaseline without accidentally blessing a regression.

## Regression budgets and dashboards

What good looks like at a team level:

- A **fixed set of critical flows** audited on every build, not a crawl of
  everything.
- An **error budget**: no new serious/critical violations; existing ones tracked
  with owners and dates.
- A dashboard split by *category* (names, contrast, ARIA validity, structure) -
  a single number hides which class is growing.
- Screen reader smoke tests on release candidates for the top three flows.

NOTE: Chromium tracks accessibility performance separately with Telemetry stories in `tools/perf/page_sets/system_health/accessibility_stories.py` - a good model for "measure the thing you are afraid of regressing".

## Choosing what to fix first

Not all violations are equal. Triage by user impact:

1. **Blocking** - a control cannot be reached or operated at all; a keyboard trap;
   an unlabeled primary action.
2. **Severe** - wrong role or state so the user is misled; a modal that does not
   contain focus; an announcement that never happens.
3. **Friction** - verbose or redundant announcements, poor heading structure,
   low-contrast secondary text.
4. **Polish** - redundant ARIA, missing landmark labels.

KEY: One unlabeled "Continue" button in checkout outranks a hundred contrast warnings in a footer. Fix by impact, not by count.

## The audit toolkit

| Tool | Best at |
| --- | --- |
| Lighthouse | quick score, CI trend, whole-page |
| axe DevTools extension | detailed rules, guided tests, intelligent triage |
| ARC Toolkit / WAVE | visual overlay of structure and issues |
| Accessibility Insights | guided manual assessment, tab-order visualization |
| `chrome://accessibility` | the actual tree Chromium exposes |
| Screen readers | the only ground truth |

TRY: Run three different tools on the same page. The union is bigger than any one of them, and the disagreements teach you what each tool assumes.
