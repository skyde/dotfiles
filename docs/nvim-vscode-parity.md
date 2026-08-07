# Neovim ↔ VS Code parity

The VS Code setup in `common/.config/Code/User/settings.json` is the reference.
This is what each of those bindings does in Neovim, and where the two
deliberately differ.

Leader is `<space>` in both.

## Source control and diffs

The whole `<leader>g` family goes through `lua/util/vcs.lua`, which detects the
backend per directory and speaks to it. **git, jj, Perforce (`p4` / `g4`) and
Mercurial all use the same keys.** Detection order is jj → git → hg → g4 → p4,
so a jj repo colocated with git is treated as jj; override with
`:lua vim.g.vcs_backend = "git"`.

| Key | VS Code | Neovim |
| --- | --- | --- |
| `<leader>gc` | focus SCM view | changed files, uncommitted — list on the left, live diff on the right; pressed again it always goes to the view (from the diff, back to the list; from another tab, jumps to it), never closing |
| `<leader>gD` | `gitTreeCompare.openAllChanges` | changed files since the fork point with trunk (same go-to behavior) |
| `<leader>gC` | — | close the changed-files view (`q` in the list does too) |
| `<leader>gb` | `gitTreeCompare.changeBase` | changed files against a revision you type |
| `<leader>gR` | refresh SCM | refresh the list |
| `<leader>gd` | `git.openChange` | diff the current file against its last committed version |
| `<leader>ga` | `git.viewChanges` | diff the current file against the fork point |
| `<leader>gp` | `git upstream-diff` in a terminal | uncommitted patch, delta-coloured, `q` closes it |
| `<leader>gA` | `diff-branch` in a terminal | full patch since the fork point, delta-coloured, `q` closes it |
| `<leader>gy` | Copy Git Diff task | copy that patch to the clipboard |
| `<leader>gl` | `git log -p` on the file | revision history of the current file; pick one to diff against |
| `<leader>gw` | `git.openFile` | from a diff, open the real file on disk at the same line |
| `<leader>gg` | LazyGit task | backend-appropriate TUI (`lazyjj`/`jjui` under jj, otherwise LazyGit) |

Commands do the same without leader keys: `:VcsChanges [working|branch|head]`,
`:VcsDiff`, `:VcsPatch`, `:VcsHistory`, `:VcsInfo`.

### Inside the changed-files view

The list is a tree, VS Code explorer style: directories first, chains of
single-child directories compacted onto one line (`a/b/c/`), and every
filename shown whole instead of a full path truncated against the panel
edge. Status letters (`M` `A` `D` `R` `C` `?`) sit in the left column,
filetype icons follow when mini.icons is around, renamed files read
`new ← old`, and the header tracks the selection as `file 3 of 12` plus the
listing's total churn (`+125 -40`). The right edge of each row carries the
review state: the file's own `+n -n` (computed in the background off the
cached bases, never a subprocess) and a `✓` once the file has been looked
at — GitHub's per-file "viewed" checks, kept per listing until its base
revision moves.

| Key | Action |
| --- | --- |
| `j` / `k` | move through files (stepping over directory rows), re-rendering the diff as you go |
| `<CR>` / `<Space>` / `o` / `l` / `<Right>` / `<Tab>` | move focus into the diff — `<Space>` deliberately shadows leader while the panel is focused, since selecting is what the panel is for |
| `J` / `K` | scroll the diff half a page from the list, for skimming a file without leaving it |
| `]c` / `[c` | step the diff to the next / previous change, cursor staying in the list |
| `]f` / `[f` | next / previous file — from *inside* the diff it renders it and keeps focus there; from the list it just moves the selection, like `j` / `k` |
| `s` | cycle scope: uncommitted → since fork point → last commit |
| `i` | toggle inline / side-by-side |
| `z` | toggle collapsing unchanged regions (both renderings; `zR` / `zM` still work per window) |
| `a` | stage / unstage the file, where the backend has an index (git) |
| `y` | copy the selected file's diff to the clipboard |
| `X` | revert the file to its base version, after a confirm; on an added or untracked file this deletes it |
| `m` | open the three-way merge view for a conflicted file; `<leader>cq` there drops back into this view |
| `r` | hard refresh: re-ask the backend for everything |
| `q` | close — also from a scratch diff pane |
| `?` | cheat sheet of these keys |

The listing also revalidates itself in the background whenever you come back
to the tab (or to Neovim), so a commit made in a terminal does not leave the
view describing a world that no longer exists.

Browsing leaves no trace: the working side is the real file, opened as an
unlisted preview, and the moment you move to the next file the previous
preview is **closed again** unless it carries unsaved edits — so at most one
looked-at file is ever loaded, and closing the view drops that too (a buffer
with unsaved edits is kept and surfaced in the buffer list instead). The
view also folds itself away before a session is saved, so quitting
mid-review cannot bake stray buffers or a junk tab into the session.

The right-hand side has two renderings, and the choice is remembered across
opens. **Inline is the default**, matching `diffEditor.renderSideBySide:
false` in the VS Code config — and like that editor it is the **real,
editable file**: the base version's missing lines are drawn between the lines
in red, new lines are highlighted green, and the overlay follows as you type.
Within a changed line the **tokens that differ are emphasized** on both
sides, exactly the way delta renders a patch in the terminal: the unchanged
part of an edited line dims, the changed tokens brighten (skipped when a line
was rewritten wholesale, where emphasis would cover everything). Lines that
merely **moved** — deleted in one place, reinserted verbatim in another — get
their own colours instead of reading as unrelated delete + add: the
departure a dimmed red leaning violet with faded text, the arrival a dimmed
green leaning teal — still red-family "left from here" and green-family
"landed here", but recognizably neither a real delete nor a real add. Like
git's `--color-moved` and delta, moves are colour-only; optional pointer
hints (relative jump offsets, partner-side glyphs) stay selectable via
`move_hint` in `util/inline_diff.lua`. Trailing whitespace on a new line
gets delta's whitespace-error red. The colours are the delta palette
from the git config, verbatim, so this view and `git diff` in a terminal are
the same picture; the overlay also slices hunks with the same histogram +
linematch settings as `'diffopt'`, so both renderings agree about what a
change is.

**Unchanged regions collapse away** (VS Code's hideUnchangedRegions, on by
default): the side-by-side panes use diff mode's native folds, the inline
overlay folds through its own foldexpr, and both keep the same context
`'diffopt'` gives native diff mode, so a review reads hunk to hunk the way a
delta patch does. `╌╌ 42 unchanged lines ╌╌` marks each gap; `zR` opens a
window up, and `z` in the panel or `<leader>cz` from anywhere turns the whole
behaviour off (remembered, like the inline/side-by-side choice).
`]c` / `[c` walk the changes, `<leader>cv` reverts the change under the
cursor. Untracked files read as a whole-file add, deleted files show their
old content struck red. `i` in the panel (or `<leader>ci` anywhere) switches
to side-by-side: native diff mode, so `]c` / `[c` / `do` / `dp` work and the
right pane is the real file; on Neovim 0.12+ `diffopt+=inline:char` gives it
the same char-level emphasis. Toggled from inside the diff (the same goes for
`<leader>cz`), focus and the reading position stay put instead of dropping
back into the list; from the panel, focus stays in the panel for more
scrubbing. The delta-rendered unified patch is still there
on `<leader>gp` / `<leader>gA`.
The diff opens scrolled to the first change, renamed files diff against their
old path rather than reading as wholly added, and every diff pane uses hybrid
line numbers — absolute on the cursor line, relative everywhere else — so a
`3j` between changes reads straight off the margin. `]c` / `[c` also echo
"Change 2 of 5", the way the VS Code diff editor numbers its changes.

Files opened by scrubbing behave like VS Code's preview editors: they stay out
of the buffer list, and are dropped again when the view closes — however it
closes, `q` or an external `:tabclose` alike. The moment one is edited it
becomes a real buffer and survives.

Navigating from inside a diff pane stays in the view. A jump that lands a file
in the pane — `gd`, a references picker, `<C-o>`, a plain `:e` — is adopted:
a file from the changed listing gets its full diff rendering against the same
base, inline or side-by-side per the current mode, with the panel selection
following; an unchanged file (its diff is empty) shows plain, with the
previous rendering's diff mode and folds scrubbed off. The window is reused
rather than rebuilt, so the jumplist survives and `<C-o>` walks back — each
return trip adopted the same way. Files a jump opens are previews like any
other; a buffer that was already open on purpose stays in the buffer list.
The code panes also pin their normal background (`NormalNC` rewired to
`Normal`), so tokyonight's `dim_inactive` never darkens the code side while
the cursor lives in the file list — the eyes are on the code either way.

Rendering a diff costs a subprocess, so `j` / `k` move the cursor immediately
and the diff follows once the keys stop (80 ms). Holding `j` through a
400-file changelist costs one render rather than four hundred. `<CR>`
pre-empts the wait and renders at once.

Everything the backend says is remembered across opens of the view: the
listing per scope and the base content per file. Reopening `<leader>gc` in a
large or server-backed repository (Perforce especially) paints instantly from
the last known state, the header shows "refreshing…" while a background pass
revalidates, and the panel only redraws if something actually changed.

Opening the view preloads the whole listing in the background — one subprocess
at a time, so it stays gentle on a loaded server and the UI never waits on any
of it — until every file has a base or the budget runs out (half the base
cache, or 32 MB of content, whichever comes first). The sweep is steered
rather than scheduled: between fetches it re-reads where the cursor is and
takes the nearest file that still has no base, so moving the selection re-aims
it at what you are reading now instead of finishing an order fixed when the
view opened. It also stands aside while a render holds a subprocess, since the
file being looked at is worth more than the one being guessed at. The churn
column fills in as the sweep goes, which is the visible sign of how far it has
got; a file whose base is still cold renders asynchronously instead of
freezing the list. `r` distrusts all of it and re-asks the backend from
scratch.

Neovim's `diffopt` is set in `lua/config/options.lua` to the same algorithm and
context as `common/.config/git/config`, so a diff reads the same in the editor
as in the terminal.

### Diff and merge conflicts

Conflict handling is marker-based (`lua/util/conflict.lua`), not git-based, so
it works in every backend and on files handed over by any other tool.

| Key | VS Code | Neovim |
| --- | --- | --- |
| `]c` / `[c` | next/prev change | next/prev change — diff hunk, conflict, or gitsigns hunk, whichever the buffer has |
| `]k` / `[k` | — | next/prev class (was `]c` in stock LazyVim, which shadowed next-change in every treesitter buffer) |
| `<leader>cn` / `<leader>cp` | same | same |
| `]x` / `[x` | next/prev unhandled conflict | next/prev conflict |
| `<leader>co` / `<leader>cO` | accept ours / all ours | take ours, here / everywhere in the file |
| `<leader>ct` / `<leader>cT` | accept theirs / all theirs | take theirs, here / everywhere |
| `<leader>cb` / `<leader>cB` | accept both | take both, here / everywhere |
| `<leader>c0` | — | take neither |
| `<leader>cm` | open merge editor | three-way view: ours │ working │ theirs |
| `<leader>cq` | accept merge | save and close the merge view (refuses while markers remain) |
| `<leader>cc` | toggle between inputs | move to the other side of the diff |
| `<leader>cd` | switch diff side | switch side in a diff, line diagnostics elsewhere |
| `<leader>ci` | toggle inline diff | toggle inline / side-by-side |
| `<leader>cz` | `diffEditor.hideUnchangedRegions.enabled` | toggle collapsing unchanged regions |
| `<leader>cv` | `diffEditor.revert` | revert this change (`do` in diff mode, gitsigns reset otherwise) — from the read-only base side it pushes the hunk into the working copy instead, so it works from either pane |
| `<leader>cV` | `git.revertSelectedRanges` | revert the selected range (working copy only: the base side's line numbers do not name the same lines) |

`git mergetool` opens Neovim on the conflicted file — see
[`neovim-mergetool.md`](neovim-mergetool.md).

## Navigation and LSP

| Key | Neovim |
| --- | --- |
| `gd` `gy` `gr` | definition / type definition / references (LazyVim) |
| `gi` | implementation (LazyVim also keeps `gI`) |
| `gp` `gu` | definition / reference picker with preview, standing in for VS Code's peek |
| `gn` | hover |
| `gh`, `<A-o>` | switch header/source (clangd) |
| `vig` `yig` `dig` | whole-buffer text object |
| `<leader>cr` | rename symbol |
| `<leader>ca` | code action (LazyVim default) |
| `<leader>cI`, `<BS><leader>` | signature help |
| `<BS><BS>` | hover |
| `<leader><BS>` | debug hover / evaluate |
| `]d` / `[d` | next / previous diagnostic |
| `<leader>xx` | problems list (Trouble) |

## Search

| Key | Neovim |
| --- | --- |
| `<leader><leader>` | find files |
| `<leader>/`, `<leader>sg` | grep |
| `<leader>se` | grep C++/Python only |
| `<leader>st` | grep the word under the cursor, limited to the current filetype |
| `<leader>sb` | open buffers |
| `<leader>sr` | resume the last picker |
| `<leader>sz` | `st` — zoekt if the tree is indexed, ripgrep otherwise |
| `<leader>si` | `si` — build the zoekt index |

`<leader>sz` and `<leader>si` shell out to the same scripts the VS Code tasks
ran, in a terminal split.

## Debug and tests

The VS Code split is kept: `<leader>t` is stepping, `<leader>T` is the test
runner. This is why the neotest keys are re-declared in
`lua/plugins/neotest.lua` instead of using LazyVim's `<leader>t` defaults.

| Key | Action |
| --- | --- |
| `<leader>tn` `<leader>ti` `<leader>to` | step over / into / out |
| `<leader>tu` `<leader>td` | up / down the call stack |
| `<leader>tc` `<leader>tl` `<leader>tw` `<leader>tb` `<leader>th` | call stack / variables / watches / breakpoints / REPL |
| `<leader>db` `<leader>dB` | breakpoint / conditional breakpoint |
| `<leader>dc` `<leader>dp` `<leader>dS` `<leader>dR` | continue / pause / stop / restart |
| `<leader>dg` `<leader>dL` | set next statement / log point |
| `<leader>dw` `<leader>dx` | watch expression / REPL |
| `<leader>Tr` `<leader>Tf` `<leader>Ta` `<leader>TR` | run nearest / file / all / last |
| `<leader>Td` `<leader>To` `<leader>Te` `<leader>TS` | debug nearest / output / explorer / stop |
| `<leader>mb` `<leader>mB` `<leader>mT` `<leader>mt` `<leader>mc` | build / pick build / run task / re-run / terminate |
| `<leader>mr` `<leader>mR` `<leader>ms` | start debugging / pick config / stop |

Tasks come from `.vscode/tasks.json` via Overseer and launch configs from
`.vscode/launch.json` via nvim-dap, so a repo set up for VS Code works
unchanged.

## UI

| Key | Action |
| --- | --- |
| `<leader>uw` `<leader>uz` `<leader>uc` `<leader>uh` | wrap / zen / conceal level / inlay hints |
| `<leader>up` `<leader>um` `<leader>ur` | font bigger / smaller / reset (Neovide, or kitty with remote control on) |
| `<leader>uk` | key-press debugging |
| `<leader>p` | command palette |
| `<leader>e` | Yazi |
| `<leader>E` | reveal in Finder/Explorer |
| `<leader>fe` | file tree, revealing the current file |
| `<leader>fl` | copy the path of the current file |
| `<BS>n`, `<leader>ft` | terminal |

## Deliberate differences

* **`<leader>1`–`<leader>9` are tabs, not editor slots.** VS Code numbers
  editors within a group; the Neovim config numbers tabpages. Unchanged from
  before.
* **No `<leader>r` sidebar toggle.** `<leader>rr` already reloads the config,
  and adding a bare `<leader>r` would put a timeout in front of it. Use
  `<leader>fe` for the tree.
* **`<leader>fp` (`g4d`) is not mapped.** It is a Google-internal command with
  no local equivalent.
* **Font zoom only works under Neovide or kitty with `allow_remote_control`.**
  In a plain terminal the font is the terminal's business; the keys say so
  rather than doing nothing.
* **No diffview.nvim.** It only supports git and hg, and having it own
  `<leader>gc` for git while something else owned it for jj and p4 would mean
  two different review UIs. One UI for every backend was the better trade.

## Tests

```bash
tests/run-nvim-specs.sh
```

Four specs, no plugins needed, each self-contained:

* `nvim_vcs_spec.lua` — the backends, against throwaway git, jj and Mercurial
  repositories: renames, paths with spaces and non-ASCII characters, deleted and
  untracked files, an empty repository, a repository whose only commit is its
  first, detached HEAD. Perforce runs against a stub `p4` binary that speaks the
  real `-ztag` protocol, which is how that backend is covered without a server.
  The jj and hg halves skip themselves when the binary is missing.
* `nvim_conflict_spec.lua` — every conflict shape and choice, including
  `merge` style with no base section, multiple and adjacent conflicts,
  conflicts spanning the whole file, unlabelled markers, and near-miss text
  (C++ templates full of angle brackets) that must *not* parse as a marker.
* `nvim_vcs_ui_spec.lua` — window layout, which buffer lands in which pane,
  scrubbing, the inline toggle, the diff-tab lifecycle, and the degenerate cases
  (no changes, no repository).
* `nvim_vcs_keys_spec.lua` — the revert keys from inside a real diff, where
  one side of the pair is a read-only scratch.

```bash
tests/check-nvim-keymaps.sh
```

Invokes every binding against the real config inside a throwaway repository.
Callback maps must not raise even with no language server and no debug session
attached — degrading with a message is fine, throwing is not.

`run-nvim-specs.sh` runs in CI (the `neovim` job in
`.github/workflows/comprehensive-test.yml`), which also installs Mercurial so
the backend spec's `hg` half actually executes rather than skipping itself.
The checks that need the plugins and the tree-sitter parsers installed stay
manual, as does `nvim_clipboard_spec.lua`.

Set `showtabline = 0` in any spec that raises `'columns'`: headless Neovim
keeps its 80x24 grid while `draw_tabline` draws at the current width, so a
wide spec that opens a second tab and enters command-line mode writes past
the end of it.

## Backend notes

* **git** — the "fork point" base is the merge base with `@{upstream}`, then
  `origin/HEAD`, then `origin/main` / `origin/master` / `main` / `master`,
  matching what `common/.local/bin/git-diff-from-last-branch` does in the shell.
* **jj** — calls that ask what the working copy looks like *now* (`diff`,
  `log`) let jj snapshot, because in jj the working copy is a commit and
  `jj status` snapshots as a matter of course. Suppressing it with
  `--ignore-working-copy` means every edit made since the last jj command is
  invisible, which is a correctness bug, not a courtesy — an earlier version did
  this and reported "no changes" for work that was right there. Calls that only
  read committed history (`root`, `show`, trunk resolution) still skip the
  snapshot, which keeps scrubbing cheap. The fork-point base is
  `latest(::@ & trunk())`, falling back to `@-` when the repo has no trunk or
  when trunk degrades to the root commit.
* **Perforce** — `p4` and `g4` are the same code path; `g4` is tried first. The
  root comes from `$P4CONFIG` if set, otherwise `p4 info`'s client root. Every
  scope compares against each file's synced (`#have`) revision, since Perforce
  has no fork-point notion. `p4 where` is asked once for the whole changelist,
  not once per file, which on a real changelist is the difference between one
  round trip and hundreds. **This backend has no live server to test against**,
  so the spec drives it through a stub that speaks the documented `-ztag`
  protocol; the git and jj paths are tested against real repositories.
* **Mercurial** — included because it was nearly free once the interface
  existed.
