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

## Shell

zsh, no framework and no plugin manager, about 50ms to a prompt (85ms before). Prefix-aware
history on the arrows, completion that matches a name from its initials, fzf on
Ctrl-R/Ctrl-T/Alt-C, and a fallback prompt for machines where starship is not
installed yet. Every key and every wrapper is covered by specs that press the key
in a real terminal — see [`docs/zsh.md`](docs/zsh.md) for the full reference, the
startup budget, and the measurements behind both.

```sh
tests/run-zsh-specs.sh          # the specs
tests/zsh-startup-bench.sh      # median/p90 time to a prompt
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

## Neovim

LazyVim, configured to match the VS Code setup key-for-key — see
[`docs/nvim-vscode-parity.md`](docs/nvim-vscode-parity.md) for the full table
and the handful of deliberate differences.

Source control is backend-agnostic: `<leader>gc` opens a changed-files list with
a live diff, and the same key works in git, jj, Perforce (`p4` / `g4`) and
Mercurial repositories. Conflict resolution
([`docs/neovim-mergetool.md`](docs/neovim-mergetool.md)) works off the markers,
so it is backend-agnostic too. `git mergetool` and `git difftool` open Neovim by
default; `-g` still reaches VS Code.

### Nvim Version

Distro packages lag badly, so on Linux install the current release straight from
upstream (`init.sh` offers to do this too):

```sh
./install-nvim.sh                        # latest release into ~/.local/bin
NVIM_VERSION=v0.11.5 ./install-nvim.sh   # pin a specific tag
```

The tarball is preferred (no FUSE needed); the AppImage is the fallback and gets
unpacked automatically when FUSE is missing. On macOS use `brew install neovim`.

### fzf Version

fzf refuses to start when given an option it does not recognise, so an old build
does not degrade — it fails. Ubuntu 24.04 ships 0.44, which is missing `--style`
(0.54), `--wrap` (0.53), `--tmux` (0.53) and `--tiebreak=pathname` (0.53). The
shell config and the `ff` / `st-*` / tmux pickers all check the version and leave
those flags out when they are unsupported, so everything works either way; a
current fzf is how you get the nicer look and the tmux popups.

```sh
./install-fzf.sh                      # latest release into ~/.local/bin
FZF_VERSION=v0.65.0 ./install-fzf.sh  # pin a specific tag
```

### Lazygit Version

`<leader>gg` opens lazygit inside Neovim, and
`common/.config/lazygit/config.yml` uses recent options, so lazygit needs to be
current as well. Debian and Ubuntu do not package it at all, so grab the release
binary (`init.sh` offers this too):

```sh
./install-lazygit.sh                          # latest release into ~/.local/bin
LAZYGIT_VERSION=v0.54.2 ./install-lazygit.sh  # pin a specific tag
```

### Plugin Versions

Plugin commits are pinned in `common/.config/nvim/lazy-lock.json`. Refresh them
with `:Lazy sync` inside Neovim and commit the updated lockfile.

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

In a Chromium checkout, Neovim keeps clangd fed the same way the ChromiumIDE
VS Code extension does — bundled clangd, auto-regenerated
`compile_commands.json`, shared `out/current_link` build-dir convention. See
[`docs/chromium-clangd.md`](docs/chromium-clangd.md).

Extensions listed in `vscode_extensions.txt` will be installed automatically
when these dotfiles are applied. Custom keybindings are documented in
[`docs/vscode-keybindings.md`](docs/vscode-keybindings.md); the Neovim
equivalents of each one are in
[`docs/nvim-vscode-parity.md`](docs/nvim-vscode-parity.md).
Neovim also draws code in the same colours VS Code does — how that mapping was
built and verified is in
[`docs/vscode-syntax-parity.md`](docs/vscode-syntax-parity.md).
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

These all work in Neovim too, in the kitty terminal and in the VS Code
integrated terminal. See [docs/footpedal-keys.md](docs/footpedal-keys.md) for
what each one maps to and how to check them.

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
