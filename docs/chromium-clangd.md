# Chromium C++ xrefs in Neovim

Goto-definition and find-usages in a Chromium checkout, made to behave the
way they do under the ChromiumIDE VS Code extension. Reading that
extension's source shows there is no magic index behind its navigation — it
is plain clangd, kept honest by automation. This config replicates that
automation, then closes the gaps the extension still leaves:

| ChromiumIDE does | here |
| --- | --- |
| generates `src/compile_commands.json` with `tools/clang/scripts/generate_compdb.py` when the first C++ file opens | `FileType` autocmd in `config/chromium.lua`, when the database is missing or older than the build dir's `build.ninja` |
| regenerates whenever a GN file is edited | `BufWritePost *.gn,*.gni`, debounced 2s |
| runs `clangd.restart` after regenerating | restarts clangd (stop-and-reattach; `:LspRestart` when the plugin provides it — under nvim 0.12's native `:lsp` command nvim-lspconfig defines no `Lsp*` commands) |
| tracks the active build dir via the `out/current_link` symlink | same symlink, so VS Code and Neovim always index the same build |
| relies on the vscode-clangd extension for gd/gu | `plugins/chromium-clangd.lua` configures clangd for real (nothing configured it before) |
| — | re-checks freshness on every `BufEnter`/`FocusGained` (throttled), so a build, gn run, or `git pull` outside the editor is noticed mid-session, not next session |
| — | probes once per file per session that the buffer's file is actually *in* the database; a miss (the fate of every file added since the last regeneration) forces one regeneration |
| — | pins clangd's workspace root to the checkout's `src`, so v8/blink/webrtc/skia (which carry their own `.git`/`.clang-format` root markers) don't each spawn a clangd instance with its own racing background indexer |

Nothing here runs outside a Chromium checkout (detected by the presence of
`tools/clang/scripts/generate_compdb.py` in an ancestor directory).

## Commands

| Command | Action |
| --- | --- |
| `:ChromiumCompdb` | force-regenerate `compile_commands.json` and restart clangd |
| `:ChromiumOutDir` | pick the build dir xrefs index; re-points `out/current_link` and regenerates |
| `:ChromiumClangd` | install the bundled clangd: sets `checkout_clangd` in `.gclient` and runs `gclient sync` |
| `:ChromiumHealth` (= `:checkhealth chromium`) | diagnose the whole chain: binary, build dir, compdb freshness, whether the current buffer is in it, the running client's actual command, background-index progress, required tools |

Without `out/current_link`, the generated out dir with the newest
`build.ninja` — the one actually being built — is used.

When gd or find-usages misbehaves, start with `:ChromiumHealth`: every
way this setup can silently degrade (stale database, buffer missing from
it, wrong binary, split clangd instances, index still building, ninja not
on PATH) is a line in that report.

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

Flags follow [//docs/clangd.md](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/clangd.md),
plus what a checkout of this size forces:

- `--background-index` — the index behind cross-file find-usages.
- `--header-insertion=never` — automatic include insertion picks wrong
  headers for anything involving generated files.
- `--limit-references=0` — clangd caps find-references at 1000 by default
  and truncates *silently*; plenty of Chromium symbols have more usages
  than that, and "find usages" has to mean all of them.
- `--compile-commands-dir=<src>` — pin database discovery instead of
  letting clangd walk up from each file; buffers under `out/` (generated
  sources reached via gd) would otherwise bind to whatever partial
  `compile_commands.json` sits inside the build dir. The command is
  computed per client from its resolved root (cmd is a function), so this
  pin never leaks into other checkouts or non-Chromium projects in the
  same session.
- `--log=error` — at the default level a Chromium session grows `lsp.log`
  by the gigabyte.

## Expectations worth having

- **The first background index takes hours** on a fresh checkout; until it
  finishes, find-references is incomplete. The index lives in
  `src/.cache/clangd/` — do not delete it casually, and it stays warm across
  sessions. `:ChromiumHealth` reports its shard count.
- **Generated headers need a build.** Files including mojom/proto headers
  cannot be parsed until the target has been built once
  (`autoninja -C out/Default chrome`).
- **A GN-file save regenerates the database, but `ninja -t compdb` reads
  the existing `build.ninja`** — new targets appear after the next
  `gn gen`/build touches it, which the `BufEnter`/`FocusGained` re-check
  then picks up.
- **The clangd remote index service is gone.** Chromium once offered
  `linux.clangd-index.chromium.org` for instant, complete references
  without local indexing; the service has been
  [permanently shut down](https://github.com/clangd/chrome-remote-index/blob/main/docs/index.md)
  (and Chromium's bundled clangd was never built with remote-index support
  anyway). The local background index is the only game in town — protect
  it.
- **Cross-config usages don't exist locally.** The compdb describes one
  build config; usages inside `#if BUILDFLAG(...)` branches that config
  doesn't compile are invisible to clangd. That completeness is what
  [source.chromium.org](https://source.chromium.org/) (Kythe) has and a
  local index cannot; its old programmatic API was
  [shut down in 2021](https://github.com/chromium/codesearch-py), so the web
  UI is the remaining way at it.
