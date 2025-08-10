# Neovim as a Git Mergetool – Efficient Merge Conflict Resolution Guide

## Setting Up Neovim as Your Git Mergetool

Current state: Fugitive and Diffview are not enabled in this Neovim config, and git-conflict.nvim is commented out. The instructions below use stock Neovim diff mode and work without plugins.

Add this minimal mergetool config to `~/.gitconfig` to use plain diff mode:

```ini
[mergetool "nvim"]
    cmd = nvim -f -d "$LOCAL" "$MERGED" "$REMOTE"
[merge]
    tool = nvim
[mergetool]
    prompt = false
```

This opens the MERGED buffer and shows LOCAL and REMOTE in diff splits. If you later enable Fugitive, you can switch to `Gdiffsplit!` in the cmd above.

## 3-Way Merge Workflow with Diff Mode (no plugins)

1. Open the diff splits via `git mergetool`.
2. Jump between changes with `]c` and `[c`.
3. To take a hunk from a side into MERGED:
    - Focus the side window (LOCAL or REMOTE) and press `dp` to put that hunk into MERGED, or
    - From MERGED, focus a side window briefly, then return to MERGED and press `do` to get the hunk from the last focused side.
4. Repeat until all conflict markers are gone, then save and quit (`:wq`).
5. To accept an entire side, in the side window do `ggVG` then `:diffput` to replace MERGED with that version.
6. Stage and commit the file when done.

## Resolving Conflict Markers Inline

Optional: `git-conflict.nvim` can provide single-key choices, but it is currently disabled in this config. If enabled, you’ll get mappings like:

- Ours – `<leader>co`
- Theirs – `<leader>ct`
- Both – `<leader>cb`
- None – `<leader>c0`

Plus navigation: `[x` and `]x`.

## Visual Merge Workflow with Diffview.nvim

Diffview is not enabled right now. If you enable `sindrets/diffview.nvim`, you can use `:DiffviewOpen` for a richer UI.

## Best Practices

- Consider enabling Git's `diff3` style for more context.
- Disable LSP diagnostics while merging to reduce noise.
- Customize highlights so conflict regions stand out.
- Use quickfix lists or Diffview's file panel to manage many files.
- Create custom keymaps that suit your workflow.
- Practice on mock conflicts to learn the commands.
- Review changes with `git diff --staged` before committing.

Using Neovim with these plugins makes resolving merge conflicts fast and efficient entirely within the editor.
