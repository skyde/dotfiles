# Ranger integration

- Ranger config lives in `dotfiles/common/ranger/.config/ranger/` (rc.conf, rifle.conf, scope.sh).
- VS Code tasks previously pointing to lf scripts (`lib/lf_open.sh`, `lib/lf_switch_and_select.sh`) now launch Ranger.

Usage

- Open Ranger from VS Code (existing tasks): the LF tasks now open Ranger.
- From shell: `ranger --selectfile=<path>` to open and select a file.

Notes

- Install Ranger on macOS: `brew install ranger`.
- Images: `chafa` if available (`brew install chafa`). Kitty image previews require the Kitty terminal.
