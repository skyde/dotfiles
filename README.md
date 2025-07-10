# Install

### Mac

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install chezmoi
chezmoi init --apply skyde
```

### Linux

```
sudo apt-get update -qq && sudo apt-get install -y curl && \
mkdir -p ~/.local/bin && \
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && export PATH="$HOME/.local/bin:$PATH" && \
curl -fsSL get.chezmoi.io | BINDIR="$HOME/.local/bin" bash -s -- init --apply skyde
```

### Windows

```ps
winget install twpayne.chezmoi
chezmoi init --apply skyde
```

# Linux Container

Try it yourself in a Docker container.

```sh
docker run --rm -it debian:testing bash -c 'apt update && apt install -y curl git && curl -fsSL get.chezmoi.io | bash -s -- init --apply skyde && exec bash'
```

### WSL Installation

```ps
wsl --install -d Debian && wsl --set-default Debian && wsl -d Debian -- bash -lc 'sudo sed -i "s/bookworm/trixie/g" /etc/apt/sources.list && sudo apt update && sudo apt full-upgrade -y && curl -fsLS get.chezmoi.io | bash -s -- init --apply skyde'
```

# Mac

## Custom Alt Tab

I use the 'Alt Tab' program for easy window switching.

Activate with footpedal + r. Navigate with arrow keys and space to select.

## Hammerspoon

Custom shortcut to open Spotlight Search with a keyboard macro. To avoid overwriting the original shortcut.

## Fluor

Automatically switches mode of fn keys per program. Important as keyboard macros use F... keys. 

## Better Display

Allows increased brightness when viewing SDR content on an HDR monitor.

# Windows

## Config

```
- To get the Alt Tab switcher to work better
    - Go to Accessibility -> Visual Effects -> Animation effects & turn them off
    - Without this moves to another tab will not work without waiting a split second.
- Set cursor blink rate to 0
- Set cursor thinkness to 6
```

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
toggle spotlight search - Shift F9
toggle eye mouse - Shift F10
toggle comment - Shift F11
```

## Platforms

Press Pgrm 1 to active on Mac
Press Pgrm qwerty to active on Windows

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
