# Syntax colour parity with VS Code

Neovim draws code in the same colours VS Code does. The editor chrome stays
Tokyo Night — its background is already `#1a1b26`, which is what
`workbench.colorCustomizations` sets `editor.background` to — and only the
colours of the code itself are replaced.

Two files do the work:

- `common/.config/nvim/lua/util/vscode_syntax.lua` — the palette and the
  capture → colour mapping.
- `common/.config/nvim/after/queries/{cpp,python}/highlights.scm` — extra
  tree-sitter captures for distinctions VS Code's grammars make that
  nvim-treesitter's defaults do not.

The mapping is applied from tokyonight's `on_highlights` hook, called from
`lua/plugins/tokyonight.lua`. That is deliberate, and the only thing that
works: LazyVim's default `colorscheme` setting is a *function* that calls
`require("tokyonight").load()`, which rebuilds every highlight **without**
firing `ColorScheme`. A `ColorScheme` autocmd therefore applies the palette
during startup and then silently loses it again a moment later. `on_highlights`
runs on every build, event or no event.

## Where the colours come from

The reference is the exact pair the VS Code config is running:

- the **Visual Studio Dark - C++** theme (`ms-vscode.cpptools-themes`,
  `themes/cpptools_dark_vs_new.json`), and
- every rule in `editor.tokenColorCustomizations.textMateRules` in
  `common/.config/Code/User/settings.json`, which overrides most of it.

Every hex in `vscode-syntax.lua` is the value VS Code *resolves* for a
construct once those two are combined, not a colour picked by eye. Resolution
follows VS Code's own rules: the theme's rules and the user's rules go into one
trie, more specific selectors beat less specific ones, ties go to whichever was
declared later (so the user's rules win), and a scope stack is walked from the
outside in with each matching scope overriding the last.

That last detail is what makes `string.quoted` `#DFA67C` while the plain
`string` rule stays `#8FAFDF`, and what leaves an unclassified `meta.*` scope
showing the `source` colour `#D4D4D4` rather than the theme's editor
foreground.

## Two layers, both mapped

VS Code has `editor.semanticHighlighting.enabled` on, so a token can be
coloured twice: by the TextMate grammar, and then again by the language
server's semantic tokens. Neovim works the same way — tree-sitter first, then
`@lsp.type.*` on top — so both layers are mapped:

- **Tree-sitter captures** (`@keyword`, `@variable`, …) get the colour the
  corresponding TextMate scope resolves to.
- **Semantic tokens** (`@lsp.type.*`) get the colour VS Code resolves for the
  equivalent semantic token type, via the default token-type → scope table VS
  Code probes when a theme has no explicit rule.

Neovim also paints an `@lsp.mod.<modifier>` and an
`@lsp.typemod.<type>.<modifier>` group for every modifier a server reports, all
at the same priority, so with several modifiers on one token the winner comes
down to iteration order. VS Code has no equivalent concept — a modifier only
matters combined with a type. So every combination VS Code has no opinion about
is cleared, leaving the type's colour, or the one meaningful override, as the
only thing that paints.

## C++ is the reference; Python follows it

VS Code's C++ setup is the ground truth, and Python is matched to it **role for
role** rather than to VS Code's own Python output.

That is a deliberate divergence. VS Code's Python grammar, MagicPython,
classifies almost nothing: annotations, calls and locals are all plain
`source.python`, and with no Python extension installed there is no language
server to repaint them. Reproducing that faithfully left Python a flat grey
next to C++ — `Sequence[CustomClass]` was a single undifferentiated run. So
each Python construct instead gets the colour its C++ counterpart has:

| Construct | Colour | C++ counterpart |
| --- | --- | --- |
| type in an annotation | `#4EC9B0` | `entity.name.type` |
| built-in type (`str`, `list`) | `#ECB763` | `int`, `size_t` |
| local variable | `#9CDCFE` | `variable` |
| parameter | `#9A9A9A` | `variable.parameter` |
| `self.attr` — the attribute | `#DADADA` | `v.x` member access |
| `obj` in `obj.attr` | `#DD9DC2` | `variable.other.object` |
| function, method call | `#DCDCAA` | `entity.name.function` |
| call parentheses | `#F89500` | `punctuation.section.arguments` |
| `self` | `#569CD6` | `this` |

`tests/check-nvim-syntax-roles.lua` asserts this: it opens a C++ and a Python
sample and checks that all 21 roles resolve to the same colour in both.

The palette itself is still entirely VS Code's — no new colours were invented,
only applied to more of Python.

The Python built-in **type** list (`str`, `int`, `list`, `super`, …), the
built-in **function** list (`len`, `print`, `sorted`, …) and the dunder
name lists are still transcribed from MagicPython itself, as is the C++
built-in integral typedef list (`size_t`, `uint64_t`, `pthread_t`, …) from
better-cpp-syntax — those are real distinctions the grammars make.

One limit worth knowing: Python's `.` is member access to tree-sitter whatever
is on the left, so `asyncio.TimeoutError` colours like `obj.field` rather than
like C++'s `std::runtime_error`. C++ can tell them apart because `::` and `.`
are different operators; Python has only the one.

## How it was checked

Each sample file was tokenized twice and compared character by character:

- **VS Code side** — run through `vscode-textmate` and `vscode-oniguruma` with
  the real grammars (better-cpp-syntax, MagicPython) and the real theme, which
  is the same code path VS Code itself uses.
- **Neovim side** — opened in Neovim running this repository's configuration,
  then `vim.inspect_pos()` at every cell to read back the highlight that
  actually wins, resolved to its foreground colour.

Result for C++, across an everyday and an awkward sample:

| Sample | Characters | Differing | Match |
| --- | --- | --- | --- |
| `sample.cpp` | 902 | 7 | 99.2% |
| `hard.cpp` | 1,380 | 29 | 97.9% |
| **total** | **2,282** | **36** | **98.4%** |

Python is not scored this way, because it deliberately no longer follows VS
Code's Python output — see the section above. What is checked for Python is
role consistency with C++, all 21 roles.

The semantic-token layer was checked separately by attaching clangd 18.1.3 and
resolving each token's type and modifiers through the same VS Code rules: 132
of 132 semantic-token characters match.

All of this is measured with `User VeryLazy` fired, so the editor is in the
state it is in during real use — without it, LazyVim's `load()` call has not
happened yet and the measurement flatters the result.

## What still differs in C++

The remaining 36 characters fall into three groups, none of them fixable by
configuration:

**One tree-sitter token, two VS Code scopes.** Tree-sitter lexes `#include` as
a single token, so the `#` cannot take the punctuation colour separately; the
same goes for a `<system>` include path and the exponent in `1.5e-3`.

**VS Code's grammar gets it wrong.** `noexcept` on a lambda falls out of
better-cpp-syntax's rules and ends up uncoloured, and a declaration following
`[[nodiscard]]` is misread as a call. Neovim colours both correctly, so these
count as differences while being improvements.

**Deliberate one-offs.** A brace-initialised member declaration is an "object
access" to better-cpp-syntax, and a non-type template parameter is a type;
matching either would mean copying a quirk into otherwise correct queries.
