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
| `<leader>gb` | `gitTreeCompare.changeBase` | changed files against a revision you type — the header then names that revision, and a name the repository does not have is reported rather than drawn as an empty listing |
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
edge. Status letters sit in the left column — `M` modified, `A` added, `D`
deleted, `R` renamed, `C` copied, `!` conflicted, `?` untracked, all of them
listed again in the `?` cheat sheet — filetype icons follow when mini.icons is
around, renamed files read `new ← old`, and the header tracks the selection as
`file 3 of 12` plus the listing's total churn (`+125 -40`). The right edge of
each row carries the review state: the file's own `+n -n` (computed in the background off the
cached bases, never a subprocess) and a `✓` once the file has been looked
at — GitHub's per-file "viewed" checks, kept per listing until its base
revision moves.

| Key | Action |
| --- | --- |
| `j` / `k` | move through files (stepping over directory rows), re-rendering the diff as you go |
| `<CR>` / `<Space>` / `o` / `l` / `<Right>` / `<Tab>` | move focus into the diff — `<Space>` deliberately shadows leader while the panel is focused, since selecting is what the panel is for |
| `J` / `K` | scroll the diff half a page from the list, for skimming a file without leaving it |
| `]c` / `[c` | step the diff to the next / previous change, cursor staying in the list |
| `]f` / `[f` | from *inside* the diff: render the next / previous file, focus staying in the diff |
| `s` | cycle scope: uncommitted → since fork point → last commit |
| `i` | toggle inline / side-by-side |
| `z` | toggle collapsing unchanged regions (both renderings; `zR` / `zM` still work per window) |
| `a` | stage / unstage the file, where the backend has an index (git) |
| `y` | copy the selected file's diff to the clipboard |
| `X` | revert the file to its base version, after a confirm; on an added or untracked file this deletes it |
| `m` | open the three-way merge view for a conflicted file — the `!` rows; `<leader>cq` there drops back into this view |
| `r` | hard refresh: re-ask the backend for everything |
| `q` | close — also from a scratch diff pane |
| `?` | cheat sheet of these keys, and what each status letter means |

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
`Normal`), so no dim-on-blur scheme can darken the code side while the cursor
lives in the file list — the eyes are on the code either way. (`dim_inactive`
itself is off in the theme config: focus changing a window's brightness reads
as the panes changing colour under you.)

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
| `<leader>cv` | `diffEditor.revert` | revert this change (`do` in diff mode, gitsigns reset otherwise) |
| `<leader>cV` | `git.revertSelectedRanges` | revert the selected range |

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
| `<leader>Backspace` | debug hover / evaluate |
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
| `<leader>dr` `<leader>dl` `<leader>du` | REPL / run last / toggle the debugger UI |
| `<leader>Tr` `<leader>Tf` `<leader>Ta` `<leader>TR` | run nearest / file / all / last |
| `<leader>Td` `<leader>To` `<leader>Te` `<leader>TS` | debug nearest / output / explorer / stop |
| `<leader>TO` `<leader>Tw` | output panel / watch the current file |
| `<leader>mb` `<leader>mB` `<leader>mT` `<leader>mt` `<leader>mc` | build / pick build / run task / re-run / terminate |
| `<leader>mr` `<leader>mR` `<leader>ms` | start debugging / pick config / stop |
| `<leader>mp` | break at cursor — run to it, starting a session first if none is running |

Tasks come from `.vscode/tasks.json` via Overseer and launch configs from
`.vscode/launch.json` via nvim-dap, so a repo set up for VS Code works
unchanged.

## UI

| Key | Action |
| --- | --- |
| `<leader>uw` `<leader>uz` `<leader>uc` `<leader>uh` | wrap / zen / whitespace / inlay hints |
| `<leader>up` `<leader>um` `<leader>ur` | font bigger / smaller / reset (Neovide, or kitty with remote control on) |
| `<leader>uk` | key-press debugging — prints each key by name (`<S-F3>`), which is how the footpedal keys get diagnosed |
| `<leader>p` | command palette |
| `<leader>e` | Yazi |
| `<leader>E` | reveal in Finder/Explorer |
| `<leader>fe` | file tree, revealing the current file |
| `<leader>fl` | copy the path of the current file |
| `<BS>n`, `<leader>ft` | terminal |
| `<leader>v` | block visual mode, since `<C-v>` is paste on Windows terminals |
| `<leader>rr` | reload the config and `:Lazy sync` |
| `<leader>bn` `<leader>bh` `<leader>bl` | new tab / move it left / move it right |
| `<leader>0` | last tab (`<leader>1`–`<leader>9` pick one by number) |

### Windows

VS Code calls these editor groups and binds the whole family under `<leader>w`;
these are the same commands under the same keys. `<C-w>h` and friends still work
— this is the VS Code spelling of them, not a replacement.

| Key | Action |
| --- | --- |
| `<leader>wh` `<leader>wj` `<leader>wk` `<leader>wl` | focus the window left / below / above / right |
| `<leader>wH` `<leader>wJ` `<leader>wK` `<leader>wL` | move this window left / below / above / right |
| `<leader>ws` `<leader>wv` | split below / split right |
| `<leader>wf` | zoom the window to fill the tab, standing in for VS Code's full screen |
| `<leader>wd` `<leader>wm` | close the window / toggle zoom (LazyVim) |

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
* **A handful of VS Code `<leader>` keys have no Neovim binding**, because what
  they do has no counterpart here rather than because they were forgotten:
  `<leader>a` / `<leader>i` / `<leader>ff` / `<leader>fT` / `<leader>sT` run
  VS Code tasks that shell out to `st` / `si` / a terminal, which `<leader>sz`,
  `<leader>si` and `<BS>n` already cover directly; `<leader>bp` / `<leader>bu`
  / `<leader>bP` / `<leader>bD` pin, unpin and reopen editors, and Neovim's
  buffer list has no pinning; `<leader>gr` and `<leader>gT` drive VS Code's SCM
  sidebar, which `<leader>gc` replaces wholesale; `<leader>dB{c,d,e,r}` and
  `<leader>t{I,U,D}` are breakpoint- and call-stack-list operations that belong
  to the debug sidebar. Add any of them if the muscle memory turns out to
  matter — nothing is shadowing those keys.

## Tests

Everything below runs in CI on every push that touches the config
(`.github/workflows/neovim.yml`), on Linux and macOS against the current Neovim
release, on Linux against 0.10.4 and 0.11.5 as well, plus an advisory run
against nightly. The four are not arbitrary: 0.10 is the floor
`:checkhealth dotfiles` claims, and the compatibility shims in `util.text` and
`util.vcs_ui` switch behaviour at 0.10, 0.12 and 0.13, so each of those
boundaries has a run either side of it.

All of it is one command — `tests/check-nvim.sh`, or `--all` to include the
three that need the plugins installed — which is what to run on a change to
`lua/`. Individually:

```bash
tests/run-nvim-specs.sh
```

The specs. Plugin-free and hermetic — no network, no `~/.local/share/nvim`, no
system clipboard; each builds what it needs in a tempdir, which is also why
they can run several at a time — the whole suite in about a third of the wall
clock, with output still printed in file order (`NVIM_SPECS_JOBS=1` for
serial). Blocks that need jj,
Mercurial or ripgrep skip when the tool is missing, which is right on a laptop
and wrong in CI: CI installs all three and sets `NVIM_CHECKS_NO_SKIP=1`, which
turns a skip into a failure so a backend cannot quietly stop being covered.

* `nvim_vcs_spec.lua` — the backends, against throwaway git, jj and Mercurial
  repositories: renames, paths with spaces and non-ASCII characters, deleted and
  untracked files, an empty repository, detached HEAD. Perforce runs against a
  stub `p4` binary that speaks the real `-ztag` protocol, which is how that
  backend is covered without a server.
* `nvim_conflict_spec.lua` — every conflict shape and choice, including
  `merge` style with no base section, multiple and adjacent conflicts,
  conflicts spanning the whole file, unlabelled markers, and near-miss text
  (C++ templates full of angle brackets) that must *not* parse as a marker.
* `nvim_vcs_ui_spec.lua` — window layout, which buffer lands in which pane,
  scrubbing, the inline toggle, the diff-tab lifecycle, an edited preview
  earning its place in the buffer list, and the degenerate cases (no changes,
  no repository).
* `nvim_inline_diff_spec.lua` — the editable overlay: extmark placement at the
  awkward spots, hunk navigation, revert for every hunk shape.
* `nvim_chromium_spec.lua` — compdb freshness, build-dir selection and the
  bundled-clangd flow, against a stubbed checkout.
* `nvim_health_spec.lua` — `:checkhealth dotfiles` against a PATH built per
  case: nothing installed, git with and without a TUI, SSH with and without the
  OSC clipboard helpers, a configured clipboard provider whose binary is
  missing, and a checkout whose version-control client is not installed.
* `nvim_text_spec.lua` — the `vim.diff` → `vim.text.diff` shim, and a sweep of
  the whole Lua tree for APIs Neovim has already deprecated.
* `nvim_ripgrep_spec.lua` — the Neovim-filetype → ripgrep-type translation
  behind `<leader>st`, including its alias table against a real `rg`.
* `nvim_clipboard_spec.lua` — yank and paste round-trips through a fake tmux
  and the OSC 52 helpers.
* `nvim_vcs_pathological_spec.lua` — the diff UI against what a real checkout is
  full of: binaries, a quarter-megabyte line, CRLF from a Windows branch, no
  trailing newline, a deleted file, paths with spaces and non-ASCII characters.
  Also the "leaves no trace" promise — at most one looked-at file loaded at a
  time — and the view driven at random without letting its async work finish.
* `nvim_config_spec.lua` — the parts of `lua/config/` that are logic rather
  than wiring: how a key press is reported; the stop chain (debug session, then
  a running Overseer task, then the CMake build, then say so); reading
  `.vscode/launch.json`, including one that does not parse; and the argv
  "reveal in file manager" builds on each platform.

```bash
tests/check-nvim-keymaps.sh      # needs the plugins installed
tests/check-nvim-syntax-roles.sh # also needs the tree-sitter parsers
tests/check-nvim-types.sh        # needs lua-language-server
python3 tests/check-footpedal-keys.py
```

The checks that need the config as actually assembled. `check-nvim-keymaps.sh`
invokes every binding inside a throwaway repository — callback maps must not
raise even with no language server and no debug session attached, since
degrading with a message is fine and throwing is not — and asserts that every
`<leader>` key in the tables above is really mapped, so this document cannot
promise a binding that does not exist. `check-nvim-syntax-roles.sh` checks C++
and Python colour the same construct the same way. `check-nvim-types.sh` runs
lua-language-server over the config and must report zero problems at Hint, the
strictest level it has; CI pins the version it installs.
`check-footpedal-keys.py` drives Shift+Fn through a real terminal into a real
Neovim.

```bash
tests/bench-nvim-vcs.sh [files]
```

Not a check: what the changed-files view costs on a listing the size a rebase
or a generated-code change produces. Three numbers — time to first paint, time
until the background base prefetch has finished, and forty files of scrubbing —
because only the first is time anyone waits. On a 3000-file listing the list is
readable in a couple of hundred milliseconds and scrubbing stays in single-digit
milliseconds while the prefetch is still running behind it. CI prints this
beside the startup cost and never gates on it; a shared runner cannot be
budgeted against.

## Backend notes

* **git** — the "fork point" base is the merge base with `@{upstream}`, then
  `origin/HEAD`, then `origin/main` / `origin/master` / `main` / `master`,
  matching what `common/.local/bin/git-diff-from-last-branch` does in the shell.
  The changed-file list is read `-z`, so a filename containing a tab, a quote,
  a backslash or a newline arrives as itself rather than C-quoted. Paths are
  handed to git as `:(literal)` pathspecs: without that, `*`, `?`, `[` and a
  leading `:` are pattern syntax, so staging `star*.txt` would stage every file
  the glob matched and `:notes.txt` could not be named at all. A rename is one
  row carrying its old path, and staging or reverting it names both halves.
  While a merge, rebase or cherry-pick is unfinished, unmerged paths are marked
  `!` rather than reading as ordinary modifications, which is what git's
  changed-file list calls them. That costs an extra command, so it is asked for
  only when a marker file in the git directory says a conflict is in progress —
  a stat rather than a process on every refresh.
* **jj** — calls that ask what the working copy looks like *now* (`diff`,
  `log`) let jj snapshot, because in jj the working copy is a commit and
  `jj status` snapshots as a matter of course. Suppressing it with
  `--ignore-working-copy` means every edit made since the last jj command is
  invisible, which is a correctness bug, not a courtesy — an earlier version did
  this and reported "no changes" for work that was right there. Calls that only
  read committed history (`root`, `show`, trunk resolution) still skip the
  snapshot, which keeps scrubbing cheap. The fork-point base is
  `latest(::@ & trunk())`, falling back to `@-` when the repo has no trunk or
  when trunk degrades to the root commit. The changed-file list comes from
  `jj diff -T`, whose template prints the source and target paths verbatim;
  `--summary` compacts a rename into a single `src/{a.txt => b.txt}` string that
  no filename containing `{` or ` => ` can be recovered from, and that form is
  only used as a fallback for a jj too old to know the template. Path arguments
  are quoted `root:` filesets, since jj parses them as fileset *expressions* —
  `report (1).pdf` is otherwise a syntax error rather than a path. A conflicted
  file is marked `!` from the same template, which already knows: in jj a
  conflict lives in the commit rather than in the working copy.
* **Perforce** — `p4` and `g4` are the same code path; `g4` is tried first. The
  root comes from `$P4CONFIG` if set, otherwise `p4 info`'s client root. Every
  scope compares against each file's synced (`#have`) revision, since Perforce
  has no fork-point notion. `p4 where` is asked once for the whole changelist,
  not once per file, which on a real changelist is the difference between one
  round trip and hundreds. A `p4 move` opens the pair as `move/add` and
  `move/delete`, which map to renamed and deleted. It is the one backend that
  does not mark conflicts: `p4 resolve -n` is a server round trip, and unlike
  the other three there is no local marker to gate it behind. **This backend has no live
  server to test against**, so the spec drives it through a stub that speaks the
  documented `-ztag` protocol; git, jj and Mercurial are tested against real
  repositories, and CI installs all three so those blocks cannot silently skip.
* **Mercurial** — `hg status -C` is what makes a rename arrive as one row
  carrying its old path rather than an unrelated add plus a delete, and `-0`
  keeps a filename containing a newline from splitting into two rows. Path
  arguments go through `path:`, since hg reads them as patterns and a leading
  `glob:` / `re:` / `set:` selects the pattern *type*. The fork-point base is
  `ancestor(., default)`, falling back to `main` and `master` for repositories
  driven by bookmarks, and to the working parent when trunk is what is checked
  out. Unresolved paths are marked `!`, asked for with `hg resolve --list` only
  when `.hg/merge` says a merge is in progress.
