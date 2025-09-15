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

## `sz` + `si` (with memoized changed-files & Chromium-aware nested repos)

* Memoize the changed/untracked file list (configurable TTL; default 30s) so long-running `fzf` sessions stay fast.
* Handle **Chromium/Chrome** trees (Skia, V8, ANGLE, Dawn, SwiftShader, PDFium, etc.) by **optionally scanning nested repos** and indexing them into the same per-repo `.zoekt/` shard dir.
* Keep everything **per-repo** (index in `./.zoekt/`; no global state).
* Preserve your **fzf + bat + nvim/VSCode** UX.

### 0) Prereqs

```bash
# macOS
brew install fzf ripgrep bat

# Debian/Ubuntu
sudo apt-get install -y fzf ripgrep bat

# Zoekt (requires Go)
go install github.com/sourcegraph/zoekt/cmd/zoekt@latest
go install github.com/sourcegraph/zoekt/cmd/zoekt-index@latest
go install github.com/sourcegraph/zoekt/cmd/zoekt-git-index@latest

# Make sure Go bin is on PATH
export PATH="$HOME/go/bin:$PATH"
```

**Ignore the index directory:**

```
.zoekt/
```

### 1) `sz` — live search (Zoekt + ripgrep overlay, memoized)

* Uses **Zoekt** if `./.zoekt/` exists.
* **Overlays ripgrep** *only* across **changed/untracked** files (so your WIP appears instantly).
* **Memoizes** the changed/untracked/deleted file lists in `~/.cache/sz/` per repo root, with a **TTL** (default **30s**, configurable).
* **Chromium-friendly:** optional nested repo discovery (Skia, V8, ANGLE, Dawn, SwiftShader, PDFium, etc.) for overlay freshness.
* **Format:** `path:line:matched_text` → matches your `ff/st` delimiter expectations.
* **Enter** opens in **Neovim** (default) or **VS Code** with `--code`.

> Save as `common/.local/bin/sz` and `chmod +x`.

```bash
#!/usr/bin/env bash
# sz — Hybrid code search with Zoekt (indexed) + ripgrep overlay for changed/untracked files.
# - Memoizes changed/untracked/deleted lists per repo (TTL) to keep long-running fzf sessions snappy.
# - Chromium-aware nested repo discovery (Skia, V8, ANGLE, Dawn, SwiftShader, PDFium, etc.).
# UX: fzf (live reload), bat preview, open in nvim (default) or VS Code (--code).

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: sz [--code] [--all] [--refresh] [PATH]
  --code      Open in VS Code instead of nvim
  --all       When NO Zoekt index exists, search entire tree with ripgrep (not just changed files)
  --refresh   Ignore memoized changed/deleted lists and recompute them now
  PATH        Optional: directory or a file within a repo to set the search root.
              Defaults to git root if inside a repo, otherwise $PWD.

Environment:
  SZ_CHANGED_TTL        TTL seconds for changed/deleted memoization (default: 30)
  SZ_NESTED_SCAN        nested repo scan mode: off | smart | deep   (default: smart)
  SZ_NESTED_MAX_DEPTH   max depth for 'deep' scan (default: 4)
  SZ_NESTED_REPOS       extra nested repo absolute paths, colon-separated (e.g., /path/to/src/third_party/skia:/path/to/src/v8)

Notes:
- If <root>/.zoekt exists and 'zoekt' is installed, sz uses Zoekt for indexed files and ripgrep for changed/untracked files.
  Deleted files are filtered out of Zoekt results to avoid stale hits.
- If no index is present, sz defaults to ripgrep on changed/untracked files only (fast). Use --all for full-tree scan.
- Output format is 'path:line:matched_text' for compatibility with your existing tools.
EOF
}

# --- utilities
abs_path() { (cd "$1" >/dev/null 2>&1 && pwd -P) || return 1; }

sha1_of() {
  if command -v sha1sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha1sum | awk '{print $1}'
  else
    printf '%s' "$1" | shasum | awk '{print $1}'
  fi
}

mtime_of() {
  local f="$1"
  if [[ ! -f "$f" ]]; then echo 0; return; fi
  if stat -f %m "$f" >/dev/null 2>&1; then
    stat -f %m "$f"      # macOS
  else
    stat -c %Y "$f"      # Linux
  fi
}

join_by() { local IFS="$1"; shift; echo "$*"; }

# --- internal backend used by fzf reload
if [[ "${1:-}" == "--_backend" ]]; then
  root="$2"; index_dir="$3"; mode="${4:-DEFAULT}"; refresh="${5:-NO}"; shift 5
  if [[ "${1:-}" == "--" ]]; then shift; fi
  query="${*:-}"

  cd "$root"

  # config
  use_zoekt=false
  [[ -d "$index_dir" ]] && command -v zoekt >/dev/null 2>&1 && use_zoekt=true

  cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/sz"
  mkdir -p "$cache_dir"
  root_abs="$(abs_path "$root")"
  key="$(sha1_of "$root_abs")"
  changed_cache="$cache_dir/${key}.changed"
  deleted_cache="$cache_dir/${key}.deleted"
  nested_cache="$cache_dir/${key}.nested"   # optional info-only
  ttl="${SZ_CHANGED_TTL:-30}"

  fresh() {
    local f="$1"
    [[ -f "$f" ]] || return 1
    local now mt
    now=$(date +%s)
    mt=$(mtime_of "$f")
    (( now - mt < ttl ))
  }

  # discover nested repos (Chromium-friendly)
  discover_nested() {
    local mode="${SZ_NESTED_SCAN:-smart}"
    local depth="${SZ_NESTED_MAX_DEPTH:-4}"
    local -a repos=()
    # curated Chromium set first (cheap checks)
    if [[ "$mode" != "off" ]]; then
      for cand in \\
        "third_party/skia" "third_party/v8" "v8" "third_party/angle" \\
        "third_party/pdfium" "third_party/swiftshader" "third_party/dawn" \\
        "third_party/blink" "third_party/perfetto" "third_party/catapult" \\
        "third_party/spirv-tools" "third_party/spirv-headers" "third_party/icu"; do
        [[ -d "$root/$cand/.git" ]] && repos+=("$root/$cand")
      done
      # option: deep find for any other nested repos, capped by depth
      if [[ "$mode" == "deep" ]]; then
        # skip common heavy dirs
        while IFS= read -r g; do
          [[ "$g" == "$root/.git" ]] && continue
          local rr="${g%/.git}"
          repos+=("$rr")
        done < <(find "$root" -mindepth 2 -maxdepth "$depth" -type d -name .git \\
                 -not -path "$root/.git" \\
                 -not -path "$root/out/*" 2>/dev/null)
      fi
    fi
    # user-provided extras
    if [[ -n "${SZ_NESTED_REPOS:-}" ]]; then
      IFS=':' read -r -a extras <<< "$SZ_NESTED_REPOS"
      for e in "${extras[@]}"; do
        [[ -d "$e/.git" ]] && repos+=("$e")
      done
    fi
    # unique
    if ((${#repos[@]})); then
      printf '%s\n' "${repos[@]}" | awk '!seen[$0]++'
    fi
  }

  recompute_lists() {
    local -a repos
    repos=("$root")
    while IFS= read -r nr; do
      repos+=("$nr")
    done < <(discover_nested)

    local tmp_changed tmp_deleted
    tmp_changed="$(mktemp)"; tmp_deleted="$(mktemp)"
    trap 'rm -f "$tmp_changed" "$tmp_deleted"' EXIT

    local r_abs relprefix
    for repo in "${repos[@]}"; do
      r_abs="$(abs_path "$repo")" || continue
      # relprefix = repo path relative to root ('' for root)
      relprefix="${r_abs#${root_abs}/}"
      [[ "$relprefix" == "$r_abs" ]] && relprefix=""  # not under root (rare), will print absolute later

      # changed & untracked
      { git -C "$repo" ls-files -m -z 2>/dev/null || true; \\
        git -C "$repo" ls-files -o --exclude-standard -z 2>/dev/null || true; } \\
        | xargs -0 -I{} bash -c '
            rpfx="$0"; f="{}"
            if [[ -n "$rpfx" ]]; then
              printf "%s/%s\n" "$rpfx" "$f"
            else
              printf "%s\n" "$f"
            fi
          ' "$relprefix" >> "$tmp_changed"

      # deleted
      git -C "$repo" ls-files --deleted -z 2>/dev/null \\
        | xargs -0 -I{} bash -c '
            rpfx="$0"; f="{}"
            if [[ -n "$rpfx" ]]; then
              printf "%s/%s\n" "$rpfx" "$f"
            else
              printf "%s\n" "$f"
            fi
          ' "$relprefix" >> "$tmp_deleted" || true
    done

    # normalize + dedupe
    sort -u -o "$tmp_changed" "$tmp_changed" 2>/dev/null || true
    sort -u -o "$tmp_deleted" "$tmp_deleted" 2>/dev/null || true
    # write caches atomically
    cp "$tmp_changed" "$changed_cache"
    cp "$tmp_deleted" "$deleted_cache"
    # keep discovered nested list (optional)
    discover_nested > "$nested_cache" 2>/dev/null || true
  }

  # load caches or recompute
  declare -a changed_files deleted_files
  if [[ "$refresh" == "YES" ]] || ! (fresh "$changed_cache" && fresh "$deleted_cache"); then
    recompute_lists
  fi
  mapfile -t changed_files < <(cat "$changed_cache" 2>/dev/null || true)
  mapfile -t deleted_files < <(cat "$deleted_cache" 2>/dev/null || true)

  # Build filter set for Zoekt (exclude changed+deleted). Include both relative and absolute forms.
  filter_file="$(mktemp)"
  trap 'rm -f "$filter_file"' EXIT
  {
    printf '%s\n' "${changed_files[@]}"
    printf '%s\n' "${deleted_files[@]}"
  } | awk -v r="$root_abs" 'NF { print $0; print r "/" $0 }' \\
    | sort -u > "$filter_file"

  if $use_zoekt; then
    # 1) Zoekt for indexed files, filtering out changed/deleted paths
    if [[ -s "$filter_file" ]]; then
      zoekt -index_dir "$index_dir" -- "$query" 2>/dev/null \\
        | awk -F':' -v OFS=':' -v f="$filter_file" '
            BEGIN { while ((getline line < f) > 0) { skip[line]=1 } }
            { if (!($1 in skip)) print $0 }
          '
    else
      zoekt -index_dir "$index_dir" -- "$query" 2>/dev/null
    fi

    # 2) ripgrep across changed/untracked files for fresh content
    if ((${#changed_files[@]})) && command -v rg >/dev/null 2>&1; then
      rg -H -n --color=never -- "$query" "${changed_files[@]}" 2>/dev/null \\
        | sed -E 's/^([^:]+:[0-9]+):[0-9]+:/\1:/'
    fi
    exit 0
  fi

  # No Zoekt index present
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ "$mode" != "ALL" ]] && ((${#changed_files[@]})); then
      # Fast path: only changed/untracked files
      if command -v rg >/dev/null 2>&1; then
        rg -H -n --color=never -- "$query" "${changed_files[@]}" 2>/dev/null \\
          | sed -E 's/^([^:]+:[0-9]+):[0-9]+:/\1:/'
        exit 0
      fi
      # Grep fallback
      grep -nH -R -- "$query" "${changed_files[@]}" 2>/dev/null
      exit 0
    fi
  fi

  # Full-tree ripgrep (either --all, no changed files, or not a git repo)
  if command -v rg >/dev/null 2>&1; then
    rg -H -n --color=never -- "$query" "$root" 2>/dev/null \\
      | sed -E 's/^([^:]+:[0-9]+):[0-9]+:/\1:/'
    exit 0
  fi
  # Grep fallback
  grep -RIn -- "$query" "$root" 2>/dev/null \\
    | sed -E 's/^([^:]+:[0-9]+):/\1:/'
  exit 0
fi
# --- end backend

# Parse user flags
open_cmd="nvim +{2} {1}"
target=""
mode="DEFAULT"   # DEFAULT | ALL
refresh="NO"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --code) open_cmd="code -r -g {1}:{2}"; shift ;;
    --all)  mode="ALL"; shift ;;
    --refresh) refresh="YES"; shift ;;
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

# Build reload command using this script path (no PATH reliance)
script_self="$0"
reload_cmd="'$script_self' --_backend '$root' '$index_dir' '$mode' '$refresh' -- {q}"

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

#### Why this solves your two asks

* **Memoization with TTL:** The changed/untracked/deleted lists are cached on disk per repo root (`~/.cache/sz/<hash>.{changed,deleted}`) and reused for **all** keystrokes during the TTL window. Use `--refresh` to force recompute now. Tune TTL via `SZ_CHANGED_TTL` (e.g., `export SZ_CHANGED_TTL=60`) for very long sessions.

* **Chromium case:** We add **nested repo discovery** (`SZ_NESTED_SCAN=smart|deep|off`). In **smart** mode (default), we check known heavyweights (Skia, V8, ANGLE, Dawn, SwiftShader, PDFium, etc.). In **deep** mode, we find *any* `.git` up to a depth (default 4). This ensures the overlay includes WIP in nested repos—exactly your Skia-in-Chromium case.

### 2) `si` — indexer (per-repo `.zoekt/`, nested repos optional)

* Writes shards under `<root>/.zoekt/>`.
* For **git repos**: `zoekt-git-index -index <root>/.zoekt <repo>` (one shard set per repo; searches span all shards in the dir).
* For **plain dirs**: `zoekt-index` (excludes VCS dirs + `.zoekt`; you can add ignores).
* **Nested indexing** (Chromium-aware) so your searches cover Skia/V8/etc. in the same index directory.
* Can install **git hooks** (`post-merge`, `post-checkout`) to keep the index fresh.
* Clears the `sz` changed-file cache after indexing so overlays are immediately consistent.

> Save as `common/.local/bin/si` and `chmod +x`.

```bash
#!/usr/bin/env bash
# si — Create/update Zoekt index under <root>/.zoekt and (optionally) index nested repos.
# Also manages git hooks to auto-refresh, and clears sz memoized caches for consistency.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  si [PATH]                         Index PATH (or git root or $PWD) into <root>/.zoekt
  si --nested [MODE] [PATH]         Also index nested repos; MODE: off | smart | deep (default: smart)
  si --install-hooks [PATH]         Install post-merge & post-checkout hooks for PATH (repo)
  si --install-global-hooks         Install hooks into ~/.git-templates/hooks (set core.hooksPath)

Environment:
  SI_NESTED_SCAN        default nested mode if --nested omitted: off | smart | deep (default: smart)
  SZ_NESTED_MAX_DEPTH   max depth for 'deep' scan (default: 4)
  SI_IGNORE_DIRS        extra dirs to ignore for plain-directory indexing (comma-separated)

Details:
- Git repos use:    zoekt-git-index -index <root>/.zoekt <repo>
- Non-git dirs use: zoekt-index    -index <root>/.zoekt -ignore_dirs ".git,.hg,.svn,.zoekt[,<SI_IGNORE_DIRS>]" <root>
- Hooks run 'si <root>' after pulls/branch switches to keep the index fresh.
EOF
}

abs_path() { (cd "$1" >/dev/null 2>&1 && pwd -P) || return 1; }

sha1_of() {
  if command -v sha1sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha1sum | awk '{print $1}'
  else
    printf '%s' "$1" | shasum | awk '{print $1}'
  fi
}

clear_sz_cache_for_root() {
  local root="$1"
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/sz"
  local key
  mkdir -p "$cache_dir"
  key="$(sha1_of "$(abs_path "$root")")"
  rm -f "$cache_dir/${key}.changed" "$cache_dir/${key}.deleted" "$cache_dir/${key}.nested" 2>/dev/null || true
}

write_hook() {
  local hook_path="$1" si_bin="$2"
  mkdir -p "$(dirname "$hook_path")"
  cat > "$hook_path" <<EOFHOOK
#!/usr/bin/env bash
set -euo pipefail
SI_BIN="$si_bin"
if [[ ! -x "$SI_BIN" ]]; then
  SI_BIN="si"  # fallback to PATH if absolute path missing
fi
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
# Quiet re-index; ignore errors so hooks never block merges/checkouts.
"$SI_BIN" "$root" >/dev/null 2>&1 || true
EOFHOOK
  chmod +x "$hook_path"
}

install_repo_hooks() {
  local repo="$1"
  if not_git=$(git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; echo $?); then
    if [[ "$not_git" -ne 0 ]]; then
      echo "Not a git repo: $repo" >&2
      exit 1
    fi
  fi
  local hooks_dir="$repo/.git/hooks"
  local si_bin
  si_bin="$(command -v si || true)"
  [[ -z "$si_bin" ]] && si_bin="si"
  write_hook "$hooks_dir/post-merge" "$si_bin"
  write_hook "$hooks_dir/post-checkout" "$si_bin"
  echo "Installed hooks: $hooks_dir/post-merge, $hooks_dir/post-checkout"
}

install_global_hooks() {
  local tmpl="$HOME/.git-templates/hooks"
  mkdir -p "$tmpl"
  local si_bin
  si_bin="$(command -v si || true)"
  [[ -z "$si_bin" ]] && si_bin="si"
  write_hook "$tmpl/post-merge" "$si_bin"
  write_hook "$tmpl/post-checkout" "$si_bin"
  echo "Installed global hooks to: $tmpl"
  echo "If not already set, run:"
  echo "  git config --global core.hooksPath \"$HOME/.git-templates/hooks\""
}

discover_nested() {
  local root="$1" mode="$2" depth="${SZ_NESTED_MAX_DEPTH:-4}"
  local -a repos=()
  if [[ "$mode" != "off" ]]; then
    for cand in \\
      "third_party/skia" "third_party/v8" "v8" "third_party/angle" \\
      "third_party/pdfium" "third_party/swiftshader" "third_party/dawn" \\
      "third_party/blink" "third_party/perfetto" "third_party/catapult" \\
      "third_party/spirv-tools" "third_party/spirv-headers" "third_party/icu"; do
      [[ -d "$root/$cand/.git" ]] && repos+=("$root/$cand")
    done
    if [[ "$mode" == "deep" ]]; then
      while IFS= read -r g; do
        [[ "$g" == "$root/.git" ]] && continue
        repos+=("${g%/.git}")
      done < <(find "$root" -mindepth 2 -maxdepth "$depth" -type d -name .git \\
               -not -path "$root/.git" \\
               -not -path "$root/out/*" 2>/dev/null)
    fi
  fi
  if ((${#repos[@]})); then
    printf '%s\n' "${repos[@]}" | awk '!seen[$0]++'
  fi
}

index_repo_git() {
  local where="$1" idx="$2"
  echo "Indexing (git) $where -> $idx"
  zoekt-git-index -index "$idx" "$where"
}

index_repo_dir() {
  local where="$1" idx="$2"
  local ignores=".git,.hg,.svn,.zoekt"
  [[ -n "${SI_IGNORE_DIRS:-}" ]] && ignores="$ignores,${SI_IGNORE_DIRS}"
  echo "Indexing (dir) $where -> $idx (ignore_dirs: $ignores)"
  zoekt-index -index "$idx" -ignore_dirs "$ignores" "$where"
}

# ---- flag parsing
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage; exit 0; fi

case "${1:-}" in
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
    target="$(abs_path "$target")"
    install_repo_hooks "$target"
    exit 0
    ;;
  --install-global-hooks)
    install_global_hooks
    exit 0
    ;;
  --nested)
    shift
    nested_mode="${1:-${SI_NESTED_SCAN:-smart}}"
    [[ "$nested_mode" != "off" && "$nested_mode" != "smart" && "$nested_mode" != "deep" ]] && {
      echo "Invalid --nested mode: $nested_mode" >&2; exit 1; }
    shift || true
    ;;
  *)
    nested_mode="${SI_NESTED_SCAN:-smart}"
    ;;
esac

# Resolve target dir
if [[ -n "${1:-}" ]]; then
  target="$(abs_path "$1")"
elif git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
  target="$(abs_path "$git_root")"
else
  target="$(abs_path "$PWD")"
fi

index_dir="${target}/.zoekt"
mkdir -p "$index_dir"

# Index target and optional nested repos
if git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  index_repo_git "$target" "$index_dir"
else
  index_repo_dir "$target" "$index_dir"
fi

# Nested indexing (Chromium-friendly)
while IFS= read -r nr; do
  git -C "$nr" rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue
  index_repo_git "$nr" "$index_dir"
done < <(discover_nested "$target" "$nested_mode")

echo "Done. Shards in: $index_dir"

# Clear sz memoized caches for this root so overlay is consistent immediately
clear_sz_cache_for_root "$target"
```

### 3) Usage

#### Bootstrap (once)

```bash
chmod +x common/.local/bin/sz common/.local/bin/si
# ensure common/.local/bin is on your PATH (you already do via stow)
```

#### Index Chromium (recommended)

From your Chromium `src` root:

```bash
# Index root + smart nested repos (Skia/V8/ANGLE/...); per-repo shards all stored in ./ .zoekt/
si --nested smart

# Or scan for any nested repos up to depth 4
SZ_NESTED_MAX_DEPTH=4 si --nested deep
```

> Tip (Chrome scale): For **Skia-only** work, you can limit nested indexing:
>
> ```bash
> SZ_NESTED_REPOS="$(pwd)/third_party/skia" si --nested off
> ```
>
> (This indexes root + Skia only.)

#### Keep index fresh automatically

```bash
# Per-repo hooks (run from Chromium src root)
si --install-hooks

# Optional: global hooks applied to all repos
si --install-global-hooks
git config --global core.hooksPath "$HOME/.git-templates/hooks"
```

#### Search

```bash
# Inside repo
sz                       # Zoekt + rg overlay (memoized changed-file list)
sz --code                # open matches in VS Code
sz --refresh             # force recompute the changed/deleted lists now
sz --all                 # if NO index: full-tree ripgrep

# From anywhere, target a repo
sz /path/to/src
```

#### Tune for long-running sessions

```bash
# Cache changed-file list for 60s (instead of 30s default)
export SZ_CHANGED_TTL=60

# In Chromium, include nested repos automatically (smart default is usually enough)
export SZ_NESTED_SCAN=smart
# or aggressive:
export SZ_NESTED_SCAN=deep
export SZ_NESTED_MAX_DEPTH=4
```

### 4) Chrome/Chromium notes (what this fixes)

1. **Nested repos (Skia, etc.)**
   Chromium’s tree includes many repos under `third_party/` (Skia, V8, ANGLE, SwiftShader, Dawn, PDFium…).

   * `si --nested` indexes those **into the same `<root>/.zoekt/>`** so a single Zoekt invocation covers everything.
   * `sz` discovers the same nested repos and **includes their WIP** in the ripgrep overlay (memoized).

2. **Speed in large trees**

   * The **changed/untracked list is memoized** (default 30s), avoiding heavy `git ls-files` across nested repos on every keystroke.
   * `--refresh` lets you bypass the cache when you know you changed a lot.

3. **No duplication/stale hits**

   * `sz` filters Zoekt’s output against the union of **changed + deleted** paths (both relative and absolute), so you don’t see stale matches from files you’ve modified or removed.

4. **Build outputs ignored**

   * Zoekt (git mode) indexes only tracked content (so `out/` etc. won’t bloat shards).
   * The overlay searches **only the changed/untracked** files list, which already respects `.gitignore`.

### 5) First-principles checklist

* **Index state** lives **inside** the repo: `<root>/.zoekt/>`.
* **Fast** results come from the **Zoekt index**; **fresh** WIP comes from the **overlay** (changed/untracked).
* **Memoization** decouples UI keystrokes from filesystem/Git scans during long sessions (tunable with `SZ_CHANGED_TTL`).
* **Nested repos** are symmetric: we **index** them and we **overlay** them.

### 6) Quick tests (run now)

* From Chromium `src`:

  ```bash
  si --nested smart
  sz 'SkPaint'            # should stream from Zoekt fast
  # edit a file in third_party/skia, then:
  sz --refresh 'SkPaint'  # should show your new match immediately from rg overlay
  ```
* Delete a file you just edited, then search again → the Zoekt result for that file should **not** show (filtered via deleted list).
