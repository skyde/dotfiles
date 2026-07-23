# Neovim source-control and merge workflow

Neovim uses Diffview+ as one consistent review surface for Git, Jujutsu, and
Perforce-compatible clients. The Perforce adapter runs `vcs-p4`, which prefers
`g4` when it is installed and otherwise runs `p4`. Set `NVIM_PERFORCE_CMD` to
override that choice.

## Everyday review

`<leader>gc` is the main entry point. It opens the working-copy changes panel;
if a Diffview is already open, it focuses that panel instead. Move with `j` and
`k` to preview changed files immediately.

| Key | Action |
| --- | --- |
| `<leader>gg` | LazyGit at the project root |
| `<leader>gc` | Working-copy changes |
| `<leader>gd` | Diff the current file |
| `<leader>gD` | Diff the branch/change against its base |
| `<leader>gC` | Enter a comparison revision or range |
| `<leader>ga` | Current file's latest working change |
| `<leader>gl` / `<leader>gL` | File / repository history |
| `<leader>gr` | Choose Git, JJ, or Perforce/G4 for this session |
| `<leader>gR` | Refresh the current view |
| `<leader>gy` | Copy the branch/change diff |
| `<leader>gw` | Open the selected worktree file and close the diff |
| `<leader>gq` | Close Diffview |
| `<leader>g?` | Show the detected backend, root, and comparison base |

Diffs start in a VS Code-like inline view. Within a Diffview:

- `<leader>ci` cycles inline, horizontal, and vertical layouts.
- `Alt+Down` / `Alt+Up` move between changes or merge conflicts.
- `<leader>cv` reverts the selected inline hunk.
- `s`, `S`, and `U` stage/unstage in Git views only.
- `q` closes the view while the file panel is focused.

Git defaults to the remote's default branch, then `origin/main`,
`origin/master`, `main`, or `master`. `<leader>gp` separately compares against
the tracking branch for the next upstream patch. JJ defaults to `trunk()` and
uses the working change's parent for `<leader>gp`. `<leader>gC` changes the base
for the current repository until Neovim exits.

## External diff and merge tools

The Git config uses the included `nvim-diff` and `nvim-merge` launchers, so
`git difftool` and `git mergetool` open the same interface. The old `vscode`
tools remain available explicitly with `git difftool --tool=vscode` or
`git mergetool --tool=vscode`.

JJ is configured with matching `diffview` diff and merge editors:

```sh
jj diff --tool diffview
jj resolve --tool diffview
```

Shell profiles export `P4DIFF=nvim-diff` and `P4MERGE=nvim-p4merge` when the
launchers are installed. Helix/P4 passes merge inputs as base, theirs, yours,
and output; `nvim-p4merge` translates that order for Diffview.

## Conflict-marker workflow

When a normal buffer contains conflict markers, `git-conflict.nvim` adds
buffer-local mappings:

| Key | Action |
| --- | --- |
| `<leader>co` | Accept ours |
| `<leader>ct` | Accept theirs |
| `<leader>ca` | Accept both |
| `<leader>c0` | Accept neither |
| `]x` / `[x` | Next / previous conflict |

The mappings are local to conflicted buffers, so `<leader>ca` remains the LSP
code-action mapping everywhere else.

## Perforce and G4 notes

Diffview+'s P4 support is experimental and needs a configured client/workspace.
Use `<leader>gr` to force the Perforce adapter in a colocated checkout. To force
a particular executable:

```sh
export NVIM_PERFORCE_CMD=p4   # or an absolute g4/p4-compatible executable
```

Review the resolved output file and use `:wqa` to accept it. Use `:cq` to abort
with a failing editor exit code. Git, JJ, or P4/G4 resumes after Neovim exits.
