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
| `<leader>gc` | focus SCM view | changed files, uncommitted — list on the left, live diff on the right; pressing it again from inside closes the view, like the VS Code sidebar |
| `<leader>gD` | `gitTreeCompare.openAllChanges` | changed files since the fork point with trunk (also a toggle) |
| `<leader>gC` | `gitTreeCompare.changeBase` | changed files against a revision you type |
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
edge. Status letters (`M` `A` `D` `R` `?` `!`) sit in the left column,
renamed files read `new ← old`, and the header tracks the selection as
`file 3 of 12`.

| Key | Action |
| --- | --- |
| `j` / `k` | move through files (stepping over directory rows), re-rendering the diff as you go |
| `<CR>` / `o` / `l` / `<Right>` / `<Tab>` | move focus into the diff (`<Space>` stays leader, so it cannot be the select key) |
| `J` / `K` | scroll the diff half a page from the list, for skimming a file without leaving it |
| `]f` / `[f` | from *inside* the diff: render the next / previous file, focus staying in the diff |
| `s` | cycle scope: uncommitted → since fork point → last commit |
| `i` | toggle inline / side-by-side |
| `a` | stage / unstage the file, where the backend has an index (git) |
| `X` | revert the file to its base version, after a confirm; on an added or untracked file this deletes it |
| `m` | open the three-way merge view for a conflicted file; `<leader>cq` there drops back into this view |
| `R` | hard refresh: re-ask the backend for everything |
| `q` | close — also from a scratch diff pane |
| `?` | cheat sheet of these keys |

The listing also revalidates itself in the background whenever you come back
to the tab (or to Neovim), so a commit made in a terminal does not leave the
view describing a world that no longer exists.

The right-hand side has two renderings, and the choice is remembered across
opens. **Inline is the default**, matching `diffEditor.renderSideBySide:
false` in the VS Code config — and like that editor it is the **real,
editable file**: the base version's missing lines are drawn between the lines
in red, new lines are highlighted green, and the overlay follows as you type.
`]c` / `[c` walk the changes, `<leader>cv` reverts the change under the
cursor. Untracked files read as a whole-file add, deleted files show their
old content struck red. `i` in the panel (or `<leader>ci` anywhere) switches
to side-by-side: native diff mode, so `]c` / `[c` / `do` / `dp` work and the
right pane is the real file. The delta-rendered unified patch is still there
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

Rendering a diff costs a subprocess, so `j` / `k` move the cursor immediately
and the diff follows once the keys stop (80 ms). Holding `j` through a
400-file changelist costs one render rather than four hundred. `<CR>`
pre-empts the wait and renders at once.

Everything the backend says is remembered across opens of the view: the
listing per scope and the base content per file. Reopening `<leader>gc` in a
large or server-backed repository (Perforce especially) paints instantly from
the last known state, the header shows "refreshing…" while a background pass
revalidates, and the panel only redraws if something actually changed. Base
content for listed files is prefetched in the background — one subprocess at
a time, starting from the cursor — so scrubbing lands on warm content; a file
whose base is still cold renders asynchronously instead of freezing the list.
`R` distrusts all of it and re-asks the backend from scratch.

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
| `<leader>ce` | code action (LazyVim also keeps `<leader>ca`) |
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
| `<leader>uw` `<leader>uz` `<leader>uc` `<leader>uh` | wrap / zen / whitespace / inlay hints |
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

Three specs, no plugins needed, each self-contained:

* `nvim_vcs_spec.lua` — the backends, against throwaway git and jj
  repositories: renames, paths with spaces and non-ASCII characters, deleted and
  untracked files, an empty repository, detached HEAD. Perforce runs against a
  stub `p4` binary that speaks the real `-ztag` protocol, which is how that
  backend is covered without a server.
* `nvim_conflict_spec.lua` — every conflict shape and choice, including
  `merge` style with no base section, multiple and adjacent conflicts,
  conflicts spanning the whole file, unlabelled markers, and near-miss text
  (C++ templates full of angle brackets) that must *not* parse as a marker.
* `nvim_vcs_ui_spec.lua` — window layout, which buffer lands in which pane,
  scrubbing, the inline toggle, the diff-tab lifecycle, and the degenerate cases
  (no changes, no repository).

```bash
tests/check-nvim-keymaps.sh
```

Invokes every binding against the real config inside a throwaway repository.
Callback maps must not raise even with no language server and no debug session
attached — degrading with a message is fine, throwing is not.

Neither is wired into CI; they are run by hand, like `nvim_clipboard_spec.lua`.

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
