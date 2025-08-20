# Dotfiles with GNU Stow

This repository contains my personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/), a symlink farm manager that makes it easy to manage your configuration files across different machines and operating systems.

## Repository Structure

```
dotfiles/
├── common/          # Shared configs across all platforms
│   ├── bash/        # Bash configuration
│   ├── git/         # Git configuration
│   ├── nvim/        # Neovim configuration
│   ├── zsh/         # Zsh configuration
│   ├── tmux/        # Tmux configuration
│   ├── Code/        # VS Code configuration
│   └── ...
├── mac/             # macOS-specific configs
│   └── hammerspoon/ # Hammerspoon Lua config
└── windows/         # Windows-specific configs
    ├── Documents/   # PowerShell profiles
    ├── vsvim/       # Visual Studio Vim settings
    └── ...
```

## How Stow Works

GNU Stow creates symlinks from your home directory to the configuration files in this repository:

- **Package**: Each subdirectory in `dotfiles/` is a "package" (e.g., `bash`, `git`, `nvim`)
- **Target**: Your home directory (`~` or `$HOME`)
- **Symlinks**: Stow creates symlinks in your home directory pointing to files in the packages

### Example

When you run `stow bash` from `dotfiles/common/`:
```
~/.bashrc → ~/.dotfiles/dotfiles/common/bash/.bashrc
```

## Quick Install

### Mac

```sh
# Install Homebrew from https://brew.sh if it's not already present
brew install stow
git clone https://github.com/skyde/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./simple_install.sh
```

### Linux

```sh
sudo apt update
sudo apt install -y stow git
git clone https://github.com/skyde/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./simple_install.sh
```

### Windows

```ps
winget install stefansundin.gnu-stow
git clone https://github.com/skyde/dotfiles.git "$env:USERPROFILE\dotfiles"
cd "$env:USERPROFILE\dotfiles"
./simple_install.ps1
```

## Manual Package Management

You can also manage individual packages manually:

### Installing Packages

```sh
cd ~/.dotfiles/dotfiles/common

# Install individual packages
stow bash          # Install bash configuration
stow git           # Install git configuration  
stow nvim          # Install neovim configuration
stow tmux          # Install tmux configuration

# Install macOS-specific configs (on Mac)
cd ../mac
stow hammerspoon   # Install Hammerspoon config
```

### Uninstalling Packages

```sh
cd ~/.dotfiles/dotfiles/common

# Remove symlinks for specific packages
stow -D bash       # Remove bash configuration
stow -D git        # Remove git configuration
```

### Restowing (Update Existing)

```sh
cd ~/.dotfiles/dotfiles/common

# Update existing installations after changes
stow -R nvim       # Restow neovim configuration
stow -R git        # Restow git configuration
```

## Platform-Specific Instructions

### macOS
The install script will:
- Install packages from `dotfiles/common/`
- Install macOS-specific configs from `dotfiles/mac/`
- Optionally install CLI tools (ripgrep, fd, bat, eza, etc.)

### Linux  
The install script will:
- Install packages from `dotfiles/common/`
- Set up Linux-specific configurations
- Optionally install CLI tools via package manager

### Windows
The PowerShell script will:
- Install packages from `dotfiles/common/` 
- Install Windows-specific configs from `dotfiles/windows/`
- Use PowerShell-compatible stow commands

## Customization

### Adding New Configurations

1. Create a new directory in `dotfiles/common/` (or platform-specific directory)
2. Structure it exactly as it would appear in your home directory
3. Use stow to install it:

```sh
# Example: Adding a new tool called 'mytool'
mkdir -p dotfiles/common/mytool/.config/mytool
echo "config=value" > dotfiles/common/mytool/.config/mytool/config.toml
cd dotfiles/common
stow mytool
```

### Handling Conflicts

If stow encounters existing files that aren't symlinks, it will warn you:

```sh
# Move existing files to backup
mv ~/.bashrc ~/.bashrc.backup

# Then install the package
stow bash
```

## Troubleshooting

### Common Issues

1. **Stow conflicts**: Remove or backup existing files first
2. **Permission errors**: Ensure you have write access to your home directory  
3. **Broken symlinks**: Run `stow -R <package>` to restow
4. **Package not found**: Check you're in the correct directory (`dotfiles/common/` etc.)

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

# Mac

## Custom Alt Tab

I use the 'Alt Tab' program for easy window switching.

Activate with footpedal + r. Navigate with arrow keys and space to select.

## Hammerspoon

Spotlight opens when the Cmd key is quickly tapped by itself. A short delay prevents accidental triggers.

## Fluor

Automatically switches mode of fn keys per program. Important as keyboard macros use F... keys.

## Better Display

Allows increased brightness when viewing SDR content on an HDR monitor.

# Windows

## Config

```
- To get the Alt Tab switcher to work better
    - Go to Accessibility -> Visual Effects -> Animation effects & turn them off
    - Without this, moving to another tab requires waiting a split second.
- Set cursor blink rate to 0
- Set cursor thickness to 6
```

lf expects its configuration under `%AppData%\lf` on Windows. These dotfiles create a symlink to `~/.config/lf` so settings apply across OSes.

## Powershell 7

Use this since it's nicer than the default one.

## Visual Studio

```
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

```
P4DIFF="C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\devenv.exe" /Diff %1 %2
```

# Visual Studio Code

I'm using a few plugins:

- Vim
- Fzf Picker (hooks into fzf, rg & bat)
- clangd for C++ language features
  Extensions listed in `vscode_extensions.txt` will be installed automatically
  when these dotfiles are applied. Custom keybindings are documented in
  [`docs/vscode-keybindings.md`](docs/vscode-keybindings.md).
  On macOS, the install script also checks for the default CLI at
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

# Keyboard

Run `kinesis-advantage2/sync-kinesis-layouts.ps1` with the Kinesis Advantage2 V-Drive connected & key bindings will auto sync.

I've had issues where the keyboard drive gets totally corrupted when syncing from Mac - so just stick to Windows.

For more detail see the 'Interaction' repo.

## Macro Bindings

```

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

# Footpedal

The config for the footpedal is located under the savant-elite2 folder.

The pedal config:

- Left is Escape
- Middle is Left Click
- Right is Right Click

The method to open V-Drive is either:

- Flip the switch on the bottom of the pedal
- Hold the pedal down briefly while connecting to the computer (waterproof version)
