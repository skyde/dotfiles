# Dotfiles with GNU Stow

This repository contains my personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/), a symlink farm manager that makes it easy to manage your configuration files across different machines and operating systems.

## Repository Structure

```text
├── common/   # Shared configs across all platforms
├── mac/      # macOS-specific configs
└── windows/  # Windows-specific configs
```

## How Stow Works

GNU Stow creates symlinks from your home directory to the configuration files in this repository:

- **Package**: Top-level directories (`common`, `mac`, `windows`)
- **Target**: Your home directory (`~` or `$HOME`)
- **Symlinks**: Stow mirrors the directory structure inside each package to your home directory

### Example

When you run `stow common`, symlinks are created:

```text
~/.bashrc → ~/dotfiles/common/.bashrc
~/.zshrc → ~/dotfiles/common/.zshrc
~/.tmux.conf → ~/dotfiles/common/.tmux.conf
```

## Quick Setup

### Mac

```sh
# Install Homebrew from https://brew.sh if not already present
# stow will be installed automatically by the init script
git clone https://github.com/skyde/dotfiles.git ~/dotfiles
cd ~/dotfiles
./init.sh
```

### Linux notes

```sh
sudo apt update
sudo apt install -y git   # stow installed automatically
git clone https://github.com/skyde/dotfiles.git ~/dotfiles
cd ~/dotfiles
./init.sh
```

### Windows (platform)

```ps
# stow will be installed automatically via winget if missing
# Install Git if needed: winget install Git.Git
git clone https://github.com/skyde/dotfiles.git "$env:USERPROFILE\dotfiles"
cd "$env:USERPROFILE\dotfiles"
.\init.ps1
```

## What the Init Scripts Do

The init scripts provide complete automation:

1. **📁 Stow Configuration Files**: Symlink all dotfiles to correct locations
2. **🔧 Install VS Code Extensions**: Auto-install essential extensions from `vscode_extensions.txt`
3. **📦 Install Development Tools**: Optionally install common CLI tools:
   - **macOS**: ripgrep, fd, fzf, bat, delta, eza, neovim, tmux, git, lazygit
   - **Linux**: ripgrep, fd-find, fzf, bat, git, neovim, tmux
   - **Windows**: Git, ripgrep, fd, bat, delta, Neovim, PowerShell, Starship

### Non-Interactive Mode

For automated setups (CI/CD, scripts):

```bash
# Skip app installation prompts
AUTO_INSTALL=0 ./init.sh

# Auto-install apps without prompting
AUTO_INSTALL=1 ./init.sh
```

```powershell
# Windows equivalent
$env:AUTO_INSTALL = "0"  # or "1" to auto-install
.\init.ps1
```

## Manual Package Management

You can also manage packages manually:

### Installing Packages

```sh
cd ~/dotfiles

# Install shared configs
stow common

# Install macOS-specific configs (on Mac)
stow mac

# Install Windows-specific configs (on Windows)
stow windows
```

### Uninstalling Packages

```sh
cd ~/dotfiles

# Remove symlinks for a package
stow -D common
```

### Restowing (Update Existing)

After editing files, restow to update the symlinks:

```sh
cd ~/dotfiles
./apply.sh --restow        # Reapply all installed packages
./apply.sh --no --restow   # Preview restow without making changes
```

To restow a single package manually, run `stow -R <package>` from the `dotfiles` directory.

## Platform-Specific Instructions

### macOS

The init script will:

- Install configs from `common/`
- Install macOS-specific configs from `mac/`
- Optionally install CLI tools (ripgrep, fd, bat, eza, etc.)

### Linux

The init script will:

- Install configs from `common/`
- Set up Linux-specific configurations
- Optionally install CLI tools via package manager

### Windows

The PowerShell script will:

- Install configs from `common/`
- Install Windows-specific configs from `windows/`
- Use PowerShell-compatible stow commands
- Optionally install CLI tools via winget

## Customization

### Adding New Configurations

1. Add files under `common/` (or the platform-specific directory) following the same structure as your home directory.
2. Restow the package to apply the changes:

```sh
# Example: Adding a new tool called 'mytool'
mkdir -p common/.config/mytool
echo "config=value" > common/.config/mytool/config.toml
cd dotfiles
stow -R common
```

### Handling Conflicts

If stow encounters existing files that aren't symlinks, it will warn you:

```sh
# Move existing files to backup
mv ~/.bashrc ~/.bashrc.backup
mv ~/.zshrc ~/.zshrc.backup

# Then install the package
stow common
```

## Troubleshooting

### Common Issues

1. **Stow conflicts**: Remove or backup existing files first
2. **Permission errors**: Ensure you have write access to your home directory
3. **Broken symlinks**: Run `stow -R <package>` to restow
4. **Package not found**: Check you're in the correct directory (root directory, etc.)

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
