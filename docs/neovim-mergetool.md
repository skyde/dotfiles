# Resolving merge conflicts in Neovim

`common/.config/git/config` sets `merge.tool = nvim` and `diff.tool = nvim`, so
`git mergetool` and `git difftool` open Neovim. `git mergetool -g` and
`git difftool -g` still open VS Code via the `guitool` settings.

Conflict handling lives in `lua/util/conflict.lua` and is driven off the
`<<<<<<< / ||||||| / ======= / >>>>>>>` markers rather than off git, so the same
keys work under jj and Perforce, and on a file some other tool left conflicted.
`merge.conflictstyle = zdiff3` means the base section is usually present, which
is why "take the base" is one of the choices.

## The loop

```bash
git mergetool
```

Neovim opens on `$MERGED` — the file with the markers in it. Conflict regions
are highlighted as you edit: ours in the add colour, base in the change colour,
theirs in the text colour.

| Key | Action |
| --- | --- |
| `]x` / `[x` | next / previous conflict (wraps) |
| `<leader>co` / `<leader>cO` | take ours, here / everywhere in the file |
| `<leader>ct` / `<leader>cT` | take theirs, here / everywhere |
| `<leader>cb` / `<leader>cB` | take both, here / everywhere |
| `<leader>c0` | take neither |
| `<leader>cm` | open the three-way view |
| `<leader>cq` | save and close |

Each resolution reports how many conflicts are left. `<leader>cq` refuses to
close while any remain, so you cannot commit a file with markers still in it by
accident.

## The three-way view

`<leader>cm` splits the file into **ours │ working │ theirs**, all in diff mode.
The outer panes are reconstructions — the file as it would read if every
conflict went that way — so they need no index access and work in any backend.

The middle pane is the real buffer. Resolve there with the keys above, or pull
a hunk across from a side pane with `dp`, or from the middle with `do`. The
whole-file keys (`<leader>cO` / `cT` / `cB`) work from any pane — they do not
depend on the cursor, so they always act on the middle one. `]c` / `[c` move
between hunks. `<leader>cc` jumps to the other side.

`<leader>cq` saves and closes the view. It asks the middle pane, not whichever
one the cursor is in — the side panes have no markers left in them by
construction, so from either of them the answer would always be "nothing left to
resolve".

## Reviewing before you commit

`<leader>gc` opens the changed-files view; `s` inside it cycles between
uncommitted changes, everything since the fork point, and the last commit. See
[`nvim-vscode-parity.md`](nvim-vscode-parity.md) for the full set.

## If you would rather have three windows from the start

```bash
git mergetool -t nvimdiff3
```

That opens `LOCAL | MERGED | REMOTE` as separate files in diff mode — the
classic layout, with `dp` / `do` and no marker keys.
