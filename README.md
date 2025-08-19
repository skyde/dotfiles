# Install

## YADM (new)

Use yadm to manage and deploy these dotfiles cross‑platform. The repo layout keeps all dotfiles under `~/chezmoi` and a yadm bootstrap links them to the correct destinations.

### macOS

```sh
brew install yadm
# First time: point yadm at this repo (remote or local path)
# Recommended when using a remote:
#   yadm clone --bootstrap git@github.com:skyde/chezmoi.git

# If running from a local checkout of this repo without changing your yadm repo:
YADM_REPO_ROOT="$PWD" YADM_SELF_TEST=1 bash .config/yadm/bootstrap
```

### Linux (Debian testing)

```sh
sudo apt update && sudo apt install -y yadm git curl ca-certificates zsh
yadm clone --bootstrap https://github.com/skyde/chezmoi.git
# Optional: self‑test to verify deployed files match sources
YADM_SELF_TEST=1 yadm bootstrap
```

### Windows

- Recommended: Use WSL (Debian) and follow the Linux steps inside WSL. Windows‑specific files (e.g., VS settings and PowerShell profile) are still in the repo and linked by the bootstrap where applicable when run under WSL.

### Test in a Debian testing container

```sh
docker run --rm -t -v "$PWD":/repo debian:testing bash -lc '
  apt-get update -qq && apt-get install -y yadm git curl ca-certificates zsh && \
  cd /root && yadm clone --bootstrap /repo && YADM_SELF_TEST=1 yadm bootstrap && echo "[yadm] container test OK"'
```

## Chezmoi (legacy)

The workflow below was used previously. It remains documented for reference but yadm is now the default.

### Mac

```sh
# Install Homebrew from https://brew.sh if it's not already present
brew install chezmoi
chezmoi init skyde
# Review changes
chezmoi diff

# Apply and be prompted before installs/changes
chezmoi apply

# Install and upgrade tools without prompting
AUTO_INSTALL=1 chezmoi apply
```

### Linux

```
apt update
apt install -y curl ca-certificates git zsh
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
chezmoi init skyde

# Review changes
chezmoi diff

# Prompt before install (Corporate Use)
chezmoi apply

# Install without prompting (Personal Use)
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
