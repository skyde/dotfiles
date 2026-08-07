# The shell

Interactive zsh, with no plugin manager and no framework. Two files:

| File            | Read by                | Holds                                                      |
| --------------- | ---------------------- | ---------------------------------------------------------- |
| `~/.zshenv`     | **every** zsh          | `PATH`, `EDITOR`, pager, ripgrep and bat settings, `DISPLAY` |
| `~/.zshrc`      | interactive shells     | options, key bindings, completion, prompt, tools, plugins   |

Anything a script or a non-interactive `zsh -c` needs belongs in `.zshenv`.
That is not a style preference: `.zshrc` is *not read* by those shells, so an
`EDITOR` set there is invisible to `git commit` run from a script.

`~/.config/shell/theme.sh` is sourced by both `.zshenv` and `.bashrc-custom` and
holds what the two shells must agree on — fzf's colours, what Ctrl-T lists, how
previews are rendered. See [tokyonight.md](tokyonight.md) for the palette.

Machine-specific additions go in `~/.zshrc.local`, which is sourced last if it
exists and is not part of this repository.

## Keys

Everything below is exercised by [`tests/zsh_keys_spec.zsh`](../tests/zsh_keys_spec.zsh)
and [`tests/zsh_completion_spec.zsh`](../tests/zsh_completion_spec.zsh), which
press the key in a real terminal and read the command line back.

### Moving and editing

| Key                | Does                                                       |
| ------------------ | ---------------------------------------------------------- |
| `Home` / `End`     | start / end of line (both terminal modes bound)            |
| `Delete`           | delete the character under the cursor                      |
| `Ctrl-←` / `Ctrl-→` | back / forward one word                                   |
| `Ctrl-W`           | delete the previous word — one path component at a time    |
| `Ctrl-_`           | undo                                                       |
| `Ctrl-G`, `Ctrl-X Ctrl-E` | open the current line in `$EDITOR`                   |
| `Alt-S`            | add `sudo` to the front of the line, or take it off        |
| `Ctrl-Z`           | at an empty prompt, return to a suspended job              |

`Ctrl-W` stopping at `/` and `=` is a deliberate change to `WORDCHARS`. The
default counts both as part of a word, so `Ctrl-W` on a long path deleted all of
it.

`Alt-S` on an empty line recalls the last command first, so the whole recovery
from a permission error is `Alt-S`, `Enter`.

### History

| Key                | Does                                                          |
| ------------------ | ------------------------------------------------------------- |
| `↑` / `↓`          | walk the history — **filtered by what is already typed**      |
| `Ctrl-P` / `Ctrl-N` | the same                                                     |
| `Ctrl-R`           | fuzzy history search, syntax-highlighted, with a preview      |
| `Ctrl-S`           | inside `Ctrl-R`: toggle sorting (walk back through time instead) |
| `Ctrl-/`           | inside any picker: toggle the preview pane                    |

Type `git com` and press `↑`: only the git commits come back. With nothing typed
it is the ordinary history walk.

The `Ctrl-R` picker dedupes, ranks by match quality with recency as the
tiebreak, and highlights the list with the same `bat` theme as everything else.
It is bound *after* fzf's own history widget so this one wins.

### Finding things

| Key                | Does                                                       |
| ------------------ | ---------------------------------------------------------- |
| `Ctrl-T`           | pick a path and paste it onto the line                     |
| `Alt-C`            | pick a directory and cd into it                            |
| `**` then `Tab`    | fuzzy-complete the current argument                        |
| `Tab`              | completion (below)                                         |
| `Shift-Tab`        | walk back up the completion menu                           |

`Ctrl-T` and `Alt-C` list through `fd` — hidden files included, `.git`
excluded — and preview through `~/.local/bin/fzf-preview`, which renders a
directory as a shallow tree, a text file through `bat`, an image through `chafa`
where it exists, and a binary as its type and size. The same script backs the
`st-*` pickers, so there is one place where that behaviour lives.

## Completion

Tab does prefix completion, ignores case in both directions, and matches words
by their initials across `.`, `_` and `-`:

```
ls tests/z_t_s<Tab>      →  ls tests/zsh_tools_spec.zsh
ls tests/r-z-s<Tab>      →  ls tests/run-zsh-specs.sh
ls TESTS/<Tab>           →  ls tests/
ls a*d<Tab>              →  ls a.md
```

Results are grouped under captions, coloured like `ls`, and navigable with the
arrows. `kill <Tab>` lists this user's processes. Completions that shell out to a
package manager are cached under `$XDG_CACHE_HOME/zsh/zcompcache`.

Three findings are worth writing down, because each of them looks fine and does
nothing:

- **`r:|[._-]=* r:|=*` matches nothing.** The partial-word rule needs `**`, not
  `*`. The single-star form is what most configs carry, and it fails silently —
  `zstyle -L` reads it back to you unchanged.
- **A `matcher-list` of several entries only uses the first.** The documentation
  describes the entries as tried in turn until one produces matches. In practice
  the conventional leading `''` ("try exact first") disables everything after it.
  So it is one entry that does case-insensitivity and partial words together.
- **Substring-anywhere matching is not there on purpose.** It works, and it
  ruins ordinary completion: `te<Tab>` then has every file *containing* "te" as
  a candidate, no common prefix to insert, and nothing happens. `**<Tab>` through
  fzf is the tool for searching rather than completing.

`_extensions` and `_approximate` (typo tolerance) were tried and dropped: neither
could be shown to do anything, and every extra completer lengthens every
completion. `_match` stays, because `ls a*d<Tab>` demonstrably works.

## Startup

Around **30–40ms** to a prompt with the plugins installed, measured with a
terminal attached:

```sh
tests/zsh-startup-bench.sh              # median/p90 over 20 runs
tests/zsh-startup-bench.sh --budget 250 # fail if the median exceeds 250ms
tests/zsh-startup-bench.sh --profile    # per-function breakdown (zprof)
tests/zsh-startup-bench.sh --real       # measure the installed ~/ instead
```

What was done, and what it was worth:

- **`tool init zsh` output is cached and byte-compiled.** starship and zoxide
  each cost a fork, an exec and a few hundred lines of parsing per shell to
  produce output that only changes on upgrade. `_zcache_source` captures it once
  and rebuilds when the binary or its config is newer. **-8ms.**
- **starship's `PROMPT2` is baked into that cache.** Its init ends with
  `PROMPT2="$(starship prompt --continuation)"`, a second fork whose answer is a
  fixed string. `STARSHIP_SHELL` has to be set while generating it, or starship
  omits the `%{...%}` wrappers and the cursor lands in the wrong column on
  continuation lines.
- **`compinit -C` daily rather than always.** The fast path skips checking
  whether any completion is newer than the dump, which is the difference between
  ~4ms and ~40ms — but taken unconditionally the dump is never rebuilt, and a
  newly installed tool's completions stay invisible until you delete the cache by
  hand. A stamp file older than 20 hours triggers the full pass.
- **No `mkdir -p` on every startup** to ensure a directory that already exists.
- **fzf's integration is skipped without a terminal.** Everything in it is a zle
  widget, so a `zsh -i -c ...` shell cannot use it. It also removes a
  "can't change option: zle" line those shells used to print to stderr, from
  fzf's own restoring of the option array.

Two things that were measured and **not** kept:

- Byte-compiling `.zshrc` and `.zshenv` themselves: no effect beyond noise, and
  a stale `.zwc` is a confusing failure.
- Copying fzf's two integration files into the cache so they would be compiled
  with it: no effect either. What they cost is running them, not parsing them.

The remaining time is mostly the two plugins. `--profile` shows where it goes.

## Behaviour worth knowing about

- **`hist_verify`**: a history expansion (`!!`, `!$`) lands on the command line
  for a look instead of running when you press Enter.
- **`auto_pushd`**: every `cd` pushes onto the directory stack, so `cd -<Tab>`
  offers where you have been. `pushd_silent` keeps it from printing the stack
  each time; `pushd_minus` makes `cd -2` mean "two back".
- **`autocd`**: a bare directory name changes to it, which is also why `..`
  works as a command.
- **`share_history`**: shells see each other's lines as they are typed.
- **`hist_ignore_space`**: a command typed with a leading space stays out of the
  history — but it lingers as the most recent entry until the next command runs,
  which is documented zsh behaviour and surprising the first time.

## Degrading

Every optional tool is guarded, and the specs check the whole config works with
none of them installed — that being the state of a fresh clone before
`./init.sh` has run.

| Missing     | What happens                                                     |
| ----------- | ---------------------------------------------------------------- |
| `starship`  | a `vcs_info` prompt: path, branch, a marker that reddens on failure |
| `fzf`       | no Ctrl-T/Alt-C/Ctrl-R picker; Tab completion unaffected          |
| `fd`        | Ctrl-T falls back to fzf's own walker                            |
| `bat`       | `cat` stays `cat`, previews use `head`, man pages use `less`      |
| `eza`       | `ls` stays `ls`                                                  |
| `delta`     | git pages through `less`                                         |
| `code`      | git's merge tool becomes `nvimdiff3`, or `vimdiff`                |
| `nc`        | nothing — VS Code sockets are probed with zsh's own `zsocket`     |

## Tests

```sh
tests/run-zsh-specs.sh              # everything
tests/run-zsh-specs.sh keys         # just the specs whose name matches "keys"
```

Each spec runs in a throwaway `HOME` whose dotfiles are symlinks into the
checkout — the shape stow produces — so they exercise the files you are about to
commit and never touch the real `~`. The runner fails if a spec changed the
working tree, which is how a tool writing into `~/.local/share` (zoxide did) gets
caught before it is committed.

| Spec                     | Covers                                                |
| ------------------------ | ----------------------------------------------------- |
| `zsh_startup_spec.zsh`   | silence, environment, PATH, options, history          |
| `zsh_prompt_spec.zsh`    | the prompt, the fallback, the init cache and its rebuilds |
| `zsh_tools_spec.zsh`     | `e`, `lfcd`, `gg`, `code`, the git wrapper, aliases, previews |
| `zsh_completion_spec.zsh` | Tab, by pressing it                                  |
| `zsh_keys_spec.zsh`      | every binding, by pressing it                         |
| `zsh_zle_spec.zsh`       | what only exists with a terminal attached             |

The last three need a terminal, which they get from
[`tests/zsh_pty.py`](../tests/zsh_pty.py): an interactive zsh under a pty, keys
written to it as if typed, and the shell's own answer read back from a file
rather than picked out of the terminal echo. Three things about driving a shell
that way are not obvious:

- Keys queued behind the setup arrive while the terminal is still in canonical
  mode, where a Tab stays a literal tab and no binding fires. The reliable signal
  that the line editor is ready is **ICANON going away** on the pty, which the
  parent can watch directly. A zle `line-init` hook is *not* equivalent — it runs
  while the terminal is still canonical.
- Sending `Ctrl-C` afterwards to clear the line eats the keys under test: the
  driver raises `SIGINT` the moment the byte arrives, and zsh discards pending
  input when interrupted.
- The harness types its own scaffolding with a leading space to keep it out of
  the history, and that is not enough on its own — see `hist_ignore_space` above.
