# Syntax colour parity with VS Code

Neovim draws code in the same colours VS Code does. The editor chrome stays
Tokyo Night — its background is already `#1a1b26`, which is what
`workbench.colorCustomizations` sets `editor.background` to — and only the
colours of the code itself are replaced.

Two files do the work:

- `common/.config/nvim/lua/plugins/vscode-syntax.lua` — the palette and the
  capture → colour mapping.
- `common/.config/nvim/after/queries/{cpp,python}/highlights.scm` — extra
  tree-sitter captures for distinctions VS Code's grammars make that
  nvim-treesitter's defaults do not.

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

## Per-language colours

The same theme produces different results per language because the grammars
differ, so some groups are set per language via `@capture.<lang>`:

| | C++ (`better-cpp-syntax`) | Python (MagicPython) |
| --- | --- | --- |
| plain identifier | `#9CDCFE` | `#D4D4D4` — MagicPython classifies almost nothing |
| type annotation | n/a | `#D4D4D4` — only a `class` name and its bases get a type colour |
| ordinary call | `#DCDCAA` | `#D4D4D4` — only the built-in name lists keep a colour |
| `#include` / `import` | `#9A9A9A` (directive) | `#ECBC6F` (control flow) |

The Python built-in **type** list (`str`, `int`, `list`, `super`, …), the
built-in **function** list (`len`, `print`, `sorted`, …) and the dunder
name lists are transcribed from MagicPython itself, as is the C++ built-in
integral typedef list (`size_t`, `uint64_t`, `pthread_t`, …) from
better-cpp-syntax. They are colour distinctions those grammars make, so
reproducing them needs the same lists.

## How it was checked

Each sample file was tokenized twice and compared character by character:

- **VS Code side** — run through `vscode-textmate` and `vscode-oniguruma` with
  the real grammars (better-cpp-syntax, MagicPython) and the real theme, which
  is the same code path VS Code itself uses.
- **Neovim side** — opened in Neovim running this repository's configuration,
  then `vim.inspect_pos()` at every cell to read back the highlight that
  actually wins, resolved to its foreground colour.

Result across four samples — everyday and awkward C++ and Python, 4,461
coloured characters:

| Sample | Characters | Differing | Match |
| --- | --- | --- | --- |
| `sample.cpp` | 902 | 7 | 99.2% |
| `hard.cpp` | 1,380 | 29 | 97.9% |
| `sample.py` | 814 | 1 | 99.9% |
| `hard.py` | 1,365 | 2 | 99.9% |
| **total** | **4,461** | **39** | **99.1%** |

The semantic-token layer was checked separately by attaching clangd 18.1.3 and
resolving each token's type and modifiers through the same VS Code rules: 132
of 132 semantic-token characters match.

## What still differs

The remaining 39 characters fall into three groups, none of them fixable by
configuration:

**One tree-sitter token, two VS Code scopes.** Tree-sitter lexes `#include` as
a single token, so the `#` cannot take the punctuation colour separately; the
same goes for a `<system>` include path, the exponent in `1.5e-3`, and an
f-string's prefix and opening quote.

**VS Code's grammar gets it wrong.** `noexcept` on a lambda falls out of
better-cpp-syntax's rules and ends up uncoloured, and a declaration following
`[[nodiscard]]` is misread as a call. Neovim colours both correctly, so these
count as differences while being improvements.

**Deliberate one-offs.** A brace-initialised member declaration is an "object
access" to better-cpp-syntax, and a non-type template parameter is a type;
matching either would mean copying a quirk into otherwise correct queries.
