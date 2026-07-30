# C/C++ LSP in Neovim (and Chromium)

Goto-definition, references, hover, rename and completion for C/C++ come from
[clangd](https://clangd.llvm.org/). Nothing needs configuring per machine: open
a `.cc`, `.h`, `.mm` or `.cpp` file and it attaches.

The Chromium checkout at `~/chrome/src` is the case that needs care, so the
config handles it specifically rather than leaving it to defaults.

## What happens when clangd starts

[`lua/util/clangd.lua`](../common/.config/nvim/lua/util/clangd.lua) answers three
questions each time a client starts, and
[`lua/plugins/clangd.lua`](../common/.config/nvim/lua/plugins/clangd.lua) wires
the answers into `nvim-lspconfig`.

**Which project root?** The outermost ancestor directory holding both `.gn` and
`build/config/BUILDCONFIG.gn`. Outermost matters: Chromium ships `.gn` files
inside `third_party/dawn`, `third_party/skia`, `third_party/angle` and friends,
and each of those is also its own git repository, so the usual "nearest root
marker wins" search would root clangd in a fragment of the tree and lose every
cross-project jump. Outside a GN checkout the ordinary clangd markers
(`compile_commands.json`, `compile_flags.txt`, `.clangd`, `.git`, …) apply.

**Which clangd binary?** In a GN checkout,
`third_party/llvm-build/Release+Asserts/bin/clangd` — the one `gclient sync`
downloaded, built from the same revision as the compiler that produced the
compilation database. That means a fresh machine needs no installation at all,
and no version skew between clangd and the flags it is replaying. Elsewhere it
falls back to Mason's clangd (installed automatically) and then to `$PATH`.

**Which compilation database?** The freshest `compile_commands.json` among the
checkout root and every `out/*` directory, passed as `--compile-commands-dir`.
Freshest rather than "root first" on purpose: a root-level
`compile_commands.json` is usually a symlink someone created once and never
repointed, so it can be months out of date while `out/Default` is rewritten by
every `gn gen`. A stale database still resolves symbols, just against the flags
and files of whenever it was generated — the failure mode is confusing, so it is
worth avoiding.

Run `:ClangdStatus` to see all three answers, plus the full command line, for
the current buffer.

## Generating the compilation database

This is the one thing that cannot be shipped in dotfiles, because it describes a
particular build directory. If it is missing, Neovim says so on attach.

```bash
helpers/chrome/generate-compile-commands.sh
```

Run from anywhere inside the checkout (or pass the root, and optionally a build
directory other than `out/Default`). It adds `export_compile_commands = true` to
`args.gn`, runs `gn gen`, and points `<root>/compile_commands.json` at the
result for editors that only look there. `gn` must be on `PATH` — that means
depot_tools, e.g. `export PATH="$PATH:$HOME/chrome/depot_tools"`.

Equivalent by hand:

```bash
gn gen out/Default --export-compile-commands
```

Regenerate after changes that move files around; day-to-day edits do not need
it, since clangd infers flags for unknown files from similar ones.

## Flags, and why they differ inside a GN checkout

| Flag | Chromium | Elsewhere |
| --- | --- | --- |
| `--background-index` | yes | yes |
| `--background-index-priority=background` | yes | yes |
| `--clang-tidy` | off | on |
| `--header-insertion` | `never` | `iwyu` |
| `--limit-results` / `--limit-references` | 100 / 1000 | defaults |
| `-j` | half the cores | default |
| `--fallback-style` | `Chromium` | `llvm` |

clang-tidy is off in Chromium because it roughly doubles per-file analysis time
on translation units that are already slow, and the tryjobs enforce the
checkout's `.clang-tidy` anyway. Header insertion is off because Chromium's
include graph is largely generated and clangd guesses it wrong more often than
right. `-j` is halved so a cold index — hours of work over ~70k translation
units — leaves the machine usable.

The first index of Chromium is slow and writes roughly 2 GB to
`src/.cache/clangd` (which the checkout gitignores). Definitions inside the
current file work immediately; whole-tree references need the index.

## Keys

| Key | Action |
| --- | --- |
| `gd` / `Shift+F8` | Goto definition |
| `gr` | References |
| `gI` | Goto implementation |
| `gy` | Goto type definition |
| `K` / `Backspace Backspace` | Hover |
| `<leader>cr` | Rename |
| `<leader>ca` / `<leader>ce` | Code action |
| `<A-o>` / `gh` / `<leader>ch` | Switch between source and header |

The source/header switch goes through clangd's `textDocument/switchSourceHeader`
extension directly ([`util.clangd`](../common/.config/nvim/lua/util/clangd.lua)),
so the three keys share one implementation and none of them depend on a command
name owned by nvim-lspconfig.

See [`docs/nvim-vscode-parity.md`](nvim-vscode-parity.md) for the full mapping
table.

## When it does not work

Run `:ClangdStatus` first; it usually names the problem.

- **No client at all.** `:checkhealth vim.lsp`. Outside a GN checkout this
  normally means Mason has not finished installing clangd — `:Mason`.
- **`compile_commands.json: MISSING`.** Generate it, above.
- **Definitions resolve but to odd places, or diagnostics look nonsensical.**
  The database is probably stale relative to the tree; regenerate it.
- **Symbols in one directory never resolve.** That directory may not be in the
  build; the database only covers what the configured target compiles.
- **A wrong root in `:ClangdStatus`.** Only expected if a stray `.gn` plus
  `build/config/BUILDCONFIG.gn` sits above the checkout.

The detection rules are covered by `tests/nvim_clangd_spec.lua`
(`./tests/run-nvim-specs.sh clangd`).
