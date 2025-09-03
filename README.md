# Dotfiles with GNU Stow

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/) for easy configuration management across machines.

## ⚠️ Before You Install - Preview First

```sh
# Preview what will be symlinked (do this first!)
stow -n -v common    # Add mac/windows on those platforms
```

Shows which files will be symlinked and any conflicts. **Only proceed after reviewing!**

## Quick Setup

```sh
# Clone and navigate
git clone https://github.com/skyde/dotfiles.git ~/dotfiles
cd ~/dotfiles

# Preview first, then install
stow -n -v common        # Preview
./init.sh                # Install if preview looks good
```

**Prerequisites**: Install `git` and `stow` first (`brew install stow` on Mac, `sudo apt install git stow` on Linux, `winget install stefansundin.gnu-stow` on Windows).

## Manual Commands

```sh
# Install packages
stow common              # Shared configs
stow mac                 # macOS-specific (on Mac)  
stow windows             # Windows-specific (on Windows)

# Remove packages
stow -D common           # Uninstall

# Update after changes
stow -R common           # Restow
```

## Linux .bashrc Note

Linux systems have a default `.bashrc`. Our dotfiles include `.bashrc-custom` to avoid conflicts:

```sh
stow common                           # Install dotfiles
echo 'source ~/.bashrc-custom' >> ~/.bashrc  # Add to existing .bashrc
```

## Starship Prompt

Starship is offered as an optional tool.
You'll be prompted to install it unless `AUTO_INSTALL=1` is set, in which case it installs and updates without prompting (winget: `Starship.Starship`).

## Fast CLI Tools

These tools are offered during setup:

- `ripgrep` for searching directories quickly
- `fd` as a faster `find`
- `bat` as a colorful `cat`
- `eza` as an improved `ls`
- `lf` as a modern terminal file manager
- `delta` for modern git diffs (also used in Lazygit)
  - diffs are side-by-side by default, while LazyGit shows inline changes
- `lazygit` for a simple git TUI

On macOS/Linux, `starship` is also installed; Windows installs it via winget.

## Mac notes

## Custom Alt Tab

I use the 'Alt Tab' program for easy window switching.

Activate with footpedal + r. Navigate with arrow keys and space to select.

Settings are stored in `mac/Library/Preferences/com.lwouis.alt-tab-macos.plist` and include:

- Custom appearance size and alignment
- Arrow keys enabled for navigation
- UI elements hidden (badges, colored circles, status icons, menubar icon)
- Control key as hold shortcut

## Hammerspoon

Spotlight opens when the Cmd key is quickly tapped by itself. A short delay prevents accidental triggers.

## Fluor

Automatically switches mode of fn keys per program. Important as keyboard macros use F... keys.

Settings are stored in `mac/Library/Preferences/com.pyrolyse.Fluor.plist` and include:

- App-specific rules for VS Code and kitty (behavior mode 2)
- Notification preferences

## Better Display

Allows increased brightness when viewing SDR content on an HDR monitor.

## Windows notes

## Config

```text
- To get the Alt Tab switcher to work better
    - Go to Accessibility -> Visual Effects -> Animation effects & turn them off
    - Without this, moving to another tab requires waiting a split second.
- Set cursor blink rate to 0
- Set cursor thickness to 6
```

lf expects its configuration under `%AppData%\lf` on Windows. These dotfiles create a symlink to `~/.config/lf` so settings apply across OSes.

## PowerShell 7

Use this since it's nicer than the default PowerShell 5.

## Visual Studio

```text
- For Visual Studio use VSVim with the provided vsvimrc
- Using the plugin 'Peasy Motion' with the following settings:
- Allowed jump label characters: tsraneiodhgmplfuc,bjvk
    - (note this is optimized for Colemak Mod DH)
- Use a plugin called MinimalVS for nice fullscreen mode
    - https://marketplace.visualstudio.com/items?itemName=pavonism.minimalVS
- There is a plugin called 'Smooth Caret' which messes with the VSVim caret - make sure it's disabled
```

## Perforce

Ensure you set the correct environment variable to allow the diff to work:

```cmd
P4DIFF="C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\devenv.exe" /Diff %1 %2
```

## Visual Studio Code

I'm using a few plugins:

- Vim
- Fzf Picker (hooks into fzf, rg & bat)
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

## Keyboard

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
toggle eye mouse - Shift F10
toggle comment - Shift F11

```

## Platforms

Press Pgrm 1 to activate on Mac
Press Pgrm qwerty to activate on Windows

Note you should always leave the keyboard in 'Windows' mode as the bindings have been manually translated.

## Footpedal

The config for the footpedal is located under the savant-elite2 folder.

The pedal config:

- Left is Escape
- Middle is Left Click
- Right is Right Click

The method to open V-Drive is either:

- Flip the switch on the bottom of the pedal
- Hold the pedal down briefly while connecting to the computer (waterproof version)
