# lazygit

`common/.config/lazygit/config.yml` is the whole configuration; every platform
links to that one file (see [Where the config lives](#where-the-config-lives)).
It targets **lazygit 0.64+**, which `./install-lazygit.sh` installs.

Two things about lazygit shape everything below:

1. **It ignores configuration it does not understand.** A key that was renamed,
   sits at the wrong nesting level, or is misspelled produces no error — the
   feature just silently stops happening. `git.pagers` (renamed to
   `git.diffRenderers` in 0.64), a top-level `scrollOffBehavior` (it belongs
   under `gui:`), `gui.theme.lightTheme` and `promptToOpenMergeTool` were all
   sitting in this file doing nothing before `./tests/check-lazygit-config.sh`
   existed. **Run that after any edit.**
2. **Custom commands are shell, run through Go templates.** Quoting mistakes
   surface as an empty argument rather than an error, which is why the checker
   parses every command with `sh -n`.

## Rendering

| Piece | Where it comes from |
| --- | --- |
| Chrome (borders, selection, branch colours) | `gui.theme` here — Tokyo Night, [`docs/tokyonight.md`](tokyonight.md) |
| Whether those hexes arrive exactly | `COLORTERM=truecolor`, which `.tmux.conf` sets — lazygit reads that, not terminfo |
| Diff colours and layout | delta, configured in `common/.config/git/config` |
| Syntax highlighting inside diffs | `BAT_THEME` (Visual Studio Dark+), via delta |

`|` cycles the diff renderer, `\` cycles back. Five are configured:

| Renderer | What it is for |
| --- | --- |
| `delta` | the default: delta with lazygit's paging off and clickable line numbers |
| `delta side-by-side` | two-column, for moved blocks and reindents (`git sbs` is the CLI equivalent) |
| `difftastic` | structural diff — tells a rename from a rewrite. Needs `./install-difftastic.sh` |
| `word-diff` | `git diff --color-words`, for prose and long single lines |
| `raw git` | no renderer at all, for when the question is what git actually said |

`{` and `}` change the diff context size live, and difftastic follows along —
its renderer entry passes lazygit's current value through `{{diffContext}}`.
The starting value is `git.diffContextSize: 10`, matching `diff.context` in the
git config so the TUI and the command line show the same amount of code.

Clicking a line number in a delta diff opens that line in Neovim: delta emits
`lazygit-edit://` hyperlinks and lazygit resolves them through `os.editPreset`.
This needs a terminal that supports OSC 8 hyperlinks (kitty and WezTerm here).

## Keys added on top of the defaults

Everything lazygit binds by default still applies — `?` lists them in context.
These are the additions and the two changes:

| Key | Context | Action |
| --- | --- | --- |
| `u` / `U` | everywhere | undo / redo (vim's `u`; `U` because lazygit has spent `<ctrl+r>` on "recent repos") |
| `Z` | everywhere | stash snapshot: saves a stash entry *and keeps the worktree*, so it is a save point rather than an interruption |
| `<ctrl+n>` | files | conventional commit — type, optional scope, breaking-change marker, subject |
| `Y` | commits | copy the diff of the selected commit(s) to the clipboard |
| `y` | branches | copy the branch name to the clipboard |
| `X` | everywhere | the extras menu, below |

### The extras menu (`X`)

Entries only appear where they apply, so the menu is short wherever you open it.

| Key | Context | Action |
| --- | --- | --- |
| `b` | files | blame the selected file, paged through delta (which paints blame too) |
| `h` | files | full history of the selected file, following renames |
| `d` | anywhere | diff the working tree against the *nearest* branch point — another local branch or `origin/main`, whichever is closer (`git-diff-from-last-branch`) |
| `c` | anywhere | copy that same diff to the clipboard |
| `s` | anywhere | which commit added or removed this string (`git log -S`) — the search lazygit's own filtering (`<ctrl+s>`, path and author) cannot do |
| `w` | branches | add a worktree for the selected branch |
| `p` | anywhere | prune stale worktrees and remote-tracking branches |
| `D` | branches | delete local branches already merged into a chosen base |
| `u` | anywhere | remove stale `.git` lock files (`git-unlock`) |
| `m` | anywhere | run `git maintenance` now |

Clipboard actions go through `osc-copy`, so they work over ssh and inside tmux
without a local clipboard tool — the same OSC 52 path Neovim uses.

### Commit messages

On a branch named `ABC-123-thing` or `feature/ABC-123-thing`, the commit message
box starts pre-filled with `ABC-123: `. Branches that do not start with a ticket
id are unaffected (`git.commitPrefix`).

## Behaviour worth knowing

- **Auto-fetch runs every 3 minutes, from `origin` only** (`refresher.fetchInterval`,
  `git.fetchAll: false`). The defaults — every 60s, `--all` — are a lot of work
  in a repository the size of Chromium, for an answer that rarely changes that
  fast.
- **Branches sort by when you last used them**, not by commit date
  (`git.localBranchSortOrder: recency`).
- **The branches panel marks how far behind the base branch each branch is**, as
  `↓12` (`gui.showDivergenceFromBaseBranch`) — the number that says a rebase is
  due. Behind only, measured against `origin/main` when that exists, and filled
  in by a background worker a moment after the panel paints.
- **`/` filters fuzzily**, so `cfgyml` finds `common/.config/lazygit/config.yml`.
- **Panel jump keys cycle tabs**: `2` `2` reaches Worktrees, `3` `3` Remotes.
- **`a` in the status panel cycles two graph commands**: the full graph, then a
  `--simplify-by-decoration` overview that stays readable in a huge repository.
- **`o` (open in browser) works over ssh**: `os.openLink` goes through
  `tmux-open-helper.sh`, which hands the URL to VS Code Remote's browser bridge
  so it opens on the machine in front of you, and copies it over OSC 52 when
  there is no bridge. The default, `xdg-open`, has nothing to open it with on a
  headless box.

- **Chromium-shaped files get their own icons**: `BUILD.gn`, `DEPS`, `OWNERS`,
  `*.gni`, `*.mojom` and `*.grd` all fall back to lazygit's generic file glyph
  otherwise, which makes a Chromium tree one repeated icon (`gui.customIcons`).

## Per-repository overrides

Settings in `<repo>/.git/lazygit.yml` win over this file, and a `.lazygit.yml`
in any parent directory of a repository applies to everything beneath it. That
is the place for anything a single tree needs — a repository big enough that
`git status` on a timer is felt, for instance:

```yaml
# <chromium>/src/.git/lazygit.yml
refresher:
  refreshInterval: 30 # git status on a huge tree, less often
  fetchInterval: 600
git:
  # the delta pass over a very large diff is the slow part; raw git is instant
  diffRenderers:
    - type: rawGit
      name: raw git
    - name: delta
      command: delta --dark --paging=never --tabs=4
```

## Where the config lives

lazygit looks for `jesseduffield/lazygit/config.yml` first and then
`lazygit/config.yml`, in the XDG config home and then the XDG config dirs. That
resolves differently per platform, so each platform's package carries a link
back to the one real file:

| Platform | Path | Comes from |
| --- | --- | --- |
| Linux | `~/.config/lazygit/config.yml` | the `common` package (the file itself) |
| macOS | `~/Library/Application Support/lazygit/config.yml` | the `mac` package (`~/.config` is searched too, but last) |
| Windows | `%APPDATA%\lazygit\config.yml` | the `windows` package |

`~/Library/Application Support/jesseduffield/lazygit/config.yml` is also linked:
it is lazygit's legacy path, still searched first, and pointing it at the same
file keeps an older install from reading something stale.

Per-repository overrides go in `<repo>/.git/lazygit.yml`, and a `.lazygit.yml`
in any parent directory of a repository applies to everything beneath it —
useful for one client's monorepo without touching this file.

Editing the config in VS Code gets completion and error checking: the first line
is a `yaml-language-server` schema comment (with the Red Hat YAML extension
installed).

## Checking the config

```sh
./tests/check-lazygit-config.sh            # after any edit
./tests/check-lazygit-config.sh --strict   # also fail on warnings
```

It validates against the JSON schema published for the *installed* lazygit
version (cached under `~/.cache/dotfiles`, downloaded once), and falls back to
comparing key paths against `lazygit --config` when offline. On top of the
schema it checks the things the schema cannot express: custom-command contexts,
`{{.Selected...}}` placeholders against lazygit's actual model fields, `{{.Form.X}}`
against the prompts that define them, keybinding names, key collisions, and
whether every command parses as shell. It also warns when a custom command
shadows a built-in binding, and when a configured diff renderer is not installed.

The checker runs its own self-test first, because a validator that has quietly
stopped validating looks exactly like a config with no problems.

## Neovim and tmux

`<leader>gg` opens lazygit inside Neovim through snacks, which layers a second
config file on top of this one (`LG_CONFIG_FILE` holds both). It sets two
things: a theme generated from the current colorscheme — so the chrome follows
the editor rather than this file when opened that way — and
`os.editPreset: nvim-remote`, so `e` opens the file in the Neovim you came from
instead of a nested one. Everything else — keys, custom commands, diff
renderers, git behaviour — is this config either way.

tmux-resurrect restores lazygit panes (`@resurrect-processes` in `.tmux.conf`).

`LAZYGIT_KEYBINDING_PLATFORM=darwin` makes a Linux box use the macOS default
bindings, which is worth knowing when ssh-ing into a remote machine from a Mac.
