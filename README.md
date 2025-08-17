# Install

### Mac

```sh
# Install Homebrew from https://brew.sh if it's not already present
brew install chezmoi
chezmoi init skyde
# Review changes if desired
chezmoi diff

# Apply and be prompted before installs/changes
chezmoi apply

# Install and upgrade tools without prompting
AUTO_INSTALL=1 chezmoi apply
```

### Linux

```
sudo apt-get update -qq && sudo apt-get install -y git chezmoi
chezmoi init skyde
# Review changes if desired
chezmoi diff

# Apply and be prompted before installs/changes
chezmoi apply

# Install and upgrade tools without prompting
AUTO_INSTALL=1 chezmoi apply
```

### Windows

```ps
winget install twpayne.chezmoi
chezmoi init skyde
# Review changes if desired
chezmoi diff

# Apply and be prompted before installs/changes
chezmoi apply

# Install and upgrade tools without prompting
$env:AUTO_INSTALL=1; chezmoi apply
```

# Linux Container

Try it yourself in a Docker container.

```sh
docker run --rm -it debian:testing bash -c 'apt update -qq && apt install -y git curl ca-certificates && sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin && chezmoi init skyde && chezmoi diff && AUTO_INSTALL=1 chezmoi apply && exec bash'
```

### Dev container with SSH (Debian testing)

This repo includes a simple Debian testing image with OpenSSH for remote dev via VS Code Remote-SSH.

```sh
# Build and run the Debian testing SSH container
docker build -t dev-debian-testing-ssh:latest ~/.local/share/chezmoi/.tmp/dev-debian-testing-ssh
docker rm -f dev-debian-testing-ssh || true
docker run -d --name dev-debian-testing-ssh -p 2222:22 dev-debian-testing-ssh:latest

# Add SSH config entry (one-time)
cat >> ~/.ssh/config <<'EOF'
Host debian-testing
  HostName 127.0.0.1
  Port 2222
  User vscode
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  IdentityFile ~/.ssh/id_ed25519
EOF

# Test and apply dotfiles
ssh debian-testing 'sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" && AUTO_INSTALL=1 "$HOME/.local/bin/chezmoi" init skyde && AUTO_INSTALL=1 "$HOME/.local/bin/chezmoi" apply --force'

# Open VS Code attached (requires VS Code CLI)
code --remote ssh-remote+debian-testing --folder-uri "vscode-remote://ssh-remote+debian-testing/home/vscode"
```

### WSL Installation

```ps
wsl --install -d Debian && wsl --set-default Debian && wsl -d Debian -- bash -lc 'sudo sed -i "s/bookworm/trixie/g" /etc/apt/sources.list && sudo apt update && sudo apt full-upgrade -y && sudo apt install -y chezmoi && chezmoi init skyde && chezmoi diff && chezmoi apply'
```

## Starship Prompt

Starship is offered as an optional tool. You'll be prompted to install it unless `AUTO_INSTALL=1` is set, in which case it installs and updates without prompting (winget: `Starship.Starship`).

## Fast CLI Tools

These tools are offered during setup:

- `ripgrep` for searching directories quickly
- `fd` as a faster `find`
- `bat` as a colorful `cat`
- `eza` as an improved `ls`
- `yazi` as a modern terminal file manager
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

Yazi expects its configuration under `%AppData%\yazi\config` on Windows. These dotfiles create a symlink to `~/.config/yazi` so settings apply across OSes.

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

Run 'chezmoi update' with Kinesis Advantage 2 V-Drive connected & key bindings will auto sync.

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
