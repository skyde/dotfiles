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
| `<leader>gc` | focus SCM view | changed files, uncommitted — list on the left, live diff on the right |
| `<leader>gD` | `gitTreeCompare.openAllChanges` | changed files since the fork point with trunk |
| `<leader>gC` | `gitTreeCompare.changeBase` | changed files against a revision you type |
| `<leader>gR` | refresh SCM | refresh the list |
| `<leader>gd` | `git.openChange` | diff the current file against its last committed version |
| `<leader>ga` | `git.viewChanges` | diff the current file against the fork point |
| `<leader>gp` | `git upstream-diff` in a terminal | uncommitted patch, delta-coloured |
| `<leader>gA` | `diff-branch` in a terminal | full patch since the fork point, delta-coloured |
| `<leader>gy` | Copy Git Diff task | copy that patch to the clipboard |
| `<leader>gl` | `git log -p` on the file | revision history of the current file; pick one to diff against |
| `<leader>gw` | `git.openFile` | from a diff, open the real file on disk at the same line |
| `<leader>gg` | LazyGit task | backend-appropriate TUI (`lazyjj`/`jjui` under jj, otherwise LazyGit) |

Commands do the same without leader keys: `:VcsChanges [working|branch|head]`,
`:VcsDiff`, `:VcsPatch`, `:VcsHistory`, `:VcsInfo`.

### Inside the changed-files view

| Key | Action |
| --- | --- |
| `j` / `k` | move through files, re-rendering the diff as you go |
| `<CR>` / `o` / `<Tab>` | move focus into the diff |
| `s` | cycle scope: uncommitted → since fork point → last commit |
| `i` | toggle inline / side-by-side |
| `R` | refresh |
| `q` | close |

The right-hand side has two renderings. Side-by-side is native diff mode, so
`]c` / `[c` / `do` / `dp` work and the right pane is the real file — edits go to
disk. `<leader>ci` switches to the inline rendering, the unified patch piped
through `delta`, matching `diffEditor.renderSideBySide: false` in the VS Code
config.

Neovim's `diffopt` is set in `lua/config/options.lua` to the same algorithm and
context as `common/.config/git/config`, so a diff reads the same in the editor
as in the terminal.

### Diff and merge conflicts

Conflict handling is marker-based (`lua/util/conflict.lua`), not git-based, so
it works in every backend and on files handed over by any other tool.

| Key | VS Code | Neovim |
| --- | --- | --- |
| `]c` / `[c` | next/prev change | next/prev change — diff hunk, conflict, or gitsigns hunk, whichever the buffer has |
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

## Backend notes

* **git** — the "fork point" base is the merge base with `@{upstream}`, then
  `origin/HEAD`, then `origin/main` / `origin/master` / `main` / `master`,
  matching what `common/.local/bin/git-diff-from-last-branch` does in the shell.
* **jj** — every read-only call passes `--ignore-working-copy`, so opening a
  diff never snapshots the working copy behind your back. The fork-point base is
  `latest(::@ & trunk())`, falling back to `@-` when the repo has no trunk.
* **Perforce** — `p4` and `g4` are the same code path; `g4` is tried first. The
  root comes from `$P4CONFIG` if set, otherwise `p4 info`'s client root. Every
  scope compares against each file's synced (`#have`) revision, since Perforce
  has no fork-point notion. **This backend is written to the documented p4 CLI
  but has not been exercised against a live server** — the git and jj paths
  have.
* **Mercurial** — included because it was nearly free once the interface
  existed.
