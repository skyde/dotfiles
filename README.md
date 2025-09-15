# Dotfiles

Personal dotfiles managed with [Stow](https://www.gnu.org/software/stow/) for easy configuration management across machines.

## Install

### Clone

```sh
# Clone and navigate
git clone https://github.com/skyde/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

### Preview

Shows which files will be symlinked and any conflicts. **Only proceed after reviewing!**

```sh
stow -n -v common        # Preview - add mac/windows on those platforms
./apply.sh -n            # Similar to previous command, but with additional checks
```

### Mutate

```sh
./init.sh                # Install if preview looks good
```

## Stow Commands

```sh
# Install packages
stow common              # Shared configs
stow mac                 # macOS-specific (on Mac)  
stow windows             # Windows-specific (on Windows)

# Remove packages
stow -D common           # Uninstall

# Update after changes (restow)
stow -R common           # Refresh symlinks after editing dotfiles
                         # Use when: files added/removed, broken links, or conflicts
```

**When to restow:**

- Added/removed files in your dotfiles
- Symlinks appear broken or missing
- After resolving stow conflicts
- When switching between git branches

## Linux .bashrc Note

Linux systems have a default `.bashrc`. These dotfiles include `.bashrc-custom` to avoid conflicts:

```sh
~/.bashrc-custom  # Add to existing .bashrc to source the custom one
```

## CLI Tools

- `ripgrep` for searching directories quickly
- `fd` as a faster `find`
- `bat` as a colorful `cat`
- `eza` as an improved `ls`
- `lf` as a modern terminal file manager
- `delta` for modern git diffs (also used in Lazygit)
  - diffs are side-by-side by default, while LazyGit shows inline changes
- `lazygit` for a simple git TUI
- `starship` for a customizable cross-shell prompt

## Mac

### Custom Alt Tab

I use the 'Alt Tab' program for easy window switching.

Activate with footpedal + r. Navigate with arrow keys and space to select.

Settings are stored in `mac/Library/Preferences/com.lwouis.alt-tab-macos.plist` and include:

- Custom appearance size and alignment
- Arrow keys enabled for navigation
- UI elements hidden (badges, colored circles, status icons, menubar icon)
- Control key as hold shortcut

### Hammerspoon

Spotlight opens when the Cmd key is quickly tapped by itself. A short delay prevents accidental triggers.

### Fluor

Automatically switches mode of fn keys per program. Important as keyboard macros use F... keys.

Settings are stored in `mac/Library/Preferences/com.pyrolyse.Fluor.plist` and include:

- App-specific rules for VS Code and kitty (behavior mode 2)
- Notification preferences

### Better Display

Allows increased brightness when viewing SDR content on an HDR monitor.

## Windows

### Config

```text
- To get the Alt Tab switcher to work better
    - Go to Accessibility -> Visual Effects -> Animation effects & turn them off
    - Without this, moving to another tab requires waiting a split second.
- Set cursor blink rate to 0
- Set cursor thickness to 6
```

lf expects its configuration under `%AppData%\lf` on Windows. These dotfiles create a symlink to `~/.config/lf` so settings apply across OSes.

### PowerShell 7

Use this since it's nicer than the default PowerShell 5.

### Visual Studio

```text
- For Visual Studio use VSVim with the provided vsvimrc
- Using the plugin 'Peasy Motion' with the following settings:
- Allowed jump label characters: tsraneiodhgmplfuc,bjvk
    - (note this is optimized for Colemak Mod DH)
- Use a plugin called MinimalVS for nice fullscreen mode
    - https://marketplace.visualstudio.com/items?itemName=pavonism.minimalVS
- There is a plugin called 'Smooth Caret' which messes with the VSVim caret - make sure it's disabled
```

### Perforce

Ensure you set the correct environment variable to allow the diff to work:

```cmd
P4DIFF="C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\devenv.exe" /Diff %1 %2
```

### Visual Studio Code

I'm using a few plugins:

- Vim
- Yazi
- clangd for C++ language features

Extensions listed in `vscode_extensions.txt` will be installed automatically
when these dotfiles are applied. Custom keybindings are documented in
[`docs/vscode-keybindings.md`](docs/vscode-keybindings.md).
On macOS, the init script falls back to
`/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code` if the
`code` command isn't in your `PATH`.

For remote development, install the **Remote - SSH** extension. Add your server
details to `~/.ssh/config`, e.g.

```ssh
Host devbox
  HostName server.example.com
  User you
```

Use the “Remote-SSH: Connect to Host…” command in VS Code to start a session.

### Keyboard

Run `kinesis-advantage2/sync-kinesis-layouts.ps1` with the Kinesis Advantage2 V-Drive connected & key bindings will auto sync.

I've had issues where the keyboard drive gets totally corrupted when syncing from Mac - so just stick to Windows.

For more detail see the 'Interaction' repo.

## Macro Bindings

```text

build and run - Shift F2
find class - Shift F3
scroll up - Shift F4
scroll down - Shift F6
stop build - Shift F7
goto definition - Shift F8
open spotlight - tap Cmd
tmux prefix / toggle eye mouse - Shift F10
toggle comment - Shift F11

```

## Kinesis

Press Pgrm 1 to activate Mac layout
Press Pgrm qwerty to activate the Windows layout

Note you should always leave the keyboard in 'Windows' mode as the bindings have been manually translated for Mac.

## Footpedal

The config for the footpedal is located under the windows/savant-elite2 folder.

- Left is Escape
- Middle is Left Click
- Right is Right Click

The method to open V-Drive is either:

- Flip the switch on the bottom of the pedal
- Hold the pedal down briefly while connecting to the computer (waterproof version)

## `sz` + `zi`: Hybrid Zoekt + ripgrep search for large repos

**Goals**

* **Fast, indexed search** using **Zoekt** whenever a repo has a local index at `./.zoekt/`.
* **Fresh results for local edits** by **merging ripgrep results** from changed/untracked files into the result stream.
* **Zero-maintenance**: optional **git hooks** to auto-refresh the index after `git pull` / branch switches.
* **Consistent UX**: `fzf` UI, `bat` preview, `:` delimiter, and *Enter* opens in **VS Code** (or **Neovim** with `--vim`), mirroring your `ff/st` tools.

---

## 0) Prerequisites

Install these once:

```bash
# Core CLI
brew install fzf ripgrep bat        # macOS
# or
sudo apt-get install fzf ripgrep bat # Debian/Ubuntu

# Zoekt (requires Go)
go install github.com/sourcegraph/zoekt/cmd/zoekt@latest
go install github.com/sourcegraph/zoekt/cmd/zoekt-index@latest
go install github.com/sourcegraph/zoekt/cmd/zoekt-git-index@latest
```

> Add `~/go/bin` to your PATH if needed:
> `export PATH="$HOME/go/bin:$PATH"`

Make sure your dotfiles’ `bin` dir is on PATH (e.g. `~/dotfiles/common/.local/bin` via `stow`).

---

## 1) Script: `common/.local/bin/sz`

**What it does**

* If repo has `./.zoekt/` **and** `zoekt` is installed:

  * Stream **Zoekt** results for indexed files.
  * Detect **changed + untracked files** via git and stream **ripgrep** results for those (so you see your local edits immediately).
  * Filter out from Zoekt any files that are changed or deleted to prevent duplicates/stale hits.
* If no index, fall back to `ripgrep` over the target directory.

**Open on Enter**

* Default: **VS Code** at the matched line.
* With `--vim`: **Neovim** at the matched line (`nvim +line file`).

> Place the file below at `common/.local/bin/sz` and `chmod +x` it.

```bash
#!/usr/bin/env bash
# sz — Hybrid code search with Zoekt (indexed) + ripgrep (changed files).
# UI: fzf with live reload; preview via bat; open in VS Code (default) or Neovim (--vim).

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: sz [--vim] [PATH]
  --vim   Open in Neovim instead of VS Code
  PATH    Optional: directory or a file within a repo to set the search root.
          Defaults to git root if inside a repo, otherwise $PWD.

Notes:
- If <root>/.zoekt exists and 'zoekt' is installed, sz uses Zoekt for indexed files
  and ripgrep for changed/untracked files. Deleted files are filtered from Zoekt output.
- If no index is present, sz falls back to ripgrep for the whole root.
USAGE
}

# --- internal backend for fzf reload (do not call directly)
if [[ "${1:-}" == "--_backend" ]]; then
  root="$2"; index_dir="$3"; shift 3
  if [[ "${1:-}" == "--" ]]; then shift; fi
  query="${*:-}"

  cd "$root"

  use_zoekt=false
  if [[ -d "$index_dir" ]] && command -v zoekt >/dev/null 2>&1; then
    use_zoekt=true
  fi

  if $use_zoekt; then
    # Build lists of changed/untracked/deleted files (paths relative to repo root)
    changed_list_file="$(mktemp)"
    deleted_list_file="$(mktemp)"
    filter_list_file="$(mktemp)"
    trap 'rm -f "$changed_list_file" "$deleted_list_file" "$filter_list_file"' EXIT

    # Modified + untracked
    { git -C "$root" ls-files -m -z 2>/dev/null || true; \
      git -C "$root" ls-files -o --exclude-standard -z 2>/dev/null || true; } \
      | xargs -0 -I{} printf "%s\n" "{}" >> "$changed_list_file"

    # Deleted
    git -C "$root" ls-files --deleted -z 2>/dev/null \
      | xargs -0 -I{} printf "%s\n" "{}" >> "$deleted_list_file" || true

    cat "$changed_list_file" "$deleted_list_file" 2>/dev/null | sort -u > "$filter_list_file"

    # 1) Zoekt for indexed files, filtering out changed/deleted paths
    #    Zoekt prints "path:line:matched_line"
    if [[ -s "$filter_list_file" ]]; then
      zoekt -index_dir "$index_dir" -- "$query" 2>/dev/null \
        | awk -F':' -v OFS=':' -v f="$filter_list_file" '
            BEGIN { while ((getline line < f) > 0) { skip[line]=1 } }
            { if (!($1 in skip)) print $0 }
          '
    else
      zoekt -index_dir "$index_dir" -- "$query" 2>/dev/null
    fi

    # 2) ripgrep only across changed/untracked files (fresh content)
    if [[ -s "$changed_list_file" ]] && command -v rg >/dev/null 2>&1; then
      # rg prints "path:line:column:match" -> normalize to "path:line:match"
      mapfile -t files < "$changed_list_file" || true
      if [[ ${#files[@]} -gt 0 ]]; then
        rg -H -n --color=never -- "$query" "${files[@]}" 2>/dev/null \
          | sed -E 's/^([^:]+:[0-9]+):[0-9]+:/\1:/'
      fi
    fi
    exit 0
  else
    # No index: ripgrep the whole root (respects .gitignore)
    if command -v rg >/dev/null 2>&1; then
      rg -H -n --color=never -- "$query" "$root" 2>/dev/null \
        | sed -E 's/^([^:]+:[0-9]+):[0-9]+:/\1:/'
      exit 0
    fi
    # Fallback if ripgrep missing
    grep -RIn -- "$query" "$root" 2>/dev/null \
      | sed -E 's/^([^:]+:[0-9]+):/\1:/'
    exit 0
  fi
fi
# --- end internal backend

# Parse flags
open_cmd="code -r -g {1}:{2}"
target=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vim) open_cmd="nvim +{2} {1}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) target="$1"; shift ;;
  esac
done

# Resolve search root
if [[ -n "${target}" ]]; then
  if [[ -f "${target}" ]]; then
    root="$(cd "$(dirname -- "${target}")" && pwd)"
  else
    root="$(cd "${target}" && pwd)"
  fi
elif git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
  root="${git_root}"
else
  root="${PWD}"
fi

index_dir="${root}/.zoekt"

# Require fzf + bat
command -v fzf >/dev/null 2>&1 || { echo "fzf not found."; exit 1; }
command -v bat >/dev/null 2>&1 || { echo "bat not found."; exit 1; }

reload_cmd="sz --_backend '${root}' '${index_dir}' -- {q}"

# FZF UI
exec fzf \
  --ansi \
  --disabled \
  --tiebreak=index \
  --delimiter ':' \
  --bind "start:reload:${reload_cmd} || true" \
  --bind "change:reload:${reload_cmd} || true" \
  --preview "cd '${root}' && bat --style=numbers --color=always --highlight-line {2} {1}" \
  --preview-window 'bottom,30%,+{2}/2' \
  --bind "enter:become(cd '${root}' && ${open_cmd})"
```

---

## 2) Script: `common/.local/bin/zi`

**What it does**

* Builds/updates a Zoekt index for a directory (prefers repo root when inside Git).
* Stores index shards under `<root>/.zoekt/` (so the index “lives with” the repo but is ignored by Git).
* Can install **git hooks** to auto-update the index after `git pull` and on branch switches.

> Place the file below at `common/.local/bin/zi` and `chmod +x` it.

```bash
#!/usr/bin/env bash
# zi — Create/update a Zoekt index under <root>/.zoekt and manage optional git hooks.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  zi [PATH]                Index PATH (or git root or $PWD) into <root>/.zoekt
  zi --install-hooks [PATH]          Install post-merge & post-checkout hooks for PATH (repo)
  zi --install-global-hooks          Install hooks into ~/.git-templates/hooks (set core.hooksPath)

Details:
- Git repos use 'zoekt-git-index -index <root>/.zoekt <root>'.
- Non-git directories use 'zoekt-index -index <root>/.zoekt -ignore_dirs ".git,.hg,.svn,.zoekt" <root>'.
- Hooks run 'zi <root>' after pulls/branch switches to keep the index fresh.
USAGE
}

write_hook() {
  local hook_path="$1" zi_bin="$2"
  mkdir -p "$(dirname "$hook_path")"
  cat > "$hook_path" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
ZI_BIN="$zi_bin"
if [[ ! -x "$ZI_BIN" ]]; then
  ZI_BIN="zi"  # fallback to PATH if absolute path missing
fi
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
# Quiet re-index; ignore errors so hooks never block merges/checkouts.
"$ZI_BIN" "$root" >/dev/null 2>&1 || true
HOOK
  chmod +x "$hook_path"
}

install_repo_hooks() {
  local repo="$1"
  if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not a git repo: $repo" >&2
    exit 1
  fi
  local hooks_dir="$repo/.git/hooks"
  local zi_bin
  zi_bin="$(command -v zi || true)"
  if [[ -z "$zi_bin" ]]; then
    echo "Warning: 'zi' is not on PATH right now; hooks will try 'zi' from PATH later." >&2
    zi_bin="zi"
  fi
  write_hook "$hooks_dir/post-merge" "$zi_bin"
  write_hook "$hooks_dir/post-checkout" "$zi_bin"
  echo "Installed hooks: $hooks_dir/post-merge, $hooks_dir/post-checkout"
}

install_global_hooks() {
  local tmpl="$HOME/.git-templates/hooks"
  mkdir -p "$tmpl"
  local zi_bin
  zi_bin="$(command -v zi || true)"
  [[ -z "$zi_bin" ]] && zi_bin="zi"
  write_hook "$tmpl/post-merge" "$zi_bin"
  write_hook "$tmpl/post-checkout" "$zi_bin"
  echo "Installed global hooks to: $tmpl"
  echo "If not already set, run:"
  echo "  git config --global core.hooksPath \"$HOME/.git-templates/hooks\""
}

# --- flags / subcommands
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --install-hooks)
    shift
    target="${1:-}"
    if [[ -z "$target" ]]; then
      if git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
        target="$git_root"
      else
        target="$PWD"
      fi
    fi
    target="$(cd "$target" && pwd)"
    install_repo_hooks "$target"
    exit 0
    ;;
  --install-global-hooks)
    install_global_hooks
    exit 0
    ;;
esac

# --- normal indexing
# Resolve target directory
if [[ -n "${1:-}" ]]; then
  target="$(cd "$1" && pwd)"
elif git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
  target="$git_root"
else
  target="$PWD"
fi

index_dir="${target}/.zoekt"
mkdir -p "$index_dir"

# Prefer git-aware indexer when available
if git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Indexing (git) $target -> $index_dir"
  zoekt-git-index -index "$index_dir" "$target"
else
  echo "Indexing (dir) $target -> $index_dir"
  zoekt-index -index "$index_dir" -ignore_dirs ".git,.hg,.svn,.zoekt" "$target"
fi

echo "Done. Shards: $index_dir"
echo "Tip: add '.zoekt/' to .gitignore if not already ignored."
```

---

## 3) Add to `.gitignore`

In each repo (or globally), ensure:

```
.zoekt/
```

> Keeps the index out of version control.

---

## 4) Usage (common flows)

### 4.1 Index a repo, once

From inside the repo (or pass a path):

```bash
zi             # indexes current repo into ./ .zoekt/
# or
zi /path/to/repo
```

**Re-running `zi`** safely refreshes the index (you can trigger it whenever you want).

### 4.2 Auto-update on `git pull` and branch switches

Install per-repo hooks:

```bash
zi --install-hooks             # inside the repo
# or
zi --install-hooks /path/to/repo
```

(Optionally) install global hooks:

```bash
zi --install-global-hooks
git config --global core.hooksPath "$HOME/.git-templates/hooks"
```

> Hooks call `zi <root>` after a merge/pull (**post-merge**) and after checkouts (**post-checkout**) to keep `./.zoekt/` current.

### 4.3 Search

```bash
sz                  # searches git root if inside a repo, else $PWD
sz path/to/repo     # search another repo
sz --vim            # same UI, but open matches in Neovim
```

**Live behavior**

* As you type:

  * If `./.zoekt/` exists → Zoekt matches stream immediately.
  * **Your local edits** (modified/untracked files) are searched via ripgrep and merged in.
  * Files **deleted** in your working tree are filtered out of Zoekt results.
* If no index is present → `rg` searches the directory.

**Result format**

```
path:line:matched_text
```

* Preview: `bat` highlights the matched **line**.
* Enter: opens at **line** in VS Code (or Neovim with `--vim`).

---

## 5) Mental model (first principles)

* **Index** → `./.zoekt/` sits next to the repo. `zoekt` answers queries fast for committed content.
* **Freshness** → we **overlay** `rg` on **changed/untracked** files so your WIP shows up instantly.
* **Hooks** → after `git pull` or `checkout`, `zi` runs to refresh the index. No manual chores.
* **UI** → `fzf` is the front-end; it simply streams `path:line:text` rows and lets you pick.

---

## 6) Implementation notes & tradeoffs

* **Performance:** Running `git ls-files` each keystroke is a small overhead compared to full-text search; Zoekt handles the heavy part. If needed, we can memoize the changed-file list for the lifetime of the `fzf` session (ping me).
* **Path delimiters:** We use `:` as the field delimiter. Paths with `:` are rare on Unix; if you have such paths, we can switch to a sentinel delimiter and remap fzf fields.
* **Non-git directories:** When there’s no git, `sz` won’t try the “changed files” overlay; it’ll use Zoekt if `./.zoekt/` exists, otherwise plain `rg`.
* **Column numbers:** Ripgrep prints `path:line:col:match`; we normalize to `path:line:match` so both sources unify (Zoekt doesn’t emit columns).
* **Editor cwd:** We `cd` to the repo root before previewing or opening files so relative paths from Zoekt resolve correctly.

---

## 7) Quick self-check (Socratic prompts)

* Do you see `./.zoekt/` in your repo after running `zi`?
* Does `sz` show **both** indexed hits and hits from files you just edited (without committing)?
* After a `git pull`, does `sz` return results for newly pulled code (hooks installed)?
* Do you want `sz` to **fallback** to your global `~/.zoekt` if no local `.zoekt/` is present? (Easy tweak.)

If you want, I can also add **unit-style smoke tests** (small repos, known queries) and a **Makefile target** (e.g., `make index`) to standardize CI or local bootstrap.

