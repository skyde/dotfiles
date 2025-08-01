# Neovim as a Git Mergetool – Efficient Merge Conflict Resolution Guide

## Setting Up Neovim as Your Git Mergetool

To use Neovim for resolving Git merge conflicts, configure Git to launch Neovim with Fugitive for a 3-way diff. Add this to `~/.gitconfig`:

```ini
[mergetool "nvim"]
    cmd = nvim -f -c "Gdiffsplit!" "$MERGED"
[merge]
    tool = nvim
[mergetool]
    prompt = false
```

Running `git mergetool` will open Neovim in diff mode showing the local, merged and remote buffers.

## 3-Way Merge Workflow with Diff Mode

1. Open the diff splits via `git mergetool` or `:Gvdiffsplit!`.
2. Jump between conflicts with `]c` and `[c`.
3. Use `dp` in a side window to put that hunk into the result.
4. Or from the result window, run `:diffget //2` or `:diffget //3` to pull from the other buffers.
5. Repeat until all conflict markers are gone, then save and quit.
6. To accept one side entirely, run `:Gwrite!` in that buffer.
7. Stage and commit the file when done.

## Resolving Conflict Markers Inline

Plugins like `git-conflict.nvim` or `conflict-marker.vim` highlight conflict markers and provide single-key choices:

- **Ours** – `co`
- **Theirs** – `ct`
- **Both** – `cb`
- **None** – `cn`

Navigate markers with `[x` and `]x`, resolve them, then save.

## Visual Merge Workflow with Diffview.nvim

`diffview.nvim` offers a merge tool UI listing conflicted files and opening a 3-way diff per file. Use its shortcuts to pull hunks from either side or accept entire versions. When all conflicts are resolved, close Diffview and commit.

## Best Practices

- Consider enabling Git's `diff3` style for more context.
- Disable LSP diagnostics while merging to reduce noise.
- Customize highlights so conflict regions stand out.
- Use quickfix lists or Diffview's file panel to manage many files.
- Create custom keymaps that suit your workflow.
- Practice on mock conflicts to learn the commands.
- Review changes with `git diff --staged` before committing.

Using Neovim with these plugins makes resolving merge conflicts fast and efficient entirely within the editor.
