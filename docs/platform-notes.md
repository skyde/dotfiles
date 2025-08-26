# Platform Notes

## macOS
- Install Xcode CLT on first run if prompted.
- Homebrew is used where appropriate; re-run `./init-macos.sh` after OS upgrades.
- Hammerspoon is optional—disable the package if you don’t use it.

## Linux
- Use your distro’s package manager to install `git` and `stow` if the init script can’t.
- Some desktop environments place configs under `~/.config`; follow the package mirrors.
- Fonts: if your terminal/UI relies on Nerd Fonts, install one you like.

## Windows
- Enable **Developer Mode** (Settings → For Developers) to allow user symlinks.
- Alternatively, run PowerShell **as Administrator**.
- Visual Studio sometimes writes settings on exit; close VS before linking.
- For per-user app data, configs often live in `%APPDATA%` or `%LOCALAPPDATA%`.

