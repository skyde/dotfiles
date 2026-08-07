# Chromium C++ xrefs in Neovim

Goto-definition and find-usages in a Chromium checkout, made to behave the
way they do under the ChromiumIDE VS Code extension. Reading that
extension's source shows there is no magic index behind its navigation — it
is plain clangd, kept honest by automation. This config replicates that
automation exactly:

| ChromiumIDE does | here |
| --- | --- |
| generates `src/compile_commands.json` with `tools/clang/scripts/generate_compdb.py` when the first C++ file opens | `FileType` autocmd in `config/chromium.lua`, when the database is missing or older than the build dir's `build.ninja` |
| regenerates whenever a GN file is edited | `BufWritePost *.gn,*.gni`, debounced 2s |
| runs `clangd.restart` after regenerating | `:LspRestart clangd` (with a manual fallback) |
| tracks the active build dir via the `out/current_link` symlink | same symlink, so VS Code and Neovim always index the same build |
| relies on the vscode-clangd extension for gd/gu | `plugins/chromium-clangd.lua` configures clangd for real (nothing configured it before) |

Nothing here runs outside a Chromium checkout (detected by the presence of
`tools/clang/scripts/generate_compdb.py` in an ancestor directory).

## Commands

| Command | Action |
| --- | --- |
| `:ChromiumCompdb` | force-regenerate `compile_commands.json` and restart clangd |
| `:ChromiumOutDir` | pick the build dir xrefs index; re-points `out/current_link` and regenerates |
| `:ChromiumClangd` | install the bundled clangd: sets `checkout_clangd` in `.gclient` and runs `gclient sync` |

Without `out/current_link`, the generated out dir with the newest
`build.ninja` — the one actually being built — is used.

## The clangd binary

Inside a checkout, clangd is the checkout's own
`third_party/llvm-build/Release+Asserts/bin/clangd`, version-matched to the
clang whose flags appear in the compile commands. It only exists when
`.gclient` opts in:

```python
"custom_vars": { "checkout_clangd": True },
```

When the binary is missing, opening a C++ file prompts to set this up:
accepting edits `.gclient` (a minimal textual insertion; a file it cannot
recognize is refused, never mangled) and runs `gclient sync`, then restarts
clangd onto the bundled binary. Declining falls back to PATH's clangd —
which mostly works but can silently misparse tip-of-tree flags —
and `:ChromiumClangd` performs the same setup later. It has to be
`gclient sync`: clangd is a GCS dep in DEPS gated on `checkout_clangd`, so
`gclient runhooks` alone never fetches it.

Flags follow [//docs/clangd.md](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/clangd.md):
`--background-index`, and `--header-insertion=never` (automatic include
insertion picks wrong headers for anything involving generated files).

## Expectations worth having

- **The first background index takes hours** on a fresh checkout; until it
  finishes, find-references is incomplete. The index lives in
  `src/.cache/clangd/` — do not delete it casually, and it stays warm across
  sessions.
- **Generated headers need a build.** Files including mojom/proto headers
  cannot be parsed until the target has been built once
  (`autoninja -C out/Default chrome`).
- **Cross-config usages don't exist locally.** The compdb describes one
  build config; usages inside `#if BUILDFLAG(...)` branches that config
  doesn't compile are invisible to clangd. That completeness is what
  [source.chromium.org](https://source.chromium.org/) (Kythe) has and a
  local index cannot; its old programmatic API was
  [shut down in 2021](https://github.com/chromium/codesearch-py), so the web
  UI is the remaining way at it.
